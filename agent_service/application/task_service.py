from __future__ import annotations

import threading

from agent_service.application.events import EventPublisher
from agent_service.application.task_control import TaskRunControl
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
        self._run_controls: dict[str, TaskRunControl] = {}
        self._run_controls_lock = threading.Lock()

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
        run_control = TaskRunControl()
        self._register_run_control(task.id, run_control)
        if request.async_mode:
            threading.Thread(
                target=self._execute_with_cleanup,
                kwargs={
                    "task_id": task.id,
                    "request": request,
                    "plan": plan,
                    "run_control": run_control,
                },
                daemon=True,
            ).start()
        else:
            self._execute_with_cleanup(task_id=task.id, request=request, plan=plan, run_control=run_control)

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
        run_control = TaskRunControl()
        self._register_run_control(task_id, run_control)
        try:
            self.executor.resume_input(task_id=task_id, message=request.message, run_control=run_control)
        finally:
            self._unregister_run_control(task_id)
        return self.store.get_task(task_id)

    def cancel_task(self, task_id: str):
        task = self.store.get_task(task_id)
        if task.status != TaskStatus.RUNNING:
            raise ValueError(f"Task is not running: {task.status}")
        run_control = self._get_run_control(task_id)
        if run_control is None:
            raise ValueError("Task cannot be cancelled right now.")
        run_control.request_cancel()
        self.store.update_task(task_id, status=TaskStatus.CANCELLED, summary="任务已停止。")
        self.events.task_cancelled(task_id, "任务已停止。")
        return self.store.get_task(task_id)

    def _execute_with_cleanup(self, *, task_id: str, request: TaskCreateRequest, plan, run_control: TaskRunControl):
        try:
            self.executor.execute(task_id=task_id, request=request, plan=plan, run_control=run_control)
        except Exception as exc:
            error = str(exc) or exc.__class__.__name__
            self.events.task_failed(task_id, error)
            self.store.update_task(task_id, status=TaskStatus.FAILED, summary=error)
        finally:
            self._unregister_run_control(task_id)


    def _register_run_control(self, task_id: str, run_control: TaskRunControl) -> None:
        with self._run_controls_lock:
            self._run_controls[task_id] = run_control

    def _get_run_control(self, task_id: str) -> TaskRunControl | None:
        with self._run_controls_lock:
            return self._run_controls.get(task_id)

    def _unregister_run_control(self, task_id: str) -> None:
        with self._run_controls_lock:
            self._run_controls.pop(task_id, None)
