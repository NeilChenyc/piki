from pathlib import Path

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.models import RiskLevel, TaskKind
from agent_service.store import SQLiteStore
from agent_service.tools import VaultToolRegistry
from agent_service.vault import Vault


def make_vault(tmp_path: Path) -> Path:
    vault = tmp_path / "vault"
    (vault / "raw/inbox").mkdir(parents=True)
    (vault / "raw/sources").mkdir(parents=True)
    (vault / "wiki").mkdir(parents=True)
    (vault / "system").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent 规则\n", encoding="utf-8")
    (vault / "purpose.md").write_text("# 目的\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text("# 索引\n", encoding="utf-8")
    (vault / "wiki/log.md").write_text("# 日志\n", encoding="utf-8")
    return vault


def make_client(tmp_path: Path) -> TestClient:
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(ServiceConfig(db_path=tmp_path / "agent.sqlite3", enable_sdk_runtime=False), store=store)
    return TestClient(app)


def create_journal(store: SQLiteStore, vault_path: Path, path: str, content: str):
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.LOW,
        vault_path=str(vault_path),
        user_input=f"write {path}",
    )
    tools = VaultToolRegistry(vault=Vault(vault_path), store=store, task_id=task.id)
    result = tools.write_file(path, content, reason="test")
    assert result.ok
    journal = tools.commit_journal_entry(conversation_id=task.id, reason="test")
    assert journal is not None
    return journal


def test_rollback_latest_journal_restores_files(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    client = make_client(tmp_path)
    store = client.app.state.store
    (vault_path / "wiki/log.md").write_text("# 日志\n", encoding="utf-8")
    journal = create_journal(store, vault_path, "wiki/log.md", "# 日志\n\n- 新内容\n")

    response = client.post(f"/journal/{journal.id}/rollback", json={"reason": "undo"})

    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] is True
    assert payload["status"] == "rolled_back"
    assert (vault_path / "wiki/log.md").read_text(encoding="utf-8") == "# 日志\n"
    assert store.get_journal_entry(journal.id).status == "rolled_back"


def test_rollback_hash_mismatch_fails_without_partial_write(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    client = make_client(tmp_path)
    store = client.app.state.store
    journal = create_journal(store, vault_path, "wiki/log.md", "# 日志\n\n- 新内容\n")
    (vault_path / "wiki/log.md").write_text("# 日志\n\n- 用户后续修改\n", encoding="utf-8")

    response = client.post(f"/journal/{journal.id}/rollback", json={})

    assert response.status_code == 200
    payload = response.json()
    assert payload["ok"] is False
    assert "hash mismatch" in payload["error"]
    assert (vault_path / "wiki/log.md").read_text(encoding="utf-8") == "# 日志\n\n- 用户后续修改\n"
    assert store.get_journal_entry(journal.id).status == "rollback_failed"


def test_rollback_only_latest_two_active_journals(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    client = make_client(tmp_path)
    store = client.app.state.store
    oldest = create_journal(store, vault_path, "wiki/old.md", "# old\n")
    create_journal(store, vault_path, "wiki/middle.md", "# middle\n")
    create_journal(store, vault_path, "wiki/latest.md", "# latest\n")

    response = client.post(f"/journal/{oldest.id}/rollback", json={})

    assert response.status_code == 200
    assert response.json()["ok"] is False
    assert "latest-two" in response.json()["error"]
    assert (vault_path / "wiki/old.md").read_text(encoding="utf-8") == "# old\n"


def test_clear_inbox_file_creates_journal_and_can_rollback(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    client = make_client(tmp_path)
    inbox_file = vault_path / "raw/inbox/note.md"
    inbox_file.write_text("# 临时笔记\n", encoding="utf-8")

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "清理这个 inbox 文件",
            "selected_paths": [str(inbox_file)],
            "mode": "clear-inbox-item",
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    task = client.get(f"/tasks/{task_id}").json()
    assert task["status"] == "completed"
    assert inbox_file.exists() is False
    journal = client.get(f"/journal/recent?vault_path={vault_path}").json()["entries"][0]
    assert journal["affected_files"] == ["raw/inbox/note.md"]
    assert journal["eligible_for_rollback"] is True

    rollback = client.post(f"/journal/{journal['id']}/rollback", json={"reason": "restore"})

    assert rollback.status_code == 200
    assert rollback.json()["ok"] is True
    assert inbox_file.read_text(encoding="utf-8") == "# 临时笔记\n"


def test_source_rescan_queues_new_modified_and_missing_sources(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    client = make_client(tmp_path)
    source = vault_path / "raw/sources/测试来源.md"
    source.write_text("# 测试来源\n\n第一版。", encoding="utf-8")

    first = client.post("/sources/rescan", json={"vault_path": str(vault_path)})
    assert first.status_code == 200
    assert first.json()["new_sources"] == ["raw/sources/测试来源.md"]
    queue = client.get("/update-queue").json()["items"]
    assert len(queue) == 1
    assert queue[0]["change_type"] == "new"

    second = client.post("/sources/rescan", json={"vault_path": str(vault_path)})
    assert second.status_code == 200
    assert second.json()["unchanged_sources"] == ["raw/sources/测试来源.md"]
    assert len(client.get("/update-queue").json()["items"]) == 1

    source.write_text("# 测试来源\n\n第二版。", encoding="utf-8")
    modified = client.post("/sources/rescan", json={"vault_path": str(vault_path)})
    assert modified.json()["modified_sources"] == ["raw/sources/测试来源.md"]
    queue = client.get("/update-queue").json()["items"]
    assert {item["change_type"] for item in queue} == {"new", "modified"}

    source.unlink()
    missing = client.post("/sources/rescan", json={"vault_path": str(vault_path)})
    assert missing.json()["missing_sources"] == ["raw/sources/测试来源.md"]
    queue = client.get("/update-queue").json()["items"]
    assert {item["change_type"] for item in queue} == {"new", "modified", "missing"}
    manifest_text = (vault_path / "system/source_manifest.json").read_text(encoding="utf-8")
    assert '"missing": true' in manifest_text
