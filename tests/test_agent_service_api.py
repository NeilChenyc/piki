from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.application.event_stream import EventStreamService
from agent_service.config import ServiceConfig
from agent_service.models import RiskLevel, TaskKind
from agent_service.runtime import RunnerStatus
from agent_service.store import SQLiteStore
from agent_service.vault import Vault


def make_client(tmp_path: Path) -> TestClient:
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            staging_root=tmp_path / ".piki/task-staging",
            enable_agent_runtime=False,
        ),
        store=store,
    )
    return TestClient(app)


def test_health(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.get("/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] is True
    assert payload["provider"] == "claude"
    assert "runner_available" in payload
    assert "agent_runtime_enabled" in payload
    assert "anthropic_api_key_configured" in payload


def test_smoke_test_reports_unconfigured_runtime(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.post("/runtime/smoke-test")

    assert response.status_code == 200
    assert response.json()["ok"] is False
    assert response.json()["agent_runtime_configured"] is False


def test_runtime_config_round_trip_masks_key_and_refreshes_health_and_smoke_test(tmp_path: Path, monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("ANTHROPIC_AUTH_TOKEN", raising=False)
    monkeypatch.chdir(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            enable_agent_runtime=True,
        ),
        store=store,
    )

    async def fake_query(*, prompt, options):
        assert options.model == "claude-live"
        assert options.env["ANTHROPIC_BASE_URL"] == "https://gateway.example"
        assert options.env["ANTHROPIC_API_KEY"] == "sk-ant-live-1234"
        yield SimpleNamespace(content=[SimpleNamespace(text="Piki Claude smoke test ok.")], session_id="sess_live")

    app.state.runner._query_impl = fake_query
    app.state.runner.status = RunnerStatus(True, "Claude Agent SDK available")
    client = TestClient(app)

    initial = client.get("/runtime/config")
    assert initial.status_code == 200
    assert initial.json()["api_key_configured"] is False
    assert initial.json()["api_key_preview"] is None
    assert initial.json()["api_key_source"] == "none"

    update = client.put(
        "/runtime/config",
        json={
            "agent_model": "claude-live",
            "anthropic_base_url": "https://gateway.example",
            "api_key": "sk-ant-live-1234",
        },
    )

    assert update.status_code == 200
    payload = update.json()
    assert payload["agent_model"] == "claude-live"
    assert payload["anthropic_base_url"] == "https://gateway.example"
    assert payload["api_key_configured"] is True
    assert payload["api_key_preview"] == "sk-a...1234"
    assert payload["api_key_source"] == "persisted"
    assert "sk-ant-live-1234" not in update.text

    health = client.get("/health")
    assert health.status_code == 200
    assert health.json()["agent_model"] == "claude-live"
    assert health.json()["anthropic_base_url"] == "https://gateway.example"
    assert health.json()["anthropic_api_key_configured"] is True
    assert "sk-ant-live-1234" not in health.text

    smoke = client.post("/runtime/smoke-test")
    assert smoke.status_code == 200
    assert smoke.json()["ok"] is True
    assert smoke.json()["agent_model"] == "claude-live"
    assert smoke.json()["anthropic_base_url"] == "https://gateway.example"

    cleared = client.put("/runtime/config", json={"clear_api_key": True})
    assert cleared.status_code == 200
    assert cleared.json()["api_key_configured"] is False
    assert cleared.json()["api_key_preview"] is None
    assert cleared.json()["api_key_source"] == "none"

    final = client.get("/runtime/config")
    assert final.status_code == 200
    assert final.json()["api_key_configured"] is False
    assert final.json()["api_key_preview"] is None
    assert final.json()["api_key_source"] == "none"


def test_runtime_config_clear_reveals_environment_fallback_source(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_AUTH_TOKEN", "env-token")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            enable_agent_runtime=True,
        ),
        store=store,
    )
    client = TestClient(app)

    updated = client.put("/runtime/config", json={"api_key": "sk-ant-live-1234"})
    assert updated.status_code == 200
    assert updated.json()["api_key_source"] == "persisted"

    cleared = client.put("/runtime/config", json={"clear_api_key": True})
    assert cleared.status_code == 200
    assert cleared.json()["api_key_configured"] is True
    assert cleared.json()["api_key_source"] == "environment"
    assert cleared.json()["api_key_preview"] == "env-...oken"


def test_runtime_config_round_trip_tingwu_config_masks_secrets(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("ALIBABA_CLOUD_ACCESS_KEY_ID", raising=False)
    monkeypatch.delenv("ALIBABA_CLOUD_ACCESS_KEY_SECRET", raising=False)
    monkeypatch.delenv("ALIYUN_ACCESS_KEY_ID", raising=False)
    monkeypatch.delenv("ALIYUN_ACCESS_KEY_SECRET", raising=False)
    monkeypatch.delenv("TINGWU_APP_KEY", raising=False)
    monkeypatch.delenv("TINGWU_REGION_ID", raising=False)
    monkeypatch.delenv("appkey", raising=False)
    monkeypatch.delenv("app_key", raising=False)
    monkeypatch.delenv("region_id", raising=False)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            enable_agent_runtime=False,
        ),
        store=store,
    )
    client = TestClient(app)

    initial = client.get("/runtime/config")
    assert initial.status_code == 200
    assert initial.json()["tingwu_configured"] is False
    assert initial.json()["tingwu_region_id"] == "cn-beijing"

    update = client.put(
        "/runtime/config",
        json={
            "aliyun_access_key_id": "LTAI-test-access-key",
            "aliyun_access_key_secret": "aliyun-secret-value",
            "tingwu_app_key": "tingwu-app-key-value",
            "tingwu_region_id": "cn-shanghai",
        },
    )

    assert update.status_code == 200
    payload = update.json()
    assert payload["tingwu_configured"] is True
    assert payload["tingwu_region_id"] == "cn-shanghai"
    assert payload["aliyun_access_key_id_preview"] == "LTAI...-key"
    assert payload["aliyun_access_key_secret_configured"] is True
    assert payload["tingwu_app_key_preview"] == "ting...alue"
    assert "aliyun-secret-value" not in update.text
    assert "tingwu-app-key-value" not in update.text

    fetched = client.get("/runtime/config")
    assert fetched.status_code == 200
    assert fetched.json()["tingwu_configured"] is True
    assert "aliyun-secret-value" not in fetched.text
    assert "tingwu-app-key-value" not in fetched.text

    cleared = client.put("/runtime/config", json={"clear_tingwu_config": True})
    assert cleared.status_code == 200
    assert cleared.json()["tingwu_configured"] is False
    assert cleared.json()["aliyun_access_key_id_preview"] is None
    assert cleared.json()["aliyun_access_key_secret_configured"] is False
    assert cleared.json()["tingwu_app_key_preview"] is None
    assert cleared.json()["tingwu_region_id"] == "cn-beijing"


def test_runtime_config_rejects_conflicting_api_key_and_clear_request(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.put(
        "/runtime/config",
        json={
            "api_key": "sk-ant-conflict",
            "clear_api_key": True,
        },
    )

    assert response.status_code == 422
    assert "cannot be sent together" in response.text


def test_runtime_config_rejects_invalid_base_url(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.put(
        "/runtime/config",
        json={
            "anthropic_base_url": "gateway.example",
        },
    )

    assert response.status_code == 422
    assert "must start with http:// or https://" in response.text


def test_async_task_streams_until_input_required(vault_path: Path, tmp_path: Path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            enable_agent_runtime=True,
            agent_model="claude-test",
        ),
        store=store,
    )

    async def fake_query(*, prompt, options):
        for matcher in options.hooks["PreToolUse"]:
            for hook in matcher.hooks:
                result = await hook(
                    {
                        "tool_name": "AskUserQuestion",
                        "tool_input": {"question": "要写进 wiki 吗？", "options": ["是", "否"]},
                    },
                    None,
                    None,
                )
                assert result["permissionDecision"] == "defer"
        yield SimpleNamespace(
            content=[],
            session_id="sess_api",
        )
        yield SimpleNamespace(
            session_id="sess_api",
            subtype="success",
            is_error=False,
            result="需要你的输入",
            errors=None,
            deferred_tool_use=SimpleNamespace(
                id="toolu_1",
                name="AskUserQuestion",
                input={"question": "要写进 wiki 吗？", "options": ["是", "否"]},
            ),
        )

    app.state.runner._query_impl = fake_query
    app.state.runner.status = RunnerStatus(True, "Claude Agent SDK available")
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "帮我整理一下",
            "async_mode": True,
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    body = client.get(f"/tasks/{task_id}/events").text
    assert "event: agent.run.started" in body
    assert "event: agent.input_requested" in body
    assert client.get(f"/tasks/{task_id}").json()["status"] == "input_required"


def test_sse_stream_emits_heartbeat_for_idle_running_task(vault_path: Path, tmp_path: Path):
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.READ_ONLY,
        vault_path=str(vault_path),
        user_input="idle",
    )
    stream = EventStreamService(store, heartbeat_interval_seconds=0).task_sse(task.id)

    assert next(stream).startswith(": ping")


def test_upload_endpoint_buffers_attachment(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.post(
        "/uploads",
        files={"file": ("note.md", b"# buffered\nhello", "text/markdown")},
        data={"original_path": "/Users/a99/Downloads/note.md"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["filename"] == "note.md"
    assert payload["original_path"] == "/Users/a99/Downloads/note.md"
    buffered_path = Path(payload["buffered_path"])
    assert buffered_path.exists()
    assert buffered_path.read_text(encoding="utf-8") == "# buffered\nhello"


def test_task_permission_error_fails_instead_of_staying_running(tmp_path: Path, monkeypatch):
    vault = tmp_path / "vault"
    (vault / "wiki").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent 规则\n", encoding="utf-8")
    (vault / "purpose.md").write_text("# Purpose\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text("# Index\n", encoding="utf-8")

    original_read_text = Vault.read_text

    def deny_agents(self, relative_path, max_bytes=20000):
        if str(relative_path) == "AGENTS.md":
            raise PermissionError("Operation not permitted")
        return original_read_text(self, relative_path, max_bytes=max_bytes)

    monkeypatch.setattr(Vault, "read_text", deny_agents)
    client = make_client(tmp_path)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault),
            "user_input": "hi",
            "async_mode": False,
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    task = client.get(f"/tasks/{task_id}").json()
    assert task["status"] == "failed"
    assert "Operation not permitted" in task["summary"]
