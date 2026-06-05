from __future__ import annotations

from dataclasses import dataclass

from agent_service.models import RiskLevel, TaskCreateRequest, TaskKind


@dataclass(frozen=True)
class TaskPlan:
    task_kind: TaskKind
    risk_level: RiskLevel
    summary: str
    ingest_source_path: str | None = None
    ingest_error: str | None = None


class TaskRouter:
    def plan(self, request: TaskCreateRequest) -> TaskPlan:
        action = str(request.action_context.get("action") or "").strip()
        task_kind = TaskKind.AGENT
        risk_level = RiskLevel.LOW if request.selected_paths or action or request.mode == "clear-inbox-item" else RiskLevel.READ_ONLY
        summary = "统一 agent 任务；服务端只装配上下文、工具、事件和 journal。"
        if action:
            summary = f"统一 agent 任务，系统动作：{action}。"
        elif request.selected_paths:
            summary = "统一 agent 任务，带用户选择文件上下文。"
        elif request.mode == "clear-inbox-item":
            summary = "受控文件管理动作：清理单个 inbox 文件。"
        return TaskPlan(
            task_kind=task_kind,
            risk_level=risk_level,
            summary=summary,
        )
