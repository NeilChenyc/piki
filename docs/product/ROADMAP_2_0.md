# Piki Roadmap 2.0：调试与优化路线图

Piki 已完成 MVP 初步开发，当前重点从“搭建能力”转向“调试真实闭环、提高可用性、消除误导状态”。

Roadmap 2.0 的目标不是重做 MVP，而是在现有 Mac App、本地 Agent Service、vault 工具、OpenAI Agents SDK runtime、change journal、lint 和 rollback 基础上，把真实用户链路调到稳定可用。

## 阶段 1：真实 Agent Runtime 闭环调试

目标：让 Mac App 中的自然语言对话真正进入 OpenAI Agents SDK 的 `PikiWikiAgent`，而不是静默降级到本地只读 query fallback。

### 当前 gap

- 本地 Agent Service 已能启动，Mac App 也能连接 `/health`、调用 `POST /tasks` 并订阅 SSE。
- `openai-agents` 包已安装，`PikiWikiAgentRunner` 可以 import SDK。
- `.env` 已配置 `OPENAI_API_KEY`、`OPENAI_BASE_URL` 和 `PIKI_AGENT_MODEL`。
- 但 `PIKI_ENABLE_SDK_RUNTIME` 未启用时，`/health` 会显示 `sdk_runtime_enabled: false`、`sdk_runtime_configured: false`。
- 在 SDK runtime 未配置时，普通自然语言任务会进入 `run_read_only_query` fallback，所以短问候或开放式对话会被误当作 wiki 关键词检索。
- 当前 `/tasks` 是同步执行任务后返回，SSE 主要回放已记录事件；尚未实现真正的 `Runner.run_streamed` 实时事件流。
- Mac App 目前只显示 service connected，不够明确地区分 `SDK agent mode` 与 `fallback query mode`。

### 实现计划

1. 启用 SDK runtime 配置：
   - 在本地 `.env` 中设置 `PIKI_ENABLE_SDK_RUNTIME=1`。
   - 保持 `OPENAI_BASE_URL=https://timicc.com`，该值来自 TiMi CC 页面配置中的 `api_base_url`。
   - 重启本地 Agent Service，让配置重新加载。

2. 跑真实 smoke test：
   - 调用 `POST /runtime/smoke-test`。
   - 若成功，确认 `/health` 显示 `sdk_runtime_enabled: true` 与 `sdk_runtime_configured: true`。
   - 若失败，优先排查 base URL、模型名、Responses API 兼容性和 `OpenAIProvider` 配置。

3. 跑最小真实任务：
   - 用 `POST /tasks` 发送普通问候或简单 query。
   - 验证事件中出现 `sdk.run.started` 和 `sdk.run.completed`。
   - 验证最终消息来自 SDK final output，而不是 `query.completed` fallback。

4. 修正状态表达：
   - `/health` 已提供 SDK runtime 字段，Mac App 需要在 Home / Settings 中明确展示当前运行模式。
   - SDK 未配置时，聊天区应提示“当前为 fallback query mode”，避免用户误以为完整 agent 正在工作。

5. 后续优化：
   - 将 `Runner.run_sync` 升级为 `Runner.run_streamed`。
   - 将 SDK message delta、tool started/finished、final output 映射为稳定 Piki task events。
   - 对 fallback 增加明确 reason，避免小聊天被展示成高置信 wiki 回答。

### 验收标准

- `/health` 显示 SDK runtime 已启用且已配置。
- `/runtime/smoke-test` 能通过当前 endpoint 和模型返回结果。
- Mac App 发起普通聊天时，后端任务事件包含 `sdk.run.started` 与 `sdk.run.completed`。
- 普通聊天不再静默走 `query.completed` fallback。
- Mac App 能清楚显示当前是 `SDK Agent` 还是 `Fallback Query`。

### 当前实现状态

- 已在 `.env` 启用 `PIKI_ENABLE_SDK_RUNTIME=1`。
- 已确认 `/health` 返回 `sdk_runtime_enabled: true` 与 `sdk_runtime_configured: true`。
- 已确认 `/runtime/smoke-test` 通过当前 `https://timicc.com` endpoint 与 `gpt-5.4` 模型。
- 已确认普通 `POST /tasks` 会产生 `sdk.run.started`、`sdk.run.completed` 和 `task.completed` 事件。
- Mac App 已在 Home、Sidebar 和 Settings 中展示当前 runtime mode，区分 `SDK Agent`、`Fallback Query` 和离线状态。
- 当前仍使用同步 `Runner.run_sync`；真正的 streaming event loop 放入后续阶段。

