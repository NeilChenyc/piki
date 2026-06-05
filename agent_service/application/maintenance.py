from __future__ import annotations

from pathlib import Path

from agent_service.application.events import EventPublisher
from agent_service.models import (
    ApprovalDecisionRequest,
    ApprovalStatus,
    EventType,
    IngestQueueEnqueueRequest,
    IngestQueueProcessRequest,
    IngestQueueStatus,
    LintFixRequest,
    LintRequest,
    RiskLevel,
    RollbackRequest,
    SourceRescanRequest,
    TaskKind,
    TaskStatus,
    UpdateQueueStatus,
)
from agent_service.store import SQLiteStore
from agent_service.vault import Vault, VaultAccessError
from agent_service.workflows import (
    apply_lint_fixes,
    cancel_ingest_queue_item,
    enqueue_ingest_files,
    process_ingest_queue,
    retry_ingest_queue_item,
    run_journal_rollback,
    run_wiki_lint,
    scan_sources_for_updates,
)


class JournalService:
    def __init__(self, store: SQLiteStore, events: EventPublisher):
        self.store = store
        self.events = events

    def recent(self, *, limit: int = 20, vault_path: str | None = None) -> dict:
        eligible_ids = {entry.id for entry in self.store.list_recent_active_journal_entries(limit=2)}
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
                    "eligible_for_rollback": entry.id in eligible_ids and entry.status == "active",
                }
            )
        return {"entries": entries}

    def rollback(self, journal_entry_id: str, request: RollbackRequest | None = None):
        journal_task = self.store.get_task_for_journal_entry(journal_entry_id)
        rollback_task = self.store.create_task(
            task_kind=TaskKind.ROLLBACK,
            risk_level=RiskLevel.LOW,
            vault_path=journal_task.vault_path,
            user_input=f"rollback {journal_entry_id}",
            status=TaskStatus.RUNNING,
            summary=f"回退 journal entry：{journal_entry_id}",
        )
        self.events.task_created(
            rollback_task.id,
            {"task_id": rollback_task.id, "journal_entry_id": journal_entry_id},
        )
        return run_journal_rollback(
            store=self.store,
            journal_entry_id=journal_entry_id,
            task_id=rollback_task.id,
            reason=(request.reason if request else ""),
        )


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
            summary="扫描 raw/sources 并更新 source manifest / update queue。",
        )
        self.events.emit(task.id, EventType.SOURCE_RESCAN_STARTED, {"vault_path": str(vault.root)})
        result = scan_sources_for_updates(vault=vault, store=self.store)
        for item in result.queued_items:
            self.events.emit(task.id, EventType.UPDATE_QUEUE_ITEM_CREATED, item.model_dump(mode="json"))
        self.events.emit(task.id, EventType.SOURCE_RESCAN_COMPLETED, result.model_dump(mode="json"))
        self.store.update_task(
            task.id,
            status=TaskStatus.COMPLETED,
            summary=f"扫描完成：新增 {len(result.new_sources)}，修改 {len(result.modified_sources)}，缺失 {len(result.missing_sources)}。",
            output=result.model_dump(mode="json"),
        )
        self.events.task_completed(task.id, summary="source rescan completed")
        return result

    def update_queue(self, *, status: str | None = "pending", limit: int = 100) -> dict:
        queue_status = UpdateQueueStatus(status) if status else None
        items = self.store.list_update_queue_items(status=queue_status, limit=limit)
        return {"items": [item.model_dump(mode="json") for item in items]}


