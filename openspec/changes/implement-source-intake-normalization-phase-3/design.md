## Context

Phase 2 can answer read-only queries from compiled wiki pages. The next product slice should let a user provide one local file from the main interaction flow and turn it into a durable source. This matches the LLM Wiki pattern: raw sources remain the truth layer, while the wiki is the compiled layer maintained later by ingest.

Current service tasks already accept `selected_paths`, but `capture` only routes as a low-risk operation and does not copy files, extract text, write canonical sources, or track source hashes.

## Goals / Non-Goals

**Goals:**

- Accept one local file path for a `capture` task through `selected_paths`.
- Support `.md`, `.markdown`, `.txt`, `.pdf`, `.docx`.
- Copy the original file into `raw/assets/<source-slug>/`.
- Write a canonical Markdown source into `raw/sources/<source-slug>.md`.
- Include title, source metadata, hash, original path, stored asset path, and extracted body in the Markdown source.
- Maintain a JSON source manifest under `system/source_manifest.json`.
- Reuse an existing source when file hash and format are unchanged.
- Persist `SourceIntakeResult` as task output.
- Emit Piki events for intake progress.
- Keep `wiki/` unchanged.

**Non-Goals:**

- No wiki source page generation.
- No concept/entity/domain/synthesis updates.
- No batch queue.
- No browser clipping.
- No OCR, table extraction, image extraction, or PDF layout reconstruction.

## Decisions

### 1. Use `raw/assets` for original files and `raw/sources` for canonical Markdown

The original file is copied into `raw/assets/<source-slug>/original.<ext>` so binary or rich source material remains available. The normalized Markdown is written to `raw/sources/<source-slug>.md` because downstream ingest should operate on stable text.

Alternative considered: copy originals into `raw/inbox` and leave canonical sources in place. That makes repeated processing less clear and blurs "waiting to process" with "accepted source".

### 2. Store manifest outside `wiki/`

The manifest lives at `system/source_manifest.json`, not under `wiki/`, because it is operational state rather than human-facing compiled knowledge.

Alternative considered: use SQLite only. A JSON manifest keeps the vault portable and inspectable alongside Markdown files.

### 3. Hash extracted from original file bytes

The source hash is SHA-256 of the original file bytes. If the same file content is submitted again, the pipeline returns the existing source path without rewriting.

Alternative considered: hash normalized text. Byte hash better detects exact source identity and avoids ambiguity across formats.

### 4. Minimal extractors with explicit limitations

Markdown/text use direct UTF-8 decoding. DOCX uses `python-docx`. PDF uses `pypdf`. Extraction failures become task failures with a clear error.

Alternative considered: call an LLM or external parser for every document. That is more powerful but too heavy for the source intake MVP and less deterministic.

### 5. Safe writes are constrained to expected vault paths

The pipeline may write only `raw/assets/`, `raw/sources/`, and `system/source_manifest.json`. It must not modify `wiki/` during this stage.

Alternative considered: reuse patch proposal/approval. Source intake is low-risk raw-layer capture and should be directly usable before the higher-risk ingest proposal stage.

## Risks / Trade-offs

- [Risk] PDF extraction quality may be poor. -> Mitigation: record format and extraction limitations in source metadata; deeper PDF parsing remains out of scope.
- [Risk] Slug collisions can occur for similar titles. -> Mitigation: append a short hash prefix to generated source filenames.
- [Risk] Manifest JSON can be edited externally. -> Mitigation: handle missing or malformed manifest as an empty manifest and rewrite valid JSON.
- [Risk] Copying large files can be slow. -> Mitigation: phase 3 handles single files only; queues and background processing come later.
