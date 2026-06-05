from __future__ import annotations

from datetime import UTC, datetime
from enum import StrEnum
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field


def utc_now_iso() -> str:
    return datetime.now(UTC).isoformat()


class TaskKind(StrEnum):
    AGENT = "agent"
    QUERY = "query"
    INGEST = "ingest"
    INGEST_QUEUE = "ingest-queue"
    LINT = "lint"
    ROLLBACK = "rollback"
    SOURCE_RESCAN = "source-rescan"
    SOURCE_INTAKE = "source-intake"
    SOURCE_CLEAR = "source-clear"


class RiskLevel(StrEnum):
    READ_ONLY = "read-only"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class TaskStatus(StrEnum):
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    NEEDS_APPROVAL = "needs_approval"


class ApprovalStatus(StrEnum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class EventType(StrEnum):
    AGENT_PROGRESS = "agent.progress"
    TASK_CREATED = "task.created"
    INTENT_RECEIVED = "intent.received"
    CONTEXT_LOADED = "context.loaded"
    QUERY_SEARCHED = "query.searched"
    QUERY_COMPLETED = "query.completed"
    INGEST_STARTED = "ingest.started"
    INGEST_COMPLETED = "ingest.completed"
    SOURCE_INTAKE_STARTED = "source_intake.started"
    SOURCE_INTAKE_COPIED = "source_intake.copied"
    SOURCE_INTAKE_NORMALIZED = "source_intake.normalized"
    SOURCE_MANIFEST_UPDATED = "source_manifest.updated"
    SOURCE_CLEARED = "source.cleared"
    SDK_RUN_STARTED = "sdk.run.started"
    SDK_RUN_COMPLETED = "sdk.run.completed"
    MESSAGE_DELTA = "message.delta"
    TOOL_STARTED = "tool.started"
    TOOL_FINISHED = "tool.finished"
    TOOL_FAILED = "tool.failed"
    FILE_CHANGED = "file.changed"
    JOURNAL_ENTRY_CREATED = "journal_entry.created"
    ROLLBACK_COMPLETED = "rollback.completed"
    ROLLBACK_FAILED = "rollback.failed"
    SOURCE_RESCAN_STARTED = "source_rescan.started"
    SOURCE_RESCAN_COMPLETED = "source_rescan.completed"
    UPDATE_QUEUE_ITEM_CREATED = "update_queue.item_created"
    INGEST_QUEUE_ITEM_CREATED = "ingest_queue.item_created"
    INGEST_QUEUE_PROCESS_STARTED = "ingest_queue.process_started"
    INGEST_QUEUE_PROCESS_COMPLETED = "ingest_queue.process_completed"
    LINT_STARTED = "lint.started"
    LINT_COMPLETED = "lint.completed"
    LINT_FIX_APPLIED = "lint.fix_applied"
    DIFF_CREATED = "diff.created"
    APPROVAL_REQUIRED = "approval.required"
    APPROVAL_RESOLVED = "approval.resolved"
    TASK_COMPLETED = "task.completed"
    TASK_FAILED = "task.failed"


class TaskCreateRequest(BaseModel):
    vault_path: Path
    user_input: str = Field(min_length=1)
    selected_paths: list[str] = Field(default_factory=list)
    conversation_id: str | None = None
    mode: str = "normal"
    async_mode: bool = False


class TaskCreateResponse(BaseModel):
    task_id: str
    status: TaskStatus
    events_url: str


class TaskRecord(BaseModel):
    id: str
    task_kind: TaskKind
    status: TaskStatus
    risk_level: RiskLevel
    vault_path: str
    user_input: str
    summary: str = ""
    affected_files: list[str] = Field(default_factory=list)
    pending_approvals: list[str] = Field(default_factory=list)
    output: dict[str, Any] | None = None
    created_at: str
    updated_at: str


class TaskEvent(BaseModel):
    id: str
    task_id: str
    type: EventType | str
    payload: dict[str, Any] = Field(default_factory=dict)
    created_at: str


class PatchChange(BaseModel):
    path: str
    action: str = Field(pattern="^(create|update|delete)$")
    content: str | None = None


class PatchProposal(BaseModel):
    id: str
    task_id: str
    reason: str
    risk_level: RiskLevel
    affected_files: list[str]
    diff: str
    requires_approval: bool


class ApprovalRecord(BaseModel):
    id: str
    task_id: str
    proposal_id: str
    status: ApprovalStatus
    risk_level: RiskLevel
    affected_files: list[str]
    diff: str
    comment: str | None = None
    created_at: str
    resolved_at: str | None = None


class ApprovalDecisionRequest(BaseModel):
    approval_id: str
    comment: str | None = None


class ContextManifest(BaseModel):
    loaded_files: list[str] = Field(default_factory=list)
    missing_optional_files: list[str] = Field(default_factory=list)
    skipped_files: list[dict[str, str]] = Field(default_factory=list)
    search_terms: list[str] = Field(default_factory=list)


class QueryMode(StrEnum):
    QUICK = "quick"
    DEEP = "deep"
    RELATED = "related"


class QueryConfidence(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class Citation(BaseModel):
    path: str
    title: str
    line: int | None = None
    snippet: str = ""


class QueryResult(BaseModel):
    answer: str
    citations: list[Citation] = Field(default_factory=list)
    related_pages: list[str] = Field(default_factory=list)
    confidence: QueryConfidence = QueryConfidence.LOW
    mode: QueryMode = QueryMode.QUICK
    context_manifest: ContextManifest = Field(default_factory=ContextManifest)
    next_actions: list[str] = Field(default_factory=list)


class SourceFormat(StrEnum):
    MARKDOWN = "markdown"
    TEXT = "text"
    PDF = "pdf"
    DOCX = "docx"


class SourceIntakeResult(BaseModel):
    title: str
    format: SourceFormat
    hash: str
    original_path: str
    asset_path: str
    source_path: str
    size_bytes: int
    reused: bool = False
    captured_at: str
    body_preview: str = ""


class SourceManifestRecord(BaseModel):
    hash: str
    title: str
    format: SourceFormat
    original_path: str
    asset_path: str
    source_path: str
    size_bytes: int
    created_at: str
    updated_at: str
    content_hash: str | None = None
    ingested_hash: str | None = None
    ingest_status: str = "pending"
    source_page: str | None = None
    last_seen_at: str | None = None
    missing: bool = False


class UpdateQueueStatus(StrEnum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    DEFERRED = "deferred"


class SourceChangeType(StrEnum):
    NEW = "new"
    MODIFIED = "modified"
    MISSING = "missing"


class UpdateQueueItem(BaseModel):
    id: str
    source_path: str
    change_type: SourceChangeType
    status: UpdateQueueStatus = UpdateQueueStatus.PENDING
    previous_hash: str | None = None
    current_hash: str | None = None
    reason: str = ""
    created_at: str
    updated_at: str


class SourceRescanRequest(BaseModel):
    vault_path: Path


class SourceRescanResult(BaseModel):
    scanned: int = 0
    new_sources: list[str] = Field(default_factory=list)
    modified_sources: list[str] = Field(default_factory=list)
    missing_sources: list[str] = Field(default_factory=list)
    unchanged_sources: list[str] = Field(default_factory=list)
    queued_items: list[UpdateQueueItem] = Field(default_factory=list)
    manifest_path: str = "system/source_manifest.json"


class IngestQueueStatus(StrEnum):
    PENDING = "pending"
    PROCESSING = "processing"
    FAILED = "failed"
    RETRY = "retry"
    CANCELLED = "cancelled"
    COMPLETED = "completed"


class IngestQueueItem(BaseModel):
    id: str
    vault_path: str
    original_path: str
    status: IngestQueueStatus = IngestQueueStatus.PENDING
    attempts: int = 0
    error: str | None = None
    task_id: str | None = None
    source_path: str | None = None
    created_at: str
    updated_at: str


class IngestQueueEnqueueRequest(BaseModel):
    vault_path: Path
    selected_paths: list[str] = Field(min_length=1)


class IngestQueueEnqueueResult(BaseModel):
    items: list[IngestQueueItem] = Field(default_factory=list)
    task_id: str | None = None


class IngestQueueProcessRequest(BaseModel):
    vault_path: Path | None = None
    max_items: int = Field(default=5, ge=1, le=25)


class IngestQueueProcessResult(BaseModel):
    processed: int = 0
    completed: list[IngestQueueItem] = Field(default_factory=list)
    failed: list[IngestQueueItem] = Field(default_factory=list)
    skipped: list[IngestQueueItem] = Field(default_factory=list)
    task_id: str | None = None


class LintSeverity(StrEnum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"


class LintIssueKind(StrEnum):
    MISSING_FRONTMATTER = "missing_frontmatter"
    BROKEN_LINK = "broken_link"
    ORPHAN_PAGE = "orphan_page"
    DUPLICATE_TITLE = "duplicate_title"
    MISSING_INDEX_ENTRY = "missing_index_entry"
    STALE_PAGE = "stale_page"
    THIN_PAGE = "thin_page"
    KNOWLEDGE_GAP = "knowledge_gap"
    MISSING_HEADING = "missing_heading"


class LintIssue(BaseModel):
    id: str
    kind: LintIssueKind
    severity: LintSeverity
    path: str
    message: str
    details: dict[str, Any] = Field(default_factory=dict)
    fixable: bool = False


class LintRequest(BaseModel):
    vault_path: Path


class LintResult(BaseModel):
    generated_at: str
    scanned_files: int = 0
    issues: list[LintIssue] = Field(default_factory=list)
    issue_counts: dict[str, int] = Field(default_factory=dict)
    fixable_issue_ids: list[str] = Field(default_factory=list)


class LintFixRequest(BaseModel):
    vault_path: Path
    issue_ids: list[str] = Field(default_factory=list)


class RollbackRequest(BaseModel):
    reason: str = ""


class RollbackResult(BaseModel):
    ok: bool
    journal_entry_id: str
    task_id: str | None = None
    status: str
    affected_files: list[str] = Field(default_factory=list)
    error: str | None = None


class SourceMeta(BaseModel):
    path: str
    title: str = ""
    format: str = "markdown"
    hash: str | None = None
    source_path: str | None = None


class ExtractedEntity(BaseModel):
    name: str
    kind: str = ""
    summary: str = ""
    page_path: str | None = None


class ExtractedConcept(BaseModel):
    name: str
    summary: str = ""
    page_path: str | None = None


class Claim(BaseModel):
    text: str
    evidence: str = ""
    confidence: QueryConfidence = QueryConfidence.MEDIUM


class Conflict(BaseModel):
    text: str
    existing_page: str | None = None
    resolution: str = ""


class FileSnapshot(BaseModel):
    path: str
    before_hash: str | None = None
    after_hash: str | None = None
    before_content: str | None = None
    after_content: str | None = None


class JournalEntry(BaseModel):
    id: str
    conversation_id: str
    task_id: str
    reason: str
    affected_files: list[str] = Field(default_factory=list)
    diff: str = ""
    snapshots: list[FileSnapshot] = Field(default_factory=list)
    status: str = "active"
    created_at: str
    rolled_back_at: str | None = None


class LintFixResult(BaseModel):
    fixed_issue_ids: list[str] = Field(default_factory=list)
    affected_files: list[str] = Field(default_factory=list)
    journal_entry: JournalEntry | None = None
    task_id: str | None = None
    summary: str = ""


class ToolResult(BaseModel):
    ok: bool
    payload: dict[str, Any] = Field(default_factory=dict)
    error: str | None = None


class AgentResult(BaseModel):
    status: TaskStatus
    summary: str
    answer: str | None = None
    citations: list[dict[str, Any]] = Field(default_factory=list)
    affected_files: list[str] = Field(default_factory=list)
    journal_entry: JournalEntry | None = None
    proposals: list[PatchProposal] = Field(default_factory=list)
    review_items: list[dict[str, Any]] = Field(default_factory=list)
    next_actions: list[str] = Field(default_factory=list)


class IngestResult(BaseModel):
    source_title: str
    source_meta: SourceMeta
    summary: str
    entities: list[ExtractedEntity] = Field(default_factory=list)
    concepts: list[ExtractedConcept] = Field(default_factory=list)
    claims: list[Claim] = Field(default_factory=list)
    conflicts: list[Conflict] = Field(default_factory=list)
    changed_pages: list[str] = Field(default_factory=list)
    journal_entry: JournalEntry | None = None
    next_actions: list[str] = Field(default_factory=list)
