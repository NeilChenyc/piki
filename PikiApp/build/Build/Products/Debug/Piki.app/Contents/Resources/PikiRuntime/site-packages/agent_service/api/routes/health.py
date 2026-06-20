from __future__ import annotations

from fastapi import FastAPI
from pydantic import BaseModel, model_validator

from agent_service.config import ServiceConfig, anthropic_api_key_configured


class RuntimeConfigUpdateRequest(BaseModel):
    agent_model: str | None = None
    anthropic_base_url: str | None = None
    api_key: str | None = None
    clear_api_key: bool = False

    @model_validator(mode="after")
    def validate_request(self) -> RuntimeConfigUpdateRequest:
        if self.clear_api_key and self.api_key is not None and self.api_key.strip():
            raise ValueError("`api_key` and `clear_api_key=true` cannot be sent together.")
        if self.anthropic_base_url is not None:
            trimmed = self.anthropic_base_url.strip()
            if trimmed and not (trimmed.startswith("http://") or trimmed.startswith("https://")):
                raise ValueError("`anthropic_base_url` must start with http:// or https://.")
        return self


def register_health_routes(app: FastAPI, *, config: ServiceConfig, runner):
    @app.get("/health")
    def health():
        return {
            "ok": True,
            "runner_available": runner.status.available,
            "runner_detail": runner.status.detail,
            "provider": config.runtime_provider,
            "anthropic_api_key_configured": anthropic_api_key_configured(config),
            "anthropic_base_url": config.anthropic_base_url or None,
            "agent_model": config.agent_model or None,
            "agent_runtime_enabled": config.enable_agent_runtime,
            "agent_runtime_configured": config.agent_runtime_configured,
            "claude_config_dir": str(config.claude_config_dir.expanduser().resolve()),
        }

    @app.get("/runtime/config")
    def get_runtime_config():
        return config.runtime_config_response()

    @app.put("/runtime/config")
    def update_runtime_config(request: RuntimeConfigUpdateRequest):
        return config.update_runtime_config(
            agent_model=request.agent_model,
            anthropic_base_url=request.anthropic_base_url,
            api_key=request.api_key,
            clear_api_key=request.clear_api_key,
        )

    @app.post("/runtime/smoke-test")
    def smoke_test():
        result = runner.smoke_test(config=config)
        return {
            "ok": result.ok,
            "output": result.output,
            "error": result.error,
            "runner_available": runner.status.available,
            "provider": config.runtime_provider,
            "agent_runtime_configured": config.agent_runtime_configured,
            "anthropic_base_url": config.anthropic_base_url or None,
            "agent_model": config.agent_model or None,
        }
