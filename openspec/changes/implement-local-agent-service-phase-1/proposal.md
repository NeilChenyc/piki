## Why

Piki has a usable vault protocol and product roadmap, but it still lacks the local runtime that can execute controlled wiki operations without depending on Codex CLI. Phase 1 should establish the minimum Agent Service foundation so later `query`, `ingest`, and `lint` work can be implemented against a stable API, event stream, task store, and tool boundary.

## What Changes

- Add a local Python Agent Service skeleton using FastAPI, SQLite, and OpenAI Agents SDK integration points.
- Introduce task creation, task status, SSE event streaming, and approval endpoints.
- Add core schemas for operations, events, approvals, tool calls, and structured outputs.
- Add a single `PikiWikiAgent` runner scaffold with operation routing and context assembly.
- Add read/analyze/proposal tools for vault-safe file access and patch proposal generation.
- Ensure high-risk writes are not applied directly in Phase 1.

## Capabilities

### New Capabilities

- `local-agent-service`: Local task API, event streaming, persistence, and service lifecycle for Piki agent work.
- `piki-agent-runtime`: OpenAI Agents SDK runner scaffold, operation routing, context assembly, and tool registry.
- `approval-gate`: Approval records and endpoints that prevent high-risk writes from being applied without explicit user confirmation.

### Modified Capabilities

- None.

## Impact

- Adds a new `agent_service/` Python package.
- Adds service/runtime tests.
- Adds local dependencies for FastAPI, Pydantic, OpenAI Agents SDK, pytest, and HTTP testing.
- Establishes the API and event contracts used by later roadmap stages.
