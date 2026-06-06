## 1. Runtime And Config

- [x] 1.1 Remove `openai-agents` dependency and add `claude-agent-sdk`
- [x] 1.2 Rename runtime health/config surface to provider-neutral / Claude semantics
- [x] 1.3 Make runtime fail clearly when `ANTHROPIC_API_KEY` or runtime config is missing

## 2. Agent Tool Surface

- [x] 2.1 Remove `tool_factory.py` from the runtime main path
- [x] 2.2 Replace custom agent-visible tools with Claude built-in tool assumptions
- [x] 2.3 Add Bash CLI helpers for deterministic lint / extract workflows

## 3. Isolation And Safety

- [x] 3.1 Run Claude with hermetic settings and private `CLAUDE_CONFIG_DIR`
- [x] 3.2 Block writes to `AGENTS.md`, vault-external paths, and runtime-private paths
- [x] 3.3 Block Bash file-writing side effects and track `Write/Edit` hashes for journal

## 4. Sessions, Events, And Input Resume

- [x] 4.1 Replace `sdk.run.*` mapping with `agent.run.*` and Claude partial streaming event mapping
- [x] 4.2 Add `POST /tasks/{id}/input` and pending input task state
- [x] 4.3 Expose session/checkpoint metadata and journal events through task outputs

## 5. Client And Docs

- [x] 5.1 Update Swift DTOs, Settings, and Home state rendering to provider-neutral / Claude phrasing
- [x] 5.2 Rewrite product/runtime docs to reflect Claude-only runtime truth
- [x] 5.3 Add this OpenSpec change and supersede the old OpenAI runtime phase-4 change

## 6. Verification

- [x] 6.1 Run focused Python runtime/API tests
- [x] 6.2 Run Swift package build
- [ ] 6.3 Validate against a locally installed Claude SDK runtime end-to-end
