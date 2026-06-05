from __future__ import annotations

import difflib
import hashlib
from pathlib import Path

from agent_service.application.events import EventPublisher
from agent_service.application.task_router import TaskPlan
from agent_service.config import ServiceConfig
from agent_service.context import assemble_baseline_context
from agent_service.models import EventType, FileSnapshot, TaskCreateRequest, TaskKind, TaskStatus
from agent_service.runtime import PikiWikiAgentRunner
from agent_service.store import SQLiteStore
from agent_service.tools import VaultToolRegistry
from agent_service.vault import Vault, VaultAccessError
from agent_service.workflows import SourceIntakeError, run_read_only_query, run_source_intake
from agent_service.workflows import read_source_meta, validate_canonical_source


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
            self.events.progress(task_id, "reading_vault", "正在读取知识库", "正在读取 vault 规则、目的和索引。")
            manifest, context_contents = assemble_baseline_context(vault)
        except VaultAccessError as exc:
            self.events.task_failed(task_id, str(exc))
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=str(exc))
            return

        self.events.emit(task_id, EventType.CONTEXT_LOADED, manifest.model_dump())

        if plan.task_kind == TaskKind.SOURCE_CLEAR:
            self._execute_source_clear(task_id=task_id, request=request, vault=vault)
            return
        if plan.task_kind == TaskKind.INGEST:
            self._execute_ingest(
                task_id=task_id,
                request=request,
                vault=vault,
                context_contents=context_contents,
                source_path=plan.ingest_source_path,
                ingest_error=plan.ingest_error,
            )
            return
        if plan.task_kind == TaskKind.AGENT:
            self._execute_agent(
                task_id=task_id,
                request=request,
                vault=vault,
                context_contents=context_contents,
            )
            return
        if plan.task_kind == TaskKind.SOURCE_INTAKE:
            self._execute_source_intake(
                task_id=task_id,
                request=request,
                vault=vault,
                context_contents=context_contents,
            )

    def _execute_ingest(
        self,
        *,
        task_id: str,
        request: TaskCreateRequest,
        vault: Vault,
        context_contents: dict[str, str],
        source_path: str | None,
        ingest_error: str | None,
    ):
        self.events.progress(task_id, "organizing_source", "正在整理资料", "正在准备单 source ingest。")
        self.events.emit(task_id, EventType.INGEST_STARTED, {"source_path": source_path, "error": ingest_error})
        if ingest_error:
            self.events.task_failed(task_id, ingest_error)
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=ingest_error)
            return
        if not self.runner.can_run(self.config):
            error = "Single source ingest requires configured OpenAI Agents SDK runtime."
            self.events.task_failed(task_id, error)
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=error)
            return
        try:
            canonical_path = validate_canonical_source(vault, source_path or "")
            source_meta = read_source_meta(vault, canonical_path)
            tools = VaultToolRegistry(vault=vault, events=self.events, task_id=task_id)
            self.events.progress(task_id, "thinking", "正在思考和生成", "正在让 Agent 分析 source 并规划 wiki 更新。")
            ingest_result = self.runner.run_ingest(
                config=self.config,
                events=self.events,
                task_id=task_id,
                conversation_id=request.conversation_id or task_id,
                source_path=canonical_path,
                source_meta=source_meta,
                context_contents=context_contents,
                tool_registry=tools,
            )
        except Exception as exc:
            self.events.task_failed(task_id, str(exc))
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=str(exc))
            return

        summary = ingest_result.summary
        if ingest_result.changed_pages:
            self.events.progress(task_id, "writing_vault", "正在写入知识库", "已更新相关 wiki 页面。")
        if ingest_result.journal_entry:
            self.events.progress(task_id, "recording_changes", "正在记录变更", "已生成可回退的 Change Journal。")
        self.store.update_task(
            task_id,
            status=TaskStatus.COMPLETED,
            summary=summary,
            affected_files=ingest_result.changed_pages,
            output=ingest_result.model_dump(mode="json"),
        )
        self.events.emit(
            task_id,
            EventType.INGEST_COMPLETED,
            {
                "source_path": ingest_result.source_meta.path,
                "changed_pages": ingest_result.changed_pages,
                "journal_entry_id": ingest_result.journal_entry.id if ingest_result.journal_entry else None,
            },
        )
        self.events.task_completed(
            task_id,
            summary=summary,
            answer=summary,
            journal_entry_id=ingest_result.journal_entry.id if ingest_result.journal_entry else None,
        )
        self.events.progress(task_id, "completed", "已完成")

    def _execute_agent(
        self,
        *,
        task_id: str,
        request: TaskCreateRequest,
        vault: Vault,
        context_contents: dict[str, str],
    ):
        if self.runner.can_run(self.config):
            tools = VaultToolRegistry(vault=vault, events=self.events, task_id=task_id)
            try:
                self.events.progress(task_id, "reading_vault", "正在读取知识库", "正在让 Agent 查找相关记忆和页面。")
                agent_result = self.runner.run_task(
                    config=self.config,
                    events=self.events,
                    task_id=task_id,
                    conversation_id=request.conversation_id or task_id,
                    user_input=request.user_input,
                    context_contents=context_contents,
                    tool_registry=tools,
                )
            except Exception as exc:
                self.events.task_failed(task_id, str(exc), fallback="read_only_query")
                self.events.progress(task_id, "reading_vault", "正在读取知识库", "SDK 失败，正在使用本地只读 query fallback。")
                query_result = run_read_only_query(vault, request.user_input, mode=request.mode)
                self._persist_query_result(task_id, query_result)
                return

            if agent_result.affected_files:
                self.events.progress(task_id, "writing_vault", "正在写入知识库", "已更新 vault 文件。")
            if agent_result.journal_entry:
                self.events.progress(task_id, "recording_changes", "正在记录变更", "已生成可回退的 Change Journal。")
            self.store.update_task(
                task_id,
                status=TaskStatus.COMPLETED,
                summary=agent_result.summary,
                affected_files=agent_result.affected_files,
                output=agent_result.model_dump(mode="json"),
            )
            self.events.task_completed(
                task_id,
                summary=agent_result.summary,
                answer=agent_result.answer or agent_result.summary,
                journal_entry_id=agent_result.journal_entry.id if agent_result.journal_entry else None,
            )
            self.events.progress(task_id, "completed", "已完成")
            return

        self.events.progress(task_id, "reading_vault", "正在读取知识库", "正在使用本地只读 query fallback。")
        query_result = run_read_only_query(vault, request.user_input, mode=request.mode)
        self._persist_query_result(task_id, query_result)

    def _execute_source_intake(
        self,
        *,
        task_id: str,
        request: TaskCreateRequest,
        vault: Vault,
        context_contents: dict[str, str],
    ):
        self.events.progress(task_id, "organizing_source", "正在整理资料", "正在把文件规范化为 source。")
        self.events.emit(task_id, EventType.SOURCE_INTAKE_STARTED, {"selected_paths": request.selected_paths})
        try:
            if len(request.selected_paths) != 1:
                raise SourceIntakeError("Capture requires exactly one selected path in Phase 3.")
            intake_result = run_source_intake(vault, request.selected_paths[0])
        except SourceIntakeError as exc:
            self.events.task_failed(task_id, str(exc))
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=str(exc))
            return

        self.events.emit(
            task_id,
            EventType.SOURCE_INTAKE_COPIED,
            {"asset_path": intake_result.asset_path, "reused": intake_result.reused},
        )
        self.events.emit(
            task_id,
            EventType.SOURCE_INTAKE_NORMALIZED,
            {
                "source_path": intake_result.source_path,
                "format": intake_result.format.value,
                "hash": intake_result.hash,
            },
        )
        self.events.progress(
            task_id,
            "organizing_source",
            "正在转换为 Markdown Source",
            f"已生成 canonical source：{intake_result.source_path}",
        )
        self.events.emit(
            task_id,
            EventType.SOURCE_MANIFEST_UPDATED,
            {
                "hash": intake_result.hash,
                "source_path": intake_result.source_path,
                "reused": intake_result.reused,
            },
        )
        if self.runner.can_run(self.config):
            self._compile_intake_source(
                task_id=task_id,
                request=request,
                vault=vault,
                context_contents=context_contents,
                intake_result=intake_result,
            )
            return

        summary = (
            f"已复用 source：{intake_result.source_path}。SDK runtime 未配置，尚未编译进 wiki。"
            if intake_result.reused
            else f"已生成 source：{intake_result.source_path}。SDK runtime 未配置，尚未编译进 wiki。"
        )
        self.store.update_task(
            task_id,
            status=TaskStatus.COMPLETED,
            summary=summary,
            output={
                **intake_result.model_dump(mode="json"),
                "summary": summary,
                "answer": summary,
                "intake": intake_result.model_dump(mode="json"),
            },
        )
        self.events.task_completed(task_id, summary=summary, answer=summary)
        self.events.progress(task_id, "completed", "已完成")

    def _compile_intake_source(self, *, task_id: str, request: TaskCreateRequest, vault: Vault, context_contents, intake_result):
        try:
            self.events.progress(
                task_id,
                "reading_vault",
                "正在读取知识库",
                "正在读取索引和相关页面，准备把 source 编译进 wiki。",
            )
            source_meta = read_source_meta(vault, intake_result.source_path)
            tools = VaultToolRegistry(vault=vault, events=self.events, task_id=task_id)
            self.events.emit(
                task_id,
                EventType.INGEST_STARTED,
                {"source_path": intake_result.source_path, "trigger": "source_intake_pipeline"},
            )
            self.events.progress(
                task_id,
                "organizing_source",
                "正在编译进 Wiki",
                "正在让 Agent 更新 source、concept、entity、domain、index 和 log。",
            )
            ingest_result = self.runner.run_ingest(
                config=self.config,
                events=self.events,
                task_id=task_id,
                conversation_id=request.conversation_id or task_id,
                source_path=intake_result.source_path,
                source_meta=source_meta,
                context_contents=context_contents,
                tool_registry=tools,
            )
        except Exception as exc:
            summary = f"已生成 source：{intake_result.source_path}；但 wiki ingest 失败：{exc}"
            self.events.task_failed(task_id, summary)
            self.store.update_task(
                task_id,
                status=TaskStatus.FAILED,
                summary=summary,
                output={
                    **intake_result.model_dump(mode="json"),
                    "summary": summary,
                    "answer": summary,
                    "intake": intake_result.model_dump(mode="json"),
                },
            )
            return

        if ingest_result.changed_pages:
            self.events.progress(task_id, "writing_vault", "正在写入知识库", "已更新相关 wiki 页面。")
        if ingest_result.journal_entry:
            self.events.progress(task_id, "recording_changes", "正在记录变更", "已生成可回退的 Change Journal。")
        summary = (
            f"已记录并编译《{ingest_result.source_title}》。"
            f" Source：{intake_result.source_path}；"
            f"更新 {len(ingest_result.changed_pages)} 个 wiki 文件。"
        )
        self.store.update_task(
            task_id,
            status=TaskStatus.COMPLETED,
            summary=summary,
            affected_files=ingest_result.changed_pages,
            output={
                **intake_result.model_dump(mode="json"),
                "summary": summary,
                "answer": summary,
                "intake": intake_result.model_dump(mode="json"),
                "ingest": ingest_result.model_dump(mode="json"),
            },
        )
        self.events.emit(
            task_id,
            EventType.INGEST_COMPLETED,
            {
                "source_path": ingest_result.source_meta.path,
                "changed_pages": ingest_result.changed_pages,
                "journal_entry_id": ingest_result.journal_entry.id if ingest_result.journal_entry else None,
            },
        )
        self.events.task_completed(
            task_id,
            summary=summary,
            answer=summary,
            journal_entry_id=ingest_result.journal_entry.id if ingest_result.journal_entry else None,
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

    def _persist_query_result(self, task_id: str, query_result):
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
        self.events.progress(task_id, "completed", "已完成")


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
