## ADDED Requirements

### Requirement: Ingest queue APIs
The local agent service SHALL expose ingest queue APIs.

#### Scenario: Queue API surface
- **WHEN** the service is running
- **THEN** clients can enqueue files, list queue items, process a batch, retry failed items, and cancel pending items

### Requirement: Lint APIs
The local agent service SHALL expose lint APIs.

#### Scenario: Lint API surface
- **WHEN** the service is running
- **THEN** clients can run lint and apply supported low-risk lint fixes
