## Context

Piki already supports single-file source intake, single-source SDK ingest, source rescan/update queue, and hash-checked rollback. Stage 8 should queue multiple source files without inventing a background system. Stage 9 should expose vault health issues using deterministic checks first, while leaving SDK-assisted content judgment for later.

## Goals / Non-Goals

**Goals:**

- Queue multiple selected files for source intake.
- Process queued files one at a time or in a small batch.
- Preserve per-item status, error reason, timestamps, produced task id, and source path.
- Allow retry for failed items and cancel for pending items.
- Provide a lint report that is useful without model calls.
- Provide low-risk lint fixes that can update `wiki/index.md` and `wiki/log.md` through normal vault tools/journal tracking.

**Non-Goals:**

- No daemon or background scheduler.
- No browser clipper.
- No support beyond existing MD/TXT/PDF/DOCX intake formats.
- No automatic batch SDK ingest of every queued source.
- No complex graph clustering or surprise scoring.
- No user review queue.

## Decisions

### 1. Queue Processing Is Explicit And Synchronous

The API creates queue items and a client or test calls `POST /ingest-queue/process`. The process endpoint handles a bounded batch and returns a structured result. This keeps behavior visible and testable before the Mac client exists.

### 2. Queue Items Use Existing Source Intake

Each pending item calls `run_source_intake`. The queue item records `source_path` and a child `task_id`. It does not automatically run SDK ingest; users can feed canonical sources into the existing ingest flow or future queue worker.

### 3. Lint Is Deterministic First

The first lint workflow reads Markdown files, parses frontmatter, headings, wikilinks, and `check_after`, then reports structural and recall-health issues. This avoids model cost and makes tests stable.

### 4. Lint Fixes Are Narrow

MVP lint-fix supports low-risk generated changes only:

- Add missing `wiki/index.md` links for existing wiki pages.
- Append a lint summary to `wiki/log.md`.

If those files are modified, the normal `VaultToolRegistry` creates a conversation-level journal entry.

## Risks / Trade-offs

- [Risk] Synchronous batch processing can be slow for large PDFs. -> Mitigation: bounded `max_items` and per-item failure isolation.
- [Risk] Deterministic lint may miss semantic quality issues. -> Mitigation: label content-quality checks as simple heuristics and keep SDK lint extension open.
- [Risk] Duplicate queue entries can confuse users. -> Mitigation: dedupe pending/processing items by original path and vault.
