from __future__ import annotations

from dataclasses import dataclass

from agent_service.models import RiskLevel, TaskCreateRequest, TaskKind
from agent_service.workflows import IngestWorkflowError, detect_ingest_source_path


@dataclass(frozen=True)
class TaskPlan:
    task_kind: TaskKind
    risk_level: RiskLevel
    summary: str
    ingest_source_path: str | None = None
    ingest_error: str | None = None


class TaskRouter:
    def plan(self, request: TaskCreateRequest) -> TaskPlan:
        ingest_source_path = None
        ingest_error = None
        if not request.selected_paths:
            try:
                ingest_source_path = detect_ingest_source_path(request.user_input)
            except IngestWorkflowError as exc:
                ingest_error = str(exc)

        task_kind = (
            TaskKind.SOURCE_CLEAR
            if request.mode == "clear-inbox-item"
            else TaskKind.SOURCE_INTAKE
            if request.selected_paths
            else TaskKind.INGEST
            if ingest_source_path or ingest_error
            else TaskKind.AGENT
        )
        risk_level = (
            RiskLevel.LOW
            if task_kind in {TaskKind.SOURCE_INTAKE, TaskKind.SOURCE_CLEAR, TaskKind.INGEST}
            else RiskLevel.READ_ONLY
        )
        summary = (
            "清理单个 inbox 文件。"
            if task_kind == TaskKind.SOURCE_CLEAR
            else "用户提供了文件，进入 source intake。"
            if request.selected_paths
            else "显式单 source ingest，进入 SDK-backed wiki 编译。"
            if task_kind == TaskKind.INGEST
            else "统一 agent 任务；当前未启用真实 SDK agent loop 时使用本地只读 query fallback。"
        )
        return TaskPlan(
            task_kind=task_kind,
            risk_level=risk_level,
            summary=summary,
            ingest_source_path=ingest_source_path,
            ingest_error=ingest_error,
        )
