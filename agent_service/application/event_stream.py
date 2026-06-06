from __future__ import annotations

import json
import time
from collections.abc import Iterator

from agent_service.models import TaskStatus
from agent_service.store import SQLiteStore


class EventStreamService:
    def __init__(self, store: SQLiteStore, *, heartbeat_interval_seconds: float = 10):
        self.store = store
        self.heartbeat_interval_seconds = heartbeat_interval_seconds

    def task_sse(self, task_id: str) -> Iterator[str]:
        seen_ids = set()
        terminal_seen = False
        last_emit = time.monotonic()
        while True:
            emitted = False
            for event in self.store.list_events(task_id):
                if event.id in seen_ids:
                    continue
                seen_ids.add(event.id)
                emitted = True
                payload = event.model_dump(mode="json")
                yield f"event: {event.type}\n"
                yield f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
                last_emit = time.monotonic()
            task = self.store.get_task(task_id)
            if task.status in {
                TaskStatus.COMPLETED,
                TaskStatus.FAILED,
                TaskStatus.NEEDS_APPROVAL,
                TaskStatus.INPUT_REQUIRED,
            }:
                if terminal_seen and not emitted:
                    break
                terminal_seen = True
            if not emitted and not terminal_seen and time.monotonic() - last_emit >= self.heartbeat_interval_seconds:
                yield ": ping\n\n"
                last_emit = time.monotonic()
            time.sleep(0.25)
