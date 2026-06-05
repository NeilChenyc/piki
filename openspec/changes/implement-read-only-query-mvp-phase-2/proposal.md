## Why

Phase 1 created the local Agent Service skeleton, but `query` still only loads baseline context and completes without actually recalling from the compiled wiki. Phase 2 should prove the core Piki promise: given an existing Markdown vault, the service can answer read-only knowledge questions from wiki pages with citations and without reading every raw source.

## What Changes

- Add a read-only query pipeline for `query` tasks.
- Load `wiki/index.md` first and use it as the entry point for recall.
- Add a local Markdown search prototype that supports Chinese-friendly matching.
- Expand recall through wikilinks from initially matched pages.
- Return a structured `QueryResult` with answer text, citations, related pages, mode, and confidence notes.
- Support query modes: quick answer, deep answer, and related-pages-only.
- Keep query read-only; answers may cite relevant pages and suggest follow-up query/lint actions, but must not write files.

## Capabilities

### New Capabilities

- `read-only-query`: Covers index-first wiki query, Markdown recall, Chinese-friendly search, wikilink expansion, citations, query modes, and structured read-only query output.

### Modified Capabilities

None.

## Impact

- `agent_service/models/`: Add query-specific structured output models.
- `agent_service/context/`: Add local search and link expansion helpers for wiki pages.
- `agent_service/operations/`: Add a query pipeline used by the task API.
- `agent_service/app.py`: Execute read-only query tasks through the pipeline and persist output.
- `agent_service/store/sqlite.py`: Persist task output JSON.
- `tests/`: Add query golden-style tests for Chinese recall, citations, modes, and raw-source avoidance.
