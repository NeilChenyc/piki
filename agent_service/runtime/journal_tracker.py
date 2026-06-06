from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from agent_service.application.events import EventPublisher
from agent_service.journal import ChangeJournalService
from agent_service.models import FileSnapshot
from agent_service.store import SQLiteStore
from agent_service.vault import Vault


@dataclass
class JournalTracker:
    vault: Vault
    store: SQLiteStore
    events: EventPublisher
    task_id: str
    protected_paths: set[Path] = field(default_factory=set)
    _snapshots: dict[str, FileSnapshot] = field(default_factory=dict)
    _changed_files: list[str] = field(default_factory=list)
    illegal_attempts: list[str] = field(default_factory=list)

    def __post_init__(self):
        self.journal = ChangeJournalService(store=self.store, events=self.events)

    @property
    def changed_files(self) -> list[str]:
        return list(self._changed_files)

    def note_illegal_attempt(self, reason: str):
        if reason not in self.illegal_attempts:
            self.illegal_attempts.append(reason)

    def before_write(self, path: str) -> tuple[str, FileSnapshot]:
        relative, file_path = self._resolve_relative(path)
        before_content = file_path.read_text(encoding="utf-8", errors="replace") if file_path.exists() else None
        snapshot = FileSnapshot(
            path=relative,
            before_hash=_content_hash(before_content) if before_content is not None else None,
            before_content=before_content,
        )
        self._snapshots[relative] = snapshot
        return relative, snapshot

    def after_write(self, path: str):
        relative, file_path = self._resolve_relative(path)
        snapshot = self._snapshots.get(relative)
        if snapshot is None:
            _, snapshot = self.before_write(path)
        after_content = file_path.read_text(encoding="utf-8", errors="replace") if file_path.exists() else None
        snapshot.after_content = after_content
        snapshot.after_hash = _content_hash(after_content) if after_content is not None else None
        if snapshot.before_hash != snapshot.after_hash and relative not in self._changed_files:
            self._changed_files.append(relative)
        self.events.file_changed(
            self.task_id,
            {
                "path": relative,
                "before_hash": snapshot.before_hash,
                "after_hash": snapshot.after_hash,
                "journal_candidate": relative.startswith("raw/") or relative.startswith("wiki/"),
            },
        )

    def commit(self, *, conversation_id: str, reason: str):
        return self.journal.commit_for_task(
            task_id=self.task_id,
            conversation_id=conversation_id,
            reason=reason,
            snapshots=list(self._snapshots.values()),
        )

    def _resolve_relative(self, path: str) -> tuple[str, Path]:
        file_path = Path(path).expanduser().resolve()
        relative = str(file_path.relative_to(self.vault.root))
        return relative, file_path


def _content_hash(content: str | None) -> str | None:
    if content is None:
        return None
    import hashlib

    return "sha256:" + hashlib.sha256(content.encode("utf-8")).hexdigest()
