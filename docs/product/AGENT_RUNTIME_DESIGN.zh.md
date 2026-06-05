# Piki Agent Runtime：OpenAI Agents SDK 实施方案

## 1. 结论

Piki 自研 agent 层第一版建议直接基于 **OpenAI Agents SDK Python** 实现。

这里的“自研”不是从零手写模型循环，而是把 Piki 的产品内核保留下来：

- vault workflow 规则由 `AGENTS.md` 定义。
- vault 文件结构由 Piki 定义。
- `AGENTS.md`、`purpose.md`、`wiki/index.md`、`wiki/log.md` 的维护规则由 Piki 定义。
- vault 内外读写边界、`AGENTS.md` 只读规则、change journal 和 rollback 由 Piki 定义。
- OpenAI Agents SDK 负责 agent loop、工具调用、流式事件、session、guardrails、tracing 和模型接入。

一句话：

> SDK 负责让 agent 跑起来，Piki 负责决定 agent 能读写哪里、如何记录修改、如何回退最近写坏的 vault。

官方参考：

- OpenAI Agents SDK: https://openai.github.io/openai-agents-python/
- Agents: https://openai.github.io/openai-agents-python/agents/
- Running agents: https://openai.github.io/openai-agents-python/running_agents/
- Tools: https://openai.github.io/openai-agents-python/tools/
- Streaming: https://openai.github.io/openai-agents-python/streaming/
- Human-in-the-loop: https://openai.github.io/openai-agents-python/human_in_the_loop/
- Sessions: https://openai.github.io/openai-agents-python/sessions/
- Models: https://openai.github.io/openai-agents-python/models/
- LiteLLM model adapter: https://openai.github.io/openai-agents-python/models/litellm/
- MCP: https://openai.github.io/openai-agents-python/mcp/
- Guardrails: https://openai.github.io/openai-agents-python/guardrails/
- Tracing: https://openai.github.io/openai-agents-python/tracing/

## 2. 为什么适合 Piki

Piki MVP 的关键不是“聊天”，而是让一个 agent 长期、可靠、可审计地维护本地 Markdown wiki。

OpenAI Agents SDK 与 Piki 需求的匹配关系：

| Piki 需求 | SDK 能力 | 设计判断 |
| --- | --- | --- |
| 多步 `ingest/query/lint` | `Agent` + `Runner` agent loop | 直接复用 SDK，不手写循环 |
| 本地文件工具 | function tools / local shell-like tools / MCP tools | Piki 自己封装受控工具 |
| 客户端实时展示 | streaming events | 映射成 Piki UI event stream |
| 多轮上下文 | sessions | 用 SQLite session 保存任务上下文 |
| 结构化输出 | `output_type` / Pydantic model | 强约束 agent result、journal entry、lint report |
| 安全边界 | guardrails | 输入/输出层做风险检测和阻断 |
| 调试观测 | tracing | 开发期追踪每次模型与工具调用 |
| 后续扩展工具 | MCP | 浏览器、RSS、转写等能力可逐步 MCP 化 |
| 非 OpenAI 模型 | ModelProvider / OpenAI-compatible client / LiteLLM | 可接，但 MVP 先默认 OpenAI |

不匹配或不能外包给 SDK 的部分：

- SDK 不知道 Piki vault 的长期知识结构。
- SDK 不会自动维护 `wiki/index.md` 和 `wiki/log.md`。
- SDK 的 human-in-the-loop 不是 MVP 必需能力。
- SDK 不替代 source manifest、file hash、ingest queue、update queue。
- SDK 不替代中文 wiki 命名、frontmatter、wikilink 等约定。

## 3. 总体架构

MVP 使用一个本地 Python Agent Service，客户端通过 HTTP + SSE 或 WebSocket 与它通信。

```text
Piki Client
  -> Local Agent Service (Python)
    -> HTTP / SSE / WebSocket API
    -> Task Manager
    -> Context Assembler
    -> OpenAI Agents SDK Runner
    -> Piki Tool Registry
    -> Change Journal / Rollback
    -> Vault Writer
    -> Event Mapper
    -> SQLite Store
  -> piki-vault
```

### 3.1 Local Agent Service

职责：

- 接收客户端任务请求。
- 创建 `task_id`。
- 统一装配 `AGENTS.md`、`purpose.md`、`wiki/index.md` 和工具上下文。
- 装配上下文。
- 启动 Agents SDK run。
- 转发 streaming events。
- 管理 vault-safe read/write tools。
- 写入任务事件、session、journal entry 和队列状态。
- 当某条对话真实修改 `raw/` 或 `wiki/` 时，在对话结束后记录 before/after hash，支持最近两条修改对话回退。

技术建议：

- Python 3.12+
- FastAPI
- SQLite
- OpenAI Agents SDK
- Pydantic
- `rg` 作为文本搜索底层
- `unidiff` 或自研最小 patch 校验

