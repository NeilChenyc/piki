from __future__ import annotations

from fastapi import FastAPI, HTTPException

from agent_service.application.maintenance import LintService
from agent_service.models import LintFixRequest
from agent_service.vault import VaultAccessError


def register_lint_routes(app: FastAPI, *, lint_service: LintService):
    @app.post("/lint/fix")
    def fix_lint(request: LintFixRequest):
        try:
            return lint_service.fix(request)
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
