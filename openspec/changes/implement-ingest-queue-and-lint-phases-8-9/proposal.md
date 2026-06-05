## Why

Phase 8 and 9 complete the MVP maintenance loop after source intake, ingest, source rescan, and rollback are in place. Piki still needs a reliable way to queue multiple incoming files and a deterministic lint pass that makes vault health visible before the Mac client layer.

## What Changes

- Add an ingest queue for selected local files with pending, processing, failed, retry, cancelled, and completed states.
- Add APIs to enqueue multiple files, list queue items, retry failed items, cancel pending items, and process a small batch.
- Process queued files one by one through the existing source intake workflow, preserving per-item status and error details.
- Add a deterministic wiki lint workflow that checks frontmatter, broken wikilinks, orphan pages, duplicate titles, missing index entries, stale `check_after` markers, missing template sections, and simple knowledge gaps.
- Add lint report APIs and low-risk lint-fix support for index/log-oriented maintenance that records normal task events and journal entries when `wiki/` changes.
- Keep background workers, complex graph clustering, browser capture, and all-format import out of scope.

## Capabilities

### New Capabilities

- `ingest-queue`: File intake queue, batch processing, retry, cancel, and queue status APIs.
- `wiki-lint-maintenance`: Deterministic wiki lint report, health issue models, and low-risk fix workflow.

### Modified Capabilities

- `agent-service-api`: Adds ingest queue and lint endpoints.

## Impact

- `agent_service/models/`: Add ingest queue and lint models/events.
- `agent_service/store/`: Add ingest queue SQLite table and status helpers.
- `agent_service/workflows/`: Add queue processor and lint workflow.
- `agent_service/app.py`: Add queue and lint APIs.
- `tests/`: Add ingest queue processing, retry/cancel, lint report, and lint-fix tests.
- `docs/product/`: Keep roadmap/runtime docs aligned with no file-back MVP scope.