### 3.2 Piki Client

客户端不需要知道 SDK 细节，只消费 Piki 自己的事件协议。

核心 UI 区域：

- 会话区：自然语言输入、agent 回复、阶段性说明。
- 状态区：当前 task 阶段、风险等级、计划改动。
- 文件区：source、wiki 页面、官方节目概览、摘要、转写全文预览。
- Diff 区：文件变更摘要、本对话 journal entry、rollback 状态。
- Change 区：文件 diff、本对话 journal entry、rollback 状态。
- Task 区：运行状态、失败原因、重试入口。

## 4. 模块边界

建议服务端目录：

```text
agent_service/
  app.py
  config.py
  models/
    task.py
    events.py
    rollback.py
    outputs.py
  agents/
    piki_agent.py
    prompts.py
    guardrails.py
  runtime/
    runner.py
    event_mapper.py
    sessions.py
    tracing.py
  workflows/
    query.py
    source_intake.py
    ingest.py
    lint.py
  context/
    assembler.py
    search.py
    graph.py
  tools/
    read_file.py
    list_files.py
    search_text.py
    parse_markdown.py
    write_file.py
    append_file.py
    append_log.py
    queue_item.py
    source_meta.py
  vault/
    paths.py
    manifest.py
    markdown.py
    diff.py
    writer.py
  store/
    sqlite.py
    migrations/
```

Piki 自己要稳定维护的边界：

| 模块 | 归属 | 原因 |
| --- | --- | --- |
| Workflow rules | `AGENTS.md` + Piki | 让 agent 自主选择 query、ingest、lint 等维护流程 |
| Tool schema | Piki + SDK | Piki 定义工具，SDK 暴露给模型 |
| Event schema | Piki | 客户端渲染必须稳定 |
| Rollback policy | Piki | 决定最近修改如何被安全撤销 |
| Agent loop | SDK | 复用官方实现 |
| Session | SDK + SQLite | SDK 维护对话上下文，Piki 保存任务状态 |
| Tracing | SDK | 开发期观测和调试 |
| Vault writer | Piki | 写入必须符合 wiki 规则 |

## 5. 统一 Agent Loop

Piki 不再先把自然语言请求映射到独立任务类型。MVP 的默认路径是：

1. 客户端把自然语言、slash command、选中文件和 UI 上下文提交给 `POST /tasks`。
2. 如果请求携带 `selected_paths`，系统先执行 source intake，把文件规范化为 `raw/sources/*.md`。
3. 其他请求进入同一个 `PikiWikiAgent`。
4. Agent 默认读取 `AGENTS.md`、`purpose.md`、`wiki/index.md`。
5. Agent 拿到同一组受控 vault tools，自主判断应该 query、ingest、lint 还是记录维护标记。
6. 工具层负责读写边界：vault 内除 `AGENTS.md` 外可自由读写；`AGENTS.md` 只读；vault 外仅允许读取用户明确提供的来源路径，绝不开放写入。
7. 对话结束时，如果本对话真实修改了 `raw/` 或 `wiki/`，记录一条 journal entry；没有修改 `raw/` / `wiki/` 的对话不进入 change journal。
8. 最近两条 journal entry 支持 hash 校验回退。

这样做的原因：

- Piki MVP 工具数量少，全部注入上下文更简单。
- `AGENTS.md` 已经是 LLM Wiki 的核心协议，应该让 agent 直接遵循它。
- 前置分流容易把模糊自然语言分错，降低成功率。
- 风险边界本来应该由工具和 rollback 机制控制，而不是由一个意图分类结果控制。

### 5.1 Workflow Rules

`query` workflow 要强调：

- 先读 `wiki/index.md`。
- 搜索相关已编译 wiki 页面。
- 尽量不要重读所有 raw source。
- 回答必须带引用。

`ingest` workflow 要强调：

- 读取目标 source。
- 提取标题、作者、日期、格式和出处。
- 创建或更新 `wiki/sources/`。
- 更新相关 `wiki/entities/`、`wiki/concepts/`、`wiki/domains/`。
- 只有跨来源理解显著变化时才建议 `wiki/synthesis/`。
- 明确暴露冲突、过期说法或不确定性。
- 对主张保守，对链接慷慨。
- 直接写入 wiki，并在页面和日志中明确标记冲突、过期说法或不确定性。

`lint` workflow 要强调：

- 检查孤立页面、断链、重复概念、过期说法、冲突、frontmatter、必要章节、index。
- 低风险修复可以直接写入。
- 重要结构变化如果修改了 `raw/` 或 `wiki/`，必须在对话结束时进入本对话 journal entry。

## 6. Agent 设计

### 6.1 单 Agent 起步

MVP 使用一个 `PikiWikiAgent`，不做多 agent handoff。

原因：

