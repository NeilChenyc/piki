from __future__ import annotations

import base64
from dataclasses import dataclass
import threading
from pathlib import Path
from typing import Any, Callable

from agent_service.diagnostics import runtime_log
from agent_service.application.event_stream import EventStreamService
from agent_service.application.events import EventPublisher
from agent_service.application.maintenance import ApprovalService, IngestQueueService, JournalService, LintService, SourceService
from agent_service.application.task_service import TaskService
from agent_service.config import ServiceConfig, load_environment
from agent_service.models import (
    IngestQueueEnqueueRequest,
    IngestQueueProcessRequest,
    LintFixRequest,
    TaskCreateRequest,
    TaskInputRequest,
    TaskEvent,
)
from agent_service.runtime.runner import PikiWikiAgentRunner
from agent_service.store import SQLiteStore


@dataclass
class RuntimeWorker:
    db_path: Path
    runtime_config_path: Path
    staging_root: Path
    enable_agent_runtime: bool = False
    notify: Callable[[TaskEvent], None] | None = None

    def __post_init__(self) -> None:
        load_environment()
        runtime_log(
            "worker",
            "init",
            extra={
                "db_path": self.db_path,
                "runtime_config_path": self.runtime_config_path,
                "staging_root": self.staging_root,
                "enable_agent_runtime": self.enable_agent_runtime,
            },
        )
        self._events_condition = threading.Condition()
        self.config = ServiceConfig(
            db_path=self.db_path,
            runtime_config_path=self.runtime_config_path,
            staging_root=self.staging_root,
            enable_agent_runtime=self.enable_agent_runtime,
        )
        self.store = SQLiteStore(self.config.db_path)
        self.runner = PikiWikiAgentRunner()
        self.event_publisher = EventPublisher(self.store, on_emit=self._emit_notification)
        self.task_service = TaskService(
            store=self.store,
            events=self._events,
            router=self._router,
            executor=self._executor,
            runner_status=self.runner.status,
        )
        self.event_stream = EventStreamService(self.store)
        self.journal_service = JournalService(self.store, self._events)
        self.source_service = SourceService(self.store, self._events)
        self.ingest_queue_service = IngestQueueService(self.store, self._events)
        self.lint_service = LintService(self.store, self._events)
        self.approval_service = ApprovalService(self.store, self._events)
        runtime_log(
            "worker",
            "ready",
            extra={
                "runner_available": self.runner.status.available,
                "agent_runtime_configured": self.config.agent_runtime_configured,
                "model": self.config.agent_model or "<unset>",
                "base_url": self.config.anthropic_base_url or "<unset>",
            },
        )

    def call(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        runtime_log("worker", "call_start", extra={"method": method, "params": sorted(params.keys())})
        if method == "health":
            result = self._health()
            runtime_log(
                "worker",
                "call_finish",
                extra={
                    "method": "health",
                    "ok": result.get("ok"),
                    "runner_available": result.get("runner_available"),
                    "agent_runtime_configured": result.get("agent_runtime_configured"),
                },
            )
            return result
        if method == "get_runtime_config":
            return self.config.runtime_config_response()
        if method == "update_runtime_config":
            return self.config.update_runtime_config(
                agent_model=params.get("agent_model"),
                anthropic_base_url=params.get("anthropic_base_url"),
                api_key=params.get("api_key"),
                clear_api_key=bool(params.get("clear_api_key", False)),
            )
        if method == "smoke_test_runtime":
            return self._smoke_test_runtime()
        if method == "create_task":
            request = TaskCreateRequest.model_validate(params)
            result = self.task_service.create_task(request)
            runtime_log(
                "worker",
                "call_finish",
                extra={
                    "method": "create_task",
                    "task_id": result.task_id,
                    "status": result.status,
                    "async_mode": request.async_mode,
                },
            )
            return result.model_dump(mode="json")
        if method == "get_task":
            return self.task_service.get_task(params["task_id"]).model_dump(mode="json")
        if method == "submit_task_input":
            request = TaskInputRequest.model_validate({"message": params["message"]})
            return self.task_service.submit_task_input(params["task_id"], request).model_dump(mode="json")
        if method == "cancel_task":
            return self.task_service.cancel_task(params["task_id"]).model_dump(mode="json")
        if method == "upload_file":
            return self._upload_file(params)
        if method == "recent_journal":
            return self.journal_service.recent(
                limit=int(params.get("limit", 20)),
                vault_path=params.get("vault_path"),
            )
        if method == "rollback":
            return self.journal_service.rollback(params["entry_id"], None).model_dump(mode="json")
        if method == "task_events":
            result = self.task_events(params["task_id"], params.get("cursor"))
            runtime_log(
                "worker",
                "call_finish",
                extra={
                    "method": "task_events",
                    "task_id": params["task_id"],
                    "events": len(result.get("events", [])),
                },
            )
            return result
        if method == "list_ingest_queue":
            return self.ingest_queue_service.list(
                status=params.get("status"),
                vault_path=params.get("vault_path"),
                limit=int(params.get("limit", 100)),
            )
        if method == "enqueue_ingest":
            return self.ingest_queue_service.enqueue(
                IngestQueueEnqueueRequest.model_validate(
                    {
                        "vault_path": params["vault_path"],
                        "selected_paths": params.get("paths", []),
                    }
                )
            ).model_dump(mode="json")
        if method == "process_ingest_queue":
            return self.ingest_queue_service.process(
                IngestQueueProcessRequest.model_validate(
                    {
                        "vault_path": params.get("vault_path") or None,
                    }
                )
            ).model_dump(mode="json")
        if method == "run_lint":
            from agent_service.system import run_wiki_lint
            from agent_service.vault import Vault

            vault = Vault(params["vault_path"])
            vault.validate()
            return run_wiki_lint(vault).model_dump(mode="json")
        if method == "fix_lint":
            return self.lint_service.fix(
                LintFixRequest.model_validate(
                    {
                        "vault_path": params["vault_path"],
                        "issue_ids": params.get("issue_ids", []),
                    }
                )
            ).model_dump(mode="json")
        raise ValueError(f"Unknown runtime method: {method}")

    def task_events(self, task_id: str, cursor: str | None = None) -> dict[str, Any]:
        cursor_key = self._decode_cursor(cursor)
        events = self._events_after(task_id, cursor_key)
        runtime_log(
            "worker",
            "task_events_poll",
            extra={"task_id": task_id, "cursor": cursor or "<none>", "events_before_wait": len(events)},
        )
        if not events:
            runtime_log("worker", "task_events_wait", extra={"task_id": task_id, "timeout_s": 0.8})
            with self._events_condition:
                self._events_condition.wait(timeout=0.8)
            events = self._events_after(task_id, cursor_key)
            runtime_log(
                "worker",
                "task_events_resume",
                extra={"task_id": task_id, "events_after_wait": len(events)},
            )
        return {
            "events": [event.model_dump(mode="json") for event in events],
            "cursor": json.dumps(
                {"created_at": events[-1].created_at, "id": events[-1].id},
                ensure_ascii=False,
            ) if events else cursor,
            "has_more": False,
        }

    def events(self, task_id: str):
        for event in self.store.list_events(task_id):
            yield event.model_dump(mode="json")

    def _events_after(self, task_id: str, cursor_key: dict[str, Any] | None) -> list:
        events = self.store.list_events(task_id)
        if not cursor_key:
            return events
        cursor_created_at = cursor_key.get("created_at", "")
        cursor_id = cursor_key.get("id", "")
        return [
            event
            for event in events
            if (event.created_at, event.id) > (cursor_created_at, cursor_id)
        ]

    def _decode_cursor(self, cursor: str | None) -> dict[str, Any] | None:
        if not cursor:
            return None
        try:
            value = json.loads(cursor)
        except json.JSONDecodeError:
            return None
        return value if isinstance(value, dict) else None

    @property
    def _events(self):
        return self.event_publisher

    @property
    def _router(self):
        from agent_service.application.task_router import TaskRouter

        return TaskRouter()

    @property
    def _executor(self):
        from agent_service.application.task_executor import TaskExecutor

        return TaskExecutor(
            config=self.config,
            store=self.store,
            events=self._events,
            runner=self.runner,
        )

    def _health(self) -> dict[str, Any]:
        return {
            "ok": True,
            "runner_available": self.runner.status.available,
            "runner_detail": self.runner.status.detail,
            "provider": self.config.runtime_provider,
            "anthropic_api_key_configured": self.config.api_key_configured,
            "anthropic_base_url": self.config.anthropic_base_url or None,
            "agent_model": self.config.agent_model or None,
            "agent_runtime_enabled": self.config.enable_agent_runtime,
            "agent_runtime_configured": self.config.agent_runtime_configured,
            "claude_config_dir": str(self.config.claude_config_dir.expanduser().resolve()),
        }

    def _smoke_test_runtime(self) -> dict[str, Any]:
        result = self.runner.smoke_test(config=self.config)
        return {
            "ok": result.ok,
            "output": result.output,
            "error": result.error,
            "runner_available": self.runner.status.available,
            "provider": self.config.runtime_provider,
            "agent_runtime_configured": self.config.agent_runtime_configured,
            "anthropic_base_url": self.config.anthropic_base_url or None,
            "agent_model": self.config.agent_model or None,
        }

    def _upload_file(self, params: dict[str, Any]) -> dict[str, Any]:
        target_root = self.config.staging_root.expanduser().resolve() / "uploads" / params.get("filename", "attachment").replace("/", "_")
        target_root.mkdir(parents=True, exist_ok=True)
        safe_name = Path(params["filename"]).name
        target = target_root / safe_name
        content = base64.b64decode(params["content_base64"])
        target.write_bytes(content)
        runtime_log(
            "worker",
            "upload_file",
            extra={"filename": safe_name, "buffered_path": str(target), "size_bytes": target.stat().st_size},
        )
        return {
            "filename": safe_name,
            "buffered_path": str(target),
            "size_bytes": target.stat().st_size,
            "original_path": params.get("original_path"),
        }

    def _notify_events(self) -> None:
        with self._events_condition:
            self._events_condition.notify_all()

    def _emit_notification(self, event: TaskEvent) -> None:
        runtime_log("worker", "event_emitted", extra={"task_id": event.task_id, "type": event.type})
        self._notify_events()
        if self.notify is not None:
            self.notify(event)
