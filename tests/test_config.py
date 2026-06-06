from pathlib import Path

from agent_service.config import ServiceConfig


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
