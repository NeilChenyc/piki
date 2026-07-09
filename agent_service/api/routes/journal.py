from __future__ import annotations

from fastapi import FastAPI, HTTPException

from agent_service.application.maintenance import JournalService


def register_journal_routes(app: FastAPI, *, journal_service: JournalService):
    @app.get("/journal/recent")
    def recent_journal(limit: int = 20, vault_path: str | None = None):
        return journal_service.recent(limit=limit, vault_path=vault_path)

    @app.post("/journal/{journal_entry_id}/rollback")
    def rollback_journal_entry(journal_entry_id: str):
        raise HTTPException(
            status_code=410,
            detail="Rollback has been removed; journal entries are write activity records.",
        )
