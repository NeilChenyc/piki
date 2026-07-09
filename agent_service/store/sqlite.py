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
    JournalEntry,
    RiskLevel,
    TaskKind,
    TaskEvent,
    TaskRecord,
    TaskStatus,
    utc_now_iso,
)
from agent_service.store.repositories import EventRepository, JournalRepository, TaskRepository
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

    def get_conversation_messages(self, conversation_id: str, *, limit: int = 10) -> list[dict]:
        with self.connect() as conn:
            row = conn.execute("SELECT payload_json FROM sessions WHERE id = ?", (conversation_id,)).fetchone()
        if row is None:
            return []
        try:
            payload = json.loads(row["payload_json"])
        except json.JSONDecodeError:
            return []
        messages = payload.get("messages", [])
        if not isinstance(messages, list):
            return []
        return messages[-limit:]

    def append_conversation_message(
        self,
        conversation_id: str,
        *,
        role: str,
        content: str,
        task_id: str,
        metadata: dict | None = None,
        max_messages: int = 50,
    ):
        messages = self.get_conversation_messages(conversation_id, limit=max_messages)
        messages.append(
            {
                "role": role,
                "content": content,
                "task_id": task_id,
                "metadata": metadata or {},
                "created_at": utc_now_iso(),
            }
        )
        payload = {"messages": messages[-max_messages:]}
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
                (conversation_id, task_id, json.dumps(payload, ensure_ascii=False), now, now),
            )

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
                    "",
                    json.dumps(affected_files, ensure_ascii=False),
                    "[]",
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
