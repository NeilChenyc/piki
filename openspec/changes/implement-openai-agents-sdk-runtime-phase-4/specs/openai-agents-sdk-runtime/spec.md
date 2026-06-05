## ADDED Requirements

### Requirement: SDK runtime configuration
The system SHALL expose OpenAI Agents SDK runtime configuration state through health checks without exposing secrets.

#### Scenario: Health shows runtime configuration
- **WHEN** a client requests `/health`
- **THEN** the response includes SDK availability, API key configured state, base URL, model, runtime enabled state, runtime configured state, and tracing enabled state

### Requirement: SDK smoke test
The system SHALL provide a smoke-test endpoint that runs a minimal SDK agent only when the runtime is configured.

#### Scenario: Smoke test unconfigured
- **WHEN** the SDK runtime is not fully configured
- **THEN** the smoke-test response reports `ok: false` with a clear configuration error

#### Scenario: Smoke test configured
- **WHEN** the SDK runtime is configured and the endpoint returns successfully
- **THEN** the smoke-test response reports `ok: true` and includes the model output

### Requirement: SDK function tools
The system SHALL register vault tools as OpenAI Agents SDK function tools.

#### Scenario: SDK tool registry includes vault tools
- **WHEN** the Piki agent is built for an SDK run
- **THEN** it receives `read_file`, `list_files`, `search_text`, `parse_markdown`, `write_file`, and `append_file` tools

### Requirement: Direct vault write tools
The system SHALL allow SDK tools to directly write allowed vault files while blocking `AGENTS.md` and vault-external paths.

#### Scenario: Write allowed wiki file
- **WHEN** the `write_file` tool writes `wiki/log.md`
- **THEN** the file changes and the task records tool and file-change events

#### Scenario: Block AGENTS write
- **WHEN** the `write_file` tool targets `AGENTS.md`
- **THEN** the write is rejected and `AGENTS.md` remains unchanged

### Requirement: Conversation-level journal entry
The system SHALL create at most one journal entry per agent task when the task truly modifies files under `raw/` or `wiki/`.

#### Scenario: Raw or wiki write creates journal entry
- **WHEN** an SDK-backed task writes one or more changed files under `raw/` or `wiki/`
- **THEN** the task creates one journal entry with affected files, before/after hashes, snapshots, and diff

#### Scenario: System-only write does not create journal entry
- **WHEN** an SDK-backed task only writes files outside `raw/` and `wiki/`
- **THEN** no journal entry is created

### Requirement: SDK task execution
The system SHALL run normal agent tasks through OpenAI Agents SDK when the SDK runtime is configured.

#### Scenario: Configured agent task uses SDK
- **WHEN** a client creates an agent task and SDK runtime is configured
- **THEN** the service starts an SDK run, persists final output on the task, and records SDK run events

### Requirement: Read-only fallback
The system SHALL preserve read-only query fallback when the SDK runtime is unavailable, disabled, or unconfigured.

#### Scenario: Unconfigured task uses fallback
- **WHEN** a client creates an agent task and SDK runtime is not configured
- **THEN** the service completes the task through the local read-only query workflow
