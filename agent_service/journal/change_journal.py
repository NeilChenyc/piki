from __future__ import annotations

import difflib

from agent_service.application.events import EventPublisher
from agent_service.models import FileSnapshot, JournalEntry
from agent_service.store import SQLiteStore


class ChangeJournalService:
    def __init__(self, *, store: SQLiteStore, events: EventPublisher):
        self.store = store
        self.events = events

    def commit_for_task(
        self,
        *,
        task_id: str,
        conversation_id: str,
        reason: str,
        snapshots: list[FileSnapshot],
    ) -> JournalEntry | None:
        changed = [snapshot for snapshot in snapshots if snapshot.before_hash != snapshot.after_hash]
        journalable = [snapshot for snapshot in changed if _is_journal_path(snapshot.path)]
        if not journalable:
            return None
        affected_files = [snapshot.path for snapshot in journalable]
        diff = "\n".join(_snapshot_diff(snapshot) for snapshot in journalable).strip()
        journal_entry = self.store.create_journal_entry(
            conversation_id=conversation_id,
            task_id=task_id,
            reason=reason,
            affected_files=affected_files,
            snapshots=journalable,
            diff=diff + "\n" if diff else "",
        )
        self.events.journal_created(
            task_id,
            {
                "journal_entry_id": journal_entry.id,
                "conversation_id": conversation_id,
                "affected_files": affected_files,
            },
        )
        return journal_entry


def _is_journal_path(path: str) -> bool:
    return path.startswith("raw/") or path.startswith("wiki/")


def _snapshot_diff(snapshot: FileSnapshot) -> str:
    before = [] if snapshot.before_content is None else snapshot.before_content.splitlines(keepends=True)
    after = [] if snapshot.after_content is None else snapshot.after_content.splitlines(keepends=True)
    return "".join(
        difflib.unified_diff(
            before,
            after,
            fromfile=f"a/{snapshot.path}",
            tofile=f"b/{snapshot.path}",
        )
    )
