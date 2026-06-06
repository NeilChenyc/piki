from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.application.event_stream import EventStreamService
from agent_service.config import ServiceConfig
from agent_service.models import RiskLevel, TaskKind
from agent_service.runtime import RunnerStatus
from agent_service.store import SQLiteStore


def make_client(tmp_path: Path) -> TestClient:
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
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
