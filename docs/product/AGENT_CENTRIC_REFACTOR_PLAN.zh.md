# Piki Agent-Centric 重构原则与计划

## 1. 核心判断

当前 Agent Service 已经具备 task、event、SSE、tool、journal、rollback、source intake 和 ingest 等能力，但实现仍然偏“服务端工作流驱动”：

- 服务端 `TaskRouter` 会先判断 `SOURCE_INTAKE`、`INGEST`、`SOURCE_CLEAR` 或 `AGENT`。
- 文件上传会先由服务侧 source intake pipeline 处理，再决定是否进入 wiki ingest。
- 显式 ingest、source intake、clear 等业务路径散在 application/workflows 中。
- UI 状态既来自服务端 workflow progress，也来自 SDK/tool event，容易和 agent 真实动作不一致。

新的方向是：**除审计与安全边界外，把意图判断和业务执行重新交给 agent。**

Agent Service 不应该替用户和 agent 预先决定“这是 query / ingest / update / record”。它应该负责创建任务、装配上下文、提供受控工具、转发事件、记录真实文件变更和支持回滚。至于用户这句话意味着读、写、转换文件、整理进 wiki、修正页面还是普通聊天，由 agent 在同一个会话中根据上下文和工具自主完成。

一句话：

> 服务端变薄，agent 变强；服务端保留边界、工具、事件和审计，不保留业务意图分流。

## 2. 不变的产品约束

这些规则仍然是 Piki 的底线：

- 本地优先，vault 是用户可直接读写迁移的 Markdown 文件夹。
- Chat history 不默认成为长期记忆。
- 只有当轮对话真实修改 `raw/` 或 `wiki/` 时才进入 Change Journal。
- Journal entry 是对话级的，包含该轮对话内所有真实 raw/wiki 文件变更。
- 最近两条 eligible journal entry 支持 hash 校验回滚。
- Mac 客户端不直接写 wiki；所有语义性写入都通过 Agent Service 的受控工具。
- `AGENTS.md` 是 vault 维护协议，只读，不允许 agent 修改。

## 3. 新的统一任务模型

所有主对话入口请求都进入同一个 Agent task。

```text
POST /tasks
  -> create task
  -> assemble context envelope
  -> build tool registry
  -> run PikiWikiAgent
  -> stream agent/tool events
  -> commit journal if raw/wiki actually changed
  -> complete task
```

服务端不再先做高层语义分流：

- 不再根据 `selected_paths` 自动进入服务侧 source intake workflow。
- 不再根据自然语言里的 source path 自动进入服务侧 ingest workflow。
- 不再用服务侧 query fallback 作为正常产品路径。
- 兼容 endpoint 可以保留，但内部应转换成“带系统上下文的统一 agent task”。

## 4. Context Envelope

只要调用 agent，都装配同一类上下文信封。

### 4.1 基础上下文

每轮都注入：

- `AGENTS.md`
- `purpose.md`
- `wiki/index.md`

这些不是可选 workflow 输入，而是 agent 理解 vault 规则、目标和入口索引的基础条件。

### 4.2 用户上下文

用户上下文包括：

- 用户输入文本。
- 主会话框上传/选择的文件路径。
- Inbox 选择的文件路径。
- UI 按钮携带的上下文，例如“对当前 wiki 页面总结”“把这条回答记下来”“修正当前选中段落”。
- 系统动作上下文，例如当前页面、当前选中文本、当前文件 chip、当前消息引用。

产品原则是：**按钮不直接实现一套业务逻辑，而是把用户意图和界面上下文注入 agent 会话。**

例外只限 UI 文件管理动作本身：

- 主会话框和 Inbox 的上传/选文件，是把文件路径加入用户上下文。
- 文件 chip 的移除，是发送前的本地输入编辑。
- 明确的 clear/delete 文件动作可以是受控服务动作，但如果它修改 `raw/` 或 `wiki/`，仍要进入 journal 判断。

### 4.3 会话上下文

每轮注入最近 10 条对话：

- user message
- assistant final answer
- 必要时包含上一轮 task id、引用文件、journal id、附件摘要

用途：

- 支持“展开讲第二点”。
- 支持“把你刚才说的记下来”。
- 支持“这页刚才那个判断改一下”。

会话上下文不是长期记忆。只有 agent 调用写工具并真实改变 `raw/` 或 `wiki/` 后，内容才进入长期 vault。

## 5. Tool-Driven 业务能力

服务侧原来的 workflow 能力应被下沉成 agent 可调用工具。

### 5.1 Vault 读工具

示例工具：

- `read_file`
- `list_files`
- `search_text`
- `parse_markdown`

这些工具触发 UI 状态：`正在阅读wiki`。

