from __future__ import annotations

from fastapi import FastAPI, HTTPException

from agent_service.application.maintenance import SourceService
from agent_service.models import SourceRescanRequest
from agent_service.vault import VaultAccessError


def register_source_routes(app: FastAPI, *, source_service: SourceService):
    @app.post("/sources/rescan")
    def rescan_sources(request: SourceRescanRequest):
        try:
            return source_service.rescan(request)
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.get("/update-queue")
    def update_queue(status: str | None = "pending", limit: int = 100):
        return source_service.update_queue(status=status, limit=limit)
