from __future__ import annotations

import asyncio
import json
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from agent_service.diagnostics import runtime_log
from claude_agent_sdk._internal.sessions import project_key_for_directory  # type: ignore

from agent_service.application.events import EventPublisher


def _parse_iso_timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)
    except ValueError:
        return None


def _clip(value: str, limit: int = 200) -> str:
    value = value.strip()
    if len(value) <= limit:
        return value
    return value[:limit] + "…"


def _tool_title(tool_name: str) -> str:
    return {
        "Read": "正在阅读 Wiki",
        "Glob": "正在浏览文件",
        "Grep": "正在搜索内容",
        "Write": "正在写入 Wiki",
        "Edit": "正在写入 Wiki",
        "MultiEdit": "正在写入 Wiki",
        "Bash": "正在转换文档",
        "AskUserQuestion": "等待你的输入",
    }.get(tool_name, "正在调用工具")


def _tool_category(tool_name: str) -> str:
    return {
        "Read": "read",
        "Glob": "read",
        "Grep": "read",
        "Write": "write",
        "Edit": "write",
        "MultiEdit": "write",
        "Bash": "command",
        "AskUserQuestion": "input",
    }.get(tool_name, "tool")


def _tool_started_summary(tool_name: str, tool_input: dict[str, Any]) -> str:
    if tool_name in {"Read", "Write", "Edit", "MultiEdit"}:
        path = tool_input.get("file_path") or tool_input.get("path")
        if path:
            return f"{tool_name}：{path}"
    if tool_name == "Bash":
        return _clip(str(tool_input.get("command") or ""))
    if tool_name == "AskUserQuestion":
        return _clip(str(tool_input.get("question") or tool_input.get("prompt") or ""))
    return tool_name


def _tool_path(tool_name: str, tool_input: dict[str, Any]) -> str | None:
    if tool_name in {"Read", "Write", "Edit", "MultiEdit"}:
        path = tool_input.get("file_path") or tool_input.get("path")
        return str(path) if path else None
    if tool_name in {"Glob", "Grep"}:
        path = tool_input.get("path")
        return str(path) if path else None
    return None


def _tool_finished_summary(tool_name: str, tool_result: dict[str, Any], tool_input: dict[str, Any] | None = None) -> str:
    if tool_input:
        path = _tool_path(tool_name, tool_input)
        if path:
            return f"{tool_name}：{path}"
    if tool_name == "Bash":
        stdout = str(tool_result.get("stdout") or "").strip()
        stderr = str(tool_result.get("stderr") or "").strip()
        if stdout:
            return _clip(stdout)
        if stderr:
            return _clip(stderr)
    content = tool_result.get("content")
    if isinstance(content, str) and content.strip():
        return _clip(content)
    return tool_name


