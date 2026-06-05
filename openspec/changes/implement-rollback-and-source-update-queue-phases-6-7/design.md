## Context

Piki now lets the SDK agent write vault files directly. The safety model is no longer write-before-review; it is:

- Vault path boundaries.
- Conversation-level journal entries for real raw/wiki modifications.
- Hash-checked rollback of the latest two modification conversations.

Separately, source intake creates canonical sources and a manifest, but the system does not yet notice when `raw/sources/*.md` changes later.

## Goals / Non-Goals

**Goals:**

- Roll back latest or second-latest journal entry when all current hashes still match the journal after-hashes.
- Refuse rollback outside the latest-two window.
- Refuse rollback on any hash mismatch and avoid partial writes.
- Persist rollback status and result events.
- Scan canonical Markdown sources under `raw/sources/`.
- Update manifest metadata without touching `wiki/`.
- Queue source changes in SQLite update queue.
- Expose APIs for source scan and update queue listing.

**Non-Goals:**

- No automatic git commit.
- No branch management.
- No batch queue worker.
- No user review queue.
- No automatic deletion of wiki pages when a source is missing.

## Decisions

### 1. Rollback writes through system code, not agent tools

Rollback is a product safety action. It uses journal snapshots and vault path validation directly. It still records task events and journal status, but it does not rely on the LLM to decide what to restore.

### 2. Whole rollback fails on first detected mismatch

The workflow validates every affected file before writing anything. If any file hash differs from recorded `after_hash`, the journal entry is marked `rollback_failed` and no file is changed.

### 3. Latest two means active recent journal entries

The rollback window is computed from the latest two `active` journal entries ordered by creation time. Already rolled-back entries are not rollback candidates.

### 4. Source scan only queues work

Phase 7 detects source changes and creates update queue items. It does not automatically run phase 5 ingest for every queued item. This prevents silent wiki rewrites and keeps work inspectable.

### 5. Manifest migration is tolerant

Older manifest records may not contain new fields. Pydantic defaults and scan-time updates fill missing fields.

## Risks / Trade-offs

- [Risk] SQLite and manifest can diverge. -> Mitigation: rescan can rebuild source visibility from `raw/sources/` and rewrite manifest metadata.
- [Risk] Rollback can hide later edits if hashes are stale. -> Mitigation: strict after-hash check prevents overwriting changed files.
- [Risk] Real SDK endpoint tests can be flaky or costly. -> Mitigation: keep unit tests mocked; add an opt-in smoke path that runs only when environment is configured.
