## 1. Project Setup

- [x] 1.1 Add Python project metadata and dependencies for the local agent service
- [x] 1.2 Create the `agent_service/` package structure
- [x] 1.3 Create the test package and shared test fixtures

## 2. Persistence And Models

- [x] 2.1 Define Pydantic models for tasks, events, approvals, operations, and outputs
- [x] 2.2 Implement SQLite schema initialization and repository helpers
- [x] 2.3 Implement task, event, approval, and session persistence

## 3. Vault And Runtime Core

- [x] 3.1 Implement vault path validation and safe file access
- [x] 3.2 Implement operation routing for `query`, `ingest`, `lint`, `capture`, and `review`
- [x] 3.3 Implement baseline context assembly for `AGENTS.md`, `purpose.md`, and `wiki/index.md`
- [x] 3.4 Implement the OpenAI Agents SDK runner scaffold with graceful unavailable fallback

## 4. Tools And Approval

- [x] 4.1 Implement vault-safe read, list, search, and markdown parse tools
- [x] 4.2 Implement patch proposal creation without applying file changes
- [x] 4.3 Implement approval creation and approve/reject resolution without applying patches

## 5. API And Events

- [x] 5.1 Implement FastAPI app factory and health endpoint
- [x] 5.2 Implement task creation and task inspection endpoints
- [x] 5.3 Implement SSE task event endpoint with replayed events
- [x] 5.4 Implement approve and reject endpoints

## 6. Verification

- [x] 6.1 Add unit tests for routing, vault safety, context assembly, and tools
- [x] 6.2 Add API tests for task creation, event replay, and approval resolution
- [x] 6.3 Run OpenSpec validation and Python tests
