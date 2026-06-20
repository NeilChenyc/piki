from __future__ import annotations

from datetime import date

from agent_service.application.events import EventPublisher
from agent_service.journal import ChangeJournalService
from agent_service.models import JournalEntry
from agent_service.store import SQLiteStore
from agent_service.vault import Vault
from agent_service.vault.writer import VaultWriter


class DeterministicVaultHelper:
    def __init__(self, *, vault: Vault, store: SQLiteStore, events: EventPublisher, task_id: str):
        self.vault = vault
        self.store = store
        self.events = events
        self.task_id = task_id
        self.writer = VaultWriter(vault)
        self.journal = ChangeJournalService(store=store, events=events)
        self._snapshots = []
        self.changed_files: list[str] = []

    def write_file(self, path: str, content: str) -> bool:
        write = self.writer.write(path, content)
        if not write.changed:
            return False
        self._snapshots.append(self.writer.snapshot_for(write))
        if write.path not in self.changed_files:
            self.changed_files.append(write.path)
        self.events.file_changed(
            self.task_id,
            {
                "path": write.path,
                "action": "write",
                "before_hash": write.before_hash,
                "after_hash": write.after_hash,
                "journal_candidate": True,
            },
        )
        return True

    def append_file(self, path: str, content: str) -> bool:
        write = self.writer.append(path, content)
        if not write.changed:
            return False
        self._snapshots.append(self.writer.snapshot_for(write))
        if write.path not in self.changed_files:
            self.changed_files.append(write.path)
        self.events.file_changed(
            self.task_id,
            {
                "path": write.path,
                "action": "append",
                "before_hash": write.before_hash,
                "after_hash": write.after_hash,
                "journal_candidate": True,
            },
        )
        return True

    def commit_journal_entry(self, *, conversation_id: str, reason: str) -> JournalEntry | None:
        return self.journal.commit_for_task(
            task_id=self.task_id,
            conversation_id=conversation_id,
            reason=reason,
            snapshots=self._snapshots,
        )


def lint_log_entry(addition_count: int) -> str:
    return f"\n## {date.today().isoformat()} 检查 | 自动补充索引\n\n- 补充索引条目：{addition_count} 条。\n"
