## Why

Piki's product entry point is a conversation box with natural language and files, but the current roadmap implementation can only query an existing wiki and assumes ingest already has a usable Markdown source. Phase 3 should create the missing intake step: turn one user-provided MD/TXT/PDF/DOCX file into a canonical Markdown source under `raw/sources/` without touching `wiki/`.

## What Changes

- Add a source intake pipeline for `capture` tasks with selected local file paths.
- Copy the original file into the vault's raw layer according to directory responsibilities.
- Normalize Markdown, text, PDF, and DOCX into canonical Markdown source files.
- Extract minimal source metadata: title, format, hash, original path, stored raw path, source path, size, and timestamps.
- Add a source manifest so unchanged files reuse the existing normalized source instead of duplicating work.
- Persist a structured `SourceIntakeResult` task output.
- Emit task events for intake start, file copied, source normalized, manifest updated, and failures.
- Keep this stage read/write-limited to `raw/` and manifest files; it SHALL NOT update `wiki/`.

## Capabilities

### New Capabilities

- `source-intake-normalization`: Covers single-file capture from a local path, raw storage, MD/TXT/PDF/DOCX text extraction, canonical Markdown source generation, source manifest update, duplicate detection, structured task output, and failure handling.

### Modified Capabilities

None.

## Impact

- `agent_service/models/`: Add source intake result and manifest models.
- `agent_service/operations/`: Add source intake and normalization pipeline.
- `agent_service/vault/`: Add safe write/copy helpers constrained to vault raw/system paths.
- `agent_service/app.py`: Route capture tasks with `selected_paths` through source intake.
- `pyproject.toml`: Add lightweight document extraction dependencies.
- `tests/`: Add golden-style intake tests for Markdown, DOCX, duplicate detection, API output, and wiki non-modification.