### 暂不做

- 不在本阶段实现多 agent handoff。
- 不在本阶段引入向量数据库或复杂检索。
- 不把 SSE 完整实时 streaming 作为阶段 1 的阻塞项；先确认真实 SDK agent loop 可用。
- 不迁移 `.env` 到 Application Support；产品打包前再做配置迁移。

## 阶段 2：Agent 可观察性、主入口文件流与 Journal UI

目标：把 MVP 从“能跑通”调到“用户知道它在做什么、知道它改了什么、能从主对话入口和 Inbox 完成文件摄入与回退”。

这一阶段围绕一个产品原则收敛：Home 对话框是自然语言和附件协同的主入口；Inbox 仍可作为文件上传、预览和单文件操作入口；Wiki 只作为浏览和检索入口。客户端不暴露批量 ingest、全局 clear 或直接新建 wiki 页面等容易绕过 agent 维护规则的操作。服务端已经写好的批处理、队列或兼容接口可以暂时保留，客户端先不暴露。

### 当前核实结论

- Agent Service 已经有 task event 表、SSE endpoint、SDK run event、tool event、file changed event、journal entry 和 rollback API。
- `/tasks/{id}/events` 当前只回放已落库事件；`POST /tasks` 同步执行完成后才返回，因此前端无法在 agent 真正运行中实时看到进度。
- SDK runner 当前使用 `Runner.run_sync`，不是 `Runner.run_streamed`。
- 后端会记录较底层事件，例如 `tool.started`、`tool.finished`、`file.changed`、`sdk.run.started`、`sdk.run.completed`，但没有稳定的用户友好 progress event。
- Home 当前只把 `.started` 事件类型直接显示成技术字符串，例如 `sdk.run.started`，没有转译成用户可理解的状态。
- 对话内容“像中断”的主要原因之一是：SDK `AgentResult.summary` 在后端被截断为 `final_output[:500]`，`task.completed` 也只发送这个 summary；Mac 端收到 `task.completed` 后认为已经有最终消息，不再调用 `GET /tasks/{id}` 读取完整 `output.answer`。
- Recent Activity 当前只显示本次会话内收到的 `task.completed` 文本，不读取 `/journal/recent`。
- 后端 `/journal/recent` 已返回 `id`、`task_id`、`status`、`affected_files`、`created_at`、`eligible_for_rollback` 等字段；Mac 端 `JournalEntry` DTO 仍期望 `description`、`timestamp`、`changed_files`，字段契约不匹配。
- `POST /journal/{journal_entry_id}/rollback` 已存在，且后端只允许最近两条 active journal entry 按 hash 校验回退。
- Inbox 目前展示 Drop Zone、`Ingest All` 和 `Clear` 按钮；其中 Drop Zone 可以保留，但文件 drop 只是本地追加 UI item，没有调用后端。
- Inbox 右侧单项 `Ingest` / `Remove` 按钮目前是空 action；产品上应保留单文件 ingest 和 clear，但需要通过 Agent Service 执行。
- Swift `APIClient.enqueueIngest` 发送 `paths`，但后端 `IngestQueueEnqueueRequest` 需要 `selected_paths`，当前会 422。
- 后端已支持两种摄入入口：`POST /tasks` 携带单个 `selected_paths` 执行 source intake；`POST /ingest-queue/enqueue` + `POST /ingest-queue/process` 执行队列式 source intake。
- 后端 source intake 当前只做文件规范化到 `raw/sources/*.md`，不会自动执行 SDK-backed wiki ingest。
- Home 对话框的 `+` 按钮目前无 action，也没有 Finder 选择文件、拖拽文件或粘贴文件能力。
- Wiki 页面目前已移除直接新建按钮；当前定位是浏览本地 wiki 页面。

### 2.1 Agent 进度状态：从底层事件到用户友好状态

产品期望不是把每个工具名都暴露给用户，而是显示 agent 正在做的大阶段。阶段 2 先定义稳定的用户友好状态，再由后端或前端把底层事件映射过去。

建议状态：