- Piki 第一版工具少，统一注入上下文更稳定。
- 写入边界比专家分工更重要。
- 多 agent 会增加调试和回退定位复杂度。

Agent 基础配置：

```python
from agents import Agent

piki_agent = Agent(
    name="PikiWikiAgent",
    instructions=build_piki_instructions(),
    tools=[
        read_file,
        list_files,
        search_text,
        parse_markdown,
        write_file,
        append_file,
        record_change_set,
    ],
    output_type=AgentResult,
)
```

注意：

- vault 内写入工具可以直接暴露给 agent，但必须经过路径校验；如果本对话真实修改了 `raw/` 或 `wiki/`，对话结束时进入本对话 journal entry。
- `AGENTS.md` 只读，不暴露写入能力。
- vault 外写入能力绝不暴露。

### 6.2 什么时候引入 handoff

OpenAI Agents SDK 支持 handoffs，但 Piki MVP 不建议第一版使用。

后续可考虑这些专门 agent：

| Agent | 触发条件 |
| --- | --- |
| `IngestAgent` | 长文、播客、PDF 等复杂 source |
| `QueryAgent` | 复杂跨页面问答 |
| `LintAgent` | 大型 vault 健康检查 |
| `RollbackAgent` | 后续如果需要更复杂的变更解释和回退辅助 |

引入 handoff 的条件：

- 单 agent prompt 已经明显过长。
- 不同 workflow 的工具权限差异很大，且单 agent 已经难以用 prompt 控制。
- tracing 显示 agent 经常混淆角色。

### 6.3 Dynamic Instructions

Agents SDK 支持动态 instructions。Piki 应为每次任务动态生成 prompt。

动态内容：

- 用户原始请求和可选 workflow hint。
- vault 根路径。
- 允许访问的路径。
- 读写边界。
- 已加载上下文摘要。
- 本次任务风险等级。
- 是否允许自动写入。
- 输出格式要求。

示例结构：

```text
你是 Piki 的本地 wiki 维护 agent。

workflow hint: ingest
当前 vault: /Users/.../piki-vault
必须遵守: AGENTS.md
语言规则: wiki 页面文件名、标题和正文使用中文；骨架目录保持英文。
写入策略: vault 内除 AGENTS.md 外可直接写入；本对话如真实修改 raw/ 或 wiki/，必须在对话结束时生成一条 journal entry；只修改 system/、purpose.md 等非 raw/wiki 文件时不生成 journal entry。
本次目标 source: raw/inbox/example.md
```

## 7. Context Assembler

Context Assembler 是 Piki 的关键模块，不能简单交给模型自由搜索。

### 7.1 默认加载顺序

所有任务默认加载：

1. `piki-vault/AGENTS.md`
2. `piki-vault/purpose.md`
3. `piki-vault/wiki/index.md`

随后由 agent 使用工具按需追加：

| Workflow | 追加上下文 |
| --- | --- |
| `query` | 搜索命中的 wiki 页面、wikilink 邻居、source overlap 页面 |
| `ingest` | 目标 source、相关 entity/concept/domain/source 页面 |
| `lint` | wiki 文件列表、frontmatter 扫描结果、wikilink 图、index 摘要 |

### 7.2 搜索策略

MVP 搜索顺序：

1. 关键词搜索。
2. 中文 bigram / CJK friendly token search。
3. wikilink 图扩展。
4. source overlap。
5. 必要时 raw source。

`query` 默认不读取所有 raw source。

只有这些情况才读取 raw source：

- 已编译 wiki 内容不足。
- 已编译页面互相冲突。
- 用户明确要求“看原文”。
- 需要核对引用。

### 7.3 Context Budget

每次 run 都记录 context manifest：

```json
{
  "loaded_files": [
    "AGENTS.md",
    "purpose.md",
    "wiki/index.md",
    "wiki/concepts/个人记忆系统.md"
  ],
  "skipped_files": [
    {
      "path": "raw/sources/long.md",
      "reason": "query 默认不读取 raw source"
    }
  ],
  "search_terms": ["个人记忆"],
  "token_estimate": 18320
}
```

这个 manifest 要作为 `context.loaded` 事件发给客户端。

## 8. Tool Registry

Piki 工具必须小、稳、可审计。

### 8.1 工具分级

| 等级 | 例子 | MVP 策略 |
| --- | --- | --- |
| Read | `read_file`、`list_files`、`search_text` | vault 内可读；vault 外仅可读用户明确提供的来源 |
| Analyze | `parse_markdown`、`extract_source_meta`、`build_link_graph` | 可直接执行 |
| Write | `write_file`、`append_file`、`update_index`、`append_log` | vault 内除 `AGENTS.md` 外可直接写入 |
| Rollback | `rollback_journal_entry` | 仅回退最近两条 raw/wiki 修改对话，且必须 hash 匹配 |

MVP 建议：