### 5.2 Vault 写工具

示例工具：

- `write_file`
- `append_file`
- 后续可增加更结构化的 `upsert_wiki_page`、`append_wiki_log`

这些工具触发 UI 状态：`正在写入wiki`。

写工具必须返回：

- `changed`
- `path`
- `before_hash`
- `after_hash`
- 是否属于 journal scope

### 5.3 文件转换工具

服务侧 source intake 不再作为独立业务流程存在，改为 agent 工具：

- `convert_pdf_to_markdown`
- `convert_docx_to_markdown`
- `read_external_text_file`
- `copy_source_asset`
- `write_canonical_source`

Agent 可以按需调用：

1. 读取用户提供的外部文件。
2. 转换为 Markdown。
3. 写入 `raw/assets/` 和 `raw/sources/`。
4. 继续读取 wiki/index。
5. 写入 `wiki/sources/`、`wiki/entities/`、`wiki/concepts/` 等页面。

文件工具的安全边界：

- 只能读取用户当轮明确提供的路径。
- 不能写 vault 外路径。
- 写入 vault 内文件必须走 Vault Writer。

### 5.4 维护工具

lint、index 修复、断链检查、重复概念检查等也应逐步工具化：

- agent 可以自主决定是否调用。
- 低风险修复仍通过写工具落盘。
- 是否 journal 只由真实 raw/wiki 变更决定。

## 6. Journal 规则

Journal 判断只看当轮对话的真实写入，不看服务端预判的 task kind。

规则：

1. 当轮 agent 没有调用写工具：不入 journal。
2. 当轮 agent 调用了写工具，但所有写入 `changed=false`：不入 journal。
3. 当轮 agent 调用了写工具，且至少一个 `raw/` 或 `wiki/` 文件 hash 发生变化：入 journal。
4. 写入 `system/`、task store、event store 等非 raw/wiki 状态：不进入 Change Journal。
5. Clear/delete 如果删除的是 `raw/` 或 `wiki/` 文件，也按真实变更进入 journal。

实现上不需要扫描整个 vault。更轻的方案是：

- 写工具执行前读取目标文件内容和 hash。
- 写工具执行后计算目标文件新 hash。
- 只记录当轮写工具实际触达的路径。
- task 结束时由 `ChangeJournalService.commit_for_task()` 根据这些 snapshots 判断是否创建 journal entry。

这比全量 vault hash 轻，也比依赖 task kind 更准确。

## 7. UI 状态规则

会话中的 agent 状态只基于 agent 当前是否调用工具，以及调用了什么工具。

通用规则：

- agent run 开始但尚未调用工具：显示 `正在思考`。
- 读类工具开始：显示 `正在阅读wiki`。
- 写类工具开始：显示 `正在写入wiki`。
- 文件转换类工具开始：显示 `正在整理文件` 或 `正在转换文档`。
- journal commit 开始：显示 `正在记录变更`。
- task terminal：显示 `已完成` 或 `失败`。
- 从一个工具开始到下一个工具开始前，状态保持不变。
- 不因为 `sdk.run.started`、message delta 或 tool finished 自动把状态重置成 `正在思考`。

因此，问“孟岩正在做点啥？”时：

```text
正在思考
正在阅读wiki    # 如果 agent 调用 read/search/list/parse 工具
已完成
```

普通问候时：

```text
正在思考
已完成
```

上传 PDF 并说“帮我记录这个文档”时，状态不是服务端硬编码流水线，而是由 agent 工具调用自然产生：

```text
正在思考
正在转换文档      # convert_pdf_to_markdown
正在写入wiki      # write raw/source or wiki page
正在阅读wiki      # read/search index and related pages
正在写入wiki      # update compiled wiki
正在记录变更
已完成
```

## 8. 高优用例在新模型下的后台流程

### 8.1 普通问候 / 探索式聊天

UI：

- 用户发送普通消息。
- Assistant 流式回复。
- 状态：`正在思考` -> `已完成`。

后台：

- `POST /tasks`
- 装配基础上下文、用户上下文、近 10 条会话上下文。
- 进入统一 agent task。
- Agent 直接回答。
- 不调用写工具，不入 journal。

### 8.2 查询知识库事实

UI：

- 状态：`正在思考`。
- 如果 agent 调用读工具，显示 `正在阅读wiki`。
- 回复中显示引用路径或来源 chip。
- 没找到时明确说明知识库没有足够记录。
- Recent Activity 不新增记录。

后台：

- `POST /tasks`
- 装配统一上下文。
- Agent 自主调用 `read_file`、`search_text`、`parse_markdown` 等工具。
- Agent 生成回答和引用。
- 未调用写工具，不入 journal。

