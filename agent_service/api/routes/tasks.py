from __future__ import annotations

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse

from agent_service.application.event_stream import EventStreamService
from agent_service.application.task_service import TaskService
from agent_service.models import TaskCreateRequest, TaskCreateResponse
from agent_service.vault import VaultAccessError


def register_task_routes(app: FastAPI, *, task_service: TaskService, event_stream: EventStreamService):
    @app.post("/tasks", response_model=TaskCreateResponse)
    def create_task(request: TaskCreateRequest):
        try:
            return task_service.create_task(request)
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.get("/tasks/{task_id}")
    def get_task(task_id: str):
        try:
            return task_service.get_task(task_id)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    @app.get("/tasks/{task_id}/events")
    def task_events(task_id: str):
        try:
            task_service.get_task(task_id)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        return StreamingResponse(event_stream.task_sse(task_id), media_type="text/event-stream")
