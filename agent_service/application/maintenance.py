from __future__ import annotations

from pathlib import Path

from agent_service.application.events import EventPublisher
from agent_service.models import (
    ApprovalDecisionRequest,
    ApprovalStatus,
    EventType,
    LintFixRequest,
    RiskLevel,
    SourceRescanRequest,
    TaskKind,
    TaskStatus,
)
from agent_service.store import SQLiteStore
from agent_service.system import (
    apply_lint_fixes,
    scan_sources_for_updates,
)
from agent_service.vault import Vault, VaultAccessError


class JournalService:
    def __init__(self, store: SQLiteStore, events: EventPublisher):
        self.store = store
        self.events = events

    def recent(self, *, limit: int = 20, vault_path: str | None = None) -> dict:
        entries = []
        for entry in self.store.list_journal_entries(limit=limit):
            task = self.store.get_task_for_journal_entry(entry.id)
            if vault_path and str(Path(vault_path).expanduser().resolve()) != task.vault_path:
                continue
            entries.append(
                {
                    "id": entry.id,
                    "conversation_id": entry.conversation_id,
                    "task_id": entry.task_id,
                    "status": entry.status,
                    "affected_files": entry.affected_files,
                    "created_at": entry.created_at,
                    "rolled_back_at": entry.rolled_back_at,
                }
            )
        return {"entries": entries}


class SourceService:
    def __init__(self, store: SQLiteStore, events: EventPublisher):
        self.store = store
        self.events = events

    def rescan(self, request: SourceRescanRequest):
        vault = Vault(request.vault_path)
        vault.validate()
        task = self.store.create_task(
            task_kind=TaskKind.SOURCE_RESCAN,
            risk_level=RiskLevel.LOW,
            vault_path=str(vault.root),
            user_input="source rescan",
            status=TaskStatus.RUNNING,
            summary="扫描 raw/sources 并更新 source manifest。",
        )
        self.events.emit(task.id, EventType.SOURCE_RESCAN_STARTED, {"vault_path": str(vault.root)})
        result = scan_sources_for_updates(vault=vault, store=self.store)
        self.events.emit(task.id, EventType.SOURCE_RESCAN_COMPLETED, result.model_dump(mode="json"))
        self.store.update_task(
            task.id,
            status=TaskStatus.COMPLETED,
            summary=f"扫描完成：新增 {len(result.new_sources)}，修改 {len(result.modified_sources)}，缺失 {len(result.missing_sources)}。",
            output=result.model_dump(mode="json"),
        )
        self.events.task_completed(task.id, summary="source rescan completed")
        return result


class LintService:
    def __init__(self, store: SQLiteStore, events: EventPublisher):
        self.store = store
        self.events = events

    def fix(self, request: LintFixRequest):
        vault = Vault(request.vault_path)
        vault.validate()
        task = self.store.create_task(
            task_kind=TaskKind.MAINTENANCE,
            risk_level=RiskLevel.LOW,
            vault_path=str(vault.root),
            user_input="lint fix",
            status=TaskStatus.RUNNING,
            summary="执行低风险 lint 修复。",
        )
        result = apply_lint_fixes(
            vault=vault,
            store=self.store,
            events=self.events,
            task_id=task.id,
            issue_ids=request.issue_ids,
        )
        self.events.emit(task.id, EventType.LINT_FIX_APPLIED, result.model_dump(mode="json"))
        self.store.update_task(
            task.id,
            status=TaskStatus.COMPLETED,
            summary=result.summary,
            affected_files=result.affected_files,
            output=result.model_dump(mode="json"),
        )
        self.events.task_completed(task.id, summary=result.summary)
        return result


class ApprovalService:
    def __init__(self, store: SQLiteStore, events: EventPublisher):
        self.store = store
        self.events = events

    def resolve(self, task_id: str, request: ApprovalDecisionRequest, status: ApprovalStatus):
        approval = self.store.get_approval(request.approval_id)
        if approval.task_id != task_id:
            raise ValueError("Approval does not belong to task")
        if approval.status != ApprovalStatus.PENDING:
            raise ValueError("Approval is already resolved")
        resolved = self.store.resolve_approval(
            request.approval_id,
            status=status,
            comment=request.comment,
        )
        self.events.emit(
            task_id,
            EventType.APPROVAL_RESOLVED,
            {
                "approval_id": resolved.id,
                "proposal_id": resolved.proposal_id,
                "status": resolved.status.value,
                "comment": resolved.comment,
                "phase_1_note": "No files are modified by approval resolution in Phase 1.",
            },
        )
        remaining_approvals = self.store.get_task(task_id).pending_approvals
        if not remaining_approvals:
            summary = (
                "Approval approved; no files changed in Phase 1."
                if status == ApprovalStatus.APPROVED
                else "Approval rejected; no files changed."
            )
            self.store.update_task(task_id, status=TaskStatus.COMPLETED, summary=summary)
            self.events.task_completed(task_id, summary=summary)
        return resolved