### 8.3 跨页面综合 / 分析

UI：

- 状态：`正在思考`。
- 如调用读工具，显示 `正在阅读wiki`。
- 默认不显示写入或 Recent Activity。

后台：

- 统一 agent task。
- Agent 根据问题跨 `wiki/index.md`、concept、domain、synthesis、entity 页面检索和阅读。
- 默认只读回答。
- 如果用户明确要求“保存为综合页”，agent 可调用写工具，真实变更后入 journal。

### 8.4 基于回答继续追问

UI：

- 在同一会话继续展示。
- 状态由工具调用决定。

后台：

- 统一 agent task。
- 注入近 10 条会话上下文。
- Agent 利用上一轮回答理解“第二点”等指代。
- 是否读 wiki、是否写 wiki 都由 agent 自主决定。

### 8.5 记录对话框中的内容

UI：

- 状态：`正在思考`。
- 如果读取旧页面，显示 `正在阅读wiki`。
- 如果写入 source/wiki，显示 `正在写入wiki`。
- 完成后 Recent Activity 出现 journal entry。

后台：

- 统一 agent task。
- 用户上下文包含要记录的文本、引用的上一条 user/assistant 消息或选中文本。
- Agent 判断应该写入 `raw/sources/`、`wiki/sources/` 或相关 wiki 页面。
- 写工具真实改变 raw/wiki 后，task 结束时 commit journal。

### 8.6 上传文件并要求记录

UI：

- 输入框显示 file chip。
- 发送后状态由工具调用驱动。
- 文件转换、读 wiki、写 wiki、记录变更都在同一条 assistant 对话里可见。

后台：

- `POST /tasks` 带 `selected_paths`。
- 服务端只把文件路径作为用户上下文和工具 allowlist 注入 agent。
- Agent 自主调用 PDF/DOCX/MD 转换工具。
- Agent 自主写入 canonical source。
- Agent 自主继续 ingest 到 wiki。
- 真实 raw/wiki 变更后入 journal。

### 8.7 更新 / 修正已有 wiki 知识

UI：

- 状态：`正在思考`。
- 如查找目标页，显示 `正在阅读wiki`。
- 如修改页面，显示 `正在写入wiki`。
- 完成后 Recent Activity 出现 journal entry。

后台：

- 统一 agent task。
- Agent 搜索/读取目标页面。
- Agent 调用写工具做局部更新。
- 写工具记录 before/after hash。
- task 结束时 commit journal，支持回滚。

## 9. 目标架构

```text
api/
  routes: HTTP 入参、出参、SSE，不做业务意图判断
application/
  TaskService: 创建 task、启动 executor
  AgentTaskExecutor: 装配 context envelope、运行 agent、提交 journal
  EventPublisher/EventStreamService
context/
  BaselineContextAssembler
  ConversationContextAssembler
  UserContextAssembler
runtime/
  AgentRunner: SDK run / streaming
  SdkEventMapper: message delta / raw event 映射
  ToolFactory: 注册所有 agent tools
tools/
  vault_read_tools
  vault_write_tools
  document_conversion_tools
  maintenance_tools
vault/
  VaultAccess
  VaultWriter
journal/
  ChangeJournalService
store/
  task/event/journal/session repositories
```

迁移后的依赖方向：

- API 不 import workflows。
- Application 不做高层意图分类。
- Runtime 不直接更新 task 状态。
- Tools 不创建 task，不决定 task kind。
- Journal 只根据写工具 snapshots 决定是否入 journal。
- Workflows 如果保留，只作为 agent 工具内部的可复用算法，不作为主任务入口。

## 10. 重构计划

### Phase A：文档与契约锁定

目标：先锁住 agent-centric 规则，避免继续沿服务侧 workflow 加功能。

- 新增本文件作为架构基准。
- 更新 Roadmap 2.0，加入 Agent-Centric Runtime Simplification 阶段。
- 补 characterization tests，锁住外部 API 兼容：`POST /tasks`、SSE、`message.delta`、journal recent、rollback。

验收：

- 产品和工程文档都明确：主入口统一进 agent，服务端不做高层业务分流。

### Phase B：统一 Context Envelope

目标：每轮 agent 调用都拿到同一类上下文。

- 新增 `ConversationContextAssembler`，读取近 10 条会话。
- 新增 `UserContextAssembler`，封装 user input、selected paths、UI action context、selected message/page。
- Task executor 统一构造 `AgentTaskInput`。
- Runner prompt 明确区分基础上下文、用户上下文、会话上下文和工具规则。

验收：

- “展开讲第二点”能依赖上一轮上下文。
- “把你刚才说的记下来”能引用上一条 assistant message。
- 带文件任务进入同一个 agent runner，而不是提前 source intake。