- `正在理解请求`：收到 task、装配上下文、判断是普通对话、source intake、ingest、lint 或 rollback。
- `正在读取知识库`：由 `context.loaded`、`query.searched`、`tool.started/read_file`、`tool.started/list_files`、`tool.started/search_text`、`tool.started/parse_markdown` 统一映射而来。
- `正在整理资料`：由 `source_intake.started`、`source_intake.normalized`、`ingest.started`、`ingest_queue.process_started` 统一映射而来。
- `正在思考和生成`：由 `sdk.run.started` 到首个写入/完成事件之间映射而来。
- `正在写入知识库`：由 `tool.started/write_file`、`tool.started/append_file`、`file.changed` 统一映射而来。
- `正在记录变更`：由 `journal_entry.created` 或 `task.completed` 中带 `journal_entry_id` 映射而来。
- `正在回退变更`：由 `rollback.completed` / `rollback.failed` 映射而来。
- `已完成` / `失败`：由 `task.completed` / `task.failed` 映射而来。

实现方式：

1. 后端新增轻量 progress event，建议事件名为 `agent.progress`，payload 只包含：
   - `stage`：稳定枚举，例如 `reading_vault`、`writing_vault`。
   - `title`：中文短句，例如“正在读取知识库”。
   - `detail`：可选的一句话，不暴露过细工具参数。
2. 保留底层 `tool.started` / `tool.finished` 事件用于调试和日志，不直接在普通 UI 中展示工具名。
3. 在 `VaultToolRegistry` 和主要 workflow 节点中集中发 progress event，避免前端猜太多。
4. Mac Home 只显示 progress title/detail；必要时再在开发模式展开底层 event。

验收标准：

- 用户发起一次普通 query 时，Home 至少显示“正在理解请求”“正在读取知识库/正在思考和生成”“已完成”。
- 用户发起一次会写 vault 的任务时，Home 能显示“正在写入知识库”和“正在记录变更”。
- UI 不展示原始技术事件名，例如 `sdk.run.started`。

### 2.2 对话最终内容完整渲染

当前 bug：

- 后端 `AgentResult.summary` 截断为 500 字符。
- `task.completed` payload 只带 summary。
- Mac 端收到 `task.completed` 后把 summary 当最终消息并停止补拉任务详情。
- 因此长回答会像提前结束。

实现方式：

1. 后端保持 `summary` 为短摘要，但 `task.completed` 需要同时带可渲染的完整 answer，或者明确只带 `answer_ref`。
2. 更稳妥的客户端策略：收到 `task.completed` 后总是调用 `GET /tasks/{id}`，优先渲染 `output.answer`，其次 `output.summary`，最后才用 event summary。
3. `sdk.run.completed` 中的 `final_output_preview` 只作为状态预览，不作为最终回答。
4. 如果后续实现 `Runner.run_streamed`，message delta 只负责流式预览，最终仍以 task record 中的完整 answer 校准一次。

验收标准：

- 超过 500 字的回答不会被截断。
- `task.completed` 后，Mac 端最终消息与 `GET /tasks/{id}` 的 `output.answer` 一致。
- fallback query、SDK agent、ingest 失败三种路径都有明确最终消息。

### 2.3 Recent Activity 改为 Change Journal 视图

产品期望：

- Recent Activity 不是普通 task 历史，而是 Change Journal 视图。
- 只显示真实修改过 `raw/` 或 `wiki/` 的对话级 journal entry。
- 最新两条 eligible journal entry 显示 rollback 按钮。

当前 gap：

- 后端已有 `/journal/recent` 和 `/journal/{id}/rollback`。
- 后端会返回 `eligible_for_rollback`，符合“最多最近两条可回退”的产品规则。
- Mac 端 DTO 与后端字段不匹配，且 HomeViewModel 未调用 `recentJournal`。
- ActivityRow 没有 rollback action，也没有展示 affected files。

实现方式：

1. 修正 Swift `JournalEntry` DTO：
   - `id`
   - `task_id`
   - `status`
   - `affected_files`
   - `created_at`
   - `rolled_back_at`
   - `eligible_for_rollback`
2. Home 加载和每次 task 完成后调用 `/journal/recent?vault_path=...` 刷新 Recent Activity。
3. Recent Activity item 展示：
   - 变更时间。
   - 影响文件数量和最多 2-3 个路径。
   - 状态：active / rolled_back / rollback_failed。
   - 最新两条 active 且 `eligible_for_rollback=true` 的记录显示 rollback 按钮。
