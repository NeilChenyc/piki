"""Runtime helpers for Piki Agent Service."""

from __future__ import annotations

from typing import TYPE_CHECKING

__all__ = ["PikiWikiAgentRunner", "RunnerStatus", "SmokeTestResult"]

if TYPE_CHECKING:
    from agent_service.runtime.runner import PikiWikiAgentRunner, RunnerStatus, SmokeTestResult


def __getattr__(name: str):
    if name in __all__:
        from agent_service.runtime.runner import PikiWikiAgentRunner, RunnerStatus, SmokeTestResult

        exports = {
            "PikiWikiAgentRunner": PikiWikiAgentRunner,
            "RunnerStatus": RunnerStatus,
            "SmokeTestResult": SmokeTestResult,
        }
        return exports[name]
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
