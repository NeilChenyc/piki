from pathlib import Path

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.application.events import EventPublisher
from agent_service.journal import ChangeJournalService
from agent_service.config import ServiceConfig
from agent_service.models import RiskLevel, TaskKind
from agent_service.store import SQLiteStore
from agent_service.vault import Vault
from agent_service.vault.writer import VaultWriter


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
    app = create_app(ServiceConfig(db_path=tmp_path / "agent.sqlite3", enable_agent_runtime=False), store=store)
    return TestClient(app)


def create_journal(store: SQLiteStore, vault_path: Path, path: str, content: str):
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.LOW,
        vault_path=str(vault_path),
        user_input=f"write {path}",
    )
    writer = VaultWriter(Vault(vault_path))
    write = writer.write(path, content)
    assert write.changed is True
    journal = ChangeJournalService(store=store, events=EventPublisher(store)).commit_for_task(
        task_id=task.id,
        conversation_id=task.id,
        reason="test",
        snapshots=[writer.snapshot_for(write)],
    )
    assert journal is not None
    return journal


def test_rollback_endpoint_is_gone_and_does_not_modify_files(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    client = make_client(tmp_path)
    store = client.app.state.store
    (vault_path / "wiki/log.md").write_text("# 日志\n", encoding="utf-8")
    journal = create_journal(store, vault_path, "wiki/log.md", "# 日志\n\n- 新内容\n")

    response = client.post(f"/journal/{journal.id}/rollback", json={"reason": "undo"})

    assert response.status_code == 410
    assert "removed" in response.json()["detail"]
    assert (vault_path / "wiki/log.md").read_text(encoding="utf-8") == "# 日志\n\n- 新内容\n"
    assert store.get_journal_entry(journal.id).status == "active"
    with store.connect() as conn:
        rollback_tasks = conn.execute("SELECT COUNT(*) AS count FROM tasks WHERE task_kind = 'rollback'").fetchone()
    assert rollback_tasks["count"] == 0


def test_recent_journal_is_write_activity_without_rollback_eligibility(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    client = make_client(tmp_path)
    store = client.app.state.store
    journal = create_journal(store, vault_path, "wiki/log.md", "# 日志\n\n- 新内容\n")

    response = client.get(f"/journal/recent?vault_path={vault_path}")

    assert response.status_code == 200
    entry = response.json()["entries"][0]
    assert entry["id"] == journal.id
    assert entry["affected_files"] == ["wiki/log.md"]
    assert "eligible_for_rollback" not in entry


def test_clear_inbox_file_creates_write_activity_without_restore_snapshot(tmp_path: Path):
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
    assert "eligible_for_rollback" not in journal
    stored_journal = client.app.state.store.get_journal_entry(journal["id"])
    assert stored_journal.snapshots == []


def test_source_rescan_updates_manifest_without_update_queue(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    client = make_client(tmp_path)
    source = vault_path / "raw/sources/测试来源.md"
    source.write_text("# 测试来源\n\n第一版。", encoding="utf-8")

    first = client.post("/sources/rescan", json={"vault_path": str(vault_path)})
    assert first.status_code == 200
    assert first.json()["new_sources"] == ["raw/sources/测试来源.md"]
    assert "queued_items" not in first.json()
    assert client.get("/update-queue").status_code == 404

    second = client.post("/sources/rescan", json={"vault_path": str(vault_path)})
    assert second.status_code == 200
    assert second.json()["unchanged_sources"] == ["raw/sources/测试来源.md"]

    source.write_text("# 测试来源\n\n第二版。", encoding="utf-8")
    modified = client.post("/sources/rescan", json={"vault_path": str(vault_path)})
    assert modified.json()["modified_sources"] == ["raw/sources/测试来源.md"]
    assert "queued_items" not in modified.json()

    source.unlink()
    missing = client.post("/sources/rescan", json={"vault_path": str(vault_path)})
    assert missing.json()["missing_sources"] == ["raw/sources/测试来源.md"]
    manifest_text = (vault_path / "system/source_manifest.json").read_text(encoding="utf-8")
    assert '"missing": true' in manifest_text