4. 点击 rollback 调用 `POST /journal/{id}/rollback`，完成后刷新 journal 和 vault status。

验收标准：

- 没有 vault 修改的普通 query 不出现在 Recent Activity。
- lint fix、SDK 写入、ingest 写入产生 journal entry 后会出现在 Recent Activity。
- 只有最新两条 active journal entry 显示 rollback。
- 回退成功后状态变为 rolled_back，并从可回退状态中移除。

### 2.4 Inbox / Wiki 客户端交互收敛

产品决策：

- Home 对话框是自然语言 + 附件的主入口，但 Inbox 也可以在客户端直接提供上传入口。
- Inbox 保留当前上传区域，用于拖拽或选择文件进入待处理列表。
- Inbox 右侧栏保留单文件 `Ingest` 与单文件 `Clear` 能力。
- Wiki 不提供直接上传或新建 wiki 文档入口；wiki 由 agent 维护。
- Inbox 不提供 `Ingest All` 和全局 `Clear`。
- 这里的“权限收敛”只指客户端交互收敛；服务端已实现的队列、批处理或兼容接口可以暂时保留，不要求在本阶段删除。

当前 gap：

- Inbox 顶部 Drop Zone 可以保留，但目前只改前端状态，没有接 Agent Service。
- Inbox 底部有 `Ingest All` 和 `Clear`。
- 右侧栏单文件 `Ingest` / `Remove` 尚未接后端。
- 现有 `ingest-queue/process` 支持批处理；服务端接口可以保留，但产品上不应作为主 UI 按钮暴露。

实现方式：

1. 保留 Inbox 的上传区域，并让 Drop Zone / Browse 选择文件后调用 Agent Service，而不是只追加本地 UI item。
2. 移除 Inbox 底部的 `Ingest All` 和全局 `Clear` 客户端按钮；服务端批处理接口暂时保留。
3. Inbox 继续读取 `raw/inbox` 与 `raw/sources`，作为队列/来源状态浏览界面。
4. 右侧栏单文件 `Ingest`：
   - 对 `raw/inbox` 或 vault 外用户选中文件，调用 `POST /tasks`，body 带 `selected_paths: [path]`，进入 source intake。
   - source intake 成功后刷新 Inbox 列表。
   - 如后续需要“从 canonical source 写入 wiki”，再由用户在 Home 对话框明确要求 `/wiki:ingest raw/sources/xxx.md` 或自然语言触发 SDK-backed ingest。
5. 右侧栏单文件 `Clear`：
   - 当前后端没有“清理 inbox 文件”的明确 task action。
   - 阶段 2 需要新增一个受控清理动作，并通过 Agent Service 执行，而不是 Mac App 直接删除文件。
   - 推荐实现为 `POST /tasks` 增加 `mode` 或 `action` 语义，例如 `mode: "clear-inbox-item"`，只允许清理 `raw/inbox/` 下的单个文件；执行前后记录 task event。
   - 如果清理行为会修改 `raw/`，应进入 change journal；如果只是取消 ingest queue item，则走 `POST /ingest-queue/{id}/cancel`，不进入 vault change journal。
6. 修正 Swift `enqueueIngest` 字段名为 `selected_paths`，即使批量处理不在客户端主 UI 暴露，也保持 API client 正确。

验收标准：

- Inbox 页面保留上传区域，但没有 `Ingest All` 和全局 `Clear`。
- 通过 Inbox 上传区域添加文件会调用 Agent Service，并能进入后续 source intake 或待处理状态。
- 用户仍可对单个 Inbox item 发起 ingest。
- 用户仍可对单个 Inbox item 发起 clear，并且 clear 通过 Agent Service 执行。
- Wiki 页面只浏览/搜索，不提供直接创建或上传 wiki 文件入口。

### 2.5 Home 对话框文件上传：Finder 与粘贴文件

产品期望：

- 主对话框同时支持自然语言和文件。
- 用户可以点 `+` 调起 Finder 选择文件。
- 用户可以直接粘贴文件到对话框。
- 上传/选择文件后，由 Agent Service 统一 source intake，不由 Mac App 直接写 vault。

