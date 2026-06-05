## ADDED Requirements

### Requirement: Recent journal listing
The system SHALL expose recent journal entries for rollback inspection.

#### Scenario: List recent journal entries
- **WHEN** a client requests recent journal entries
- **THEN** the response includes journal id, task id, conversation id, status, affected files, created time, and rollback eligibility

### Requirement: Latest-two rollback window
The system SHALL allow rollback only for the latest two active raw/wiki modification journal entries.

#### Scenario: Latest journal rollback allowed
- **WHEN** a client requests rollback for the latest active journal entry
- **THEN** the system considers the journal entry eligible

#### Scenario: Third latest rollback denied
- **WHEN** a client requests rollback for an active journal entry older than the latest two
- **THEN** the system rejects rollback without modifying files

### Requirement: Hash checked rollback
The system SHALL validate current file hashes against journal after-hashes before writing rollback contents.

#### Scenario: Hashes match
- **WHEN** all affected files have current hashes equal to recorded after-hashes
- **THEN** the system restores each file to its recorded before-content and marks the journal entry rolled back

#### Scenario: Hash mismatch
- **WHEN** any affected file current hash differs from recorded after-hash
- **THEN** the system fails the whole rollback, writes no files, and marks the journal entry rollback failed

### Requirement: Rollback events
The system SHALL record rollback task events.

#### Scenario: Rollback completed
- **WHEN** rollback succeeds
- **THEN** the system records a rollback completed event and returns affected files

#### Scenario: Rollback failed
- **WHEN** rollback fails
- **THEN** the system records a rollback failed event with the reason
