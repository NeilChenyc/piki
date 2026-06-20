from __future__ import annotations

from fastapi import FastAPI, HTTPException

from agent_service.application.maintenance import IngestQueueService
from agent_service.models import IngestQueueEnqueueRequest, IngestQueueProcessRequest
from agent_service.vault import VaultAccessError


def register_ingest_queue_routes(app: FastAPI, *, ingest_queue_service: IngestQueueService):
    @app.post("/ingest-queue/enqueue")
    def enqueue_ingest_queue(request: IngestQueueEnqueueRequest):
        try:
            return ingest_queue_service.enqueue(request)
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.get("/ingest-queue")
    def list_ingest_queue(status: str | None = None, vault_path: str | None = None, limit: int = 100):
        return ingest_queue_service.list(status=status, vault_path=vault_path, limit=limit)

    @app.post("/ingest-queue/process")
    def process_ingest_queue_api(request: IngestQueueProcessRequest):
        try:
            return ingest_queue_service.process(request)
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.post("/ingest-queue/{item_id}/retry")
    def retry_ingest_queue(item_id: str):
        try:
            return ingest_queue_service.retry(item_id)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.post("/ingest-queue/{item_id}/cancel")
    def cancel_ingest_queue(item_id: str):
        try:
            return ingest_queue_service.cancel(item_id)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
