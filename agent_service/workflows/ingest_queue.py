from __future__ import annotations

from pathlib import Path

from agent_service.models import (
    EventType,
    IngestQueueEnqueueResult,
    IngestQueueItem,
    IngestQueueProcessResult,
    IngestQueueStatus,
    RiskLevel,
    TaskKind,
    TaskStatus,
)
from agent_service.store import SQLiteStore
from agent_service.vault import Vault
from agent_service.workflows.source_intake import SourceIntakeError, run_source_intake


def enqueue_ingest_files(
    *,
    store: SQLiteStore,
    vault: Vault,
    selected_paths: list[str],
) -> IngestQueueEnqueueResult:
    items = []
    for selected_path in selected_paths:
        normalized_path = str(Path(selected_path).expanduser().resolve())
        item = store.create_ingest_queue_item(
            vault_path=str(vault.root),
            original_path=normalized_path,
        )
        items.append(item)
    return IngestQueueEnqueueResult(items=items)


def process_ingest_queue(
    *,
    store: SQLiteStore,
    vault_path: str | None = None,
    max_items: int = 5,
) -> IngestQueueProcessResult:
    result = IngestQueueProcessResult()
    candidates = store.list_ingest_queue_items(
        vault_path=vault_path,
        processable=True,
        limit=max_items,
    )
    for item in candidates:
        result.processed += 1
        processing_item = store.update_ingest_queue_item(
            item.id,
            status=IngestQueueStatus.PROCESSING,
            attempts=item.attempts + 1,
            clear_error=True,
        )
        child_task = store.create_task(
            task_kind=TaskKind.SOURCE_INTAKE,
            risk_level=RiskLevel.LOW,
            vault_path=processing_item.vault_path,
            user_input=f"process ingest queue item {processing_item.id}",
            status=TaskStatus.RUNNING,
            summary=f"处理 ingest queue item：{processing_item.original_path}",
        )
        store.add_event(
            child_task.id,
            EventType.INGEST_QUEUE_PROCESS_STARTED,
            {"queue_item_id": processing_item.id, "original_path": processing_item.original_path},
        )
        try:
            intake_result = run_source_intake(Vault(processing_item.vault_path), processing_item.original_path)
        except SourceIntakeError as exc:
            failed = store.update_ingest_queue_item(
                processing_item.id,
                status=IngestQueueStatus.FAILED,
                error=str(exc),
                task_id=child_task.id,
            )
            store.add_event(
                child_task.id,
                EventType.TASK_FAILED,
                {"queue_item_id": processing_item.id, "error": str(exc)},
            )
            store.update_task(child_task.id, status=TaskStatus.FAILED, summary=str(exc))
            result.failed.append(failed)
            continue

        completed = store.update_ingest_queue_item(
            processing_item.id,
            status=IngestQueueStatus.COMPLETED,
            clear_error=True,
            task_id=child_task.id,
            source_path=intake_result.source_path,
        )
        summary = (
            f"已复用 source：{intake_result.source_path}"
            if intake_result.reused
            else f"已生成 source：{intake_result.source_path}"
        )
        store.add_event(
            child_task.id,
            EventType.SOURCE_INTAKE_NORMALIZED,
            intake_result.model_dump(mode="json"),
        )
        store.add_event(
            child_task.id,
            EventType.INGEST_QUEUE_PROCESS_COMPLETED,
            {"queue_item_id": processing_item.id, "source_path": intake_result.source_path},
        )
        store.update_task(
            child_task.id,
            status=TaskStatus.COMPLETED,
            summary=summary,
            output=intake_result.model_dump(mode="json"),
        )
        store.add_event(child_task.id, EventType.TASK_COMPLETED, {"summary": summary})
        result.completed.append(completed)
    return result


def retry_ingest_queue_item(*, store: SQLiteStore, item_id: str) -> IngestQueueItem:
    item = store.get_ingest_queue_item(item_id)
    if item.status != IngestQueueStatus.FAILED:
        raise ValueError(f"Only failed ingest queue items can be retried: {item.status.value}")
    return store.update_ingest_queue_item(
        item.id,
        status=IngestQueueStatus.PENDING,
        clear_error=True,
        clear_task=True,
        clear_source=True,
    )


def cancel_ingest_queue_item(*, store: SQLiteStore, item_id: str) -> IngestQueueItem:
    item = store.get_ingest_queue_item(item_id)
    if item.status not in {IngestQueueStatus.PENDING, IngestQueueStatus.RETRY}:
        raise ValueError(f"Only pending ingest queue items can be cancelled: {item.status.value}")
    return store.update_ingest_queue_item(
        item.id,
        status=IngestQueueStatus.CANCELLED,
    )
