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


def anthropic_api_key_configured() -> bool:
    return bool(os.environ.get("ANTHROPIC_API_KEY"))


def env_flag(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


class ServiceConfig(BaseModel):
    db_path: Path = Path(".piki/agent_service.sqlite3")
    agent_model: str = Field(default_factory=lambda: os.environ.get("PIKI_AGENT_MODEL", ""))
    anthropic_base_url: str = Field(default_factory=lambda: os.environ.get("ANTHROPIC_BASE_URL", "").strip())
    enable_agent_runtime: bool = Field(
        default_factory=lambda: env_flag("PIKI_ENABLE_AGENT_RUNTIME", env_flag("PIKI_ENABLE_SDK_RUNTIME"))
    )
    agent_task_timeout_seconds: int = Field(
        default_factory=lambda: int(os.environ.get("PIKI_AGENT_TASK_TIMEOUT_SECONDS", "180"))
    )
    agent_stream_idle_timeout_seconds: int = Field(
        default_factory=lambda: int(os.environ.get("PIKI_AGENT_STREAM_IDLE_TIMEOUT_SECONDS", "20"))
    )
    claude_config_dir: Path = Field(
        default_factory=lambda: Path(os.environ.get("CLAUDE_CONFIG_DIR", ".piki/claude-runtime")).expanduser()
    )
    staging_root: Path = Field(
        default_factory=lambda: Path(os.environ.get("PIKI_TASK_STAGING_ROOT", ".piki/task-staging")).expanduser()
    )
    enable_file_checkpointing: bool = Field(
        default_factory=lambda: env_flag("PIKI_ENABLE_FILE_CHECKPOINTING")
    )
    runtime_provider: str = "claude"

    @property
    def api_key_configured(self) -> bool:
        return anthropic_api_key_configured()

    @property
    def agent_runtime_configured(self) -> bool:
        return self.enable_agent_runtime and self.api_key_configured

    @property
    def enable_sdk_runtime(self) -> bool:
        return self.enable_agent_runtime

    @property
    def sdk_runtime_configured(self) -> bool:
        return self.agent_runtime_configured