- Agent 可以直接调用 Read、Analyze、Write。
- `AGENTS.md` 不开放写入工具。
- vault 外路径永不开放写入工具。
- 每次 Write 必须生成 task event；只有对话真实修改 `raw/` 或 `wiki/` 时，才在对话结束后生成一条 journal entry。

### 8.2 核心工具

#### `read_file`

读取 vault 内允许路径。

输入：

```json
{
  "path": "wiki/index.md",
  "max_bytes": 20000
}
```

安全要求：

- 路径必须在当前 vault 内。
- vault 外读取只允许用户明确提供的来源路径。
- 禁止读取 `.env`、密钥、系统目录。
- 超过大小限制时返回截断信息。

#### `list_files`

枚举目录。

输入：

```json
{
  "path": "wiki/concepts",
  "glob": "*.md",
  "max_results": 200
}
```

#### `search_text`

基于 `rg` 或本地索引搜索。

输入：

```json
{
  "query": "个人记忆",
  "scope": "wiki",
  "max_results": 20
}
```

返回：

```json
{
  "matches": [
    {
      "path": "wiki/concepts/个人记忆系统.md",
      "line": 12,
      "snippet": "个人记忆系统的价值在于..."
    }
  ]
}
```

#### `parse_markdown`

解析 frontmatter、标题、章节和 wikilink。

返回：

```json
{
  "frontmatter": {
    "title": "个人记忆系统",
    "type": "concept"
  },
  "headings": ["定义", "为什么重要"],
  "wikilinks": ["sources/大模型维基"],
  "missing_required_sections": []
}
```

#### `write_file`

写入 vault 内允许路径，并记录 task event；若目标在 `raw/` 或 `wiki/` 下且内容真实变化，本对话结束时会汇总进 journal entry。

输入：

```json
{
  "path": "wiki/sources/示例来源.md",
  "content": "---\ntitle: 示例来源\n...",
  "reason": "创建 source page"
}
```

返回：

```json
{
  "affected_files": ["wiki/sources/示例来源.md"],
  "before_hash": null,
  "after_hash": "sha256:...",
  "journal_scope": "conversation"
}
```

#### `append_file`

追加写入 vault 内允许路径，并记录 task event；若目标在 `raw/` 或 `wiki/` 下且内容真实变化，本对话结束时会汇总进 journal entry。

输入：

```json
{
  "path": "wiki/log.md",
  "content": "## [2026-06-04] 摄入 | 示例来源\n...",
  "reason": "记录 ingest 日志"
}
```

#### `rollback_journal_entry`

回退最近一条或倒数第二条真实修改了 `raw/` / `wiki/` 的对话。

输入：

```json
{
  "journal_entry_id": "journal_123"
}
```

要求：

- journal entry 必须在最近两条可回退记录内。
- 回退前所有当前文件 hash 必须等于对应 `after_hash`。
- 任一 hash 不匹配，整次回退失败，不做部分回退。

### 8.3 SDK function tools

Agents SDK 的 function tools 可以从 Python 函数自动生成工具 schema。Piki 工具函数必须使用类型标注和 Pydantic 模型。

示例：

```python
from pydantic import BaseModel, Field
from agents import function_tool, RunContextWrapper

class ReadFileInput(BaseModel):
    path: str = Field(description="Vault-relative path")
    max_bytes: int = 20000

@function_tool
async def read_file(ctx: RunContextWrapper[PikiRunContext], input: ReadFileInput) -> str:
    return ctx.context.vault.read_file(input.path, max_bytes=input.max_bytes)
```

工具实现要求：

- 不在工具里拼接未校验路径。
- 不返回密钥或 `.env` 内容。
- 每次工具调用写入 task events。
- 所有错误返回结构化错误，不把 traceback 直接给模型。

## 9. Change Journal / Rollback

MVP 不使用写入前审批。写入安全由读写边界、change journal 和 rollback 共同承担。

### 9.1 读写边界

- vault 内除 `AGENTS.md` 外，agent 可自由读写。
- `AGENTS.md` 只读，不开放写入工具。
- vault 外仅可读取用户明确提供的来源路径。
- vault 外绝不开放写入。

### 9.2 Change Journal

Change journal 是对话级记录。只有某条对话真实修改了 `raw/` 或 `wiki/`，才生成 journal entry：

- `journal_entry_id`
- `conversation_id`
- `task_id`
- `reason`
- `affected_files`，仅包含本对话修改过的 `raw/` / `wiki/` 文件
- 每个文件的 `before_hash`、`after_hash`
- 每个文件的 `before_content`、`after_content`
- diff
- created_at

同一条用户对话最多生成一条 journal entry。工具调用、task event 和普通文件变更事件可以有多条，但它们不是 change journal 的回退单位。

如果一条对话只修改了 `system/`、`purpose.md` 或其他非 `raw/` / `wiki/` 文件，可以记录 task event 和普通文件事件，但不创建 journal entry，也不能通过 MVP rollback 回退。

