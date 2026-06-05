from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class MappedSdkEvent:
    event_type: str
    payload: dict


def extract_text_delta(event) -> str:
    event_type = event_value(event, "type")
    data = event_value(event, "data")
    raw_type = event_value(data, "type") if data is not None else None
    raw = data if raw_type else event
    raw_type = raw_type or event_type
    if raw_type != "response.output_text.delta":
        return ""
    delta = event_value(raw, "delta")
    return delta if isinstance(delta, str) else ""


def map_stream_event(event) -> list[MappedSdkEvent]:
    delta = extract_text_delta(event)
    if delta:
        return [
            MappedSdkEvent("agent.trace.delta", {"delta": delta}),
        ]

    event_type = event_value(event, "type")
    if event_type == "run_item_stream_event":
        name = event_value(event, "name") or ""
        item = event_value(event, "item")
        return [_map_run_item_event(name, item)]

    if event_type == "agent_updated_stream_event":
        new_agent = event_value(event, "new_agent")
        agent_name = event_value(new_agent, "name") or "agent"
        return [
            MappedSdkEvent(
                "agent.trace.event",
                {
                    "kind": "agent_updated",
                    "title": "切换 Agent",
                    "summary": str(agent_name),
                    "status": "completed",
                },
            )
        ]

    return []


def _map_run_item_event(name: str, item) -> MappedSdkEvent:
    if name == "tool_called":
        tool_name = _tool_name_from_item(item)
        title, category = _tool_title_and_category(tool_name)
        return MappedSdkEvent(
            "agent.trace.event",
            {
                "kind": "tool_started",
                "title": title,
                "summary": f"调用工具：{tool_name}" if tool_name else "调用工具。",
                "tool": tool_name,
                "category": category,
                "status": "running",
            },
        )
    if name == "tool_output":
        tool_name = _tool_name_from_item(item)
        return MappedSdkEvent(
            "agent.trace.event",
            {
                "kind": "tool_finished",
                "title": "工具调用完成",
                "summary": _summarize_item_output(item),
                "tool": tool_name,
                "category": _tool_title_and_category(tool_name)[1],
                "status": "completed",
            },
        )
    if name == "reasoning_item_created":
        return MappedSdkEvent(
            "agent.trace.event",
            {
                "kind": "reasoning",
                "title": "正在思考",
                "summary": "模型正在规划下一步。",
                "status": "running",
            },
        )
    if name == "message_output_created":
        return MappedSdkEvent(
            "agent.trace.event",
            {
                "kind": "message_output",
                "title": "生成回答",
                "summary": "模型生成了一段可见回复。",
                "status": "completed",
            },
        )
    return MappedSdkEvent(
        "agent.trace.event",
        {
            "kind": name or "run_item",
            "title": "Agent 事件",
            "summary": name or "run item",
            "status": "completed",
        },
    )


def _tool_name_from_item(item) -> str:
    raw_item = event_value(item, "raw_item") or item
    for key in ("name", "tool_name", "function_name"):
        value = event_value(raw_item, key) or event_value(item, key)
        if isinstance(value, str) and value:
            return value
    function = event_value(raw_item, "function") or event_value(item, "function")
    value = event_value(function, "name")
    return value if isinstance(value, str) else ""


def _summarize_item_output(item) -> str:
    output = event_value(item, "output")
    if output is None:
        output = event_value(event_value(item, "raw_item"), "output")
    if output is None:
        return "工具返回了结果。"
    text = str(output).replace("\n", " ").strip()
    if len(text) > 160:
        return text[:157] + "..."
    return text or "工具返回了结果。"


def _tool_title_and_category(tool_name: str) -> tuple[str, str]:
    if tool_name in {"read_file", "list_files", "search_text", "parse_markdown", "run_lint"}:
        return "正在阅读 Wiki", "read"
    if tool_name in {"write_file", "append_file", "apply_lint_fixes"}:
        return "正在写入 Wiki", "write"
    if tool_name in {"read_external_text_file", "write_canonical_source"}:
        return "正在转换文档", "convert"
    return "正在调用工具", "tool"


def event_value(event, key: str):
    if event is None:
        return None
    if isinstance(event, dict):
        return event.get(key)
    return getattr(event, key, None)
