## ADDED Requirements

### Requirement: Source manifest tracking fields
The source manifest SHALL track canonical source content hash, ingest status, source page, last seen time, and missing state.

#### Scenario: Existing manifest migration
- **WHEN** an older manifest record is read
- **THEN** missing tracking fields receive safe defaults

### Requirement: Source rescan
The system SHALL scan canonical Markdown sources under `raw/sources/`.

#### Scenario: New source detected
- **WHEN** a Markdown file exists under `raw/sources/` but has no manifest record
- **THEN** the scan adds a manifest record and creates a pending update queue item

#### Scenario: Modified source detected
- **WHEN** a manifest source file content hash differs from the recorded content hash
- **THEN** the scan updates the manifest and creates a pending update queue item

#### Scenario: Missing source detected
- **WHEN** a manifest source path no longer exists
- **THEN** the scan marks the record missing and creates a pending update queue item

#### Scenario: Unchanged source skipped
- **WHEN** a source file hash matches the manifest content hash
- **THEN** the scan does not create a duplicate pending update item

### Requirement: Update queue listing
The system SHALL expose update queue items.

#### Scenario: List update queue
- **WHEN** a client requests the update queue
- **THEN** pending source update items are returned with id, source path, change type, status, hashes, reason, and timestamps