### 9.3 Rollback

MVP 只支持最近两条 raw/wiki 修改对话的回退。

回退流程：

1. 用户选择最近一条或倒数第二条 journal entry。
2. 系统读取 affected files 并计算当前 hash。
3. 如果所有当前 hash 都等于对应 `after_hash`，恢复 `before_content`。
4. 如果任一 hash 不匹配，整次回退失败。
5. 回退本身记录 task event，并更新原 journal entry 状态为 `rolled_back` 或 `rollback_failed`；MVP 不为 rollback action 再生成新的 journal entry，避免形成回退链。

这个方案可以避免把用户或后续 task 的新修改覆盖掉。

## 10. Streaming Event Mapping

Agents SDK streaming 会产生模型增量、run item、工具调用等事件。Piki 不应把 SDK 原始事件直接暴露给客户端，而要映射成稳定产品事件。

Piki event schema：

| Event | 触发来源 | UI 用法 |
| --- | --- | --- |
| `task.created` | Task Manager | 新任务出现在任务列表 |
| `intent.received` | Task API | 展示用户输入、附件和 task kind |
| `context.loaded` | Context Assembler | 展示读取了哪些文件 |
| `message.delta` | SDK streaming | 流式展示 agent 文本 |
| `tool.started` | SDK tool call | 展示正在读文件/搜索/写入 |
| `tool.finished` | SDK tool result | 展示工具结果摘要 |
| `file.changed` | write tools | 展示文件 diff |
| `journal_entry.created` | Change Journal | 展示可回退修改对话 |
| `rollback.completed` | Rollback API | 显示回退成功 |
| `rollback.failed` | Rollback API | 显示 hash 不匹配等失败原因 |
| `queue.updated` | Queue tool | 更新队列 |
| `file.changed` | Vault Writer | 文件树刷新 |
| `task.completed` | Runner | 收尾状态 |
| `task.failed` | Runner | 错误与重试 |

事件必须可回放。客户端刷新后可以从 SQLite 重新加载 task timeline。

## 11. Sessions

Agents SDK 支持 sessions，适合保存 agent 对话历史。Piki 还需要自己的 task store。

### 11.1 两类状态

| 状态 | 存哪里 | 用途 |
| --- | --- | --- |
| Model conversation/session | SDK session / SQLite | 给 agent 延续上下文 |
| Product task/event/journal entry | Piki SQLite | 给客户端展示和恢复 |

不要把全部 vault 内容放进 session。

Session 里保留：

- 用户最近操作。
- Agent 已解释过的任务背景。
- 最近使用过的 result summary。

Session 外保留：

- Markdown vault。
- source manifest。
- task events。
- journal entries。
- queue items。
- index/search cache。

### 11.2 Session Key

建议 session key：

```text
vault:{vault_id}:conversation:{conversation_id}
```

不同 vault 不共享 session。不同用户或不同 workspace 不共享 session。

## 12. Structured Output

Piki 不应该让 agent 最终只返回自然语言。

### 12.1 AgentResult

agent 最终输出一个结构化结果：

```python
class AgentResult(BaseModel):
    workflow_hint: Literal["query", "ingest", "lint", "source-intake", "rollback"] | None
    status: Literal["completed", "failed", "rolled_back"]
    summary: str
    answer: str | None = None
    citations: list[Citation] = []
    affected_files: list[str] = []
    journal_entry: JournalEntry | None = None
    next_actions: list[str] = []
```

### 12.2 QueryResult

```python
class QueryResult(BaseModel):
    answer: str
    citations: list[Citation]
    related_pages: list[str]
    confidence: Literal["low", "medium", "high"]
```

### 12.3 IngestResult

```python
class IngestResult(BaseModel):
    source_title: str
    source_meta: SourceMeta
    summary: str
    entities: list[ExtractedEntity]
    concepts: list[ExtractedConcept]
    claims: list[Claim]
    conflicts: list[Conflict]
    changed_pages: list[str]
    journal_entry: JournalEntry | None
```

### 12.4 LintResult

```python
class LintResult(BaseModel):
    checked_files: int
    orphan_pages: list[str]
    broken_links: list[BrokenLink]
    duplicate_concepts: list[DuplicateConcept]
    stale_claims: list[StaleClaim]
    missing_frontmatter: list[str]
    index_issues: list[IndexIssue]
    journal_entry: JournalEntry | None
```

Structured output 的好处：

- 客户端不用猜文本结构。
- 测试可以直接断言字段。
- 后续可持久化为 task artifact。
- 低置信度与冲突不会被混在散文里。

## 13. Guardrails

Guardrails 用来在模型输入和输出层拦截风险。

### 13.1 Input Guardrails

输入层检查：

