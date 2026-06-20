from __future__ import annotations

from fastapi import FastAPI, HTTPException

from agent_service.application.maintenance import ApprovalService
from agent_service.models import ApprovalDecisionRequest, ApprovalStatus


def register_approval_routes(app: FastAPI, *, approval_service: ApprovalService):
    @app.post("/tasks/{task_id}/approve")
    def approve(task_id: str, request: ApprovalDecisionRequest):
        try:
            return approval_service.resolve(task_id, request, ApprovalStatus.APPROVED)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.post("/tasks/{task_id}/reject")
    def reject(task_id: str, request: ApprovalDecisionRequest):
        try:
            return approval_service.resolve(task_id, request, ApprovalStatus.REJECTED)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
