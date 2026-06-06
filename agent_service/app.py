from __future__ import annotations

from fastapi import FastAPI

from agent_service.api.routes import (
    register_approval_routes,
    register_health_routes,
    register_ingest_queue_routes,
    register_journal_routes,
    register_lint_routes,
    register_source_routes,
    register_task_routes,
)
from agent_service.application.event_stream import EventStreamService
from agent_service.application.events import EventPublisher
from agent_service.application.maintenance import (
    ApprovalService,
    IngestQueueService,
    JournalService,
    LintService,
    SourceService,
)
from agent_service.application.task_executor import TaskExecutor
from agent_service.application.task_router import TaskRouter
from agent_service.application.task_service import TaskService
from agent_service.config import ServiceConfig, load_environment
from agent_service.runtime import PikiWikiAgentRunner
from agent_service.store import SQLiteStore


def create_app(config: ServiceConfig | None = None, store: SQLiteStore | None = None) -> FastAPI:
    load_environment()
    service_config = config or ServiceConfig()
    sqlite_store = store or SQLiteStore(service_config.db_path)
    runner = PikiWikiAgentRunner()
    events = EventPublisher(sqlite_store)

    task_executor = TaskExecutor(
        config=service_config,
        store=sqlite_store,
        events=events,
        runner=runner,
    )
    task_service = TaskService(
        store=sqlite_store,
        events=events,
        router=TaskRouter(),
        executor=task_executor,
        runner_status=runner.status,
    )
    event_stream = EventStreamService(sqlite_store)
    journal_service = JournalService(sqlite_store, events)
    source_service = SourceService(sqlite_store, events)
    ingest_queue_service = IngestQueueService(sqlite_store, events)
    lint_service = LintService(sqlite_store, events)
    approval_service = ApprovalService(sqlite_store, events)

    app = FastAPI(title="Piki Local Agent Service")
    app.state.store = sqlite_store
    app.state.runner = runner
    app.state.events = events
    app.state.task_service = task_service

    register_health_routes(app, config=service_config, runner=runner)
    register_task_routes(app, task_service=task_service, event_stream=event_stream, config=service_config)
    register_journal_routes(app, journal_service=journal_service)
    register_source_routes(app, source_service=source_service)
    register_ingest_queue_routes(app, ingest_queue_service=ingest_queue_service)
    register_lint_routes(app, lint_service=lint_service)
    register_approval_routes(app, approval_service=approval_service)
    return app


app = create_app()
