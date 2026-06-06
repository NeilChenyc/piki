# Piki Product Notes

Working notes after the Claude runtime migration.

## Runtime Notes

- Claude Agent SDK is now the single intended runtime path.
- The client should render Piki-owned product events, not provider-specific raw event names.
- The agent-visible tool surface should stay minimal and default to Claude built-ins.
- Piki should keep owning journal, rollback, staging, and vault safety.

## Interaction Model

- Natural language and slash commands are two faces of the same task API.
- Buttons should inject `action_context`, not bypass the agent with a second workflow tree.
- File attachments are context inputs first; whether they become canonical sources or wiki updates is decided inside the agent loop plus system post-processing.

## Safety Notes

- `AGENTS.md` stays read-only.
- Vault-external writes stay forbidden.
- Bash is useful, but only as a read/extract/compute lane in v1.
- Claude checkpointing is internal infrastructure; product rollback truth stays with Piki journal.
