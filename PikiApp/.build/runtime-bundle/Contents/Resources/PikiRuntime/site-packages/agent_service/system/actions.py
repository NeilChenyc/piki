from __future__ import annotations

from agent_service.application.events import EventPublisher
from agent_service.models import EventType, TaskCreateRequest, TaskStatus
from agent_service.store import SQLiteStore
from agent_service.system.lint import run_wiki_lint
from agent_service.vault import Vault


class DeterministicActionExecutor:
    def __init__(self, *, store: SQLiteStore, events: EventPublisher):
        self.store = store
        self.events = events

    def can_handle(self, request: TaskCreateRequest) -> bool:
        action = str(request.action_context.get("action") or "").strip()
        return action == "run_lint"

    def execute(self, *, task_id: str, request: TaskCreateRequest) -> bool:
        action = str(request.action_context.get("action") or "").strip()
        if action != "run_lint":
            return False

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
        return True
