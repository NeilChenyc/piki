## ADDED Requirements

### Requirement: Local task API
The system SHALL expose a local HTTP API for creating and inspecting agent tasks.

#### Scenario: Create task
- **WHEN** a client posts a task request with a vault path and user input
- **THEN** the system returns a task id, running status, and events URL

#### Scenario: Inspect task
- **WHEN** a client requests a task by id
- **THEN** the system returns the task operation, status, risk level, summary, affected files, and pending approvals

### Requirement: Task event stream
The system SHALL expose an event stream for each task using stable Piki event types rather than raw SDK events.

#### Scenario: Subscribe to task events
- **WHEN** a client subscribes to the task event endpoint
- **THEN** the system streams previously recorded and newly emitted task events in order

#### Scenario: Tool event recorded
- **WHEN** a task reads, searches, or proposes work through a tool
- **THEN** the system records a corresponding Piki event with task id, event type, payload, and timestamp

### Requirement: SQLite task persistence
The system SHALL persist tasks, events, approvals, and sessions in local SQLite storage.

#### Scenario: Restart-safe status
- **WHEN** the service is restarted after a task has emitted events
- **THEN** the task status and recorded events remain available from SQLite

### Requirement: Vault path validation
The system SHALL validate that task operations target an allowed local vault path.

#### Scenario: Missing vault path
- **WHEN** a task request omits the vault path
- **THEN** the system rejects the request with a validation error

#### Scenario: Valid vault path
- **WHEN** a task request points at a vault containing `AGENTS.md` and `wiki/index.md`
- **THEN** the system accepts the task request
