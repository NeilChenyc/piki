from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class MappedClaudeEvent:
    event_type: str
    payload: dict


def extract_text_delta(message) -> str:
    event = getattr(message, "event", None)
    if not isinstance(event, dict):
        return ""
    if event.get("type") != "content_block_delta":
        return ""
    delta = event.get("delta") or {}
    if isinstance(delta, dict):
        return str(delta.get("text") or "")
    return ""


def extract_text_snapshot(message) -> str:
    content = getattr(message, "content", None)
    if not isinstance(content, list):
        return ""
    text_parts: list[str] = []
    for block in content:
        text = getattr(block, "text", None)
        if text:
            text_parts.append(str(text))
    return "".join(text_parts)


def extract_thinking_delta(message) -> str:
    event = getattr(message, "event", None)
    if not isinstance(event, dict):
        return ""
    if event.get("type") != "content_block_delta":
        return ""
    delta = event.get("delta") or {}
    if not isinstance(delta, dict):
        return ""
    return str(delta.get("thinking") or "")


def extract_thinking_snapshot(message) -> str:
    content = getattr(message, "content", None)
    if not isinstance(content, list):
        return ""
    thoughts: list[str] = []
    for block in content:
        thinking = getattr(block, "thinking", None)
        if thinking:
            thoughts.append(str(thinking))
    return "\n\n".join(thoughts)


def map_stream_event(message) -> list[MappedClaudeEvent]:
    event = getattr(message, "event", None)
    if not isinstance(event, dict):
        return []
    event_type = str(event.get("type") or "")
    if event_type == "content_block_start":
        block = event.get("content_block") or {}
        if isinstance(block, dict) and block.get("type") == "thinking":
            return [
                MappedClaudeEvent(
                    "agent.trace.event",
                    {
                        "kind": "thinking_started",
                        "title": "正在思考",
                        "summary": "Claude 正在规划本轮回答与工具路径。",
                        "category": "model",
                        "status": "running",
                    },
                )
            ]
        if isinstance(block, dict) and block.get("type") == "tool_use":
            tool_name = str(block.get("name") or "")
            tool_use_id = str(block.get("id") or "")
            return [
                MappedClaudeEvent(
                    "tool.started",
                    {
                        "tool": tool_name,
                        "tool_use_id": tool_use_id,
                        "title": _tool_title(tool_name),
                        "summary": _tool_summary(tool_name, block.get("input")),
                        "source_path": _tool_path(tool_name, block.get("input")),
                        "category": _tool_category(tool_name),
                        "status": "running",
                    },
                )
            ]
    if event_type == "content_block_stop":
        return [
            MappedClaudeEvent(
                "agent.trace.event",
                {
                    "kind": "content_block_stop",
                    "title": "阶段完成",
                    "summary": "Claude 完成了一个输出块。",
                    "status": "completed",
                },
            )
        ]
    return []


def _tool_title(tool_name: str) -> str:
    if tool_name in {"Read", "Glob", "Grep"}:
        return "正在阅读 Wiki"
    if tool_name in {"Write", "Edit", "MultiEdit"}:
        return "正在写入 Wiki"
    if tool_name == "Bash":
        return "正在运行命令"
    if tool_name == "AskUserQuestion":
        return "等待你的输入"
    return "正在调用工具"


def _tool_category(tool_name: str) -> str:
    if tool_name in {"Read", "Glob", "Grep"}:
        return "read"
    if tool_name in {"Write", "Edit", "MultiEdit"}:
        return "write"
    if tool_name == "Bash":
        return "command"
    if tool_name == "AskUserQuestion":
        return "input"
    return "tool"


def _tool_summary(tool_name: str, tool_input) -> str:
    if tool_name in {"Read", "Write", "Edit", "MultiEdit"} and isinstance(tool_input, dict):
        path = tool_input.get("file_path") or tool_input.get("path")
        if path:
            return f"{tool_name}：{path}"
    if tool_name == "Bash" and isinstance(tool_input, dict):
        command = str(tool_input.get("command") or "").strip()
        return command[:160]
    if tool_name == "AskUserQuestion" and isinstance(tool_input, dict):
        prompt = str(tool_input.get("question") or tool_input.get("prompt") or "").strip()
        return prompt[:160]
    return tool_name or "tool"


def _tool_path(tool_name: str, tool_input) -> str | None:
    if not isinstance(tool_input, dict):
        return None
    if tool_name in {"Read", "Write", "Edit", "MultiEdit"}:
        path = tool_input.get("file_path") or tool_input.get("path")
        return str(path) if path else None
    if tool_name in {"Glob", "Grep"}:
        path = tool_input.get("path")
        return str(path) if path else None
    return None
