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

    def trace_delta(self, task_id: str, *, delta: str, content: str) -> TaskEvent:
        return self.emit(
            task_id,
            EventType.AGENT_TRACE_DELTA,
            {
                "delta": delta,
                "content": content,
            },
        )

    def trace_event(
        self,
        task_id: str,
        *,
        kind: str,
        title: str,
        summary: str = "",
        tool: str | None = None,
        category: str | None = None,
        status: str | None = None,
    ) -> TaskEvent:
        payload: dict[str, Any] = {
            "kind": kind,
            "title": title,
            "summary": summary,
        }
        if tool:
            payload["tool"] = tool
        if category:
            payload["category"] = category
        if status:
            payload["status"] = status
        return self.emit(task_id, EventType.AGENT_TRACE_EVENT, payload)

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
        meta = _tool_display_meta(tool)
        return self.emit(task_id, EventType.TOOL_STARTED, {"tool": tool, **meta, **payload})

    def tool_finished(self, task_id: str, tool: str, payload: dict[str, Any]) -> TaskEvent:
        meta = _tool_display_meta(tool)
        return self.emit(task_id, EventType.TOOL_FINISHED, {"tool": tool, **meta, **payload})

    def tool_failed(self, task_id: str, tool: str, error: str) -> TaskEvent:
        meta = _tool_display_meta(tool)
        return self.emit(task_id, EventType.TOOL_FAILED, {"tool": tool, **meta, "error": error})

    def file_changed(self, task_id: str, payload: dict[str, Any]) -> TaskEvent:
        return self.emit(task_id, EventType.FILE_CHANGED, payload)

    def journal_created(self, task_id: str, payload: dict[str, Any]) -> TaskEvent:
        return self.emit(task_id, EventType.JOURNAL_ENTRY_CREATED, payload)


def _tool_display_meta(tool: str) -> dict[str, str]:
    if tool in {"read_file", "list_files", "search_text", "parse_markdown", "run_lint"}:
        return {"category": "read", "title": "正在阅读 Wiki", "summary": _tool_summary(tool)}
    if tool in {"write_file", "append_file"}:
        return {"category": "write", "title": "正在写入 Wiki", "summary": _tool_summary(tool)}
    if tool in {"read_external_text_file", "write_canonical_source"}:
        return {"category": "convert", "title": "正在转换文档", "summary": _tool_summary(tool)}
    if tool == "apply_lint_fixes":
        return {"category": "write", "title": "正在写入 Wiki", "summary": _tool_summary(tool)}
    return {"category": "tool", "title": "正在调用工具", "summary": _tool_summary(tool)}


def _tool_summary(tool: str) -> str:
    return {
        "read_file": "读取 Wiki 文件。",
        "list_files": "列出 Wiki 文件。",
        "search_text": "搜索 Wiki 内容。",
        "parse_markdown": "解析 Markdown 页面。",
        "run_lint": "检查知识库结构。",
        "write_file": "写入 Wiki 文件。",
        "append_file": "追加 Wiki 内容。",
        "read_external_text_file": "读取用户提供的文件。",
        "write_canonical_source": "转换并记录用户提供的文件。",
        "apply_lint_fixes": "应用低风险维护修复。",
    }.get(tool, f"调用 {tool}。")
