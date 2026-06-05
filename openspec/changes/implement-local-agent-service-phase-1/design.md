## Context

Stage 0 has established the local Markdown vault protocol: `AGENTS.md`, `purpose.md`, `wiki/index.md`, `wiki/log.md`, and seed wiki pages. Stage 1 needs a local Agent Service that can run without Codex CLI and provide stable product-facing contracts for future `query`, `ingest`, and `lint` work.

The service should be small but real: HTTP task creation, task status, SSE event streaming, SQLite persistence, operation routing, context assembly, vault-safe tools, and approval endpoints.

## Goals / Non-Goals

**Goals:**

- Add a Python `agent_service/` package that can be imported and tested.
- Provide a FastAPI app with task, event, and approval endpoints.
- Persist task, event, approval, and session state in SQLite.
- Add a `PikiWikiAgent` runner scaffold using OpenAI Agents SDK when installed.
- Keep tests passing even if the SDK package is absent by using an explicit unavailable-runner fallback.
- Provide vault-safe read/search/parse/propose tools.
- Ensure high-risk work creates patch proposals and pending approvals, not file writes.

**Non-Goals:**

- Do not implement full `query` answer generation.
- Do not implement real `ingest` wiki page generation.
- Do not apply patches to vault files after approval in Phase 1.
- Do not implement multi-agent handoff, MCP tools, or non-OpenAI providers.
- Do not build the Mac client UI.

## Decisions

### Decision: Python package plus FastAPI app

Use `agent_service/` as a Python package and expose `agent_service.app:create_app`.

Rationale:

- Matches the OpenAI Agents SDK Python path.
- Keeps phase 1 independently testable without a UI.
- Gives the Mac client a simple HTTP/SSE boundary later.

Alternative considered:

- TypeScript service. Deferred because the selected runtime strategy is OpenAI Agents SDK Python and existing podcast tooling is already Python.

### Decision: SQLite for runtime state

Use local SQLite for tasks, task events, approvals, and sessions.

Rationale:

- It is enough for a local-first MVP.
- It supports restart-safe event replay.
- It avoids adding a heavier database.

Alternative considered:

- JSONL-only state. Simpler, but harder for task lookup, approval status, event replay, and future queue queries.

### Decision: Piki event schema hides SDK raw events

The service maps all internal activity into Piki-owned event types such as `task.created`, `operation.detected`, `context.loaded`, `tool.started`, `tool.finished`, `diff.created`, `approval.required`, and `approval.resolved`.

Rationale:

- The client should not depend on OpenAI Agents SDK raw event shapes.
- Tests can assert stable product behavior.

### Decision: SDK runner scaffold with graceful fallback

The `PikiWikiAgent` runner attempts to import OpenAI Agents SDK. If unavailable, the service still starts and reports runner availability as false.

Rationale:

- The repository currently has no dependency file or installed SDK guarantee.
- Stage 1 API and tool tests should not require a live OpenAI key.
- Later stages can add model-backed integration tests.

### Decision: Tools are service-controlled

Read/analyze/proposal tools are normal Python functions behind a `ToolRegistry`, not arbitrary shell commands.

Rationale:

- Vault path validation is critical.
- `.env` and credentials must never be exposed.
- High-risk writes should be proposals only.

### Decision: Approval records are persisted, but not applied

Approving a pending proposal changes approval state and records an event, but Phase 1 does not modify vault files.

Rationale:

- This directly enforces the roadmap boundary: Stage 1 creates the service and approval flow; Stage 4 implements safe writes.
- It prevents accidentally treating approval as a write path before the writer is designed and tested.

## Data Model

SQLite tables:

- `tasks`: id, operation, status, risk_level, vault_path, user_input, summary, created_at, updated_at.
- `task_events`: id, task_id, type, payload_json, created_at.
- `approvals`: id, task_id, proposal_id, status, risk_level, affected_files_json, diff, comment, created_at, resolved_at.
- `sessions`: id, task_id, payload_json, created_at, updated_at.

## API Shape

- `POST /tasks`
- `GET /tasks/{task_id}`
- `GET /tasks/{task_id}/events`
- `POST /tasks/{task_id}/approve`
- `POST /tasks/{task_id}/reject`
- `GET /health`

SSE should replay existing events first, then end for Phase 1. Later stages can keep the stream open while long-running tasks execute.

## Runtime Flow

Task creation:

1. Validate request.
2. Validate vault path.
3. Route operation.
4. Insert task.
5. Emit `task.created`.
6. Assemble baseline context.
7. Emit `operation.detected`.
8. Emit `context.loaded`.
9. For high-risk operations, create a placeholder patch proposal and approval.
10. Emit `diff.created` and `approval.required`.
11. Return task id and events URL.

Read-only query in Phase 1:

- The system routes the operation as `query`.
- It loads baseline context and records events.
- It does not generate a final LLM answer yet.

Ingest in Phase 1:

- The system routes the operation as `ingest`.
- It creates a high-risk proposal placeholder.
- It does not write files.

## Risks / Trade-offs

- [Risk] The service skeleton may look too thin without real model calls. → Mitigation: make APIs, events, SQLite, routing, context loading, and proposal approval fully real and tested.
- [Risk] SDK dependency may not be installed. → Mitigation: provide explicit runner availability detection and fallback tests.
- [Risk] Placeholder patch proposals could become misleading. → Mitigation: mark them as phase-1 scaffold proposals and do not apply them.
- [Risk] API shape may need adjustment when real streaming arrives. → Mitigation: keep Piki event schema stable and versionable.
- [Risk] Vault paths can leak sensitive files. → Mitigation: validate vault-relative paths and block `.env`, keys, and outside-vault access.

## Migration Plan

1. Add `agent_service/` package and tests.
2. Keep existing vault and docs untouched except for implementation files.
3. Add dependency metadata if no Python project file exists.
4. Run unit and API tests.
5. Stage 2 can build real query behavior on top of the same task/event/context foundations.

Rollback:

- Remove `agent_service/`, tests, and dependency metadata.
- No vault data migration is required because Phase 1 does not modify runtime vault content through the service.

## Open Questions

- Should the eventual Mac app call FastAPI over localhost HTTP or embed the service process directly?
- Should Phase 2 introduce real OpenAI model calls immediately, or keep a deterministic local planner for query search first?
- Should task events use SSE only, or add WebSocket once approval resume becomes interactive?