@dataclass
class ClaudeTranscriptMirror:
    claude_config_dir: Path
    cwd: Path
    task_id: str
    user_input: str
    events: EventPublisher
    emit_message_snapshot: Callable[[str], None] | None = None
    emit_trace_snapshot: Callable[[str], None] | None = None
    resume_session_id: str | None = None
    activation_delay_seconds: float = 2.0
    poll_interval_seconds: float = 0.25
    started_at: datetime = field(default_factory=lambda: datetime.now(UTC))
    started_monotonic: float = field(default_factory=time.monotonic)
    transcript_path: Path | None = None
    active: bool = False

    _offset: int = 0
    _seen_entry_ids: set[str] = field(default_factory=set)
    _tool_names_by_use_id: dict[str, str] = field(default_factory=dict)
    _tool_inputs_by_use_id: dict[str, dict[str, Any]] = field(default_factory=dict)

    async def run(self, stop_event: asyncio.Event) -> None:
        runtime_log("transcript", "run_start", extra={"task_id": self.task_id, "cwd": self.cwd})
        while not stop_event.is_set():
            self._discover_transcript_if_needed()
            self._drain_transcript()
            await asyncio.sleep(self.poll_interval_seconds)
        self._discover_transcript_if_needed()
        self._drain_transcript()
        runtime_log("transcript", "run_stop", extra={"task_id": self.task_id})

    def _discover_transcript_if_needed(self) -> None:
        if self.transcript_path is not None:
            return
        if time.monotonic() - self.started_monotonic < self.activation_delay_seconds:
            return
        project_dir = self._project_dir()
        if not project_dir.exists():
            return
        runtime_log("transcript", "discover_project_dir", extra={"task_id": self.task_id, "project_dir": project_dir})
        if self.resume_session_id:
            candidate = project_dir / f"{self.resume_session_id}.jsonl"
            if candidate.exists():
                self.transcript_path = candidate
                runtime_log("transcript", "discovered_resume_transcript", extra={"task_id": self.task_id, "path": candidate})
                return
        candidates = sorted(
            project_dir.glob("*.jsonl"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        threshold = self.started_at.timestamp() - 5
        for candidate in candidates:
            if candidate.stat().st_mtime < threshold:
                continue
            if self._matches_prompt(candidate):
                self.transcript_path = candidate
                runtime_log("transcript", "discovered_transcript", extra={"task_id": self.task_id, "path": candidate})
                return

    def _project_dir(self) -> Path:
        project_key = project_key_for_directory(str(self.cwd))
        return self.claude_config_dir / "projects" / project_key

    def _matches_prompt(self, path: Path) -> bool:
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                for _ in range(12):
                    line = handle.readline()
                    if not line:
                        break
                    record = json.loads(line)
                    if record.get("type") != "user":
                        continue
                    message = record.get("message") or {}
                    content = message.get("content")
                    if isinstance(content, str) and self.user_input[:40] in content:
                        return True
        except (OSError, json.JSONDecodeError):
            return False
        return False

    def _drain_transcript(self) -> None:
        path = self.transcript_path
        if path is None or not path.exists():
            return
        runtime_log("transcript", "drain_start", extra={"task_id": self.task_id, "path": path, "offset": self._offset})
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                handle.seek(self._offset)
                for line in handle:
                    self._process_line(line)
                self._offset = handle.tell()
        except OSError:
            return
        runtime_log("transcript", "drain_finish", extra={"task_id": self.task_id, "offset": self._offset})

    def _process_line(self, line: str) -> None:
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            return
        timestamp = _parse_iso_timestamp(record.get("timestamp"))
        if timestamp is not None and timestamp < self.started_at:
            return
        entry_id = str(record.get("uuid") or f"{record.get('type')}:{record.get('timestamp')}:{hash(line)}")
        if entry_id in self._seen_entry_ids:
            return
        self._seen_entry_ids.add(entry_id)

        record_type = str(record.get("type") or "")
        if record_type == "assistant":
            self._emit_assistant_record(record)
        elif record_type == "user":
            self._emit_tool_result_record(record)

    def _emit_assistant_record(self, record: dict[str, Any]) -> None:
        message = record.get("message") or {}
        content = message.get("content") or []
        if not isinstance(content, list):
            return
        stop_reason = str(message.get("stop_reason") or "")
        for block in content:
            if not isinstance(block, dict):
                continue
            block_type = str(block.get("type") or "")
            if block_type == "thinking":
                thinking = str(block.get("thinking") or "").strip()
                if thinking:
                    if self.emit_trace_snapshot is not None:
                        self.emit_trace_snapshot(thinking)
                    else:
                        self.events.trace_delta(self.task_id, delta=thinking, content=thinking)
                    runtime_log("transcript", "assistant_thinking", extra={"task_id": self.task_id})
                    self.active = True
            elif block_type == "text":
                text = str(block.get("text") or "")
                if not text:
                    continue
                if stop_reason == "tool_use":
                    if self.emit_trace_snapshot is not None:
                        self.emit_trace_snapshot(text)
                    else:
                        self.events.trace_delta(self.task_id, delta=text, content=text)
                elif self.emit_message_snapshot is not None:
                    self.emit_message_snapshot(text)
                else:
                    self.events.message_delta(self.task_id, delta=text, content=text)
                runtime_log("transcript", "assistant_text", extra={"task_id": self.task_id})
                self.active = True
            elif block_type == "tool_use":
                tool_name = str(block.get("name") or "")
                tool_use_id = str(block.get("id") or "")
                tool_input = block.get("input") or {}
                if tool_use_id:
                    self._tool_names_by_use_id[tool_use_id] = tool_name
                    if isinstance(tool_input, dict):
                        self._tool_inputs_by_use_id[tool_use_id] = tool_input
                payload = {
                    "tool": tool_name,
                    "tool_use_id": tool_use_id,
                    "title": _tool_title(tool_name),
                    "summary": _tool_started_summary(tool_name, tool_input if isinstance(tool_input, dict) else {}),
                    "source_path": _tool_path(tool_name, tool_input if isinstance(tool_input, dict) else {}),
                    "category": _tool_category(tool_name),
                    "status": "running",
                }
                self.events.tool_started(self.task_id, tool_name, payload)
                runtime_log("transcript", "tool_started", extra={"task_id": self.task_id, "tool": tool_name})
                self.active = True

    def _emit_tool_result_record(self, record: dict[str, Any]) -> None:
        message = record.get("message") or {}
        content = message.get("content") or []
        if not isinstance(content, list):
            return
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_result":
                continue
            tool_use_id = str(block.get("tool_use_id") or "")
            tool_name = self._tool_names_by_use_id.get(tool_use_id, "Tool")
            tool_input = self._tool_inputs_by_use_id.get(tool_use_id, {})
            is_error = bool(block.get("is_error"))
            payload = {
                "tool": tool_name,
                "tool_use_id": tool_use_id,
                "title": _tool_title(tool_name),
                "summary": _tool_finished_summary(tool_name, block, tool_input),
                "source_path": _tool_path(tool_name, tool_input),
                "category": _tool_category(tool_name),
                "status": "failed" if is_error else "completed",
            }
            if is_error:
                self.events.tool_failed(self.task_id, tool_name, payload["summary"], payload)
            else:
                self.events.tool_finished(self.task_id, tool_name, payload)
            runtime_log(
                "transcript",
                "tool_result",
                extra={"task_id": self.task_id, "tool": tool_name, "status": "failed" if is_error else "completed"},
            )
            self.active = True
