from __future__ import annotations

SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,
  task_kind TEXT NOT NULL,
  status TEXT NOT NULL,
  risk_level TEXT NOT NULL,
  vault_path TEXT NOT NULL,
  user_input TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  affected_files_json TEXT NOT NULL DEFAULT '[]',
  output_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS task_events (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  type TEXT NOT NULL,
  payload_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE IF NOT EXISTS approvals (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  proposal_id TEXT NOT NULL,
  status TEXT NOT NULL,
  risk_level TEXT NOT NULL,
  affected_files_json TEXT NOT NULL DEFAULT '[]',
  diff TEXT NOT NULL,
  comment TEXT,
  created_at TEXT NOT NULL,
  resolved_at TEXT,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  task_id TEXT,
  payload_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS journal_entries (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  task_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  diff TEXT NOT NULL DEFAULT '',
  affected_files_json TEXT NOT NULL DEFAULT '[]',
  snapshots_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  rolled_back_at TEXT,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);
"""


def apply_compat_migrations(conn):
    columns = {
        row["name"]
        for row in conn.execute("PRAGMA table_info(tasks)").fetchall()
    }
    if "output_json" not in columns:
        conn.execute("ALTER TABLE tasks ADD COLUMN output_json TEXT")
    if "task_kind" not in columns:
        conn.execute("ALTER TABLE tasks ADD COLUMN task_kind TEXT NOT NULL DEFAULT 'agent'")
        if "operation" in columns:
            conn.execute(
                """
                UPDATE tasks
                SET task_kind = CASE
                  WHEN operation = 'capture' THEN 'source-intake'
                  WHEN operation = 'query' THEN 'agent'
                  ELSE 'agent'
                END
                """
            )
