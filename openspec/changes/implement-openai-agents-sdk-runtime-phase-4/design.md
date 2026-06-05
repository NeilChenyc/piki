## Context

The product docs define phase 4 as the point where Piki stops merely detecting the OpenAI Agents SDK and starts using it as the local agent runtime. The implementation must remain conservative:

- The SDK may drive agent/tool loops.
- Piki still owns vault path validation, write permissions, task events, and change journal semantics.
- MVP does not use write-before-review.
- A journal entry is conversation-level: only a task/conversation that truly modifies `raw/` or `wiki/` creates one entry.
- `AGENTS.md` is read-only.
- Vault-external paths are never writable.

## Goals / Non-Goals

**Goals:**

- Build a minimal SDK-backed `PikiWikiAgent` runner.
- Support OpenAI-compatible endpoint config.
- Provide a deterministic smoke-test API/runner method.
- Register Piki vault tools as SDK function tools.
- Let agent tools read/write vault-internal allowed paths.
- Track direct writes and create at most one journal entry per task when raw/wiki changed.
- Preserve task events for tool calls and SDK completion.
- Keep local fallback behavior when SDK is unavailable or unconfigured.

**Non-Goals:**

- No phase 5 ingest generation rules.
- No multi-agent handoff.
- No MCP tools.
- No complex session memory.
- No rollback API implementation beyond journal persistence.
- No network-dependent tests.

## Decisions

### 1. Use the installed `agents` package directly

`PikiWikiAgentRunner` imports `Agent`, `Runner`, and `function_tool`. It exposes a thin `run_task` method and a `smoke_test` method. This keeps SDK-specific code in `agent_service/runtime/`.

### 2. Use sync SDK calls for the MVP API path

The current FastAPI route is sync and tests are sync. Phase 4 uses `Runner.run_sync` where available. Async streaming can come later; the API still emits stable Piki events after each tool call and completion.

### 3. Tool registry remains the safety boundary

SDK tools are wrappers around `VaultToolRegistry`. The registry validates all paths, blocks `AGENTS.md` writes, blocks vault-external writes via `Vault.resolve_path`, records tool events, and tracks write snapshots.

### 4. Journal entries are produced after the run

Each write tool records before/after snapshots in memory for the current task. After the SDK run completes, the runner asks the registry to persist one journal entry if any tracked file under `raw/` or `wiki/` actually changed.

### 5. Tests mock the SDK runner boundary

Tests should verify our runtime integration and tool behavior without requiring a live model endpoint. A smoke-test method can be monkeypatched or run against a fake runner class.

## Risks / Trade-offs

- [Risk] OpenAI-compatible endpoints may differ in exact supported APIs. -> Mitigation: expose base URL/model in health and keep smoke test separate from normal health.
- [Risk] SDK tracing may send content unexpectedly. -> Mitigation: default tracing disabled through config/environment.
- [Risk] Direct write tools can modify vault content. -> Mitigation: `AGENTS.md` blocked, vault-external writes impossible, raw/wiki writes journaled with hashes and snapshots.
- [Risk] Existing approval tests still expect old behavior. -> Mitigation: keep old approval endpoints/models for compatibility, but new write tools do not depend on them.
