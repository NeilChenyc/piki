import json
from pathlib import Path

from agent_service.config import ServiceConfig, anthropic_api_key_configured


def test_agent_runtime_flag_prefers_new_env(monkeypatch):
    monkeypatch.setenv("PIKI_ENABLE_AGENT_RUNTIME", "1")
    monkeypatch.setenv("PIKI_ENABLE_SDK_RUNTIME", "0")

    config = ServiceConfig()

    assert config.enable_agent_runtime is True
    assert config.enable_sdk_runtime is True


def test_agent_runtime_flag_falls_back_to_legacy_env(monkeypatch):
    monkeypatch.delenv("PIKI_ENABLE_AGENT_RUNTIME", raising=False)
    monkeypatch.setenv("PIKI_ENABLE_SDK_RUNTIME", "1")

    config = ServiceConfig()

    assert config.enable_agent_runtime is True


def test_claude_config_dir_defaults_to_private_runtime_dir(monkeypatch):
    monkeypatch.delenv("CLAUDE_CONFIG_DIR", raising=False)

    config = ServiceConfig()

    assert config.claude_config_dir == Path(".piki/claude-runtime")
    assert config.runtime_config_path == Path(".piki/runtime-config.json")


def test_agent_stream_idle_timeout_defaults_to_sixty_seconds(monkeypatch):
    monkeypatch.delenv("PIKI_AGENT_STREAM_IDLE_TIMEOUT_SECONDS", raising=False)

    config = ServiceConfig()

    assert config.agent_stream_idle_timeout_seconds == 60


def test_runtime_is_configured_with_anthropic_auth_token(monkeypatch):
    monkeypatch.setenv("PIKI_ENABLE_AGENT_RUNTIME", "1")
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("ANTHROPIC_AUTH_TOKEN", "test-token")

    config = ServiceConfig()

    assert anthropic_api_key_configured() is True
    assert config.agent_runtime_configured is True


def test_runtime_config_persists_and_masks_api_key(tmp_path: Path, monkeypatch):
    monkeypatch.delenv("PIKI_AGENT_MODEL", raising=False)
    monkeypatch.delenv("ANTHROPIC_BASE_URL", raising=False)
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("ANTHROPIC_AUTH_TOKEN", raising=False)

    config = ServiceConfig(
        runtime_config_path=tmp_path / "runtime-config.json",
        enable_agent_runtime=True,
    )

    config.update_runtime_config(
        agent_model="claude-3-7-sonnet",
        anthropic_base_url="https://claude-gateway.example",
        api_key="sk-ant-1234567890",
    )

    assert config.agent_model == "claude-3-7-sonnet"
    assert config.anthropic_base_url == "https://claude-gateway.example"
    assert config.api_key_configured is True
    assert config.api_key_preview == "sk-a...7890"
    assert config.api_key_source == "persisted"
    assert "1234567890" not in json.dumps(config.runtime_config_response())

    saved_payload = json.loads((tmp_path / "runtime-config.json").read_text(encoding="utf-8"))
    assert saved_payload == {
        "agent_model": "claude-3-7-sonnet",
        "anthropic_base_url": "https://claude-gateway.example",
        "api_key": "sk-ant-1234567890",
    }


def test_runtime_config_can_clear_persisted_api_key(tmp_path: Path, monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("ANTHROPIC_AUTH_TOKEN", raising=False)

    config = ServiceConfig(
        runtime_config_path=tmp_path / "runtime-config.json",
        enable_agent_runtime=True,
    )
    config.update_runtime_config(api_key="sk-ant-keepme")

    config.update_runtime_config(clear_api_key=True)

    assert config.api_key_configured is False
    assert config.api_key_preview is None
    assert config.api_key_source == "none"
    saved_payload = json.loads((tmp_path / "runtime-config.json").read_text(encoding="utf-8"))
    assert "api_key" not in saved_payload


def test_runtime_config_clear_falls_back_to_environment_key(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_AUTH_TOKEN", "env-token")

    config = ServiceConfig(
        runtime_config_path=tmp_path / "runtime-config.json",
        enable_agent_runtime=True,
    )
    config.update_runtime_config(api_key="sk-ant-keepme")

    config.update_runtime_config(clear_api_key=True)

    assert config.api_key_configured is True
    assert config.api_key_preview == "env-...oken"
    assert config.api_key_source == "environment"


def test_runtime_config_precedence_prefers_persisted_values(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("PIKI_AGENT_MODEL", "env-model")
    monkeypatch.setenv("ANTHROPIC_BASE_URL", "https://env.example")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "env-secret")
    (tmp_path / "runtime-config.json").write_text(
        json.dumps(
            {
                "agent_model": "persisted-model",
                "anthropic_base_url": "https://persisted.example",
                "api_key": "persisted-secret",
            }
        ),
        encoding="utf-8",
    )

    config = ServiceConfig(
        runtime_config_path=tmp_path / "runtime-config.json",
        enable_agent_runtime=True,
    )

    assert config.agent_model == "persisted-model"
    assert config.anthropic_base_url == "https://persisted.example"
    assert config.api_key_configured is True
    assert config.api_key_preview == "pers...cret"
    assert config.api_key_source == "persisted"


def test_runtime_config_falls_back_to_env_when_no_saved_config(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("PIKI_AGENT_MODEL", "env-model")
    monkeypatch.setenv("ANTHROPIC_BASE_URL", "https://env.example")
    monkeypatch.setenv("ANTHROPIC_AUTH_TOKEN", "env-token")

    config = ServiceConfig(
        runtime_config_path=tmp_path / "runtime-config.json",
        enable_agent_runtime=True,
    )

    assert config.agent_model == "env-model"
    assert config.anthropic_base_url == "https://env.example"
    assert config.api_key_configured is True
    assert config.api_key_preview == "env-...oken"
    assert config.api_key_source == "environment"


def test_runtime_config_file_written_atomically_with_private_permissions(tmp_path: Path, monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("ANTHROPIC_AUTH_TOKEN", raising=False)
    config_path = tmp_path / "runtime-config.json"
    config = ServiceConfig(runtime_config_path=config_path)

    config.update_runtime_config(api_key="sk-ant-1234")

    file_mode = config_path.stat().st_mode & 0o777
    assert file_mode == 0o600
