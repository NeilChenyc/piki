## ADDED Requirements

### Requirement: Approval records
The system SHALL persist approval records for patch proposals that require user confirmation.

#### Scenario: Approval required
- **WHEN** a high-risk patch proposal is created
- **THEN** the system creates a pending approval record containing the proposal id, diff, affected files, and risk level

#### Scenario: Approval listed on task
- **WHEN** a client inspects a task with pending approvals
- **THEN** the response includes the pending approval ids

### Requirement: Approve endpoint
The system SHALL expose an endpoint for approving a pending proposal.

#### Scenario: Approve pending proposal
- **WHEN** a client approves a pending approval id
- **THEN** the approval status changes to approved and an `approval.resolved` event is recorded

### Requirement: Reject endpoint
The system SHALL expose an endpoint for rejecting a pending proposal.

#### Scenario: Reject pending proposal
- **WHEN** a client rejects a pending approval id
- **THEN** the approval status changes to rejected and an `approval.resolved` event is recorded

### Requirement: No automatic high-risk apply
The system SHALL NOT apply high-risk patch proposals during Phase 1.

#### Scenario: Approval does not write files
- **WHEN** a pending approval is approved in Phase 1
- **THEN** the system records the decision but does not modify vault files

#### Scenario: Rejection does not write files
- **WHEN** a pending approval is rejected
- **THEN** the system records the decision and does not modify vault files
