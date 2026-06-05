## Why

Phase 4 and 5 established direct vault writes, task events, and conversation-level journal entries for raw/wiki modifications. The MVP still lacks the user-facing safety and maintenance loop promised in the roadmap:

- Roll back the latest two raw/wiki modification conversations when hashes still match.
- Scan canonical sources for changes and queue source updates instead of silently rewriting the wiki.

Phases 6 and 7 should complete those two product safety rails without adding batch ingest workers or user review queues.

## What Changes

- Add rollback request/result models.
- Add APIs for listing recent journal entries and rolling back a journal entry.
- Enforce the "latest two journal entries only" rollback window.
- Validate current file hashes against journal `after_hash` before rollback.
- Fail the entire rollback if any hash mismatches; no partial rollback.
- Mark journal entries as `rolled_back` or `rollback_failed`.
- Extend source manifest records with canonical source content hash, ingest status, source page, last seen timestamp, and missing marker.
- Add SQLite update queue records for source changes.
- Add a source rescan API that scans `raw/sources/*.md`, updates manifest metadata, and enqueues new/modified/missing sources.
- Keep automatic queue processing out of scope; queued sources can later be processed by phase 5 single-source ingest or phase 8 queue workers.

## Capabilities

### New Capabilities

- `journal-rollback`: Hash-checked rollback for the latest two raw/wiki modification journal entries.
- `source-update-scan`: Source manifest scan and update queue creation for canonical Markdown source changes.

### Modified Capabilities

- `source-manifest`: Adds fields needed to compare canonical source contents and track ingest/update status.
- `agent-service-api`: Adds rollback and source rescan/list endpoints.

## Impact

- `agent_service/models/`: Add rollback and update queue models.
- `agent_service/store/`: Add update queue table and journal status helpers.
- `agent_service/workflows/`: Add rollback and source update scan workflows.
- `agent_service/app.py`: Add rollback, recent journal, rescan, and update queue APIs.
- `tests/`: Add hash rollback tests, rollback failure tests, latest-two-window tests, source scan/update queue tests, and a real SDK smoke test when environment is configured.
