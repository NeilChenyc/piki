from __future__ import annotations

import difflib
import hashlib
from pathlib import Path

from agent_service.application.events import EventPublisher
from agent_service.application.task_router import TaskPlan
from agent_service.config import ServiceConfig
from agent_service.context import assemble_agent_task_input, assemble_baseline_context
from agent_service.models import EventType, FileSnapshot, TaskCreateRequest, TaskStatus
from agent_service.runtime import PikiWikiAgentRunner
from agent_service.store import SQLiteStore
from agent_service.tools import VaultToolRegistry
from agent_service.vault import Vault, VaultAccessError
from agent_service.workflows import run_read_only_query


class TaskExecutor:
    def __init__(
        self,
        *,
        config: ServiceConfig,
        store: SQLiteStore,
        events: EventPublisher,
        runner: PikiWikiAgentRunner,
    ):
        self.config = config
        self.store = store
        self.events = events
        self.runner = runner

    def execute(self, *, task_id: str, request: TaskCreateRequest, plan: TaskPlan):
        vault = Vault(request.vault_path)
        try:
            vault.validate()
            self.events.progress(task_id, "thinking", "正在思考", "正在装配本轮 agent 上下文。")
            manifest, context_contents = assemble_baseline_context(vault)
        except VaultAccessError as exc:
            self.events.task_failed(task_id, str(exc))
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=str(exc))
            return

        self.events.emit(task_id, EventType.CONTEXT_LOADED, manifest.model_dump())

        action_context = dict(request.action_context or {})
        if request.mode == "clear-inbox-item" and "action" not in action_context:
            action_context["action"] = "clear_inbox_item"
        if action_context.get("action") == "clear_inbox_item":
            self._execute_source_clear(task_id=task_id, request=request, vault=vault)
            return
        self._execute_agent(
            task_id=task_id,
            request=request,
            vault=vault,
            context_contents=context_contents,
        )

    def _execute_agent(
        self,
        *,
        task_id: str,
        request: TaskCreateRequest,
        vault: Vault,
        context_contents: dict[str, str],
    ):
        conversation_id = request.conversation_id or task_id
        conversation_messages = self.store.get_conversation_messages(conversation_id, limit=10)
        task_input = assemble_agent_task_input(
            request=request,
            conversation_messages=conversation_messages,
        )
        if self.runner.can_run(self.config):
            tools = VaultToolRegistry(
                vault=vault,
                events=self.events,
                task_id=task_id,
                allowed_external_paths=request.selected_paths,
            )
            try:
                self.events.progress(task_id, "thinking", "正在思考", "正在让 Agent 判断本轮需要调用哪些工具。")
                agent_result = self.runner.run_task(
                    config=self.config,
                    events=self.events,
                    task_id=task_id,
                    conversation_id=conversation_id,
                    user_input=request.user_input,
                    agent_input=task_input.render_prompt(),
                    context_contents=context_contents,
                    tool_registry=tools,
                )
            except Exception as exc:
                if isinstance(exc, TimeoutError):
                    if _requires_configured_agent(request):
                        self.events.task_failed(task_id, str(exc))
                        self.store.update_task(task_id, status=TaskStatus.FAILED, summary=str(exc))
                        return
                    self._execute_local_fallback(
                        task_id=task_id,
                        request=request,
                        vault=vault,
                        conversation_id=conversation_id,
                        reason=str(exc),
                        kind="sdk_timeout_fallback",
                    )
                    return
                if _requires_configured_agent(request):
                    self.events.task_failed(task_id, str(exc))
                    self.store.update_task(task_id, status=TaskStatus.FAILED, summary=str(exc))
                    return
                self._execute_local_fallback(
                    task_id=task_id,
                    request=request,
                    vault=vault,
                    conversation_id=conversation_id,
                    reason=str(exc),
                    kind="sdk_error_fallback",
                )
                return

            if agent_result.affected_files:
                self.events.progress(task_id, "writing_wiki", "正在写入 Wiki", "已更新 vault 文件。")
            if agent_result.journal_entry:
                self.events.progress(task_id, "recording_changes", "正在记录变更", "已生成可回退的 Change Journal。")
            output = agent_result.model_dump(mode="json")
            output["action_context"] = task_input.action_context
            output["selected_paths"] = task_input.selected_paths
            if tools.last_source_intake_result:
                output["source_intake"] = tools.last_source_intake_result
            if tools.last_lint_result:
                output["lint_result"] = tools.last_lint_result
            if tools.last_lint_fix_result:
                output["lint_fix_result"] = tools.last_lint_fix_result
            self.store.update_task(
                task_id,
                status=TaskStatus.COMPLETED,
                summary=agent_result.summary,
                affected_files=agent_result.affected_files,
                output=output,
            )
            self.events.task_completed(
                task_id,
                summary=agent_result.summary,
                answer=agent_result.answer or agent_result.summary,
                journal_entry_id=agent_result.journal_entry.id if agent_result.journal_entry else None,
            )
            self._append_conversation_messages(
                conversation_id=conversation_id,
                task_id=task_id,
                user_input=request.user_input,
                answer=agent_result.answer or agent_result.summary,
                metadata={"action_context": task_input.action_context, "selected_paths": task_input.selected_paths},
            )
            self.events.progress(task_id, "completed", "已完成")
            return

        if _requires_configured_agent(request):
            error = "This task requires configured OpenAI Agents SDK runtime because it includes files, system action context, or an explicit write/ingest intent."
            self.events.task_failed(task_id, error)
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=error)
            return
        self._execute_local_fallback(
            task_id=task_id,
            request=request,
            vault=vault,
            conversation_id=conversation_id,
            reason="OpenAI Agents SDK runtime is not configured.",
            kind="sdk_unconfigured_fallback",
        )

    def _execute_source_clear(self, *, task_id: str, request: TaskCreateRequest, vault: Vault):
        self.events.progress(task_id, "clearing_source", "正在清理文件", "正在清理单个 inbox 文件。")
        try:
            if len(request.selected_paths) != 1:
                raise VaultAccessError("Clear requires exactly one selected path.")
            relative_path = _relative_inbox_path(vault, request.selected_paths[0])
            target = vault.resolve_path(relative_path)
            if not target.exists() or not target.is_file():
                raise VaultAccessError(f"Inbox file not found: {relative_path}")
            before_content = target.read_text(encoding="utf-8", errors="replace")
            before_hash = _content_hash(before_content)
            target.unlink()
            snapshot = FileSnapshot(
                path=relative_path,
                before_hash=before_hash,
                after_hash=None,
                before_content=before_content,
                after_content=None,
            )
            journal_entry = self.store.create_journal_entry(
                conversation_id=request.conversation_id or task_id,
                task_id=task_id,
                reason=f"Clear inbox file {relative_path}",
                affected_files=[relative_path],
                snapshots=[snapshot],
                diff=_delete_diff(relative_path, before_content),
            )
        except (OSError, VaultAccessError) as exc:
            error = str(exc)
            self.events.task_failed(task_id, error)
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=error)
            return

        summary = f"已清理 inbox 文件：{relative_path}"
        self.events.emit(task_id, EventType.SOURCE_CLEARED, {"path": relative_path, "journal_entry_id": journal_entry.id})
        self.events.progress(task_id, "recording_changes", "正在记录变更", "已生成可回退的 Change Journal。")
        self.store.update_task(
            task_id,
            status=TaskStatus.COMPLETED,
            summary=summary,
            affected_files=[relative_path],
            output={
                "summary": summary,
                "affected_files": [relative_path],
                "journal_entry": journal_entry.model_dump(mode="json"),
            },
        )
        self.events.task_completed(task_id, summary=summary, answer=summary, journal_entry_id=journal_entry.id)
        self.events.progress(task_id, "completed", "已完成")

    def _persist_query_result(self, task_id: str, query_result, *, conversation_id: str | None = None, user_input: str = ""):
        self.events.emit(
            task_id,
            EventType.QUERY_SEARCHED,
            {
                "mode": query_result.mode.value,
                "citations": len(query_result.citations),
                "related_pages": query_result.related_pages,
                "loaded_files": query_result.context_manifest.loaded_files,
                "search_terms": query_result.context_manifest.search_terms,
            },
        )
        self.store.update_task(
            task_id,
            status=TaskStatus.COMPLETED,
            summary=query_result.answer,
            output=query_result.model_dump(mode="json"),
        )
        self.events.emit(
            task_id,
            EventType.QUERY_COMPLETED,
            {
                "confidence": query_result.confidence.value,
                "citation_count": len(query_result.citations),
                "related_page_count": len(query_result.related_pages),
            },
        )
        self.events.task_completed(task_id, summary=query_result.answer, answer=query_result.answer)
        if conversation_id:
            self._append_conversation_messages(
                conversation_id=conversation_id,
                task_id=task_id,
                user_input=user_input,
                answer=query_result.answer,
                metadata={"fallback": "read_only_query"},
            )
        self.events.progress(task_id, "completed", "已完成")

    def _execute_local_fallback(
        self,
        *,
        task_id: str,
        request: TaskCreateRequest,
        vault: Vault,
        conversation_id: str,
        reason: str,
        kind: str,
    ):
        if _is_small_talk(request.user_input):
            answer = _small_talk_fallback_answer(request.user_input)
            self.events.trace_event(
                task_id,
                kind=kind,
                title="切换到本地回复",
                summary=reason,
                status="completed",
            )
            self._persist_direct_answer(
                task_id,
                answer,
                conversation_id=conversation_id,
                user_input=request.user_input,
                metadata={"fallback": "small_talk", "reason": reason},
            )
            return

        self.events.trace_event(
            task_id,
            kind=kind,
            title="切换到本地查询",
            summary=reason,
            status="completed",
        )
        self.events.progress(task_id, "reading_wiki", "正在阅读 Wiki", "SDK 暂不可用，正在使用本地只读 query fallback。")
        query_result = run_read_only_query(vault, request.user_input, mode=request.mode)
        self._persist_query_result(task_id, query_result, conversation_id=conversation_id, user_input=request.user_input)

    def _persist_direct_answer(
        self,
        task_id: str,
        answer: str,
        *,
        conversation_id: str | None = None,
        user_input: str = "",
        metadata: dict | None = None,
    ):
        self.store.update_task(
            task_id,
            status=TaskStatus.COMPLETED,
            summary=answer,
            output={"answer": answer, "summary": answer, **(metadata or {})},
        )
        self.events.task_completed(task_id, summary=answer, answer=answer)
        if conversation_id:
            self._append_conversation_messages(
                conversation_id=conversation_id,
                task_id=task_id,
                user_input=user_input,
                answer=answer,
                metadata=metadata,
            )
        self.events.progress(task_id, "completed", "已完成")

    def _append_conversation_messages(
        self,
        *,
        conversation_id: str,
        task_id: str,
        user_input: str,
        answer: str,
        metadata: dict | None = None,
    ):
        self.store.append_conversation_message(
            conversation_id,
            role="user",
            content=user_input,
            task_id=task_id,
            metadata=metadata,
        )
        self.store.append_conversation_message(
            conversation_id,
            role="assistant",
            content=answer,
            task_id=task_id,
            metadata=metadata,
        )


