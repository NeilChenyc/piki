## ADDED Requirements

### Requirement: Queue multiple selected files
The system SHALL allow clients to enqueue multiple local files for source intake.

#### Scenario: Enqueue files
- **WHEN** a client submits a vault path and selected file paths
- **THEN** the system creates pending ingest queue items with original path, vault path, status, and timestamps

#### Scenario: Duplicate pending file
- **WHEN** a file already has a pending or processing queue item for the same vault
- **THEN** the system returns the existing item instead of creating a duplicate

### Requirement: List ingest queue
The system SHALL expose ingest queue items by status.

#### Scenario: List pending items
- **WHEN** a client requests pending ingest queue items
- **THEN** the response includes id, vault path, original path, status, attempts, error, task id, source path, and timestamps

### Requirement: Process ingest queue
The system SHALL process queued files one by one through source intake.

#### Scenario: Successful processing
- **WHEN** a pending item is processed and source intake succeeds
- **THEN** the item is marked completed and records the produced source path and child task id

#### Scenario: Failed processing
- **WHEN** source intake fails for an item
- **THEN** the item is marked failed with an error and later items in the batch can continue

### Requirement: Retry and cancel
The system SHALL support retrying failed items and cancelling pending items.

#### Scenario: Retry failed item
- **WHEN** a failed item is retried
- **THEN** it becomes pending and its error is cleared

#### Scenario: Cancel pending item
- **WHEN** a pending item is cancelled
- **THEN** it becomes cancelled and will not be processed
