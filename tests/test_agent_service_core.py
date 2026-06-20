from pathlib import Path

import pytest

from agent_service.context import assemble_baseline_context
from agent_service.application.events import EventPublisher
from agent_service.journal import ChangeJournalService
from agent_service.models import FileSnapshot, RiskLevel, TaskKind
from agent_service.store import SQLiteStore
from agent_service.vault import Vault, VaultAccessError
from agent_service.vault.writer import VaultWriter


def test_vault_rejects_outside_path(vault_path: Path):
    vault = Vault(vault_path)

    with pytest.raises(VaultAccessError):
        vault.resolve_path("../.env")


def test_context_assembly_loads_baseline(vault_path: Path):
    manifest, contents = assemble_baseline_context(Vault(vault_path))

    assert "AGENTS.md" in manifest.loaded_files
    assert "purpose.md" in manifest.loaded_files
    assert "wiki/index.md" in manifest.loaded_files
    assert "AGENTS.md" in contents


def test_vault_read_permission_error_becomes_access_error(tmp_path: Path, monkeypatch):
    vault_root = tmp_path / "vault"
    vault_root.mkdir()
    agents = vault_root / "AGENTS.md"
    agents.write_text("# Agent 规则\n", encoding="utf-8")

    original_read_bytes = Path.read_bytes

    def deny_read_bytes(path: Path):
        if path == agents:
            raise PermissionError("Operation not permitted")
        return original_read_bytes(path)

    monkeypatch.setattr(Path, "read_bytes", deny_read_bytes)

    with pytest.raises(VaultAccessError, match="Cannot read vault file"):
        Vault(vault_root).read_text("AGENTS.md")


def test_vault_writer_and_journal_commit_changes(tmp_path: Path):
    vault_root = tmp_path / "vault"
    (vault_root / "wiki").mkdir(parents=True)
    (vault_root / "AGENTS.md").write_text("# Agent 规则\n", encoding="utf-8")
    (vault_root / "wiki/log.md").write_text("# 原始日志\n", encoding="utf-8")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.READ_ONLY,
        vault_path=str(vault_root),
        user_input="test",
    )
    vault = Vault(vault_root)
    writer = VaultWriter(vault)
    write = writer.write("wiki/log.md", "# test\n")

    assert write.changed is True
    assert write.path == "wiki/log.md"
    assert write.before_content is not None
    assert write.after_content == "# test\n"

    journal = ChangeJournalService(store=store, events=EventPublisher(store)).commit_for_task(
        task_id=task.id,
        conversation_id=task.id,
        reason="test proposal",
        snapshots=[writer.snapshot_for(write)],
    )

    assert journal is not None
    assert journal.affected_files == ["wiki/log.md"]
    assert store.list_events(task.id)[-1].type == "journal.created"


def test_change_journal_skips_non_wiki_and_non_raw_files(tmp_path: Path):
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.LOW,
        vault_path=str(tmp_path),
        user_input="test",
    )

    journal = ChangeJournalService(store=store, events=EventPublisher(store)).commit_for_task(
        task_id=task.id,
        conversation_id=task.id,
        reason="ignore system files",
        snapshots=[
            FileSnapshot(
                path="system/source_manifest.json",
                before_hash="sha256:old",
                after_hash="sha256:new",
                before_content="{}",
                after_content='{"ok": true}',
            )
        ],
    )

    assert journal is None
