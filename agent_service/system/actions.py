from __future__ import annotations

from agent_service.application.events import EventPublisher
from agent_service.models import EventType, TaskCreateRequest, TaskStatus
from agent_service.store import SQLiteStore
from agent_service.system.source_scan import scan_sources_for_updates
from agent_service.system.lint import run_wiki_lint
from agent_service.vault import Vault
from agent_service.workflows.podcast import PodcastWorkflowError, run_podcast_transcription


class DeterministicActionExecutor:
    def __init__(self, *, store: SQLiteStore, events: EventPublisher):
        self.store = store
        self.events = events

    def can_handle(self, request: TaskCreateRequest) -> bool:
        action = str(request.action_context.get("action") or "").strip()
        return action in {"run_lint", "podcast_transcribe"}

    def execute(self, *, task_id: str, request: TaskCreateRequest, return_payload: bool = False):
        action = str(request.action_context.get("action") or "").strip()
        if action == "run_lint":
            vault = Vault(request.vault_path)
            vault.validate()
            self.events.progress(task_id, "reading_wiki", "正在阅读 Wiki", "正在执行系统 lint 检查。")
            self.events.emit(task_id, EventType.LINT_STARTED, {"vault_path": str(vault.root)})
            result = run_wiki_lint(vault)
            self.events.emit(task_id, EventType.LINT_COMPLETED, result.model_dump(mode="json"))
            self.store.update_task(
                task_id,
                status=TaskStatus.COMPLETED,
                summary=f"检查完成：发现 {len(result.issues)} 个问题。",
                output={
                    "summary": f"检查完成：发现 {len(result.issues)} 个问题。",
                    "lint_result": result.model_dump(mode="json"),
                    "action_context": dict(request.action_context or {}),
                    "selected_paths": list(request.selected_paths),
                    "conversation_id": request.conversation_id or task_id,
                },
            )
            self.events.task_completed(task_id, summary="lint completed", answer="lint completed")
            self.events.progress(task_id, "completed", "已完成")
            return (True, None) if return_payload else True

        if action == "podcast_transcribe":
            vault = Vault(request.vault_path)
            vault.validate()
            podcast_url = str(request.action_context.get("podcast_url") or "").strip()
            try:
                result = run_podcast_transcription(
                    vault=vault,
                    episode_url=podcast_url,
                    events=self.events,
                    task_id=task_id,
                )
            except PodcastWorkflowError as exc:
                self.store.update_task(
                    task_id,
                    status=TaskStatus.FAILED,
                    summary=str(exc),
                    output={
                        "summary": str(exc),
                        "action_context": dict(request.action_context or {}),
                        "selected_paths": list(request.selected_paths),
                        "conversation_id": request.conversation_id or task_id,
                    },
                )
                self.events.task_failed(task_id, str(exc))
                return (True, None) if return_payload else True

            rescan = scan_sources_for_updates(vault=vault, store=self.store)
            self.events.emit(task_id, EventType.SOURCE_RESCAN_COMPLETED, rescan.model_dump(mode="json"))
            if return_payload:
                return True, result
            summary = f"播客已完成转录，并生成来源页：{result['source_path']}。"
            self.store.update_task(
                task_id,
                status=TaskStatus.COMPLETED,
                summary=summary,
                affected_files=[result["source_path"]],
                output={
                    "summary": summary,
                    "answer": summary,
                    "podcast_result": result,
                    "action_context": dict(request.action_context or {}),
                    "selected_paths": list(request.selected_paths),
                    "conversation_id": request.conversation_id or task_id,
                },
            )
            self.events.task_completed(task_id, summary=summary, answer=summary)
            self.events.progress(task_id, "completed", "已完成")
            return (True, result) if return_payload else True

        if action != "run_lint":
            return (False, None) if return_payload else False
        return (False, None) if return_payload else False
