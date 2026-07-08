from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass
class UserFacingError(Exception):
    code: str
    title: str
    message: str
    recovery_suggestion: str | None = None
    retryable: bool = False
    action_label: str | None = None
    action_target: str | None = None
    technical_detail: str | None = None

    def __post_init__(self) -> None:
        Exception.__init__(self, self.message)

    def __str__(self) -> str:
        return self.message

    def to_event_payload(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "error": self.message,
            "error_code": self.code,
            "error_title": self.title,
            "error_message": self.message,
            "retryable": self.retryable,
        }
        if self.recovery_suggestion:
            payload["recovery_suggestion"] = self.recovery_suggestion
        if self.action_label:
            payload["action_label"] = self.action_label
        if self.action_target:
            payload["action_target"] = self.action_target
        return payload

    def to_http_detail(self) -> dict[str, Any]:
        return self.to_event_payload()
