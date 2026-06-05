from __future__ import annotations

from typing import Any

from agent_service.models import EventType, TaskEvent
from agent_service.store import SQLiteStore


class EventPublisher:
    def __init__(self, store: SQLiteStore):
        self.store = store

    def emit(self, task_id: str, event_type: EventType | str, payload: dict[str, Any]) -> TaskEvent:
        return self.store.add_event(task_id, event_type, payload)

    def progress(self, task_id: str, stage: str, title: str, detail: str = "") -> TaskEvent:
        return self.emit(
            task_id,
            EventType.AGENT_PROGRESS,
            {
                "stage": stage,
                "title": title,
                "detail": detail,
            },
        )

    def message_delta(self, task_id: str, *, delta: str, content: str) -> TaskEvent:
        return self.emit(
            task_id,
            EventType.MESSAGE_DELTA,
            {
                "delta": delta,
                "content": content,
            },
        )

    def task_created(self, task_id: str, payload: dict[str, Any]) -> TaskEvent:
        return self.emit(task_id, EventType.TASK_CREATED, payload)

    def task_completed(
        self,
        task_id: str,
        *,
        summary: str,
        answer: str | None = None,
        journal_entry_id: str | None = None,
    ) -> TaskEvent:
        payload: dict[str, Any] = {"summary": summary}
        if answer is not None:
            payload["answer"] = answer
        if journal_entry_id is not None:
            payload["journal_entry_id"] = journal_entry_id
        return self.emit(task_id, EventType.TASK_COMPLETED, payload)

    def task_failed(self, task_id: str, error: str, **extra: Any) -> TaskEvent:
        return self.emit(task_id, EventType.TASK_FAILED, {"error": error, **extra})

    def tool_started(self, task_id: str, tool: str, payload: dict[str, Any]) -> TaskEvent:
        return self.emit(task_id, EventType.TOOL_STARTED, {"tool": tool, **payload})

    def tool_finished(self, task_id: str, tool: str, payload: dict[str, Any]) -> TaskEvent:
        return self.emit(task_id, EventType.TOOL_FINISHED, {"tool": tool, **payload})

    def tool_failed(self, task_id: str, tool: str, error: str) -> TaskEvent:
        return self.emit(task_id, EventType.TOOL_FAILED, {"tool": tool, "error": error})

    def file_changed(self, task_id: str, payload: dict[str, Any]) -> TaskEvent:
        return self.emit(task_id, EventType.FILE_CHANGED, payload)

    def journal_created(self, task_id: str, payload: dict[str, Any]) -> TaskEvent:
        return self.emit(task_id, EventType.JOURNAL_ENTRY_CREATED, payload)
