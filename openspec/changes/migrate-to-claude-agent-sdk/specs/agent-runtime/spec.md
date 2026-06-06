## ADDED Requirements

### Requirement: Claude runtime is the only primary runtime
The system SHALL use Claude Agent SDK as the primary runtime for normal agent tasks.

#### Scenario: Unconfigured runtime fails clearly
- **WHEN** a client creates a normal task and Claude runtime is unavailable, disabled, or unconfigured
- **THEN** the task fails with a clear runtime-unavailable reason
- **AND** the system does not silently fall back to the historical read-only query path

#### Scenario: Configured task uses Claude runtime
- **WHEN** a client creates a normal task and Claude runtime is configured
- **THEN** the service starts a Claude-backed agent run
- **AND** the task records provider-neutral run events and final output

### Requirement: Agent-visible tools use Claude built-ins
The system SHALL not depend on a custom Piki agent-visible tool registry for the normal runtime path.

#### Scenario: Built-in tools are the agent tool surface
- **WHEN** the runtime constructs a Claude agent session
- **THEN** the normal tool surface is restricted to Claude built-in tools such as `Read`, `Write`, `Edit`, `Glob`, `Grep`, `Bash`, and `AskUserQuestion`

#### Scenario: Deterministic helpers stay outside the tool registry
- **WHEN** the agent needs lint or source extraction support
- **THEN** it invokes local deterministic helpers through `Bash`
- **AND** vault writes still happen through `Write` or `Edit`

### Requirement: Runtime is hermetic
The system SHALL isolate the Claude runtime from host-level memory and default Claude settings.

#### Scenario: Runtime starts with private Claude settings
- **WHEN** the runtime builds Claude options
- **THEN** it uses no host setting sources
- **AND** it disables automatic memory
- **AND** it uses a private `CLAUDE_CONFIG_DIR`

### Requirement: Write boundaries are enforced by hooks
The system SHALL enforce vault safety through Claude tool hooks.

#### Scenario: Block protected write
- **WHEN** the agent attempts to write `AGENTS.md`, a vault-external path, or a runtime-private path
- **THEN** the runtime rejects the tool use

#### Scenario: Block Bash side-effect write
- **WHEN** the agent attempts a Bash command with file-writing side effects
- **THEN** the runtime rejects the command before execution

### Requirement: Tasks can pause for user input and resume
The system SHALL support Claude-driven input pauses and task recovery.

#### Scenario: AskUserQuestion pauses a task
- **WHEN** the runtime reaches an `AskUserQuestion` or deferred approval input
- **THEN** the task enters `input_required`
- **AND** the task output records pending input details

#### Scenario: Input resumes the same session
- **WHEN** a client submits `POST /tasks/{task_id}/input`
- **THEN** the task resumes the same Claude session
- **AND** the service records an input-resolved event before continuing

### Requirement: Journal remains the product rollback truth
The system SHALL continue using Piki journal entries as the user-facing rollback source of truth.

#### Scenario: Raw or wiki write creates one journal entry
- **WHEN** a Claude-backed task changes one or more files under `raw/` or `wiki/`
- **THEN** the task creates at most one conversation-level journal entry for that task

#### Scenario: System-only write does not create journal entry
- **WHEN** a Claude-backed task only changes files outside `raw/` and `wiki/`
- **THEN** the task does not create a rollback-eligible journal entry
