## ADDED Requirements

### Requirement: Single file capture input
The system SHALL accept a single local file path for `capture` tasks through `selected_paths`.

#### Scenario: Capture task receives selected file
- **WHEN** a user creates a `capture` task with exactly one supported selected path
- **THEN** the system processes that file through source intake

### Requirement: Supported file formats
The system SHALL support Markdown, plain text, PDF, and DOCX files for source intake.

#### Scenario: Unsupported file format
- **WHEN** a user creates a `capture` task with an unsupported file extension
- **THEN** the task fails with a clear unsupported-format error and does not modify wiki files

### Requirement: Original file preservation
The system SHALL copy the submitted original file into `raw/assets/<source-slug>/`.

#### Scenario: Original file copied
- **WHEN** a supported file is captured
- **THEN** the output includes the stored asset path under `raw/assets/`

### Requirement: Canonical Markdown source
The system SHALL write extracted content to a canonical Markdown file under `raw/sources/`.

#### Scenario: Markdown source generated
- **WHEN** a supported file is captured successfully
- **THEN** `raw/sources/<source-slug>.md` exists and contains metadata plus extracted body text

### Requirement: Source metadata
The canonical Markdown source SHALL include title, original format, content hash, original path, stored asset path, source path, and captured timestamp.

#### Scenario: Metadata is present
- **WHEN** source intake completes
- **THEN** the generated Markdown source includes frontmatter or metadata lines for title, format, hash, original path, stored asset path, source path, and captured timestamp

### Requirement: Source manifest
The system SHALL maintain `system/source_manifest.json` with one record per normalized source hash.

#### Scenario: Manifest updated
- **WHEN** source intake completes successfully
- **THEN** the manifest contains the file hash, source path, asset path, format, title, size, and timestamps

### Requirement: Duplicate source reuse
The system SHALL reuse an existing normalized source when the same file hash is captured again.

#### Scenario: Duplicate capture
- **WHEN** the same file content is captured twice
- **THEN** the second task returns the existing source path and marks the result as reused

### Requirement: Structured source intake output
The system SHALL persist `SourceIntakeResult` on the task record.

#### Scenario: Task inspection includes source intake result
- **WHEN** a completed capture task is fetched through `GET /tasks/{id}`
- **THEN** the response includes output data with title, format, hash, source path, asset path, and reused status

### Requirement: Wiki non-modification
The system SHALL NOT modify files under `wiki/` during source intake.

#### Scenario: Capture leaves wiki unchanged
- **WHEN** a source intake task completes or fails
- **THEN** existing files under `wiki/` are unchanged
