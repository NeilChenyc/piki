from pathlib import Path

import pytest

from agent_service.context import assemble_baseline_context
from agent_service.models import PatchChange, RiskLevel, TaskKind
from agent_service.store import SQLiteStore
from agent_service.tools import VaultToolRegistry
from agent_service.vault import Vault, VaultAccessError


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


def test_vault_tools_read_parse_and_propose(vault_path: Path, tmp_path: Path):
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.READ_ONLY,
        vault_path=str(vault_path),
        user_input="test",
    )
    tools = VaultToolRegistry(vault=Vault(vault_path), store=store, task_id=task.id)

    read_result = tools.read_file("wiki/index.md")
    assert read_result.ok
    assert "Piki 维基索引" in read_result.payload["content"]

    parse_result = tools.parse_markdown("wiki/index.md")
    assert parse_result.ok
    assert "Piki 维基索引" in parse_result.payload["headings"]

    proposal = tools.propose_patch(
        reason="test proposal",
        changes=[
            PatchChange(path="wiki/log.md", action="update", content="# test\n"),
        ],
        risk_level=RiskLevel.HIGH,
    )

    assert proposal.requires_approval is True
    assert proposal.affected_files == ["wiki/log.md"]
    assert store.get_task(task.id).pending_approvals
