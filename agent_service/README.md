# Agent Service 目录说明

`agent_service/` 是 Piki 的本地 Agent Service。它不再承担“替 agent 做业务判断”的角色，而是作为一个轻量运行宿主，负责：

- 任务创建、状态持久化与 SSE 事件流
- vault 上下文装配与运行时隔离
- Claude Agent SDK 会话、hooks、暂停与恢复
- 对话级 journal / rollback
- 附件 staging 与少量确定性后处理

当前主链路是：

```text
SwiftUI App -> FastAPI Agent Service -> Claude Agent SDK -> Claude built-in tools
```

其中 agent 可见工具面默认只使用 Claude 内建工具：

- `Read`
- `Write`
- `Edit`
- `Glob`
- `Grep`
- `Bash`
- `AskUserQuestion`

Piki 自己保留的能力是 hooks、journal、rollback、staging、lint/extract CLI helper 和系统 API，不再维护自定义 agent-visible toolset。

## 顶层文件

| 路径 | 说明 |
| --- | --- |
| `__init__.py` | Python package 标记文件。 |
| `app.py` | FastAPI 应用入口，定义 `/tasks`、`/health`、SSE、rollback、queue、lint 等本地 API。 |
| `config.py` | 服务配置与 `.env` 加载逻辑，例如 Anthropic key、Claude config dir、model、runtime 开关和 staging 路径。 |
| `README.md` | 本目录结构和职责说明。 |

## 子目录

| 目录 | 说明 |
| --- | --- |
| `agents/` | Agent prompt 组装与运行时协议文案。 |
| `api/` | 路由定义，例如 `/health`、`/tasks`、`/journal`。 |
| `application/` | 任务执行、事件发布、SSE replay、系统动作协调。 |
| `context/` | 基础上下文装配，例如 `AGENTS.md`、`purpose.md`、`wiki/index.md`。 |
| `models/` | Pydantic 数据模型和枚举，包括 task、event、journal、rollback、input request。 |
| `runtime/` | Claude Agent SDK runner、事件映射、hooks、journal tracker、CLI helpers。 |
| `store/` | SQLite task/event/session/journal/queue 存储。 |
| `vault/` | vault 路径安全、读写、复制等底层访问封装。 |
| `workflows/` | 保留确定性系统工作流，例如 source intake、ingest queue、lint、rollback 和 source rescan。 |

## 关键文件

| 路径 | 说明 |
| --- | --- |
| `context/assembler.py` | 加载任务默认上下文，并记录已加载和缺失的基础文件。 |
| `models/core.py` | 核心 API 和运行时数据结构，包括 `TaskStatus.INPUT_REQUIRED`、Claude session 字段和事件类型。 |
| `application/task_executor.py` | 统一任务主入口；普通 `/tasks` 不再静默 fallback 到旧 query pipeline。 |
| `application/task_service.py` | task 创建、恢复输入、journal 查询和系统动作封装。 |
| `runtime/runner.py` | Claude Agent SDK runner，负责 hermetic 配置、hooks、staging、stream 事件映射和会话恢复。 |
| `runtime/event_mapper.py` | Claude partial streaming 事件到 Piki SSE 事件的映射。 |
| `runtime/journal_tracker.py` | 跟踪 `Write/Edit` 触达文件、hash 和快照，并在任务结束后提交 journal。 |
| `runtime/cli.py` | 供 agent 通过 `Bash` 调用的确定性 CLI helper，例如 `lint` 和 `extract-source`。 |
| `workflows/source_intake.py` | 将外部文件规范化为 `raw/sources/*.md`。 |
| `workflows/lint.py` | 确定性 lint / 低风险修复逻辑。 |
| `workflows/rollback.py` | 最近两条 active journal 的 hash 校验回退。 |
| `store/sqlite.py` | SQLite schema 初始化和任务、事件、journal、queue 的读写。 |
| `vault/access.py` | vault-relative 路径校验、敏感文件阻断、文本读写和文件复制。 |

## 当前运行时边界

- `POST /tasks` 是唯一主 agent 入口。
- 当 `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY` 或 runtime 开关未配置时，`/health` 会明确报告不可用，`POST /tasks` 会直接失败，不再静默切到旧 query fallback。
- 运行时默认 hermetic：
  - `setting_sources: []`
  - `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`
  - `strict_mcp_config=true`
  - `CLAUDE_CONFIG_DIR` 指向应用私有目录
- 仓库根 `.claude/` 与用户 `~/.claude` 不作为产品 vault agent 的默认记忆来源。
- `AGENTS.md` 继续是 vault 协议文件，但只读，不允许 agent 修改。
- `selected_paths` 会先复制到 `.piki/task-staging/<task_id>/`；agent 默认只读 staging 内路径，而不是直接读取宿主外部绝对路径。

## 文件与安全规则

- 允许 agent 修改 vault 的唯一方式是 Claude 内建 `Write/Edit`。
- `Bash` 在 v1 只用于读取、提取、计算和调用确定性 CLI helper，不允许直接改 vault 文件。
- `PreToolUse` hook 会拒绝：
  - 写 `AGENTS.md`
  - 写 vault 外路径
  - 写 runtime 私有目录、数据库、session 存储和 staging 目录
  - 具有文件副作用的 Bash 命令，例如重定向、`tee`、`sed -i`、`mv`、`cp`、`rm`、`git reset`
- `PostToolUse` hook 会记录 `Write/Edit` 的写前/写后 hash、快照和 tool trace。
- 任务结束时，只有真实修改了 `raw/` 或 `wiki/` 的对话才会生成一条 conversation-level journal entry。

## 主要 API 约定

- `GET /health`
  - 返回 provider-neutral runtime 状态，例如 `provider`、`model`、`anthropic_api_key_configured`、`agent_runtime_enabled`、`agent_runtime_configured`
- `POST /runtime/smoke-test`
  - 运行最小 Claude runtime 检查
- `POST /tasks`
  - 创建任务并启动 Claude agent 主循环
- `POST /tasks/{task_id}/input`
  - 恢复被 `AskUserQuestion` 或审批暂停的任务
- `GET /tasks/{task_id}/events`
  - SSE / replay 事件流
- `GET /journal/recent`
  - 最近 journal 记录
- `POST /journal/{journal_entry_id}/rollback`
  - 对最近两条 active journal 执行 hash 校验回退

## 兼容接口说明

`/lint`、`/sources/rescan`、`/ingest-queue` 等系统接口暂时保留，用于兼容已有 UI 和确定性维护流程；它们不是新的 agent 主路径，也不应该再扩展成第二套产品真相。