- 用户是否要求读取 vault 外路径。
- 用户是否要求读取密钥或 `.env`。
- 用户是否要求写入 vault 外路径。
- 用户是否要求删除大量页面。
- 用户是否要求自动写入敏感内容。

结果：

- 只读危险请求直接拒绝。
- vault 外写入危险请求直接拒绝。
- 模糊请求要求用户澄清。

### 13.2 Output Guardrails

输出层检查：

- 回答是否缺少引用。
- 是否声称已写入但没有 `file.changed` event。
- 是否把低置信度内容写成确定事实。
- 是否违反中文 wiki 文件名和标题规则。
- 是否建议修改 raw source。
- 是否写入了 vault 外路径或 `AGENTS.md`。

如果触发 guardrail：

- task 进入 `failed` 或 `needs_revision`。
- 事件中记录原因。
- 不应用 patch。

## 14. Tracing 与 Observability

Agents SDK 提供 tracing。Piki MVP 应默认在开发环境开启 tracing，生产环境允许用户关闭或本地化。

需要追踪：

- 用户输入、附件和 workflow hint。
- context manifest。
- model call。
- tool call。
- journal entry。
- rollback。
- final output。

Piki 自己也要记录本地事件：

- task events。
- affected files。
- rollback result。
- queue changes。
- error stack summary。

隐私要求：

- 不把 `.env`、AccessKey、用户敏感 raw source 上传到第三方 tracing。
- 如果 tracing 会离开本机，必须在设置中明确说明并允许关闭。
- 本地开发可使用 SDK tracing 调试，用户版本优先保守。

## 15. 模型接入策略

### 15.1 默认模型

MVP 默认使用 OpenAI 模型和 Responses API 路径。

原因：

- Agents SDK 官方路径最完整。
- tool calling、structured output、streaming、tracing、sessions 配合最好。
- 减少第一版变量。

配置：

```env
OPENAI_API_KEY=
PIKI_AGENT_MODEL=
PIKI_AGENT_REASONING_EFFORT=medium
```

模型名以实际可用模型为准，不能在代码里写死为单一版本。

### 15.2 非 OpenAI 模型

Agents SDK 可以通过这些方式接非 OpenAI 模型：

- OpenAI-compatible endpoint。
- 自定义 `ModelProvider`。
- LiteLLM adapter。

设计判断：

| 接入方式 | 适合场景 | 风险 |
| --- | --- | --- |
| OpenAI-compatible endpoint | OpenRouter、兼容网关、部分国产模型服务 | tool calling 与 structured output 兼容性不稳定 |
| LiteLLM | 快速接多家模型 | 多一层依赖和错误映射 |
| 自定义 ModelProvider | 深度控制 provider 行为 | 开发成本更高 |

Piki 的策略：

- P0 默认 OpenAI。
- P1 抽象 `ModelConfig` 和 `ModelProviderConfig`。
- P1.5 试 LiteLLM / OpenAI-compatible endpoint。
- 不把 provider-specific 差异暴露给 vault 规则。

最重要的是：Piki 的核心工具都做成本地 function tools。这样即使用别家模型，也不依赖 provider 的 hosted tools。

## 16. MCP 策略

Agents SDK 支持 MCP。Piki 不需要第一版就把所有工具做成 MCP。

第一版：

- 直接使用本地 Python function tools。
- 工具更容易做路径校验、diff、journal entry 和测试。

后续适合 MCP 化的能力：

- 浏览器抓取。
- RSS 解析。
- 小宇宙转写工具。
- 文档解析工具。
- Obsidian / 文件系统扩展。
- 外部搜索。

MCP 工具也必须经过 Piki Tool Registry 包装，不能绕过读写边界和 change journal。

## 17. API 设计

### 17.1 创建任务

`POST /tasks`

请求：

```json
{
  "vault_path": "/Users/a99/.../piki-vault",
  "conversation_id": "conv_123",
  "user_input": "把 raw/inbox/article.md ingest 到 wiki",
  "selected_paths": ["raw/inbox/article.md"],
  "mode": "normal"
}
```

响应：

```json
{
  "task_id": "task_123",
  "status": "running",
  "events_url": "/tasks/task_123/events"
}
```

### 17.2 订阅事件

`GET /tasks/{task_id}/events`

建议使用 SSE：

```text
event: intent.received
data: {"task_kind":"agent","workflow_hint":"ingest","risk_level":"read-only"}

event: context.loaded
data: {"loaded_files":["AGENTS.md","wiki/index.md","raw/inbox/article.md"]}
```

SSE 对桌面客户端足够简单；如果需要双向实时控制，可以再加 WebSocket。

### 17.3 回退

`POST /change-sets/{change_set_id}/rollback`

```json
{
  "reason": "这次 ingest 写坏了概念页"
}
```

### 17.4 查询任务状态

`GET /tasks/{task_id}`

返回：

