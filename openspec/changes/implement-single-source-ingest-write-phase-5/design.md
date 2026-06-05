## Context

`llm-wiki.md` recommends that ingest is not a one-page summary. A new source should be integrated into the persistent wiki by updating source pages, relevant concept/entity/topic pages, index, and log, while surfacing contradictions and stale claims.

For Piki MVP, phase 5 should implement the first reliable slice of that pattern without trying to solve batching or full graph maintenance.

## Goals / Non-Goals

**Goals:**

- Accept one canonical source path under `raw/sources/`.
- Run the ingest through OpenAI Agents SDK when the SDK runtime is configured.
- Give the agent clear ingest-specific instructions from `AGENTS.md` and product rules.
- Persist a structured `IngestResult`.
- Ensure task output shows changed pages, extracted entities/concepts/claims/conflicts when available, and journal entry id.
- Record tool events, file changes, SDK run events, and journal entry events.
- Keep fallback behavior for non-ingest query tasks.

**Non-Goals:**

- No batch ingest.
- No update queue.
- No rollback API implementation.
- No PDF/DOCX parsing during ingest; phase 3 already normalizes those to Markdown.
- No deterministic local wiki writer that bypasses the SDK for real ingest.

## Decisions

### 1. Use explicit ingest hints, not an operation router

Piki no longer has a general operation layer. Phase 5 recognizes only stable explicit signals: `/wiki:ingest`, `/wiki:compile`, or an explicit `raw/sources/*.md` path. This is a workflow hint, not a broad natural-language classifier.

### 2. Agent does the semantic write

The SDK agent uses the phase 4 vault tools to read related pages and write wiki updates. Piki wraps the run, validates the source path, and records output/events.

### 3. Require a conservative minimum

The prompt requires `wiki/sources/`, `wiki/index.md`, and `wiki/log.md` updates. Concept/entity/domain updates are encouraged when clearly supported. Synthesis is optional and only for significant cross-source changes.

### 4. Structured output is best-effort

In production, the SDK can return structured output. In tests, mocked runs may return an `IngestResult` instance or JSON/text that Piki normalizes into an `IngestResult`. The authoritative record of actual file writes is still the tool registry and journal entry.

## Risks / Trade-offs

- [Risk] Model may under-update related pages. -> Mitigation: ingest prompt requires searching related pages before writing and reporting skipped candidates.
- [Risk] Model may over-update synthesis. -> Mitigation: prompt explicitly limits synthesis to significant cross-source changes.
- [Risk] Tests cannot depend on live model behavior. -> Mitigation: mocked SDK runner executes deterministic tool writes.
