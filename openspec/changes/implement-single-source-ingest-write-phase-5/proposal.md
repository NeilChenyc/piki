## Why

Piki can now normalize files into canonical Markdown sources and run a real OpenAI Agents SDK task with vault-safe read/write tools. The missing MVP step is the LLM Wiki ingest action: turning one canonical source into compiled wiki pages.

Phase 5 should prove the core loop: one `raw/sources/*.md` file can be read, analyzed, and integrated into `wiki/` by the SDK-backed agent, with index/log updates and conversation-level journal tracking.

## What Changes

- Add a single-source ingest workflow hint for `/wiki:ingest`, `/wiki:compile`, or an explicit `raw/sources/*.md` path.
- Resolve and validate exactly one canonical source path under `raw/sources/`.
- Build an ingest-specific SDK prompt that instructs the agent to read the source, inspect related wiki pages, and directly write conservative wiki updates.
- Add structured `IngestResult` output on task records.
- Require the ingest task to update at least a `wiki/sources/` source page, `wiki/index.md`, and `wiki/log.md`.
- Allow conservative updates to `wiki/concepts/`, `wiki/entities/`, and `wiki/domains/`; only create/update `wiki/synthesis/` when the source significantly changes cross-source understanding.
- Preserve phase 4 task events, file-change events, and conversation-level journal entry behavior.
- Keep batch ingest, queues, rollback API, and deep source parsing out of scope.

## Capabilities

### New Capabilities

- `single-source-ingest-write`: SDK-backed ingest of one canonical Markdown source into the compiled wiki layer.

### Modified Capabilities

- `agent-task-api`: Recognizes explicit ingest hints and runs an ingest-specific SDK prompt instead of generic agent prompt.
- `runtime-agent-runner`: Supports an ingest task variant that returns `IngestResult`.

## Impact

- `agent_service/models/`: Add ingest result and extracted item models.
- `agent_service/workflows/`: Add source path detection and ingest prompt construction helpers.
- `agent_service/runtime/`: Add SDK ingest runner method.
- `agent_service/app.py`: Route explicit single-source ingest hints through the SDK-backed ingest flow.
- `tests/`: Add golden-style ingest tests with mocked SDK runner and real vault tool writes.
