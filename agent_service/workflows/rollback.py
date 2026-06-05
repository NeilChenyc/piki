from __future__ import annotations

import hashlib
from pathlib import Path

from agent_service.models import EventType, RollbackResult, TaskStatus, utc_now_iso
from agent_service.store import SQLiteStore
from agent_service.vault import Vault, VaultAccessError


class RollbackError(ValueError):
    pass


def run_journal_rollback(
    *,
    store: SQLiteStore,
    journal_entry_id: str,
    task_id: str,
    reason: str = "",
) -> RollbackResult:
    journal = store.get_journal_entry(journal_entry_id)
    task = store.get_task_for_journal_entry(journal_entry_id)
    vault = Vault(task.vault_path)
    recent_ids = {entry.id for entry in store.list_recent_active_journal_entries(limit=2)}
    if journal.id not in recent_ids:
        error = "Journal entry is outside the latest-two active rollback window."
        store.update_journal_status(journal.id, status="rollback_failed")
        store.add_event(task_id, EventType.ROLLBACK_FAILED, {"journal_entry_id": journal.id, "error": error})
        store.update_task(task_id, status=TaskStatus.FAILED, summary=error)
        return RollbackResult(ok=False, journal_entry_id=journal.id, task_id=task_id, status="rollback_failed", error=error)
    if journal.status != "active":
        error = f"Journal entry is not active: {journal.status}"
        store.add_event(task_id, EventType.ROLLBACK_FAILED, {"journal_entry_id": journal.id, "error": error})
        store.update_task(task_id, status=TaskStatus.FAILED, summary=error)
        return RollbackResult(ok=False, journal_entry_id=journal.id, task_id=task_id, status="rollback_failed", error=error)

    try:
        _validate_hashes(vault, journal.snapshots)
        affected_files = _restore_snapshots(vault, journal.snapshots)
    except RollbackError as exc:
        error = str(exc)
        store.update_journal_status(journal.id, status="rollback_failed")
        store.add_event(task_id, EventType.ROLLBACK_FAILED, {"journal_entry_id": journal.id, "error": error})
        store.update_task(task_id, status=TaskStatus.FAILED, summary=error)
        return RollbackResult(ok=False, journal_entry_id=journal.id, task_id=task_id, status="rollback_failed", error=error)

    store.update_journal_status(journal.id, status="rolled_back", rolled_back_at=utc_now_iso())
    summary = f"已回退 journal entry：{journal.id}"
    payload = {
        "journal_entry_id": journal.id,
        "affected_files": affected_files,
        "reason": reason,
    }
    store.add_event(task_id, EventType.ROLLBACK_COMPLETED, payload)
    result = RollbackResult(
        ok=True,
        journal_entry_id=journal.id,
        task_id=task_id,
        status="rolled_back",
        affected_files=affected_files,
    )
    store.update_task(
        task_id,
        status=TaskStatus.COMPLETED,
        summary=summary,
        affected_files=affected_files,
        output=result.model_dump(mode="json"),
    )
    store.add_event(task_id, EventType.TASK_COMPLETED, {"summary": summary})
    return result


def _validate_hashes(vault: Vault, snapshots):
    mismatches = []
    for snapshot in snapshots:
        path = vault.resolve_path(snapshot.path)
        current_content = _read_optional(path)
        current_hash = _content_hash(current_content) if current_content is not None else None
        if current_hash != snapshot.after_hash:
            mismatches.append(
                {
                    "path": snapshot.path,
                    "expected": snapshot.after_hash,
                    "actual": current_hash,
                }
            )
    if mismatches:
        raise RollbackError(f"Rollback hash mismatch: {mismatches}")


def _restore_snapshots(vault: Vault, snapshots) -> list[str]:
    affected_files = []
    for snapshot in snapshots:
        try:
            path = vault.resolve_path(snapshot.path)
        except VaultAccessError as exc:
            raise RollbackError(str(exc)) from exc
        if snapshot.before_content is None:
            if path.exists():
                path.unlink()
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(snapshot.before_content, encoding="utf-8")
        affected_files.append(snapshot.path)
    return affected_files


def _read_optional(path: Path) -> str | None:
    if not path.exists():
        return None
    if not path.is_file():
        raise RollbackError(f"Path is not a file: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def _content_hash(content: str) -> str:
    return "sha256:" + hashlib.sha256(content.encode("utf-8")).hexdigest()
