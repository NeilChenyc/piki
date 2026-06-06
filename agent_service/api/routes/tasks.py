from __future__ import annotations

import shutil
import uuid
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi import File, Form, UploadFile
from fastapi.responses import StreamingResponse

from agent_service.application.event_stream import EventStreamService
from agent_service.config import ServiceConfig
from agent_service.application.task_service import TaskService
from agent_service.models import BufferedUploadResponse, TaskCreateRequest, TaskCreateResponse, TaskInputRequest
from agent_service.vault import VaultAccessError


def register_task_routes(
    app: FastAPI,
    *,
    task_service: TaskService,
    event_stream: EventStreamService,
    config: ServiceConfig,
):
    @app.post("/tasks", response_model=TaskCreateResponse)
    def create_task(request: TaskCreateRequest):
        try:
            return task_service.create_task(request)
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.post("/uploads", response_model=BufferedUploadResponse)
    def upload_file(
        file: UploadFile = File(...),
        original_path: str | None = Form(default=None),
    ):
        uploads_root = config.staging_root.expanduser().resolve() / "uploads" / uuid.uuid4().hex
        uploads_root.mkdir(parents=True, exist_ok=True)
        safe_name = Path(file.filename or "attachment.bin").name
        target = uploads_root / safe_name
        with target.open("wb") as handle:
            shutil.copyfileobj(file.file, handle)
        size_bytes = target.stat().st_size
        return BufferedUploadResponse(
            filename=safe_name,
            buffered_path=str(target),
            size_bytes=size_bytes,
            original_path=original_path,
        )

    @app.get("/tasks/{task_id}")
    def get_task(task_id: str):
        try:
            return task_service.get_task(task_id)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
    
    @app.post("/tasks/{task_id}/input")
    def submit_task_input(task_id: str, request: TaskInputRequest):
        try:
            return task_service.submit_task_input(task_id, request)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.get("/tasks/{task_id}/events")
    def task_events(task_id: str):
        try:
            task_service.get_task(task_id)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return StreamingResponse(event_stream.task_sse(task_id), media_type="text/event-stream")
