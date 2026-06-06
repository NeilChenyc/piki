from __future__ import annotations

import threading

from agent_service.application.events import EventPublisher
from agent_service.application.task_executor import TaskExecutor
from agent_service.application.task_router import TaskRouter
from agent_service.models import TaskCreateRequest, TaskCreateResponse, TaskInputRequest, TaskStatus
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
                "tool_context_policy": "Claude built-in Read/Write/Edit/Glob/Grep/Bash/AskUserQuestion are available; selected external files are staged read-only; raw/wiki changes are journaled after Write/Edit change content",
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

    def submit_task_input(self, task_id: str, request: TaskInputRequest):
        task = self.store.get_task(task_id)
        if task.status != TaskStatus.INPUT_REQUIRED:
            raise ValueError(f"Task is not waiting for input: {task.status}")
        self.executor.resume_input(task_id=task_id, message=request.message)
        return self.store.get_task(task_id)
