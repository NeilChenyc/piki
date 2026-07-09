from __future__ import annotations

import hashlib
from pathlib import Path

from agent_service.models import (
    SourceFormat,
    SourceManifestRecord,
    SourceRescanResult,
    utc_now_iso,
)
from agent_service.store import SQLiteStore
from agent_service.vault import Vault
from agent_service.workflows.source_intake import (
    MANIFEST_PATH,
    extract_title,
    read_source_manifest,
    write_source_manifest,
)


def scan_sources_for_updates(*, vault: Vault, store: SQLiteStore | None = None) -> SourceRescanResult:
    manifest = read_source_manifest(vault)
    records_by_path = {record.source_path: (source_hash, record) for source_hash, record in manifest.items()}
    now = utc_now_iso()
    result = SourceRescanResult()
    raw_sources = vault.resolve_path("raw/sources")
    raw_sources.mkdir(parents=True, exist_ok=True)

    seen_paths: set[str] = set()
    for path in sorted(raw_sources.rglob("*.md")):
        relative = str(path.relative_to(vault.root))
        seen_paths.add(relative)
        result.scanned += 1
        content = path.read_text(encoding="utf-8", errors="replace")
        current_hash = _content_hash(content)
        key_record = records_by_path.get(relative)
        if key_record is None:
            title = extract_title(path, content)
            record = SourceManifestRecord(
                hash=current_hash,
                title=title,
                format=SourceFormat.MARKDOWN,
                original_path=relative,
                asset_path="",
                source_path=relative,
                size_bytes=path.stat().st_size,
                created_at=now,
                updated_at=now,
                content_hash=current_hash,
                ingest_status="pending",
                last_seen_at=now,
                missing=False,
            )
            manifest[current_hash] = record
            result.new_sources.append(relative)
            continue

        source_hash, record = key_record
        previous_hash = record.content_hash
        record.last_seen_at = now
        record.missing = False
        record.size_bytes = path.stat().st_size
        if previous_hash is None:
            record.content_hash = current_hash
            record.updated_at = now
            if record.ingest_status == "":
                record.ingest_status = "pending"
            result.unchanged_sources.append(relative)
        elif previous_hash != current_hash:
            record.content_hash = current_hash
            record.ingest_status = "pending_update"
            record.updated_at = now
            result.modified_sources.append(relative)
        else:
            result.unchanged_sources.append(relative)
        manifest[source_hash] = record

    for source_hash, record in list(manifest.items()):
        if record.source_path in seen_paths:
            continue
        if record.source_path.startswith("raw/sources/") and not record.missing:
            record.missing = True
            record.ingest_status = "missing"
            record.updated_at = now
            result.missing_sources.append(record.source_path)
            manifest[source_hash] = record

    write_source_manifest(vault, manifest)
    result.manifest_path = MANIFEST_PATH
    return result


def _content_hash(content: str) -> str:
    return "sha256:" + hashlib.sha256(content.encode("utf-8")).hexdigest()
