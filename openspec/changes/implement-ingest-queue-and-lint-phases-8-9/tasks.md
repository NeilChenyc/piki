## 1. OpenSpec Artifacts

- [x] 1.1 Add proposal, design, tasks, and delta specs for phases 8 and 9

## 2. Ingest Queue Models And Store

- [x] 2.1 Add ingest queue status, item, request, and result models
- [x] 2.2 Add ingest queue SQLite table and migrations
- [x] 2.3 Add enqueue/list/get/status helper methods with pending dedupe

## 3. Ingest Queue Workflow And API

- [x] 3.1 Implement bounded synchronous queue processing via source intake
- [x] 3.2 Preserve per-item success/failure status, error, task id, source path, and attempts
- [x] 3.3 Add enqueue/list/process/retry/cancel APIs
- [x] 3.4 Add queue success, failure, retry, cancel, and dedupe tests

## 4. Lint Models And Workflow

- [x] 4.1 Add lint issue/report/fix request/result models
- [x] 4.2 Implement frontmatter, broken link, orphan, duplicate title, missing index, stale, thin page, and knowledge gap checks
- [x] 4.3 Implement narrow low-risk lint fix for missing index entries and lint log append

## 5. Lint API And Tests

- [x] 5.1 Add lint run and lint fix APIs
- [x] 5.2 Add lint report tests
- [x] 5.3 Add lint fix and journal tests

## 6. Documentation And Verification

- [x] 6.1 Update agent_service README and product docs if implementation boundaries changed
- [x] 6.2 Run unit/integration tests
- [x] 6.3 Run OpenSpec validation and compile checks
- [x] 6.4 Run diff check and clean generated caches
