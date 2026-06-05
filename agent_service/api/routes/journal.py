from __future__ import annotations

from fastapi import FastAPI, HTTPException

from agent_service.application.maintenance import JournalService
from agent_service.models import RollbackRequest


def register_journal_routes(app: FastAPI, *, journal_service: JournalService):
    @app.get("/journal/recent")
    def recent_journal(limit: int = 20, vault_path: str | None = None):
        return journal_service.recent(limit=limit, vault_path=vault_path)

    @app.post("/journal/{journal_entry_id}/rollback")
    def rollback_journal_entry(journal_entry_id: str, request: RollbackRequest | None = None):
        try:
            return journal_service.rollback(journal_entry_id, request)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
