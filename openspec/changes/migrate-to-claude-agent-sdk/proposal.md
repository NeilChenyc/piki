## Why

Piki 的产品内核已经明确是 agent-first：vault 是真相源，服务端只负责边界、事件、journal 和回退，判断与执行尽量交给 agent。此前的 OpenAI Agents SDK 路径已经不再适合当前架构目标：

- runtime、测试和文档残留大量 OpenAI / `function_tool` 语义
- `VaultToolRegistry` 会把 Claude 退化成“换壳模型”
- 普通任务仍有历史 fallback 叙事，和统一 agent 主循环相冲突
- repo `.claude/` 与用户级 memory 有污染产品 runtime 的风险

本变更将 Piki 的主 runtime 完整迁移到 Claude Agent SDK，并同步清理旧的 OpenAI 时代表述和接口假设。

## What Changes

- 将 Claude Agent SDK 设为唯一主 runtime。
- 删除 OpenAI runtime 主路径和自定义 agent-visible toolset 的中心地位。
- 将 agent 工具面收敛为 Claude built-in tools：`Read`、`Write`、`Edit`、`Glob`、`Grep`、`Bash`、`AskUserQuestion`。
- 通过 hooks 实施 vault 写边界、Bash 写副作用阻断、journal 审计和输入暂停恢复。
- 让 runtime 默认 hermetic，不读取 repo `.claude/`、用户 `~/.claude` 和记忆。
- 将任务事件、健康检查、客户端 DTO 和文案改为 provider-neutral / Claude-only。
- 新增 `POST /tasks/{id}/input` 恢复暂停任务。
- 明确保留 journal / rollback / staging / lint helper 作为 Piki 的系统基础设施，而不是 agent-visible custom tools。

## Capabilities

### New Capabilities

- `claude-agent-runtime`: Claude Agent SDK session、hooks、partial streaming、pause-resume、journal-aware task execution

### Modified Capabilities

- `agent-service-health`: 输出 provider-neutral 的 runtime 状态
- `agent-service-api`: 使用新的任务输入恢复接口和事件协议
- `wiki-lint-maintenance`: 通过 Bash + CLI helper 配合 agent，而不是自定义函数工具

## Impact

- `pyproject.toml`
- `agent_service/config.py`
- `agent_service/runtime/*`
- `agent_service/application/*`
- `agent_service/api/routes/*`
- `PikiApp/PikiApp/Core/*`
- `PikiApp/PikiApp/Features/Home/*`
- `PikiApp/PikiApp/Features/Settings/*`
- `docs/product/*`
- `tests/*`
