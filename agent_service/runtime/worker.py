from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from agent_service.application.event_stream import EventStreamService
from agent_service.application.maintenance import ApprovalService, IngestQueueService, JournalService, LintService, SourceService
from agent_service.application.task_service import TaskService
from agent_service.config import ServiceConfig, load_environment
from agent_service.models import (
    IngestQueueEnqueueRequest,
    IngestQueueProcessRequest,
    LintFixRequest,
    TaskCreateRequest,
    TaskInputRequest,
)
from agent_service.runtime.runner import PikiWikiAgentRunner
from agent_service.store import SQLiteStore


@dataclass
class RuntimeWorker:
    db_path: Path
    runtime_config_path: Path
    staging_root: Path
    enable_agent_runtime: bool = False

    def __post_init__(self) -> None:
        load_environment()
        self.config = ServiceConfig(
            db_path=self.db_path,
            runtime_config_path=self.runtime_config_path,
            staging_root=self.staging_root,
            enable_agent_runtime=self.enable_agent_runtime,
        )
        self.store = SQLiteStore(self.config.db_path)
        self.runner = PikiWikiAgentRunner()
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

    def call(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        if method == "health":
            return self._health()
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
            return list(self.events(params["task_id"]))
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

    def events(self, task_id: str):
        for event in self.store.list_events(task_id):
            yield event.model_dump(mode="json")

    @property
    def _events(self):
        from agent_service.application.events import EventPublisher

        return EventPublisher(self.store)

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
        return {
            "filename": safe_name,
            "buffered_path": str(target),
            "size_bytes": target.stat().st_size,
            "original_path": params.get("original_path"),
        }

def run_stdio() -> int:
    import sys

    worker = RuntimeWorker(
        db_path=Path(".piki/agent_service.sqlite3"),
        runtime_config_path=Path(".piki/runtime-config.json"),
        staging_root=Path(".piki/task-staging"),
    )
    for line in iter(sys.stdin.readline, ""):
        if not line.strip():
            continue
        request = json.loads(line)
        result = worker.call(request["method"], request.get("params", {}))
        print(json.dumps({"kind": "response", "id": request["id"], "result": result, "error": None}, ensure_ascii=False))
        sys.stdout.flush()
    return 0