def _relative_inbox_path(vault: Vault, raw_path: str) -> str:
    path = Path(raw_path).expanduser()
    resolved = path.resolve() if path.is_absolute() else vault.resolve_path(path)
    try:
        relative = str(resolved.relative_to(vault.root))
    except ValueError as exc:
        raise VaultAccessError(f"Path is outside vault: {raw_path}") from exc
    if not relative.startswith("raw/inbox/"):
        raise VaultAccessError(f"Clear is only allowed for raw/inbox files: {relative}")
    return relative


def _content_hash(content: str) -> str:
    return "sha256:" + hashlib.sha256(content.encode("utf-8")).hexdigest()


def _delete_diff(relative_path: str, before_content: str) -> str:
    return "".join(
        difflib.unified_diff(
            before_content.splitlines(keepends=True),
            [],
            fromfile=f"a/{relative_path}",
            tofile=f"b/{relative_path}",
        )
    )


WRITE_INTENT_MARKERS = (
    "/wiki:ingest",
    "/wiki:compile",
    "记一下",
    "记录",
    "保存",
    "收进",
    "摄入",
    "整理进去",
    "更新",
    "修正",
    "改成",
    "补充",
)


SMALL_TALK_INPUTS = {
    "hi",
    "hello",
    "hey",
    "你好",
    "您好",
    "嗨",
    "在吗",
    "你在吗",
    "你是谁",
    "你能做什么",
}


def _is_small_talk(user_input: str) -> bool:
    normalized = user_input.strip().lower()
    normalized = normalized.strip(" \t\r\n,.!?。！？")
    return normalized in SMALL_TALK_INPUTS


def _small_talk_fallback_answer(user_input: str) -> str:
    normalized = user_input.strip().lower().strip(" \t\r\n,.!?。！？")
    if normalized in {"你能做什么", "你是谁"}:
        return "我可以帮你查询这个 Piki wiki、整理上传资料、把内容写入 Wiki，也可以按按钮动作执行 lint 或 inbox ingest。"
    return "你好，我在。你可以直接问我关于这个 Piki wiki 的问题，或让我帮你整理/记录资料。"


def _requires_configured_agent(request: TaskCreateRequest) -> bool:
    if request.selected_paths or request.action_context or request.mode == "clear-inbox-item":
        return True
    return any(marker in request.user_input for marker in WRITE_INTENT_MARKERS)
