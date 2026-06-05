from pathlib import Path

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.store import SQLiteStore


def make_client(tmp_path: Path) -> TestClient:
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(ServiceConfig(db_path=tmp_path / "agent.sqlite3", enable_sdk_runtime=False), store=store)
    return TestClient(app)


def test_health(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert "runner_available" in response.json()
    assert "openai_base_url" in response.json()
    assert response.json()["sdk_runtime_enabled"] is False


def test_smoke_test_reports_unconfigured_runtime(tmp_path: Path):
    client = make_client(tmp_path)

    response = client.post("/runtime/smoke-test")

    assert response.status_code == 200
    assert response.json()["ok"] is False
    assert response.json()["sdk_runtime_configured"] is False


def test_create_query_task_and_replay_events(vault_path: Path, tmp_path: Path):
    client = make_client(tmp_path)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "Piki 是什么？",
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]

    task_response = client.get(f"/tasks/{task_id}")
    assert task_response.status_code == 200
    assert task_response.json()["task_kind"] == "agent"
    assert task_response.json()["status"] == "completed"

    events_response = client.get(f"/tasks/{task_id}/events")
    assert events_response.status_code == 200
    body = events_response.text
    assert "event: task.created" in body
    assert "event: context.loaded" in body


def test_async_task_streams_until_completion(vault_path: Path, tmp_path: Path):
    client = make_client(tmp_path)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "Piki 是什么？",
            "async_mode": True,
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    assert response.json()["status"] == "running"

    events_response = client.get(f"/tasks/{task_id}/events")

    assert events_response.status_code == 200
    body = events_response.text
    assert "event: agent.progress" in body
    assert "event: task.completed" in body
    assert client.get(f"/tasks/{task_id}").json()["status"] == "completed"


def test_proposed_patch_approval_does_not_apply_without_writer(vault_path: Path, tmp_path: Path):
    from agent_service.models import PatchChange, RiskLevel
    from agent_service.tools import VaultToolRegistry
    from agent_service.vault import Vault

    client = make_client(tmp_path)
    log_before = (vault_path / "wiki/log.md").read_text(encoding="utf-8")

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "把 raw/sources/llm-wiki.md ingest 到 wiki",
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    store = client.app.state.store
    tools = VaultToolRegistry(vault=Vault(vault_path), store=store, task_id=task_id)
    tools.propose_patch(
        reason="approval test proposal",
        changes=[PatchChange(path="wiki/log.md", action="update", content="# test\n")],
        risk_level=RiskLevel.HIGH,
    )
    task = client.get(f"/tasks/{task_id}").json()
    assert task["status"] == "needs_approval"
    assert task["pending_approvals"]

    approval_id = task["pending_approvals"][0]
    approve_response = client.post(
        f"/tasks/{task_id}/approve",
        json={"approval_id": approval_id, "comment": "phase 1 approval test"},
    )

    assert approve_response.status_code == 200
    assert approve_response.json()["status"] == "approved"

    resolved_task = client.get(f"/tasks/{task_id}").json()
    assert resolved_task["status"] == "completed"
    assert resolved_task["pending_approvals"] == []
    assert (vault_path / "wiki/log.md").read_text(encoding="utf-8") == log_before

    events_response = client.get(f"/tasks/{task_id}/events")
    assert "event: approval.resolved" in events_response.text
    assert "event: task.completed" in events_response.text