当前 gap：

- ChatInputView 的 `+` 按钮无 action。
- Home send request 只发送 `user_input`，没有 `selected_paths`。
- ChatInputView 没有文件 chips、附件状态、Finder picker、drop 或 pasteboard 文件解析。
- 当前 source intake 支持单文件，`selected_paths` 多于一个会失败；多文件需要走 ingest queue 或逐个 task。

实现方式：

1. ChatInputView 增加附件状态：
   - 显示已选择文件 chips。
   - 支持移除单个附件。
   - 支持发送时附带 `selected_paths`。
2. `+` 按钮调起 `NSOpenPanel`：
   - 支持选择 PDF、DOCX、Markdown、TXT。
   - MVP 先限制一次一个文件，和当前 source intake 能力一致。
   - 多文件后续可转 ingest queue。
3. 粘贴文件：
   - 监听 pasteboard 中的 `fileURL`。
   - 粘贴到输入框时，如果是文件 URL，则加入附件 chips；如果是普通文本，则按文本粘贴。
4. HomeViewModel 发送 task：
   - 无附件：普通 agent task。
   - 单附件：`POST /tasks` 带 `selected_paths: [path]`，让后端执行 source intake。
   - 附件 + 文本：文本作为用户说明，附件路径作为 selected path。
5. Source intake 完成后，UI 提示生成的 `raw/sources/*.md` 路径，并建议下一步是否执行 wiki ingest。

验收标准：

- 用户可以从 Home 对话框通过 Finder 选择一个支持文件并发送。
- 用户可以把 Finder 中的文件复制后粘贴到 Home 对话框并发送。
- 文件不会由 Mac App 直接写入 vault；必须通过 Agent Service 的 task/source intake。
- 文件 intake 成功后，Inbox 能看到对应状态变化或新的 source。

### 阶段 2 交付顺序

1. 修复最终回答截断：客户端 task completed 后补拉完整 task record，优先渲染 `output.answer`。
2. 建立 `agent.progress` 事件和前端状态映射。
3. Recent Activity 接入 `/journal/recent`，实现 rollback 按钮。
4. 收敛 Inbox/Wiki UI：Inbox 保留上传区域和单文件操作，去掉 `Ingest All` 和全局 `Clear`；Wiki 只保留浏览/搜索。
5. Home 对话框实现 Finder 文件选择。
6. Home 对话框实现粘贴文件。
7. 单文件 Ingest / Clear 经 Agent Service 执行，并修正 ingest queue API 字段契约。

### 当前实现状态

- 已为 `POST /tasks` 增加 `async_mode`；默认同步行为保留，Mac 客户端使用异步任务以便通过 SSE 看到运行中事件。
- 已新增 `agent.progress` 用户友好进度事件，并将读库、整理资料、思考生成、写入、记录变更、清理和完成等阶段映射为中文状态。
- 已修复 SSE 在任务终态附近提前断开的 race，确保 `task.completed` / `task.failed` 等终态事件能送达客户端。
- 已修复长回答截断体验：Mac 客户端在 task 结束后补拉 `GET /tasks/{id}`，优先渲染完整 `output.answer`。
- 已修正 `task.completed` payload，在 SDK agent、query fallback、source intake、ingest、clear 等路径尽量带 `answer`。
- 已将 Recent Activity 接入 `/journal/recent`，显示 Change Journal，而不是普通 task history。
- 已在 Recent Activity 的 eligible journal entry 上显示 rollback 按钮，并通过 `POST /journal/{id}/rollback` 执行回退。
- 已修正 Swift Journal DTO 与后端 `/journal/recent` 字段契约。
- 已修正 Swift ingest queue enqueue 字段，从 `paths` 改为 `selected_paths`。
- Inbox 保留上传区域；Drop / Browse 文件会通过 Agent Service 创建 source intake task。
- Inbox 已移除客户端底部 `Ingest All` 和全局 `Clear`，服务端批处理接口保留。
- Inbox 右侧栏单文件 `Ingest` 已接入 `POST /tasks selected_paths`。
- Inbox 右侧栏单文件 `Clear` 已接入 `mode: clear-inbox-item`，后端只允许清理 `raw/inbox/` 单文件，并记录 Change Journal。
- Home 对话框 `+` 已支持 Finder 选择 PDF、DOCX、Markdown、TXT 文件，并随消息发送到 Agent Service。
- Home 对话框已支持粘贴文件 URL 并作为附件发送。
- 后端自动化测试覆盖 async task stream、clear inbox journal 和 rollback；当前 `pytest` 为 33 passed, 1 skipped，Swift build 通过。