```json
{
  "task_id": "task_123",
  "task_kind": "agent",
  "status": "completed",
  "summary": "已更新 3 个 wiki 文件",
  "affected_files": ["wiki/sources/示例来源.md"],
  "journal_entry": "journal_123"
}
```

## 18. 数据库设计

MVP SQLite 表：

### 18.1 `tasks`

| 字段 | 说明 |
| --- | --- |
| `id` | task id |
| `conversation_id` | 会话 id |
| `vault_path` | vault 路径 |
| `task_kind` | agent / source-intake |
| `status` | running / completed / failed / rolled_back |
| `risk_level` | low / medium / high |
| `created_at` | 创建时间 |
| `updated_at` | 更新时间 |

### 18.2 `task_events`

| 字段 | 说明 |
| --- | --- |
| `id` | event id |
| `task_id` | task id |
| `type` | event type |
| `payload_json` | event payload |
| `created_at` | 创建时间 |

### 18.3 `journal_entries`

| 字段 | 说明 |
| --- | --- |
| `id` | journal entry id |
| `conversation_id` | 对话 id |
| `task_id` | task id |
| `reason` | 修改原因 |
| `status` | active / rolled_back / rollback_failed |
| `diff` | diff 内容 |
| `affected_files_json` | 文件列表 |
| `snapshots_json` | 每个文件的 before/after hash 与内容 |
| `created_at` | 创建时间 |
| `rolled_back_at` | 回退时间 |

### 18.4 `source_manifest`

| 字段 | 说明 |
| --- | --- |
| `path` | source 路径 |
| `hash` | 内容 hash |
| `mtime` | 修改时间 |
| `size` | 大小 |
| `source_page` | 对应 wiki source page |
| `status` | active / missing / changed / ignored |

### 18.5 `queue_items`

| 字段 | 说明 |
| --- | --- |
| `id` | queue item id |
| `queue` | ingest / update / lint |
| `status` | pending / processing / completed / failed / deferred |
| `payload_json` | 队列内容 |
| `created_at` | 创建时间 |
| `updated_at` | 更新时间 |

## 19. 关键实现流程

### 19.1 `query` 流程

```text
POST /tasks
-> unified agent loop
-> load AGENTS.md + purpose.md + wiki/index.md
-> search wiki
-> load related pages
-> Runner.run_streamed(agent, input, session)
-> tool calls if needed
-> final QueryResult
-> emit citations
```

写入策略：

- 默认只读。
- 如果用户明确要求把某个综合写入 wiki，这属于普通 agent 写入；若修改 `raw/` 或 `wiki/`，记录 journal entry。MVP 不提供独立保存工作流。

### 19.2 `ingest` 流程

```text
POST /tasks
-> unified agent loop
-> load AGENTS.md + purpose.md + wiki/index.md
-> read source
-> extract source meta
-> search related wiki pages
-> Runner.run_streamed
-> write source/concept/entity/domain updates
-> update index/log
-> record journal entry if raw/wiki changed
-> task.completed
```

写入策略：

- source/entity/concept/domain/synthesis 更新都可直接写入 vault。
- 冲突和低置信度内容写入页面中的明确标记。
- 对话内只要写入了 `raw/` 或 `wiki/`，对话结束时必须记录 journal entry。

### 19.3 `lint` 流程

```text
POST /tasks
-> unified agent loop
-> scan wiki tree
-> parse frontmatter and wikilinks
-> build link graph
-> detect orphan/broken/duplicate/stale/index issues
-> Runner summarizes report
-> optional write low-risk fixes
-> append log
-> record journal entry if raw/wiki changed
```

写入策略：

- 只读 report 不写 vault。
- 自动修复直接写入；若修改 `wiki/`，记录 journal entry。

## 20. 安全与权限

### 20.1 路径安全

所有工具必须使用 vault-relative path。

规则：

- vault 内除 `AGENTS.md` 外可读写。
- `AGENTS.md` 只读。
- vault 外仅可读取用户明确提供的来源路径。
- vault 外绝不开放写入。
- 禁止读取 `.env`、SSH key、AccessKey、浏览器 cookie。

### 20.2 Hash Rollback

MVP 使用 hash rollback，不把 Git checkpoint 作为必需依赖。

策略：

- 保留最近 2 条 raw/wiki 修改对话的 journal entry。
- 每个 journal entry 保存 affected files 的 before/after hash 和内容。
- 回退前当前 hash 必须等于 after_hash。
- hash 不匹配时整次回退失败，避免覆盖后续修改。

### 20.3 错误恢复

每个失败任务必须保留：

- 失败阶段。
- 错误摘要。
- 已读文件。
- 已生成 journal entry。
- 是否已写入文件。
- 推荐重试方式。

## 21. 测试策略

### 21.1 单元测试

必须覆盖：

- task API 和 source intake 分支。
- path sanitizer。
- markdown parser。
- wikilink parser。
- source meta extractor。
- diff generator。
- journal entry recorder。
- rollback hash checker。
- event mapper。

