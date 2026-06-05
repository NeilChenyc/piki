## 1. OpenSpec Artifacts

- [x] 1.1 Add proposal, design, tasks, and delta specs for phases 6 and 7

## 2. Rollback Models And Store

- [x] 2.1 Add rollback request/result models
- [x] 2.2 Add journal status update helpers and latest-two listing
- [x] 2.3 Add rollback task/event persistence

## 3. Rollback Workflow And API

- [x] 3.1 Implement hash-checked rollback workflow
- [x] 3.2 Enforce latest-two active journal rollback window
- [x] 3.3 Add recent journal and rollback API endpoints
- [x] 3.4 Add rollback success, mismatch, and outside-window tests

## 4. Source Manifest And Update Queue Models

- [x] 4.1 Extend source manifest records with canonical source tracking fields
- [x] 4.2 Add update queue item model and SQLite table
- [x] 4.3 Add update queue create/list helpers with pending dedupe

## 5. Source Change Scan Workflow And API

- [x] 5.1 Implement raw/sources Markdown scan and content hashing
- [x] 5.2 Detect new, modified, missing, and unchanged sources
- [x] 5.3 Update source manifest without modifying wiki
- [x] 5.4 Add source rescan and update queue list APIs
- [x] 5.5 Add source scan and queue tests

## 6. Verification

- [x] 6.1 Run unit/integration tests
- [x] 6.2 Run OpenSpec validation and compile checks
- [x] 6.3 Run real SDK smoke test when configured
- [x] 6.4 Run diff check and clean generated caches
