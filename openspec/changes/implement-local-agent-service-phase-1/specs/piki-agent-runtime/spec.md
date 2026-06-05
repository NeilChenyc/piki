## ADDED Requirements

### Requirement: Operation routing
The system SHALL classify user task input into a controlled Piki operation.

#### Scenario: Query operation
- **WHEN** a user asks a knowledge-base question without requesting writes
- **THEN** the system classifies the task as `query` with read-only risk

#### Scenario: Ingest operation
- **WHEN** a user asks to ingest or compile a source into the wiki
- **THEN** the system classifies the task as `ingest` with high write risk and approval required

### Requirement: Required context assembly
The system SHALL load baseline vault context before running the Piki agent.

#### Scenario: Baseline context
- **WHEN** an agent task starts for a valid vault
- **THEN** the system loads `AGENTS.md`, `purpose.md` when present, and `wiki/index.md`

#### Scenario: Context event
- **WHEN** baseline context is loaded
- **THEN** the system records a `context.loaded` event listing loaded and missing optional files

### Requirement: PikiWikiAgent runner
The system SHALL provide a single agent runner scaffold backed by OpenAI Agents SDK integration points.

#### Scenario: Runner available
- **WHEN** a task is created
- **THEN** the system can construct a `PikiWikiAgent` with instructions, tools, and structured output models

#### Scenario: SDK unavailable fallback
- **WHEN** OpenAI Agents SDK is not installed in the environment
- **THEN** the service still starts and reports the runner as unavailable without breaking read-only API tests

### Requirement: Vault-safe read tools
The system SHALL expose read/analyze/proposal tools that only operate inside the selected vault.

#### Scenario: Read index
- **WHEN** the read file tool is called with `wiki/index.md`
- **THEN** it returns file content and records a tool event

#### Scenario: Reject unsafe path
- **WHEN** a tool is called with a path outside the vault or a sensitive file path
- **THEN** it rejects the call and records a tool error event

### Requirement: Patch proposal only
The system SHALL allow the agent to generate patch proposals without applying them directly.

#### Scenario: Create proposal
- **WHEN** the propose patch tool receives intended file changes
- **THEN** it returns a proposal id, affected files, risk level, diff text, and approval requirement

#### Scenario: No direct write
- **WHEN** a high-risk operation creates a patch proposal
- **THEN** no vault files are changed until approval is resolved
