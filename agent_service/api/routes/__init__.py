from agent_service.api.routes.approvals import register_approval_routes
from agent_service.api.routes.health import register_health_routes
from agent_service.api.routes.inspirations import register_inspiration_routes
from agent_service.api.routes.journal import register_journal_routes
from agent_service.api.routes.lint import register_lint_routes
from agent_service.api.routes.sources import register_source_routes
from agent_service.api.routes.tasks import register_task_routes

__all__ = [
    "register_approval_routes",
    "register_health_routes",
    "register_inspiration_routes",
    "register_journal_routes",
    "register_lint_routes",
    "register_source_routes",
    "register_task_routes",
]