## 阶段 3：流式 Agent 对话与文件摄入编译流水线

目标：让 Home 对话真正像 agent 工作台一样呈现执行过程。普通知识库问题要在读库时显示“正在读取知识库”，模型回答要流式出现；用户带文件发出“帮我记录/摄入/整理这个文档”这类自然语言时，系统要显式经过 source intake、Markdown canonical source、wiki ingest 和 change journal，而不是只返回一个 source 路径。

### 当前 gap

- 后端任务可以异步创建并通过 SSE 回放事件，但 SDK runner 仍主要使用 `Runner.run_sync`；前端看不到模型文本 delta。
- SDK 原始 streaming 事件不应直接暴露给 Mac App；需要映射为稳定的 Piki 事件，例如 `message.delta`。
- 对普通 query，UI 容易被 `sdk.run.started` 或默认“正在思考”覆盖，导致用户看不到“正在读取知识库”这个关键阶段。
- `selected_paths` 当前只执行 source intake：复制资产、抽取文本、写入 `raw/sources/*.md` 和 `system/source_manifest.json`。它不会继续把 canonical source 编译进 `wiki/`。
- 文件摄入过程目前更像后台任务结果，不像一次可观察的 agent 对话：用户不能在同一条 assistant 回复里看到 intake、转换、读库、写库、记录变更等阶段。

### 产品决策

- `message.delta` 是稳定客户端协议：payload 只包含 `delta` 和可选 `content`，不暴露 SDK raw event shape。
- `agent.progress` 是阶段状态协议：Home 普通模式展示中文阶段和简短 detail；底层 `tool.started`、`sdk.run.started`、`file.changed` 继续保留给调试。
- 对普通知识库问题，读库相关事件优先级高于泛化“正在思考”。只有首个模型文本 delta 或明确生成阶段出现后，才进入“正在生成回答”。
- 对带文件的 Home 任务，默认执行完整流水线：source intake -> canonical Markdown source -> SDK-backed wiki ingest -> journal。若 SDK runtime 不可用，则停在 source intake，并明确告诉用户已生成 source、尚未编译进 wiki。
- 对 Inbox 的纯文件单项操作可以复用同一后端路径；后续如需“只 intake 不 ingest”，再增加明确 mode，而不是让主入口默认半途停止。

### 实现计划

1. 后端 runner streaming：
   - 将 `run_task` 和 `run_ingest` 的 SDK 调用优先切到 `Runner.run_streamed`。
   - 消费 SDK `response.output_text.delta`，映射为 `message.delta`。
   - 运行结束后仍以 `final_output` 校准 task `output.answer`，避免 delta 丢包造成最终回答不一致。

2. 状态优先级：
   - 普通 agent task 先显示“正在读取知识库”，等待工具事件和文本 delta 推动后续阶段。
   - Mac 端不再把 `sdk.run.started` 直接渲染成“正在思考”覆盖当前读库状态。
   - 收到 `message.delta` 后显示“正在生成回答”，并增量更新 assistant 消息。

3. 文件摄入编译流水线：
   - `selected_paths` 单文件任务先执行 source intake。
   - 成功后发出“正在转换为 Markdown Source”“正在编译进 Wiki”等 progress。
   - SDK runtime 可用时自动调用现有 single-source ingest workflow，读取刚生成的 `raw/sources/*.md` 并写入 `wiki/`。
   - 完成时 task output 同时包含 `intake` 和 `ingest` 结果，`task.completed.answer` 给出用户可读总结和 journal 信息。
   - SDK runtime 不可用时，task 仍成功完成 source intake，但 answer 明确说明下一步需要启用 SDK 后再 ingest。

4. 前端对话渲染：
   - assistant 气泡支持 progress steps，像 agent 对话一样显示已发生阶段。
   - `message.delta` 直接追加到当前 assistant 内容。
   - `task.completed` 后补拉完整 task record，并用最终 answer 校准流式内容。

### 验收标准

