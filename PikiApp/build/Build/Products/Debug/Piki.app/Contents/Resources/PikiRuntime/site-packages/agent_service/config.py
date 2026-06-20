from __future__ import annotations

import json
import os
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any

from pydantic import BaseModel, Field, SecretStr


def load_environment(env_path: Path = Path(".env")):
    try:
        from dotenv import load_dotenv
    except Exception:
        return
    if env_path.exists():
        load_dotenv(env_path, override=False)


def anthropic_auth_token(config: ServiceConfig | None = None) -> str:
    if config is not None:
        return config.api_key
    return _env_anthropic_auth_token()


def anthropic_api_key_configured(config: ServiceConfig | None = None) -> bool:
    if config is not None:
        return config.api_key_configured
    return bool(_env_anthropic_auth_token())


def env_flag(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _env_agent_model() -> str:
    return os.environ.get("PIKI_AGENT_MODEL", "").strip()


def _env_anthropic_base_url() -> str:
    return os.environ.get("ANTHROPIC_BASE_URL", "").strip()


def _env_anthropic_auth_token() -> str:
    return (
        os.environ.get("ANTHROPIC_AUTH_TOKEN", "").strip()
        or os.environ.get("ANTHROPIC_API_KEY", "").strip()
    )


def _normalize_optional_text(value: str | None) -> str:
    return (value or "").strip()


def _mask_api_key(value: str | None) -> str | None:
    token = _normalize_optional_text(value)
    if not token:
        return None
    if len(token) <= 8:
        return f"{token[0]}...{token[-1]}"
    return f"{token[:4]}...{token[-4:]}"


class ServiceConfig(BaseModel):
    db_path: Path = Path(".piki/agent_service.sqlite3")
    runtime_config_path: Path = Path(".piki/runtime-config.json")
    agent_model: str = ""
    anthropic_base_url: str = ""
    runtime_api_key: SecretStr | None = Field(default=None, exclude=True, repr=False)
    runtime_api_key_source: str = Field(default="none", exclude=True, repr=False)
    enable_agent_runtime: bool = Field(
        default_factory=lambda: env_flag("PIKI_ENABLE_AGENT_RUNTIME", env_flag("PIKI_ENABLE_SDK_RUNTIME"))
    )
    agent_task_timeout_seconds: int = Field(
        default_factory=lambda: int(os.environ.get("PIKI_AGENT_TASK_TIMEOUT_SECONDS", "180"))
    )
    agent_stream_idle_timeout_seconds: int = Field(
        default_factory=lambda: int(os.environ.get("PIKI_AGENT_STREAM_IDLE_TIMEOUT_SECONDS", "20"))
    )
    agent_max_turns: int = Field(
        default_factory=lambda: int(os.environ.get("PIKI_AGENT_MAX_TURNS", "50"))
    )
    agent_max_turns_configured: bool = Field(
        default_factory=lambda: "PIKI_AGENT_MAX_TURNS" in os.environ
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

    def model_post_init(self, __context: Any) -> None:
        runtime_config = self._read_runtime_config_file()

        if "agent_model" not in self.model_fields_set:
            self.agent_model = _normalize_optional_text(
                runtime_config.get("agent_model") or _env_agent_model()
            )
        else:
            self.agent_model = _normalize_optional_text(self.agent_model)

        if "anthropic_base_url" not in self.model_fields_set:
            self.anthropic_base_url = _normalize_optional_text(
                runtime_config.get("anthropic_base_url") or _env_anthropic_base_url()
            )
        else:
            self.anthropic_base_url = _normalize_optional_text(self.anthropic_base_url)

        if "runtime_api_key" not in self.model_fields_set:
            persisted_api_key = _normalize_optional_text(runtime_config.get("api_key"))
            env_api_key = _env_anthropic_auth_token()
            api_key = persisted_api_key or env_api_key
            self.runtime_api_key = SecretStr(api_key) if api_key else None
            self.runtime_api_key_source = "persisted" if persisted_api_key else ("environment" if env_api_key else "none")

    @property
    def api_key(self) -> str:
        if self.runtime_api_key is None:
            return ""
        return self.runtime_api_key.get_secret_value().strip()

    @property
    def api_key_configured(self) -> bool:
        return bool(self.api_key)

    @property
    def api_key_preview(self) -> str | None:
        return _mask_api_key(self.api_key)

    @property
    def api_key_source(self) -> str:
        return self.runtime_api_key_source

    @property
    def agent_runtime_configured(self) -> bool:
        return self.enable_agent_runtime and self.api_key_configured

    @property
    def enable_sdk_runtime(self) -> bool:
        return self.enable_agent_runtime

    @property
    def sdk_runtime_configured(self) -> bool:
        return self.agent_runtime_configured

    def runtime_config_response(self) -> dict[str, Any]:
        return {
            "provider": self.runtime_provider,
            "agent_model": self.agent_model or None,
            "anthropic_base_url": self.anthropic_base_url or None,
            "api_key_configured": self.api_key_configured,
            "api_key_preview": self.api_key_preview,
            "api_key_source": self.api_key_source,
            "agent_runtime_enabled": self.enable_agent_runtime,
        }

    def update_runtime_config(
        self,
        *,
        agent_model: str | None = None,
        anthropic_base_url: str | None = None,
        api_key: str | None = None,
        clear_api_key: bool = False,
    ) -> dict[str, Any]:
        runtime_config = self._read_runtime_config_file()

        if agent_model is not None:
            normalized_agent_model = _normalize_optional_text(agent_model)
            if normalized_agent_model:
                runtime_config["agent_model"] = normalized_agent_model
            else:
                runtime_config.pop("agent_model", None)

        if anthropic_base_url is not None:
            normalized_base_url = _normalize_optional_text(anthropic_base_url)
            if normalized_base_url:
                runtime_config["anthropic_base_url"] = normalized_base_url
            else:
                runtime_config.pop("anthropic_base_url", None)

        if clear_api_key:
            runtime_config.pop("api_key", None)
        elif api_key is not None:
            normalized_api_key = _normalize_optional_text(api_key)
            if normalized_api_key:
                runtime_config["api_key"] = normalized_api_key

        self._write_runtime_config_file(runtime_config)
        self.reload_runtime_config()
        return self.runtime_config_response()

    def reload_runtime_config(self) -> None:
        runtime_config = self._read_runtime_config_file()
        self.agent_model = _normalize_optional_text(runtime_config.get("agent_model") or _env_agent_model())
        self.anthropic_base_url = _normalize_optional_text(
            runtime_config.get("anthropic_base_url") or _env_anthropic_base_url()
        )
        persisted_api_key = _normalize_optional_text(runtime_config.get("api_key"))
        env_api_key = _env_anthropic_auth_token()
        api_key = persisted_api_key or env_api_key
        self.runtime_api_key = SecretStr(api_key) if api_key else None
        self.runtime_api_key_source = "persisted" if persisted_api_key else ("environment" if env_api_key else "none")

    def _read_runtime_config_file(self) -> dict[str, str]:
        path = self.runtime_config_path.expanduser()
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}
        except (OSError, json.JSONDecodeError):
            return {}
        if not isinstance(payload, dict):
            return {}
        return {
            key: _normalize_optional_text(value)
            for key, value in payload.items()
            if key in {"agent_model", "anthropic_base_url", "api_key"} and isinstance(value, str)
        }

    def _write_runtime_config_file(self, payload: dict[str, str]) -> None:
        path = self.runtime_config_path.expanduser()
        path.parent.mkdir(parents=True, exist_ok=True)
        serialized = {
            key: value
            for key, value in payload.items()
            if key in {"agent_model", "anthropic_base_url", "api_key"} and _normalize_optional_text(value)
        }
        serialized_text = json.dumps(serialized, indent=2, sort_keys=True)
        temp_path: Path | None = None
        try:
            with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
                handle.write(serialized_text)
                handle.flush()
                os.fsync(handle.fileno())
                temp_path = Path(handle.name)
            os.chmod(temp_path, 0o600)
            temp_path.replace(path)
            os.chmod(path, 0o600)
        finally:
            if temp_path is not None and temp_path.exists():
                temp_path.unlink(missing_ok=True)
