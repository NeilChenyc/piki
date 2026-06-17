from __future__ import annotations

import difflib
import hashlib
from pathlib import Path

from agent_service.application.events import EventPublisher
from agent_service.application.task_control import TaskRunControl
from agent_service.application.task_router import TaskPlan
from agent_service.config import ServiceConfig
from agent_service.context import assemble_agent_task_input, assemble_baseline_context
from agent_service.models import EventType, FileSnapshot, TaskCreateRequest, TaskStatus
from agent_service.runtime import PikiWikiAgentRunner
from agent_service.store import SQLiteStore
from agent_service.vault import Vault, VaultAccessError


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

    def execute(self, *, task_id: str, request: TaskCreateRequest, plan: TaskPlan, run_control: TaskRunControl | None = None):
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
            run_control=run_control,
        )

    def _execute_agent(
        self,
        *,
        task_id: str,
        request: TaskCreateRequest,
        vault: Vault,
        context_contents: dict[str, str],
        run_control: TaskRunControl | None,
    ):
        conversation_id = request.conversation_id or task_id
        conversation_messages = self.store.get_conversation_messages(conversation_id, limit=10)
        task_input = assemble_agent_task_input(
            request=request,
            conversation_messages=conversation_messages,
        )
        if not self.runner.can_run(self.config):
            error = "Claude Agent runtime is not configured."
            self.events.task_failed(task_id, error)
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=error)
            return

        try:
            self.events.progress(task_id, "thinking", "正在思考", "正在让 Claude 判断本轮需要调用哪些工具。")
            agent_result = self.runner.run_task(
                config=self.config,
                store=self.store,
                events=self.events,
                task_id=task_id,
                conversation_id=conversation_id,
                user_input=request.user_input,
                agent_input=task_input.render_prompt(),
                context_contents=context_contents,
                vault=vault,
                selected_paths=request.selected_paths,
                action_context=task_input.action_context,
                resume_session_id=_last_agent_session_id(conversation_messages),
                run_control=run_control,
            )
        except Exception as exc:
            self.events.task_failed(task_id, str(exc))
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=str(exc))
            return

        if _should_keep_task_cancelled(store=self.store, task_id=task_id, run_control=run_control):
            output = agent_result.model_dump(mode="json")
            output["action_context"] = task_input.action_context
            output["selected_paths"] = task_input.selected_paths
            output["conversation_id"] = conversation_id
            self.store.update_task(
                task_id,
                status=TaskStatus.CANCELLED,
                summary="任务已停止。",
                affected_files=agent_result.affected_files,
                output=output,
            )
            self.events.task_cancelled(task_id, "任务已停止。", answer=agent_result.answer or "")
            return

        if agent_result.status == TaskStatus.CANCELLED:
            output = agent_result.model_dump(mode="json")
            output["action_context"] = task_input.action_context
            output["selected_paths"] = task_input.selected_paths
            output["conversation_id"] = conversation_id
            self.store.update_task(
                task_id,
                status=TaskStatus.CANCELLED,
                summary=agent_result.summary,
                affected_files=agent_result.affected_files,
                output=output,
            )
            self.events.task_cancelled(task_id, agent_result.summary, answer=agent_result.answer or "")
            return

        if agent_result.affected_files:
            self.events.progress(task_id, "writing_wiki", "正在写入 Wiki", "已更新 vault 文件。")
        if agent_result.journal_entry:
            self.events.progress(task_id, "recording_changes", "正在记录变更", "已生成可回退的 Change Journal。")
        output = agent_result.model_dump(mode="json")
        output["action_context"] = task_input.action_context
        output["selected_paths"] = task_input.selected_paths
        output["conversation_id"] = conversation_id
        self.store.update_task(
            task_id,
            status=agent_result.status,
            summary=agent_result.summary,
            affected_files=agent_result.affected_files,
            output=output,
        )
        if agent_result.status == TaskStatus.INPUT_REQUIRED:
            return
        if agent_result.status == TaskStatus.FAILED:
            self.events.task_failed(task_id, agent_result.summary)
            return
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
            metadata={
                "action_context": task_input.action_context,
                "selected_paths": task_input.selected_paths,
                "agent_session_id": agent_result.session_id,
            },
        )
        self.events.progress(task_id, "completed", "已完成")

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

    def resume_input(self, *, task_id: str, message: str, run_control: TaskRunControl | None = None):
        task = self.store.get_task(task_id)
        if task.status != TaskStatus.INPUT_REQUIRED:
            raise ValueError(f"Task is not waiting for input: {task.status}")
        output = dict(task.output or {})
        session_id = output.get("session_id")
        conversation_id = output.get("conversation_id") or task_id
        request = TaskCreateRequest(
            vault_path=Path(task.vault_path),
            user_input=message,
            selected_paths=list(output.get("selected_paths") or []),
            action_context=dict(output.get("action_context") or {}),
            conversation_id=conversation_id,
            mode="normal",
            async_mode=False,
        )
        self.store.update_task(
            task_id,
            status=TaskStatus.RUNNING,
            summary="正在继续上一次等待输入的任务。",
            output={**output, "pending_input": None},
        )
        self.events.emit(task_id, EventType.AGENT_INPUT_RESOLVED, {"message": message, "session_id": session_id})
        vault = Vault(task.vault_path)
        _, context_contents = assemble_baseline_context(vault)
        conversation_messages = self.store.get_conversation_messages(conversation_id, limit=10)
        task_input = assemble_agent_task_input(request=request, conversation_messages=conversation_messages)
        agent_result = self.runner.run_task(
            config=self.config,
            store=self.store,
            events=self.events,
            task_id=task_id,
            conversation_id=conversation_id,
            user_input=message,
            agent_input=task_input.render_prompt(),
            context_contents=context_contents,
            vault=vault,
            selected_paths=request.selected_paths,
            action_context=task_input.action_context,
            resume_session_id=session_id,
            run_control=run_control,
        )
        merged_output = {
            **output,
            **agent_result.model_dump(mode="json"),
            "action_context": task_input.action_context,
            "selected_paths": task_input.selected_paths,
            "conversation_id": conversation_id,
        }
        if _should_keep_task_cancelled(store=self.store, task_id=task_id, run_control=run_control):
            self.store.update_task(
                task_id,
                status=TaskStatus.CANCELLED,
                summary="任务已停止。",
                affected_files=agent_result.affected_files,
                output=merged_output,
            )
            self.events.task_cancelled(task_id, "任务已停止。", answer=agent_result.answer or "")
            return
        self.store.update_task(
            task_id,
            status=agent_result.status,
            summary=agent_result.summary,
            affected_files=agent_result.affected_files,
            output=merged_output,
        )
        if agent_result.status == TaskStatus.CANCELLED:
            self.events.task_cancelled(task_id, agent_result.summary, answer=agent_result.answer or "")
            return
        if agent_result.status == TaskStatus.FAILED:
            self.events.task_failed(task_id, agent_result.summary)
            return
        if agent_result.status == TaskStatus.INPUT_REQUIRED:
            return
        self.events.task_completed(
            task_id,
            summary=agent_result.summary,
            answer=agent_result.answer or agent_result.summary,
            journal_entry_id=agent_result.journal_entry.id if agent_result.journal_entry else None,
        )
        self._append_conversation_messages(
            conversation_id=conversation_id,
            task_id=task_id,
            user_input=message,
            answer=agent_result.answer or agent_result.summary,
            metadata={"agent_session_id": agent_result.session_id, "continued_task_id": task_id},
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


def _last_agent_session_id(messages: list[dict]) -> str | None:
    for message in reversed(messages):
        metadata = message.get("metadata") or {}
        session_id = metadata.get("agent_session_id")
        if isinstance(session_id, str) and session_id:
            return session_id
    return None


def _should_keep_task_cancelled(*, store: SQLiteStore, task_id: str, run_control: TaskRunControl | None) -> bool:
    if run_control is not None and run_control.cancel_requested:
        return True
    try:
        return store.get_task(task_id).status == TaskStatus.CANCELLED
    except KeyError:
        return False
