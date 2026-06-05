from __future__ import annotations


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


def event_value(event, key: str):
    if event is None:
        return None
    if isinstance(event, dict):
        return event.get(key)
    return getattr(event, key, None)
