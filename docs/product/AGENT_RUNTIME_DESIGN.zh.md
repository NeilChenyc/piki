# Piki Agent Runtime：Claude Agent SDK 实施方案

## 1. 设计目标

Piki 的 runtime 目标不是“自研一整套 agent 框架”，而是：

- 用 Claude Agent SDK 承担 agent loop、session、streaming 和内建工具
- 用 Piki 服务端承担边界、安全、审计、journal 和回退
- 保持产品的 agent-first 哲学，不把业务判断重新塞回服务端

当前收敛后的目标架构是：

```text
SwiftUI App -> PikiRuntimeHost -> internal Python worker -> Claude Agent SDK -> Claude built-in tools
```

## 2. 为什么选 Claude Agent SDK

Claude Agent SDK 已经提供 Piki 真正需要的运行时要素：

- `Read / Write / Edit / Glob / Grep / Bash / AskUserQuestion`
- session / resume
- hooks / permissions
- partial streaming
- checkpointing
- hermetic settings 控制

这意味着 Piki 不需要继续维护一套 OpenAI 时代的自定义工具注册层，只需要把自己的产品边界清晰地放在 hooks 和系统 API 上。

## 3. 基本原则

### 3.1 Claude 是唯一主 runtime

- Python worker 继续保留
- 产品主路径不再依赖 `openai-agents`
- 不再使用 localhost HTTP/SSE 作为产品协议

### 3.2 不再维护自定义 agent-visible toolset

agent 默认可见工具只保留：

- `Read`
- `Write`
- `Edit`
- `Glob`
- `Grep`
- `Bash`
- `AskUserQuestion`

需要判断的事交给 agent，需要确定性的事变为本地 CLI 或系统工作流。

### 3.3 运行时必须 hermetic

默认要求：

- `setting_sources: []`
- `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`
- `strict_mcp_config=true`
- `CLAUDE_CONFIG_DIR` 指向 app 私有目录

目标是避免仓库根 `.claude/CLAUDE.md`、用户 `~/.claude` 和记忆污染产品 vault agent 的行为。

## 4. 上下文信封

每一轮 agent task 都应注入：

- `AGENTS.md`
- `purpose.md`
- `wiki/index.md`
- `action_context`
- 最近对话上下文
- `selected_paths` 的 staging manifest

`AGENTS.md` 继续是产品协议源文件，不强制迁成 vault 内 `CLAUDE.md`。

## 5. 文件与权限模型

### 5.1 写入规则

- agent 修改 vault 的唯一方式是 `Write/Edit`
- `Bash` 默认只做读取、提取、分析和调用确定性 CLI
- vault 外写入永远拒绝
- `AGENTS.md` 永远只读

### 5.2 Bash 规则

v1 中 `Bash` 是“读/算/提取工具”，而不是旁路写工具。默认拒绝：

- 重定向写入
- `tee`
- `sed -i`
- `mv`
- `cp`
- `rm`
- `git reset`

允许的典型命令：

- `python -m agent_service.runtime.cli lint ...`
- `python -m agent_service.runtime.cli extract-source ...`
- 只读 shell / grep / cat / jq / diff / hash 计算

## 6. Hook 设计

### 6.1 `PreToolUse`

负责硬性阻断：

- 写 `AGENTS.md`
- 写 vault 外路径
- 写数据库、session、runtime 私有目录、staging 目录
- Bash 文件副作用命令
- 未批准的 `AskUserQuestion` 场景转入暂停

### 6.2 `PostToolUse`

负责记录：

- `Write/Edit` 触达路径
- 写前/写后 hash
- 快照与 trace 元数据
- 可观察 tool 事件

### 6.3 `Stop`

任务结束时：

- 聚合当轮写入
- 只在真实修改 `raw/` 或 `wiki/` 时生成单条 journal
- 若发现越界写入痕迹，则整轮任务失败

## 7. 会话、暂停与恢复

Piki 需要两类恢复能力：

- Claude session 级上下文恢复
- AskUserQuestion / approval 级任务恢复

对外 API：

- `POST /tasks`
- `POST /tasks/{id}/input`

返回字段应至少包含：

- `session_id`
- `checkpoint_id`
- `pending_input`
- `journal_entry_id`

## 8. 事件桥协议

UI 只渲染可观察事件，不渲染隐藏推理链。

统一协议：

- `agent.run.started`
- `agent.progress`
- `message.delta`
- `tool.started`
- `tool.finished`
- `agent.input_requested`
- `agent.input_resolved`
- `journal.created`
- `task.completed`
- `task.failed`

Claude partial streaming 映射：

- `content_block_delta.text_delta` -> `message.delta`
- `content_block_start(tool_use)` -> `tool.started`
- `content_block_stop(tool_use)` / `PostToolUse` -> `tool.finished`

Swift host 当前通过 worker 的增量 task event envelope 做长轮询桥接；协议层保持这些事件语义稳定，后续若替换成更直接的 push bridge，UI 不需要改语义。

当前实现已经补上 worker 事件通知信号：

- worker 在事件写入 SQLite 时，会顺手输出一条轻量 notification
- host 仍保留 cursor 回放与超时轮询，作为断线/重连兜底
- UI 看到的是稳定 task event 流，不耦合底层传输形态

## 9. Journal 与回退

Piki 仍坚持 conversation-level journal：

- 单轮多文件写入只生成 1 条 journal entry
- 仅 `system/*` 变化不生成 journal
- 最近两条 active journal 支持 hash 校验回退

Claude checkpoint 可作为内部恢复能力，但对用户暴露的回退真相源仍是 Piki journal。

## 10. 系统接口保留原则

保留但降级为系统接口：

- `/lint`
- `/sources/rescan`
- `/ingest-queue`

它们可以继续服务兼容 UI 和确定性维护，但不应再发展成第二套 runtime 主路径。

## 11. v1 非目标

- 不把 WebSearch/WebFetch 作为默认能力
- 不做自定义 MCP 工具主路径
- 不把 repo `.claude` / 用户 memory 直接暴露给产品运行时
- 不把 Claude checkpointing 直接包装成用户可见回退功能
