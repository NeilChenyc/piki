from __future__ import annotations

import threading

from agent_service.application.events import EventPublisher
from agent_service.application.task_executor import TaskExecutor
from agent_service.application.task_router import TaskRouter
from agent_service.models import TaskCreateRequest, TaskCreateResponse, TaskStatus
from agent_service.store import SQLiteStore
from agent_service.vault import Vault, VaultAccessError


class TaskService:
    def __init__(
        self,
        *,
        store: SQLiteStore,
        events: EventPublisher,
        router: TaskRouter,
        executor: TaskExecutor,
        runner_status,
    ):
        self.store = store
        self.events = events
        self.router = router
        self.executor = executor
        self.runner_status = runner_status

    def create_task(self, request: TaskCreateRequest) -> TaskCreateResponse:
        vault = Vault(request.vault_path)
        vault.validate()
        plan = self.router.plan(request)
        task = self.store.create_task(
            task_kind=plan.task_kind,
            risk_level=plan.risk_level,
            vault_path=str(vault.root),
            user_input=request.user_input,
            status=TaskStatus.RUNNING,
            summary=plan.summary,
        )
        self.events.task_created(
            task.id,
            {
                "task_id": task.id,
                "vault_path": str(vault.root),
                "runner_available": self.runner_status.available,
            },
        )
        self.events.emit(
            task.id,
            "intent.received",
            {
                "task_kind": plan.task_kind.value,
                "risk_level": plan.risk_level.value,
                "selected_paths": request.selected_paths,
                "action_context": request.action_context,
                "mode": request.mode,
                "tool_context_policy": "all vault tools are available to the agent; selected external files are read-allowlisted; raw/wiki changes are journaled only when write tools change content",
                "reason": plan.summary,
            },
        )
        if request.async_mode:
            threading.Thread(
                target=self.executor.execute,
                kwargs={
                    "task_id": task.id,
                    "request": request,
                    "plan": plan,
                },
                daemon=True,
            ).start()
        else:
            self.executor.execute(task_id=task.id, request=request, plan=plan)

        return TaskCreateResponse(
            task_id=task.id,
            status=self.store.get_task(task.id).status,
            events_url=f"/tasks/{task.id}/events",
        )

    def get_task(self, task_id: str):
        return self.store.get_task(task_id)
