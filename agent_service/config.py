from __future__ import annotations

import os
from pathlib import Path

from pydantic import BaseModel, Field


def load_environment(env_path: Path = Path(".env")):
    try:
        from dotenv import load_dotenv
    except Exception:
        return
    if env_path.exists():
        load_dotenv(env_path, override=False)
    if os.environ.get("OPENAI_API_KEY") == "":
        os.environ.pop("OPENAI_API_KEY")


def openai_api_key_configured() -> bool:
    return bool(os.environ.get("OPENAI_API_KEY"))


def env_flag(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def openai_base_url_from_env() -> str:
    for name in ("OPENAI_BASE_URL", "OPENAI_API_BASE", "OPENAI_API_BASE_URL"):
        value = os.environ.get(name)
        if value and value.strip():
            return value.strip()
    return ""


class ServiceConfig(BaseModel):
    db_path: Path = Path(".piki/agent_service.sqlite3")
    agent_model: str = Field(default_factory=lambda: os.environ.get("PIKI_AGENT_MODEL", ""))
    openai_base_url: str = Field(default_factory=openai_base_url_from_env)
    enable_sdk_runtime: bool = Field(default_factory=lambda: env_flag("PIKI_ENABLE_SDK_RUNTIME"))
    tracing_enabled: bool = Field(default_factory=lambda: env_flag("PIKI_TRACING_ENABLED"))
    agent_task_timeout_seconds: int = Field(
        default_factory=lambda: int(os.environ.get("PIKI_AGENT_TASK_TIMEOUT_SECONDS", "180"))
    )
    agent_stream_idle_timeout_seconds: int = Field(
        default_factory=lambda: int(os.environ.get("PIKI_AGENT_STREAM_IDLE_TIMEOUT_SECONDS", "20"))
    )

    @property
    def api_key_configured(self) -> bool:
        return openai_api_key_configured()

    @property
    def sdk_runtime_configured(self) -> bool:
        return self.enable_sdk_runtime and self.api_key_configured and bool(self.agent_model)
