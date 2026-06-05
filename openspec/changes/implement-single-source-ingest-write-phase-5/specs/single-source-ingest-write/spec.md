## ADDED Requirements

### Requirement: Explicit single-source ingest hint
The system SHALL recognize explicit single-source ingest requests without restoring a general operation router.

#### Scenario: Slash command ingest
- **WHEN** a task input contains `/wiki:ingest` or `/wiki:compile` and one `raw/sources/*.md` path
- **THEN** the service treats the task as a single-source ingest workflow

#### Scenario: Source path ingest
- **WHEN** a task input contains one `raw/sources/*.md` path and no selected file upload
- **THEN** the service may treat the task as a single-source ingest workflow

### Requirement: Canonical source validation
The system SHALL only ingest canonical Markdown sources under `raw/sources/` during phase 5.

#### Scenario: Valid canonical source
- **WHEN** the requested source path exists under `raw/sources/` and has `.md` suffix
- **THEN** the ingest workflow can proceed

#### Scenario: Invalid source
- **WHEN** the requested source path is outside `raw/sources/`, missing, or not Markdown
- **THEN** the task fails with a clear error and does not modify wiki files

### Requirement: SDK-backed ingest execution
The system SHALL run single-source ingest through OpenAI Agents SDK when the SDK runtime is configured.

#### Scenario: Ingest uses SDK runner
- **WHEN** a valid ingest task starts and SDK runtime is configured
- **THEN** the service starts an SDK run with ingest-specific instructions and vault tools

### Requirement: Wiki write coverage
The ingest prompt SHALL instruct the agent to update the compiled wiki layer conservatively.

#### Scenario: Minimum wiki updates
- **WHEN** ingest succeeds
- **THEN** the task writes or updates a `wiki/sources/` source page, `wiki/index.md`, and `wiki/log.md`

#### Scenario: Related page updates
- **WHEN** the source clearly affects existing or new concepts, entities, or domains
- **THEN** the agent updates the relevant pages with source links and explicit uncertainty/conflict markers when needed

### Requirement: Structured ingest output
The system SHALL persist `IngestResult` on the task record.

#### Scenario: Task output includes ingest result
- **WHEN** an ingest task completes
- **THEN** task output includes source title, source metadata, summary, extracted entities/concepts/claims/conflicts, changed pages, and journal entry when present

### Requirement: Journaled ingest writes
The system SHALL use the phase 4 change journal path for ingest writes.

#### Scenario: Ingest creates journal entry
- **WHEN** ingest modifies files under `wiki/`
- **THEN** the task creates one conversation-level journal entry covering those modified files
