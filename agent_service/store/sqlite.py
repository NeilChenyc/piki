from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from uuid import uuid4

from agent_service.models import (
    ApprovalRecord,
    ApprovalStatus,
    EventType,
    FileSnapshot,
    IngestQueueItem,
    IngestQueueStatus,
    JournalEntry,
    RiskLevel,
    SourceChangeType,
    TaskKind,
    TaskEvent,
    TaskRecord,
    TaskStatus,
    UpdateQueueItem,
    UpdateQueueStatus,
    utc_now_iso,
)
from agent_service.store.repositories import EventRepository, JournalRepository, QueueRepository, TaskRepository
from agent_service.store.schema import SCHEMA, apply_compat_migrations


class SQLiteStore:
    def __init__(self, db_path: Path | str):
        self.db_path = Path(db_path)
        if self.db_path != Path(":memory:"):
            self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.init_schema()
        self.tasks = TaskRepository(self)
        self.events = EventRepository(self)
        self.journal = JournalRepository(self)
        self.queues = QueueRepository(self)

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def init_schema(self):
        with self.connect() as conn:
            conn.executescript(SCHEMA)
            apply_compat_migrations(conn)

    def create_task(
        self,
        *,
        task_kind: TaskKind,
        risk_level: RiskLevel,
        vault_path: str,
        user_input: str,
        status: TaskStatus = TaskStatus.RUNNING,
        summary: str = "",
    ) -> TaskRecord:
        task_id = f"task_{uuid4().hex}"
        now = utc_now_iso()
        with self.connect() as conn:
            columns = {
                row["name"]
                for row in conn.execute("PRAGMA table_info(tasks)").fetchall()
            }
            if "operation" in columns:
                conn.execute(
                    """
                    INSERT INTO tasks
                      (id, task_kind, operation, status, risk_level, vault_path, user_input, summary, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        task_id,
                        task_kind.value,
                        task_kind.value,
                        status.value,
                        risk_level.value,
                        vault_path,
                        user_input,
                        summary,
                        now,
                        now,
                    ),
                )
            else:
                conn.execute(
                    """
                    INSERT INTO tasks
                      (id, task_kind, status, risk_level, vault_path, user_input, summary, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        task_id,
                        task_kind.value,
                        status.value,
                        risk_level.value,
                        vault_path,
                        user_input,
                        summary,
                        now,
                        now,
                    ),
                )
        return self.get_task(task_id)

    def get_task(self, task_id: str) -> TaskRecord:
        with self.connect() as conn:
            row = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
            if row is None:
                raise KeyError(f"Task not found: {task_id}")
            approvals = conn.execute(
                "SELECT id FROM approvals WHERE task_id = ? AND status = ? ORDER BY created_at",
                (task_id, ApprovalStatus.PENDING.value),
            ).fetchall()
        return TaskRecord(
            id=row["id"],
            task_kind=TaskKind(row["task_kind"]),
            status=TaskStatus(row["status"]),
            risk_level=RiskLevel(row["risk_level"]),
            vault_path=row["vault_path"],
            user_input=row["user_input"],
            summary=row["summary"],
            affected_files=json.loads(row["affected_files_json"]),
            pending_approvals=[approval["id"] for approval in approvals],
            output=json.loads(row["output_json"]) if row["output_json"] else None,
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    def update_task(
        self,
        task_id: str,
        *,
        status: TaskStatus | None = None,
        summary: str | None = None,
        affected_files: list[str] | None = None,
        output: dict | None = None,
    ) -> TaskRecord:
        task = self.get_task(task_id)
        new_status = status or task.status
        new_summary = task.summary if summary is None else summary
        new_affected = task.affected_files if affected_files is None else affected_files
        new_output = task.output if output is None else output
        with self.connect() as conn:
            conn.execute(
                """
                UPDATE tasks
                SET status = ?, summary = ?, affected_files_json = ?, output_json = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    new_status.value,
                    new_summary,
                    json.dumps(new_affected, ensure_ascii=False),
                    json.dumps(new_output, ensure_ascii=False) if new_output is not None else None,
                    utc_now_iso(),
                    task_id,
                ),
            )
        return self.get_task(task_id)

    def add_event(self, task_id: str, event_type: EventType | str, payload: dict) -> TaskEvent:
        event_id = f"event_{uuid4().hex}"
        now = utc_now_iso()
        type_value = event_type.value if isinstance(event_type, EventType) else str(event_type)
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO task_events (id, task_id, type, payload_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (event_id, task_id, type_value, json.dumps(payload, ensure_ascii=False), now),
            )
        return TaskEvent(
            id=event_id,
            task_id=task_id,
            type=type_value,
            payload=payload,
            created_at=now,
        )

    def list_events(self, task_id: str) -> list[TaskEvent]:
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT * FROM task_events WHERE task_id = ? ORDER BY created_at, id",
                (task_id,),
            ).fetchall()
        return [
            TaskEvent(
                id=row["id"],
                task_id=row["task_id"],
                type=row["type"],
                payload=json.loads(row["payload_json"]),
                created_at=row["created_at"],
            )
            for row in rows
        ]

    def create_approval(
        self,
        *,
        task_id: str,
        proposal_id: str,
        risk_level: RiskLevel,
        affected_files: list[str],
        diff: str,
    ) -> ApprovalRecord:
        approval_id = f"approval_{uuid4().hex}"
        now = utc_now_iso()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO approvals
                  (id, task_id, proposal_id, status, risk_level, affected_files_json, diff, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    approval_id,
                    task_id,
                    proposal_id,
                    ApprovalStatus.PENDING.value,
                    risk_level.value,
                    json.dumps(affected_files, ensure_ascii=False),
                    diff,
                    now,
                ),
            )
        return self.get_approval(approval_id)

    def get_approval(self, approval_id: str) -> ApprovalRecord:
        with self.connect() as conn:
            row = conn.execute("SELECT * FROM approvals WHERE id = ?", (approval_id,)).fetchone()
            if row is None:
                raise KeyError(f"Approval not found: {approval_id}")
        return ApprovalRecord(
            id=row["id"],
            task_id=row["task_id"],
            proposal_id=row["proposal_id"],
            status=ApprovalStatus(row["status"]),
            risk_level=RiskLevel(row["risk_level"]),
            affected_files=json.loads(row["affected_files_json"]),
            diff=row["diff"],
            comment=row["comment"],
            created_at=row["created_at"],
            resolved_at=row["resolved_at"],
        )

    def resolve_approval(
        self,
        approval_id: str,
        *,
        status: ApprovalStatus,
        comment: str | None = None,
    ) -> ApprovalRecord:
        if status not in {ApprovalStatus.APPROVED, ApprovalStatus.REJECTED}:
            raise ValueError("Approval can only be resolved as approved or rejected")
        self.get_approval(approval_id)
        with self.connect() as conn:
            conn.execute(
                """
                UPDATE approvals
                SET status = ?, comment = ?, resolved_at = ?
                WHERE id = ?
                """,
                (status.value, comment, utc_now_iso(), approval_id),
            )
        return self.get_approval(approval_id)

    def create_journal_entry(
        self,
        *,
        conversation_id: str,
        task_id: str,
        reason: str,
        affected_files: list[str],
        snapshots: list[FileSnapshot],
        diff: str,
    ) -> JournalEntry:
        journal_id = f"journal_{uuid4().hex}"
        now = utc_now_iso()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO journal_entries
                  (id, conversation_id, task_id, reason, status, diff, affected_files_json, snapshots_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    journal_id,
                    conversation_id,
                    task_id,
                    reason,
                    "active",
                    diff,
                    json.dumps(affected_files, ensure_ascii=False),
                    json.dumps([snapshot.model_dump(mode="json") for snapshot in snapshots], ensure_ascii=False),
                    now,
                ),
            )
        return self.get_journal_entry(journal_id)

    def get_journal_entry(self, journal_id: str) -> JournalEntry:
        with self.connect() as conn:
            row = conn.execute("SELECT * FROM journal_entries WHERE id = ?", (journal_id,)).fetchone()
            if row is None:
                raise KeyError(f"Journal entry not found: {journal_id}")
        return JournalEntry(
            id=row["id"],
            conversation_id=row["conversation_id"],
            task_id=row["task_id"],
            reason=row["reason"],
            status=row["status"],
            diff=row["diff"],
            affected_files=json.loads(row["affected_files_json"]),
            snapshots=[FileSnapshot(**snapshot) for snapshot in json.loads(row["snapshots_json"])],
            created_at=row["created_at"],
            rolled_back_at=row["rolled_back_at"],
        )

    def list_journal_entries(self, limit: int = 20) -> list[JournalEntry]:
        with self.connect() as conn:
            rows = conn.execute(
                "SELECT id FROM journal_entries ORDER BY created_at DESC, id DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [self.get_journal_entry(row["id"]) for row in rows]

    def list_recent_active_journal_entries(self, limit: int = 2) -> list[JournalEntry]:
        with self.connect() as conn:
            rows = conn.execute(
                """
                SELECT id FROM journal_entries
                WHERE status = 'active'
                ORDER BY created_at DESC, id DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [self.get_journal_entry(row["id"]) for row in rows]

    def update_journal_status(
        self,
        journal_id: str,
        *,
        status: str,
        rolled_back_at: str | None = None,
    ) -> JournalEntry:
        self.get_journal_entry(journal_id)
        with self.connect() as conn:
            conn.execute(
                """
                UPDATE journal_entries
                SET status = ?, rolled_back_at = COALESCE(?, rolled_back_at)
                WHERE id = ?
                """,
                (status, rolled_back_at, journal_id),
            )
        return self.get_journal_entry(journal_id)

    def get_task_for_journal_entry(self, journal_id: str) -> TaskRecord:
        journal = self.get_journal_entry(journal_id)
        return self.get_task(journal.task_id)

    def create_update_queue_item(
        self,
        *,
        source_path: str,
        change_type: SourceChangeType,
        previous_hash: str | None,
        current_hash: str | None,
        reason: str,
    ) -> UpdateQueueItem:
        existing = self.find_pending_update_queue_item(
            source_path=source_path,
            change_type=change_type,
            current_hash=current_hash,
        )
        if existing:
            return existing
        item_id = f"queue_{uuid4().hex}"
        now = utc_now_iso()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO update_queue
                  (id, source_path, change_type, status, previous_hash, current_hash, reason, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    item_id,
                    source_path,
                    change_type.value,
                    UpdateQueueStatus.PENDING.value,
                    previous_hash,
                    current_hash,
                    reason,
                    now,
                    now,
                ),
            )
        return self.get_update_queue_item(item_id)

    def find_pending_update_queue_item(
        self,
        *,
        source_path: str,
        change_type: SourceChangeType,
        current_hash: str | None,
    ) -> UpdateQueueItem | None:
        with self.connect() as conn:
            row = conn.execute(
                """
                SELECT id FROM update_queue
                WHERE source_path = ?
                  AND change_type = ?
                  AND status = ?
                  AND COALESCE(current_hash, '') = COALESCE(?, '')
                ORDER BY created_at DESC, id DESC
                LIMIT 1
                """,
                (
                    source_path,
                    change_type.value,
                    UpdateQueueStatus.PENDING.value,
                    current_hash,
                ),
            ).fetchone()
        return self.get_update_queue_item(row["id"]) if row else None

    def get_update_queue_item(self, item_id: str) -> UpdateQueueItem:
        with self.connect() as conn:
            row = conn.execute("SELECT * FROM update_queue WHERE id = ?", (item_id,)).fetchone()
            if row is None:
                raise KeyError(f"Update queue item not found: {item_id}")
        return UpdateQueueItem(
            id=row["id"],
            source_path=row["source_path"],
            change_type=SourceChangeType(row["change_type"]),
            status=UpdateQueueStatus(row["status"]),
            previous_hash=row["previous_hash"],
            current_hash=row["current_hash"],
            reason=row["reason"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    def list_update_queue_items(
        self,
        *,
        status: UpdateQueueStatus | None = None,
        limit: int = 100,
    ) -> list[UpdateQueueItem]:
        if status is None:
            query = "SELECT id FROM update_queue ORDER BY created_at DESC, id DESC LIMIT ?"
            params = (limit,)
        else:
            query = "SELECT id FROM update_queue WHERE status = ? ORDER BY created_at DESC, id DESC LIMIT ?"
            params = (status.value, limit)
        with self.connect() as conn:
            rows = conn.execute(query, params).fetchall()
        return [self.get_update_queue_item(row["id"]) for row in rows]

    def create_ingest_queue_item(
        self,
        *,
        vault_path: str,
        original_path: str,
    ) -> IngestQueueItem:
        existing = self.find_active_ingest_queue_item(vault_path=vault_path, original_path=original_path)
        if existing:
            return existing
        item_id = f"ingestq_{uuid4().hex}"
        now = utc_now_iso()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO ingest_queue
                  (id, vault_path, original_path, status, attempts, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    item_id,
                    vault_path,
                    original_path,
                    IngestQueueStatus.PENDING.value,
                    0,
                    now,
                    now,
                ),
            )
        return self.get_ingest_queue_item(item_id)

    def find_active_ingest_queue_item(self, *, vault_path: str, original_path: str) -> IngestQueueItem | None:
        with self.connect() as conn:
            row = conn.execute(
                """
                SELECT id FROM ingest_queue
                WHERE vault_path = ?
                  AND original_path = ?
                  AND status IN ('pending', 'processing', 'retry')
                ORDER BY created_at DESC, id DESC
                LIMIT 1
                """,
                (vault_path, original_path),
            ).fetchone()
        return self.get_ingest_queue_item(row["id"]) if row else None

    def get_ingest_queue_item(self, item_id: str) -> IngestQueueItem:
        with self.connect() as conn:
            row = conn.execute("SELECT * FROM ingest_queue WHERE id = ?", (item_id,)).fetchone()
            if row is None:
                raise KeyError(f"Ingest queue item not found: {item_id}")
        return IngestQueueItem(
            id=row["id"],
            vault_path=row["vault_path"],
            original_path=row["original_path"],
            status=IngestQueueStatus(row["status"]),
            attempts=row["attempts"],
            error=row["error"],
            task_id=row["task_id"],
            source_path=row["source_path"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    def list_ingest_queue_items(
        self,
        *,
        status: IngestQueueStatus | None = None,
        vault_path: str | None = None,
        processable: bool = False,
        limit: int = 100,
    ) -> list[IngestQueueItem]:
        clauses = []
        params: list[str | int] = []
        if processable:
            clauses.append("status IN ('pending', 'retry')")
        elif status is not None:
            clauses.append("status = ?")
            params.append(status.value)
        if vault_path is not None:
            clauses.append("vault_path = ?")
            params.append(vault_path)
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        params.append(limit)
        with self.connect() as conn:
            rows = conn.execute(
                f"SELECT id FROM ingest_queue {where} ORDER BY created_at ASC, id ASC LIMIT ?",
                tuple(params),
            ).fetchall()
        return [self.get_ingest_queue_item(row["id"]) for row in rows]

    def update_ingest_queue_item(
        self,
        item_id: str,
        *,
        status: IngestQueueStatus | None = None,
        attempts: int | None = None,
        error: str | None = None,
        clear_error: bool = False,
        task_id: str | None = None,
        source_path: str | None = None,
        clear_task: bool = False,
        clear_source: bool = False,
    ) -> IngestQueueItem:
        item = self.get_ingest_queue_item(item_id)
        new_status = status or item.status
        new_attempts = item.attempts if attempts is None else attempts
        new_error = None if clear_error else item.error if error is None else error
        new_task_id = None if clear_task else item.task_id if task_id is None else task_id
        new_source_path = None if clear_source else item.source_path if source_path is None else source_path
        with self.connect() as conn:
            conn.execute(
                """
                UPDATE ingest_queue
                SET status = ?, attempts = ?, error = ?, task_id = ?, source_path = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    new_status.value,
                    new_attempts,
                    new_error,
                    new_task_id,
                    new_source_path,
                    utc_now_iso(),
                    item_id,
                ),
            )
        return self.get_ingest_queue_item(item_id)

    def upsert_session(self, session_id: str, payload: dict, task_id: str | None = None):
        now = utc_now_iso()
        with self.connect() as conn:
            conn.execute(
                """
                INSERT INTO sessions (id, task_id, payload_json, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  task_id = excluded.task_id,
                  payload_json = excluded.payload_json,
                  updated_at = excluded.updated_at
                """,
                (session_id, task_id, json.dumps(payload, ensure_ascii=False), now, now),
            )