class IngestQueueService:
    def __init__(self, store: SQLiteStore, events: EventPublisher):
        self.store = store
        self.events = events

    def enqueue(self, request: IngestQueueEnqueueRequest):
        vault = Vault(request.vault_path)
        vault.validate()
        task = self.store.create_task(
            task_kind=TaskKind.INGEST_QUEUE,
            risk_level=RiskLevel.LOW,
            vault_path=str(vault.root),
            user_input="enqueue ingest files",
            status=TaskStatus.RUNNING,
            summary=f"加入 ingest queue：{len(request.selected_paths)} 个文件。",
        )
        result = enqueue_ingest_files(
            store=self.store,
            vault=vault,
            selected_paths=request.selected_paths,
        )
        result.task_id = task.id
        for item in result.items:
            self.events.emit(task.id, EventType.INGEST_QUEUE_ITEM_CREATED, item.model_dump(mode="json"))
        self.store.update_task(
            task.id,
            status=TaskStatus.COMPLETED,
            summary=f"已加入 ingest queue：{len(result.items)} 个文件。",
            output=result.model_dump(mode="json"),
        )
        self.events.task_completed(task.id, summary="ingest queue enqueue completed")
        return result

    def list(self, *, status: str | None = None, vault_path: str | None = None, limit: int = 100) -> dict:
        queue_status = IngestQueueStatus(status) if status else None
        normalized_vault = str(Path(vault_path).expanduser().resolve()) if vault_path else None
        items = self.store.list_ingest_queue_items(
            status=queue_status,
            vault_path=normalized_vault,
            limit=limit,
        )
        return {"items": [item.model_dump(mode="json") for item in items]}

    def process(self, request: IngestQueueProcessRequest):
        normalized_vault = None
        if request.vault_path is not None:
            vault = Vault(request.vault_path)
            vault.validate()
            normalized_vault = str(vault.root)
        task = self.store.create_task(
            task_kind=TaskKind.INGEST_QUEUE,
            risk_level=RiskLevel.LOW,
            vault_path=normalized_vault or "",
            user_input="process ingest queue",
            status=TaskStatus.RUNNING,
            summary="处理 ingest queue。",
        )
        self.events.emit(
            task.id,
            EventType.INGEST_QUEUE_PROCESS_STARTED,
            {"vault_path": normalized_vault, "max_items": request.max_items},
        )
        result = process_ingest_queue(
            store=self.store,
            vault_path=normalized_vault,
            max_items=request.max_items,
        )
        result.task_id = task.id
        self.events.emit(task.id, EventType.INGEST_QUEUE_PROCESS_COMPLETED, result.model_dump(mode="json"))
        self.store.update_task(
            task.id,
            status=TaskStatus.COMPLETED,
            summary=f"队列处理完成：成功 {len(result.completed)}，失败 {len(result.failed)}。",
            output=result.model_dump(mode="json"),
        )
        self.events.task_completed(task.id, summary="ingest queue process completed")
        return result

    def retry(self, item_id: str):
        return retry_ingest_queue_item(store=self.store, item_id=item_id)

    def cancel(self, item_id: str):
        return cancel_ingest_queue_item(store=self.store, item_id=item_id)


class LintService:
    def __init__(self, store: SQLiteStore, events: EventPublisher):
        self.store = store
        self.events = events

    def lint(self, request: LintRequest):
        vault = Vault(request.vault_path)
        vault.validate()
        task = self.store.create_task(
            task_kind=TaskKind.LINT,
            risk_level=RiskLevel.READ_ONLY,
            vault_path=str(vault.root),
            user_input="lint vault",
            status=TaskStatus.RUNNING,
            summary="检查 wiki 健康状态。",
        )
        self.events.emit(task.id, EventType.LINT_STARTED, {"vault_path": str(vault.root)})
        result = run_wiki_lint(vault)
        self.events.emit(task.id, EventType.LINT_COMPLETED, result.model_dump(mode="json"))
        self.store.update_task(
            task.id,
            status=TaskStatus.COMPLETED,
            summary=f"检查完成：发现 {len(result.issues)} 个问题。",
            output=result.model_dump(mode="json"),
        )
        self.events.task_completed(task.id, summary="lint completed")
        return result

    def fix(self, request: LintFixRequest):
        vault = Vault(request.vault_path)
        vault.validate()
        task = self.store.create_task(
            task_kind=TaskKind.LINT,
            risk_level=RiskLevel.LOW,
            vault_path=str(vault.root),
            user_input="lint fix",
            status=TaskStatus.RUNNING,
            summary="执行低风险 lint 修复。",
        )
        result = apply_lint_fixes(
            vault=vault,
            store=self.store,
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
