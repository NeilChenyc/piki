## Context

Phase 1 provides a FastAPI task API, SQLite task/event/approval persistence, vault-safe tools, and a minimal OpenAI Agents SDK runner scaffold. A `query` task currently validates the vault, loads baseline context, and completes. It does not search compiled wiki pages, return citations, or expose a structured answer.

Phase 2 is the first real recall slice. It should be deterministic enough for golden tests and conservative enough to preserve the product rule that Markdown wiki pages are the source of truth.

## Goals / Non-Goals

**Goals:**

- Implement a read-only `query` pipeline behind the existing task API.
- Always start from `wiki/index.md`.
- Search compiled `wiki/**/*.md` pages with Chinese-friendly matching.
- Expand recall through wikilinks from matched pages.
- Return structured `QueryResult` data with citations and related pages.
- Support quick, deep, and related-pages-only modes.
- Record query search/loading activity as Piki task events.
- Avoid reading `raw/` sources by default.

**Non-Goals:**

- No vector database or external search service.
- No reranker.
- No full model-backed answer generation requirement.
- No automatic log append, synthesis write, or patch apply.
- No ingest implementation.

## Decisions

### 1. Deterministic local pipeline first

The first implementation will build answers from local Markdown snippets rather than requiring `Runner.run`. This keeps phase 2 testable without API keys and proves the core product behavior before model wording quality is optimized.

Alternative considered: call OpenAI Agents SDK for every query. That matches the final architecture but makes recall tests depend on model availability and nondeterministic generation.

### 2. Index-first recall

The pipeline will always read `wiki/index.md` before searching. The index participates in search ranking and citations, but the search space remains `wiki/**/*.md`.

Alternative considered: search all wiki pages first, then index. That weakens the product contract that the compiled index is the entry point for recall.

### 3. Chinese-friendly lexical search

Search will combine normalized substring matching, ASCII/number tokens, Chinese character tokens, and CJK bigrams. This is intentionally small, local, and dependency-free.

Alternative considered: add jieba or a vector store. Both can improve quality later but are unnecessary for the MVP acceptance criteria.

### 4. Wikilink expansion after initial hits

The pipeline will parse `[[wikilinks]]` in initially matched pages and load matching wiki pages as related context. Link-expanded pages are marked separately from direct hits so citations remain explainable.

Alternative considered: traverse the whole graph. That risks too much context and makes recall less predictable.

### 5. Structured task output JSON

SQLite tasks will gain an `output_json` column. `GET /tasks/{id}` will include the structured output so clients can render answers, citations, and related pages without scraping event text.

Alternative considered: only emit the answer through events. That makes refresh/replay more awkward for the client.

## Risks / Trade-offs

- [Risk] Lexical search may miss semantic matches. -> Mitigation: keep this as MVP search and leave vector/reranker for later stages.
- [Risk] Snippet-built answers may be less fluent than model answers. -> Mitigation: return clear citations and related pages; later SDK answer generation can use the same recall context.
- [Risk] Chinese bigrams can create noisy matches. -> Mitigation: weight direct query substrings and index hits more highly than token overlap.
- [Risk] Persisting output requires a SQLite schema change. -> Mitigation: use `ALTER TABLE` during schema initialization when the column is missing.
