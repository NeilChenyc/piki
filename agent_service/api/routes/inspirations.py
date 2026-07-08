from __future__ import annotations

from fastapi import FastAPI, HTTPException

from agent_service.application.inspirations import InspirationService
from agent_service.models import InspirationCompileRequest, InspirationCreateRequest, InspirationUpdateRequest
from agent_service.vault import VaultAccessError


def register_inspiration_routes(app: FastAPI, *, inspiration_service: InspirationService):
    @app.get("/inspirations")
    def list_inspirations(vault_path: str, query: str | None = None):
        try:
            return inspiration_service.list(vault_path=vault_path, query=query)
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.post("/inspirations")
    def create_inspiration(request: InspirationCreateRequest):
        try:
            return inspiration_service.create(request)
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.post("/inspirations/compile")
    def compile_inspirations(request: InspirationCompileRequest):
        try:
            return inspiration_service.compile(request)
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.patch("/inspirations/{inspiration_id}")
    def update_inspiration(inspiration_id: str, request: InspirationUpdateRequest):
        try:
            return inspiration_service.update(inspiration_id, request)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

    @app.delete("/inspirations/{inspiration_id}")
    def delete_inspiration(inspiration_id: str, vault_path: str):
        try:
            inspiration_service.delete(inspiration_id, vault_path=vault_path)
            return {"ok": True}
        except KeyError as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except VaultAccessError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
