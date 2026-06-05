## 1. Runtime Configuration

- [x] 1.1 Add base URL, model, API key, and tracing config to service settings and `/health`
- [x] 1.2 Add SDK smoke-test runner method and API endpoint

## 2. Vault Tool Registry

- [x] 2.1 Add `write_file` and `append_file` direct vault tools
- [x] 2.2 Enforce `AGENTS.md` read-only and vault-external no-write boundary
- [x] 2.3 Track before/after snapshots for true raw/wiki writes

## 3. Change Journal Persistence

- [x] 3.1 Add journal entry models and SQLite table
- [x] 3.2 Persist one conversation-level journal entry after raw/wiki changes
- [x] 3.3 Include journal entry id in task output and events

## 4. SDK Runtime Integration

- [x] 4.1 Build dynamic `PikiWikiAgent` instructions from baseline context
- [x] 4.2 Register vault tools as SDK `function_tool`s
- [x] 4.3 Run agent tasks through SDK runner when configured
- [x] 4.4 Map SDK result/tool completion into Piki task events
- [x] 4.5 Keep read-only query fallback when SDK is unavailable or unconfigured

## 5. Verification

- [x] 5.1 Add tests for health/config and smoke-test behavior
- [x] 5.2 Add tests for direct write tools and journal entry creation
- [x] 5.3 Add tests for SDK runner integration with mocked SDK result
- [x] 5.4 Run OpenSpec validation, Python tests, and compile checks
