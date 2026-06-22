from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def runtime_log(component: str, message: str, *, extra: dict[str, Any] | None = None) -> None:
    try:
        path = Path.home() / ".piki" / "runtime-worker.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now(UTC).isoformat()
        suffix = ""
        if extra:
            rendered = " ".join(f"{key}={value}" for key, value in extra.items())
            if rendered:
                suffix = f" {rendered}"
        line = f"[{timestamp}] [{component}] {message}{suffix}\n"
        with path.open("a", encoding="utf-8") as handle:
            handle.write(line)
    except OSError:
        pass
