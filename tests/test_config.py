from agent_service.config import ServiceConfig


def test_openai_base_url_prefers_standard_env(monkeypatch):
    monkeypatch.setenv("OPENAI_BASE_URL", "https://standard.example")
    monkeypatch.setenv("OPENAI_API_BASE", "https://legacy.example")

    config = ServiceConfig()

    assert config.openai_base_url == "https://standard.example"


def test_openai_base_url_ignores_lowercase_url(monkeypatch):
    monkeypatch.delenv("OPENAI_BASE_URL", raising=False)
    monkeypatch.delenv("OPENAI_API_BASE", raising=False)
    monkeypatch.delenv("OPENAI_API_BASE_URL", raising=False)
    monkeypatch.setenv("url", "https://timicc.com")

    config = ServiceConfig()

    assert config.openai_base_url == ""
