> Superseded by `openspec/changes/migrate-to-claude-agent-sdk/`.
>
> This change captured the old OpenAI runtime plan and is kept only as historical context.

## Why

Phase 1-3 built the local Agent Service shell, read-only query fallback, and source intake normalization. The service can detect whether `openai-agents` is installed, but it does not yet run a real SDK-backed `PikiWikiAgent`, register vault tools as SDK function tools, or verify an OpenAI-compatible endpoint.

Phase 4 should make the SDK runtime real while keeping the product boundary clear: Piki owns vault path safety, task events, direct vault writes, and conversation-level change journal records.

## What Changes

- Expand runtime configuration for `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `PIKI_AGENT_MODEL`, and tracing behavior.
- Add a smoke-test path that runs a minimal SDK agent against the configured endpoint.
- Build dynamic `PikiWikiAgent` instructions from vault baseline context.
- Register vault tools as SDK `function_tool`s: `read_file`, `list_files`, `search_text`, `parse_markdown`, `write_file`, and `append_file`.
- Replace the old proposal-only write path with direct vault-internal write helpers, while keeping `AGENTS.md` read-only and vault-external paths non-writable.
- Record tool start/finish/failure task events for SDK tool calls.
- Add a conversation-level journal entry recorder for tasks that truly modify `raw/` or `wiki/`.
- Map SDK final output into stable Piki task output/events.
- Keep the current local read-only query fallback for unconfigured SDK/runtime failures.

## Capabilities

### New Capabilities

- `openai-agents-sdk-runtime`: Runs `PikiWikiAgent` through OpenAI Agents SDK with configured model/endpoint, SDK function tools, smoke test, stable task events, and journal entry recording for raw/wiki writes.

### Modified Capabilities

- `vault-tools`: Adds direct `write_file` and `append_file` tools with vault boundary enforcement and write tracking.
- `agent-service-health`: Reports SDK availability, API key state, base URL, model, and tracing state.

## Impact

- `agent_service/config.py`: Add OpenAI-compatible endpoint/model/tracing configuration.
- `agent_service/runtime/`: Implement SDK agent runner, smoke test, dynamic instructions, and event/result mapping.
- `agent_service/tools/`: Add direct write tools and SDK function tool registration.
- `agent_service/store/`: Add journal entry persistence.
- `agent_service/models/`: Add journal entry and SDK runtime result models/events.
- `agent_service/app.py`: Add smoke test route and route agent tasks through SDK runner with fallback.
- `tests/`: Add unit/integration tests using mocked SDK calls/tools, without requiring a real network endpoint.