- 问“孟岩正在做点啥？”时，Home 在读取/搜索 wiki 阶段显示“正在读取知识库”，不会长期停在“正在思考”。
- SDK 模型输出在 assistant 气泡中逐步出现，而不是等任务结束一次性渲染。
- 上传文件并输入“帮我记录一下这个文档”时，同一条对话中能看到 source intake、Markdown source、wiki ingest、写入/记录变更等阶段。
- 文件流水线成功后，`raw/sources/*.md` 和相关 `wiki/` 页面都被写入；若写入了 `raw/` 或 `wiki/`，Recent Activity 出现对应 change journal。
- SDK 不可用时，文件任务不假装完成 wiki ingest，而是明确停在 canonical source 已生成。

## 阶段 4：Agent-Centric Runtime Simplification

目标：把阶段 2/3 中为跑通闭环引入的服务侧 workflow 重新收敛成统一 agent task。服务端只负责 task、context、tool、event、journal 和 rollback；自然语言意图、文件摄入、wiki 更新和跨页面分析都由 agent 在同一套上下文与工具中自主完成。

详细原则与计划见 `AGENT_CENTRIC_REFACTOR_PLAN.zh.md`。

### 当前 gap

- `TaskRouter` 仍会根据 `selected_paths`、显式 source path 和 `mode` 分流为 `SOURCE_INTAKE`、`INGEST`、`SOURCE_CLEAR` 或 `AGENT`。
- `TaskExecutor` 仍保留 `_execute_source_intake`、`_execute_ingest`、`_execute_source_clear` 等服务侧业务路径。
- Source intake 仍是服务端 pipeline，而不是 agent 自主调用的 PDF/DOCX/MD 转换与 canonical source 写入工具。
- Context assembler 目前只装配 `AGENTS.md`、`purpose.md`、`wiki/index.md`，还没有统一注入用户上下文和近 10 条会话上下文。
- UI progress 仍有部分状态来自服务侧 workflow，而不是只由 agent 工具调用驱动。

### 产品决策

- `POST /tasks` 主路径统一进入 agent，不再让服务端先判断 query、ingest、record 或 update。
- 每次 agent run 都装配基础上下文、用户上下文和会话上下文。
- 文件路径只是用户上下文和外部读取 allowlist；文件转换、canonical source 写入和 wiki ingest 由 agent 调用工具完成。
- 除 journal 判断外，其他业务判断和执行均由 agent 自主完成。
- Journal 只看当轮写工具是否真实改变 `raw/` 或 `wiki/`。
- 会话状态只由工具调用驱动：无工具时 `正在思考`；读工具 `正在阅读wiki`；写工具 `正在写入wiki`；转换工具 `正在转换文档`；终态 `已完成` / `失败`。

### 实现计划

1. 统一 context envelope：
   - 新增用户上下文和近 10 条会话上下文装配。
   - UI button action 改为注入上下文调用 agent，而不是绕过 agent 执行业务逻辑。

2. 工具化 source intake：
   - 增加 PDF/DOCX/MD/TXT 转 Markdown 工具。
   - 增加受控 asset/source 写入工具。
   - `selected_paths` 改为 agent 可读文件 allowlist。

3. 收敛 task router：
   - `POST /tasks` 主路径只创建统一 agent task。
   - 旧 ingest/source/clear endpoint 或 mode 保留兼容，但内部转换成 agent task 或受控工具动作。

4. 工具驱动 UI 状态：
   - `agent.progress` 只由 `tool.started`、journal commit 和 terminal event 推动。
   - tool finished、SDK run started 和 message delta 不覆盖当前工具状态。

5. Journal commit 收敛：
   - 写工具统一记录 before/after hash 和 snapshot。
   - task 结束时只对真实 raw/wiki 变更创建 journal entry。

### 验收标准

- 普通问候、知识库查询、继续追问、记录对话内容、上传文件记录、修正 wiki 都走统一 agent task。
- 问“孟岩正在做点啥？”时，只有 agent 真实调用读工具才显示“正在阅读wiki”，不会由服务端预设状态伪造。
- 上传文件并说“帮我记录这个文档”时，转换、读库、写库和记录变更都来自 agent 工具调用。
- 未调用写工具或写入无变化的对话不进入 Recent Activity。
- 写入 `raw/` 或 `wiki/` 的对话一定进入 Change Journal，并继续支持最近两条回滚。
