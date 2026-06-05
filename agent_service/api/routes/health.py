from __future__ import annotations

from fastapi import FastAPI

from agent_service.config import ServiceConfig, openai_api_key_configured


def register_health_routes(app: FastAPI, *, config: ServiceConfig, runner):
    @app.get("/health")
    def health():
        return {
            "ok": True,
            "runner_available": runner.status.available,
            "runner_detail": runner.status.detail,
            "openai_api_key_configured": openai_api_key_configured(),
            "openai_base_url": config.openai_base_url or None,
            "agent_model": config.agent_model or None,
            "sdk_runtime_enabled": config.enable_sdk_runtime,
            "sdk_runtime_configured": config.sdk_runtime_configured,
            "tracing_enabled": config.tracing_enabled,
        }

    @app.post("/runtime/smoke-test")
    def smoke_test():
        result = runner.smoke_test(config=config)
        return {
            "ok": result.ok,
            "output": result.output,
            "error": result.error,
            "runner_available": runner.status.available,
            "sdk_runtime_configured": config.sdk_runtime_configured,
            "agent_model": config.agent_model or None,
            "openai_base_url": config.openai_base_url or None,
        }