### Phase C：把 Source Intake 下沉为工具

目标：删除服务侧 source intake 作为主流程的地位。

- 新增文档转换工具：PDF、DOCX、MD/TXT 读取。
- 新增受控 asset/source 写入工具。
- `selected_paths` 只作为 agent 可读外部文件 allowlist。
- 旧 `/ingest-queue`、Inbox ingest 入口兼容保留，但内部改为创建统一 agent task，注入“请处理这些文件”的系统上下文。

验收：

- 上传 PDF + “帮我记录这个文档”由 agent 自主调用转换和写入工具完成。
- 服务端不再在 `TaskRouter` 中把 `selected_paths` 判成 `SOURCE_INTAKE`。

### Phase D：移除主路径 TaskRouter 语义分流

目标：`POST /tasks` 主路径只产生统一 agent task。

- `TaskKind.AGENT` 成为默认且唯一主入口 task kind。
- `SOURCE_INTAKE`、`INGEST`、`SOURCE_CLEAR` 迁移为兼容 mode 或工具内部动作。
- 显式 slash command 不由服务端分流，而是进入 prompt/user context，让 agent 按命令调用工具。
- SDK 不可用时只允许明确 fallback 提示，不伪装成完整 agent 能力。

验收：

- 普通问候、知识库查询、记录内容、上传文件、修正 wiki 都走同一个 executor。
- task event 中不再依赖服务端 workflow progress 判断产品阶段。

### Phase E：Tool-Driven UI 状态

目标：UI 状态完全跟随 agent 工具调用。

- `tool.started` 统一映射为 `agent.progress`。
- 默认 run start 显示 `正在思考`。
- tool finished 不改变状态。
- message delta 不覆盖当前工具状态。
- terminal event 显示 `已完成` / `失败`。

验收：

- 问“孟岩正在做点啥？”时，只有 agent 真实读 wiki 才显示 `正在阅读wiki`。
- 普通问候不显示读库。
- 上传文件时，转换、读、写状态来自真实工具调用。

### Phase F：Journal Commit 收敛

目标：journal 只看写工具真实变更。

- 写工具统一记录 `FileSnapshot`。
- 删除 task kind / workflow 对 journal 的影响。
- `ChangeJournalService.commit_for_task()` 只接收当轮写工具 snapshots。
- 增加测试覆盖：调用写工具但内容不变不入 journal；写 `system/` 不入 journal；写 `raw/` 或 `wiki/` 入 journal。

验收：

- 普通 query 不出现在 Recent Activity。
- 真实 raw/wiki 修改一定出现在 Recent Activity。
- 无变化写入不制造空 journal。

### Phase G：清理旧 Workflow 边界

目标：把旧 workflow 降级为工具算法或删除。

- `workflows/source_intake.py` 拆为 document conversion / canonical source helpers。
- `workflows/ingest.py` 中 prompt/helper 保留给 agent 工具或 agent instructions，主流程不直接调用。
- `workflows/query.py` 仅作为 SDK 不可用时的开发 fallback，产品 UI 明确标识 fallback。
- 更新测试和文档，删除过时阶段描述。

验收：

- 目录结构表达的是 agent tools 和审计边界，而不是服务端业务流程。
- 新用例优先加工具和 prompt，不再加新的 task kind。

## 11. 当前实现需要重点调整的点

- `agent_service/application/task_router.py` 仍在做高层分流，需要逐步移除主路径依赖。
- `agent_service/application/task_executor.py` 仍有 `_execute_source_intake`、`_execute_ingest`、`_execute_source_clear` 等服务侧 workflow。
- `agent_service/workflows/source_intake.py` 应迁移为 agent 可调用的转换/写入工具。
- `agent_service/runtime/tool_factory.py` 目前只有 vault read/write 基础工具，需要补文件转换和 source 写入工具。
- `agent_service/context/assembler.py` 目前只装配基础上下文，还缺用户上下文和近 10 条会话上下文。
- `agent_service/tools/vault_tools.py` 已经接近正确方向：写工具记录 snapshot，journal commit 可继续沿用，但应确保 journal 不依赖 task kind。

## 12. 设计原则速记

- 不用服务端猜意图，让 agent 自己判断。
- 不用 task kind 判断能否回滚，只看真实 raw/wiki 写入。
- 不把文件摄入写成服务端流水线，把转换和写入做成 agent 工具。
- 不让按钮绕过 agent，按钮只是注入上下文。
- 不用技术事件驱动用户状态，用户状态只看 agent 工具动作。
- 不把聊天历史默认写入长期记忆，只有显式写工具变更才进入 vault。