### 21.2 集成测试

最小集成用例：

1. `query` 能读取 `wiki/index.md` 并引用相关 wiki 页面。
2. `ingest` 单个 Markdown source 后直接生成 source page。
3. `ingest` 发现冲突时写入明确冲突标记。
4. `lint` 能发现断链和缺失 frontmatter。
5. 修改 `raw/` 或 `wiki/` 的对话结束后生成 journal entry。
6. 最近两条 journal entry 可以在 hash 匹配时回退。
7. hash 不匹配时回退失败，且不做部分回退。

### 21.3 Golden Vault

建立一个小型测试 vault：

```text
test-vault/
  AGENTS.md
  purpose.md
  raw/sources/llm-wiki.md
  wiki/index.md
  wiki/sources/...
  wiki/concepts/...
```

所有 workflow 都先在 golden vault 上跑。

### 21.4 Eval

后续可做轻量 eval：

- query citation accuracy。
- ingest coverage。
- conflict detection。
- Chinese filename compliance。
- no-raw-overread rule。
- no-vault-external-write rule。
- rollback hash safety。

## 22. 分阶段落地

### P0：单机最小闭环

目标：不用 CLI，Piki 客户端能通过本地服务跑 `query`、`ingest`、`lint`。

交付：

- FastAPI service。
- SQLite store。
- `PikiWikiAgent`。
- `read_file`、`list_files`、`search_text`、`parse_markdown`、`write_file`、`append_file`。
- SSE event stream。
- rollback API。
- 统一 agent loop，覆盖 query、ingest、lint 三类 workflow。

### P1：稳定写入

目标：让 agent 可以稳定写入 wiki，并让最近修改可追踪、可回退。

交付：

- journal entry recorder。
- rollback hash checker。
- `append_log`。
- `update_index`。
- source manifest。
- diff viewer。

### P2：多 source 和播客工作流

目标：接入已有小宇宙/听悟工具，让播客 source 成为正式 ingest 输入。

交付：

- podcast source normalizer。
- 官方节目概览优先规则。
- 转写全文、章节摘要、大模型摘要 source 打包。
- RSS / episode URL capture。
- 批量 ingest queue。

### P3：更强检索和可恢复长任务

目标：提升大 vault 体验。

交付：

- CJK search index。
- graph neighbor recall。
- source overlap recall。
- resumable long ingest。
- 更细 change journal 和失败恢复。
- 如有必要再评估 LangGraph 或自研状态机。

## 23. 开发注意事项

### 23.1 不要把 SDK 原始事件当产品协议

SDK 事件可能随版本演化。Piki 客户端只消费 Piki event schema。

### 23.2 不要让模型越界写文件

模型可以写 vault 内允许文件，但不能写 `AGENTS.md`，不能写 vault 外路径。所有写入都必须经过 Piki Tool Registry；真实修改 `raw/` 或 `wiki/` 的对话必须记录 journal entry。

### 23.3 不要把 session 当知识库

长期记忆必须回写 Markdown vault。

### 23.4 不要让 hosted tools 绕过本地规则

即使使用 MCP 或 hosted tools，也必须通过 Piki Tool Registry、读写边界和 change journal。

### 23.5 不要一开始做多 agent

先把单 agent 的 `query/ingest/lint` 做稳，再考虑 handoff。

## 24. 第一版开发清单

第一版只需要这些代码任务：

1. 建 `agent_service/`。
2. 建 SQLite schema。
3. 实现 `POST /tasks`。
4. 实现 `GET /tasks/{id}/events`。
5. 实现统一 task API，不做前置自然语言分流。
6. 实现 context assembler。
7. 实现 `PikiWikiAgent`。
8. 实现 read/analyze/write 类工具。
9. 实现 Piki event mapper。
10. 实现 rollback API。
11. 实现 `query`。
12. 实现 `ingest` direct write。
13. 实现 `lint` report。
14. 做 golden vault 集成测试。

暂不做：

- 多 agent handoff。
- 非 OpenAI provider。
- 复杂 MCP。
- 自动批量写入。
- 云同步。

## 25. 最终判断

OpenAI Agents SDK 适合 Piki MVP，因为它刚好覆盖“agent 怎么跑”的通用复杂度，而 Piki 仍然可以牢牢控制“长期知识怎么被写入”的产品内核。

最小可行实现应当是：

```text
FastAPI Local Service
+ OpenAI Agents SDK Runner
+ Piki Tool Registry
+ Piki Change Journal / Rollback
+ SQLite Task/Event Store
+ Markdown Vault Writer
```

这个组合足够轻，也足够接近真实产品。先用它跑通 `query`、`ingest`、`lint` 和最近两条 raw/wiki 修改对话回退，再扩展播客 source、RSS 和批量队列。
