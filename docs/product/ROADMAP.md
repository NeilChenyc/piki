# Piki MVP 开发路线图

Piki 是一个面向个人的本地优先知识库产品，核心目标是帮助用户更可靠地“记住”和更自然地“回忆”。

MVP 不追求大而全，而是先跑通一条可验证的最小闭环：

```text
Vault -> Local Agent Service -> Query -> Source Intake -> Agents SDK Runtime -> Direct Wiki Write -> Change Journal -> Rollback -> Lint -> Client
```

底层真相始终是本地 Markdown vault。Mac 客户端、API、slash command 和 agent 对话都只是操作这套 vault 的不同入口。

## 路线评估

当前产品方向合理，但实现路径需要从“分层铺能力”调整为“垂直切片优先”。

原先路线里，queue、用户审核、API、客户端、检索、编译等能力被拆成较多独立阶段。这样文档完整，但开发时容易出现两个问题：

- 前期做了很多 schema、队列和规划，但用户还无法完成一次真实 `query` 或 `ingest`。
- 本地 API 被放在较后阶段，但 OpenAI Agents SDK 本地 Agent Service 本身就需要 API、事件流、任务状态和变更记录。

优化后的路线把 **本地 Agent Service** 提前作为 P0 基础设施，然后依次验证：

1. 只读 `query` 是否可靠。
2. 单文件是否能进入 `raw/` 并规范化为 canonical Markdown source。
3. OpenAI Agents SDK 是否能通过本地服务和 OpenAI-compatible endpoint 真正运行 agent loop。
4. 单 source `ingest` 是否能直接写入 wiki、index、log。
5. 每条真实修改 `raw/` 或 `wiki/` 的对话是否能形成 journal entry，并支持最近两条修改对话 hash 校验回退。
6. `lint` 是否能维持长期质量。
7. 客户端是否能把这些能力变成顺滑工作流。

## 开发原则

- 本地优先：原始资料、wiki 页面、日志、索引都在用户本地。
- Markdown 为真相：即使不用 Piki App，也能用 Obsidian、Git 或编辑器打开。
- Agent 负责维护：用户负责选择资料和判断价值，agent 负责摘要、链接、更新、检查。
- Agent runtime 优先基于 OpenAI Agents SDK：复用 SDK 的 agent loop、工具调用、streaming、session 和 tracing。
- 本地确定性 pipeline 可以承担 source intake、基础 query 和 change journal/rollback 等系统职责；需要语义分析、综合和 wiki 写入的 workflow 必须进入 SDK agent loop。
- Piki 保留产品边界：vault 内外读写边界、AGENTS.md 只读、对话级 journal entry、index/log 和回退策略由 Piki 控制；自然语言不再经过独立前置分流层。
- 先只读，后写入：先把 `query` 跑稳，再做 `ingest` 写入。
- 先记录，后回退：agent 可直接写 vault；如果某条对话真实修改 `raw/` 或 `wiki/`，系统记录 journal entry，必要时按 hash 校验回退最近两条修改对话。
- 先单 source，后批量：避免一开始做复杂 batch ingest。
- 中文检索从 MVP 开始考虑：不能等产品后期才补中文召回。
- 每个阶段都要有可演示闭环，而不是只交付文档或内部结构。

## 阶段 0：Vault 协议与 Golden Vault

目标：把 LLM Wiki 内核作为可执行的本地协议固定下来，并建立后续测试用的 golden vault。

范围：

- 创建 `piki-vault/`。
- 建立 `raw/ + wiki/ + AGENTS.md`。
- 建立 `wiki/index.md` 和 `wiki/log.md`。
- 建立 `sources/concepts/entities/domains/synthesis` 五类 wiki 页面。
- 增加 `purpose.md`，描述这个个人记忆库的目标、记忆范围、回忆偏好、维护偏好和使用节奏。
- 建立 `test-vault/` 或等价 golden vault，用于自动化测试。

交付物：

- `piki-vault/AGENTS.md`：agent 维护协议。
- `piki-vault/purpose.md`：个人记忆目标说明。
- `piki-vault/raw/inbox/`、`raw/sources/`、`raw/assets/`。
- `piki-vault/wiki/index.md`、`wiki/log.md`。
- 至少一组 seed wiki 页面：source、concept、entity、domain、synthesis。
- Golden vault 测试 fixture。

验收标准：

- 任意 agent 进入 `piki-vault/` 后，先读 `AGENTS.md` 就能理解如何维护知识库。
- 用户能直接用 Markdown / Obsidian 浏览 vault。
- `llm-wiki.md` seed source 已经被编译进 wiki 网络。
- Golden vault 可以被测试脚本复制、运行、比对输出。

暂不做：

- 不做 UI。
- 不做自动 ingest。
- 不做复杂数据库。

## 阶段 1：本地 Agent Service 骨架

目标：建立不用 CLI 的本地 agent 承载层，让客户端可以创建任务、订阅事件、查看变更记录。

范围：

- 建立 FastAPI 本地服务。
- 建立 SQLite task/event/session/journal entry 基础表。
- 安装并探测 OpenAI Agents SDK，建立最小 runner scaffold。
- 建立 `PikiWikiAgent` 单 agent。
- 建立统一 task API：带文件请求进入 source intake，纯自然语言请求进入统一 agent 入口。
- 建立 context assembler。
- 建立 Piki event schema。
- 建立 SSE 事件流。
- 建立 rollback API 占位。
- 实现只读工具：`read_file`、`list_files`、`search_text`、`parse_markdown`。
- 实现 vault-safe 写入工具占位和对话级 journal entry 记录接口。

交付物：

- `agent_service/` 服务骨架。
- `POST /tasks`。
- `GET /tasks/{id}`。
- `GET /tasks/{id}/events`。
- `POST /tasks/{id}/rollback`。
- SQLite schema。
- Piki event schema。
- 最小 SDK runner scaffold。

验收标准：

- 客户端或 curl 可以创建一个 task。
- task events 可以通过 SSE 看到。
- agent 能读取 `AGENTS.md`、`purpose.md`、`wiki/index.md`。
- 工具调用会被记录成 Piki events。
- 真实修改 `raw/` 或 `wiki/` 的对话会被记录为 journal entry；`AGENTS.md` 和 vault 外路径不会被写入。

暂不做：

- 不做多 agent handoff。
- 不做复杂 MCP 工具体系。
- 不做 SDK agent loop 的真实业务接入。
- 不做非 OpenAI-compatible endpoint 完整兼容。
- 不做 Mac UI。

## 阶段 2：只读 Query MVP

目标：先证明 Piki 能从已有 wiki 中可靠“回忆”，并返回带引用的回答。

范围：

- 只读 query fallback。
- Index-first query：回答前先读 `wiki/index.md`。
- Markdown keyword search。
- 中文友好检索：至少支持 CJK bigram 或简单中文 token 策略。
- Wikilink recall：利用内部链接扩展相关页面。
- Citation 格式。
- Recall modes：快速回答、深入回答、列出相关页面。
- 默认不重读所有 raw source。

交付物：

- query pipeline。
- 本地搜索原型。
- citation schema。
- `QueryResult` structured output。
- `query` golden tests。

验收标准：

- 中文内容可以被关键词召回。
- query 能返回相关 wiki 页面和引用。
- agent 不默认重读所有 raw source，而是优先使用编译 wiki。
- 用户能选择快速回答、深入回答或只列相关页面。
- 重要 query 可直接追加 `wiki/log.md`；因为修改了 `wiki/`，这条对话会进入 change journal。

暂不做：

- 不把向量数据库作为必需依赖。
- 不做复杂 reranker。
- 不做全库每次暴力读完。

## 阶段 3：单文件 Source Intake 与 Markdown Normalization

目标：让用户从主交互入口上传或指定一个文件后，系统先把它可靠地变成可追踪的 canonical Markdown source，而不是立刻污染长期 wiki。

范围：

- Source intake workflow。
- 支持从用户提供路径或客户端上传临时文件载入资料。
- 支持 Markdown、纯文本、PDF、DOCX 的最小导入。
- 原始文件先进入 `raw/inbox/` 或 `raw/assets/`，按目录职责保留。
- 将可处理内容规范化为 `raw/sources/*.md`。
- Source normalization：标题、路径、来源、日期、格式、hash、原始文件引用。
- 建立或更新 source manifest，避免同一文件重复 normalization。
- 失败时保留错误原因，不写入 wiki。

交付物：

- `SourceIntakeResult` structured output。
- capture/source-intake API。
- Markdown / 文本导入器。
- PDF 文本抽取的最小实现或清晰占位策略。
- DOCX 文本抽取的最小实现。
- source meta extractor。
- canonical Markdown source 模板。
- source manifest schema。
- 单文件 intake golden tests。

验收标准：

- 用户能通过 API 提交一个本地 Markdown、PDF 或 DOCX 文件路径。
- 系统能把文件复制到合适的 `raw/` 位置，并生成 `raw/sources/*.md`。
- 生成的 source Markdown 包含标题、格式、hash、原始文件路径和正文。
- 同一 source 未变化时不会重复生成新 source。
- 失败任务不会破坏 vault，并且可以看到失败原因。
- 这个阶段不更新 `wiki/`。

暂不做：

- 不做批量 ingest。
- 不做复杂 PDF 版面还原、图片 OCR 或表格抽取。
- 不做 PPTX/音频/视频/OCR 全量支持。
- 不做浏览器插件或复杂网页剪藏。
- 不做用户逐条审核写入。

## 阶段 4：OpenAI Agents SDK Runtime 真接入

目标：让本地 Agent Service 不只“安装 SDK”，而是真正通过 OpenAI Agents SDK 和配置的 OpenAI-compatible endpoint 运行 `PikiWikiAgent`。

范围：

- 配置 `OPENAI_API_KEY`、`OPENAI_BASE_URL`、`PIKI_AGENT_MODEL`。
- 支持 OpenAI-compatible endpoint，例如 `https://timicc.cc`。
- 实现 `Runner.run` smoke test。
- 建立 `PikiWikiAgent` 动态 instructions。
- 将 vault 工具注册为 SDK `function_tool`：`read_file`、`list_files`、`search_text`、`parse_markdown`、`write_file`、`append_file`。
- 工具执行写入时先记录 task event；对话结束时，如果本对话真实修改了 `raw/` 或 `wiki/`，再汇总生成一条 journal entry。
- 将 SDK run / tool / final output 事件映射为 Piki task events。
- 默认关闭或可配置 tracing，避免把敏感 vault 内容发送到非预期 tracing 端点。

交付物：

- endpoint/model 配置与 health 展示。
- SDK smoke test task 或调试命令。
- SDK tool registry。
- SDK event mapper。
- 最小 `PikiWikiAgent` runner。
- SDK runtime 集成测试。

验收标准：

- `/health` 能显示 SDK 可用、API key 已配置、base URL 和模型配置状态。
- smoke test 能通过配置的 endpoint 返回模型结果。
- agent 能通过 SDK tool 读写 vault 内允许的文件。
- tool 调用会被记录为 Piki events。
- `write_file` / `append_file` 能直接写 vault 内允许文件；若写入目标在 `raw/` 或 `wiki/` 下，对话级 journal entry 会记录 before/after hash。

暂不做：

- 不做多 agent handoff。
- 不做 MCP 工具体系。
- 不做复杂 session 记忆。
- 不做写入前 human-in-the-loop；MVP 依赖对话级 journal entry 和 rollback。

## 阶段 5：单 Source Ingest Write

目标：让单个已规范化 Markdown source 能被分析，并直接写入 wiki、index 和 log。

范围：

- SDK-backed ingest workflow。
- 支持从 `raw/sources/` 或用户明确指定的 canonical source 读取来源。
- 使用阶段 4 的 `PikiWikiAgent` 和 SDK tools 执行 source analyze / generate / write。
- Analyze 阶段输出：摘要、实体、概念、主张、证据、冲突、低置信度内容、候选链接、建议更新页面。
- 创建或更新 source page。
- 创建或更新 concept/entity/domain 页面。
- 必要时创建或更新 synthesis 页面。
- 更新 `wiki/index.md` 和 `wiki/log.md`。
- 冲突和低置信度内容直接写入页面和日志中的明确标记。

交付物：

- `IngestResult` structured output。
- source page 生成规则。
- concept/entity/domain/synthesis 写入规则。
- wiki index/log 更新规则。
- 单 source ingest golden tests。
- SDK-backed ingest integration tests。

验收标准：

- 单个 Markdown source 可以稳定完成 analyze。
- 用户可以看到新增/修改了哪些页面。
- 新信息与旧信息冲突时，不会静默覆盖。
- agent 直接写入正式 wiki，并记录 task events。
- ingest task 真实经过 OpenAI Agents SDK runner，而不是本地占位流程。

暂不做：

- 不做批量 ingest。
- 不做 PDF/DOCX 原始文件深度解析；这些应先经阶段 3 转成 source。
- 不做写入前用户审核流。

## 阶段 6：Change Journal 与 Rollback

目标：让 agent 直接写入 vault 的同时，系统能对真实修改 `raw/` 或 `wiki/` 的对话建 journal，并支持最近两条修改对话 hash 校验回退。

范围：

- 对话级 journal entry 记录。
- 某条对话首次修改 `raw/` / `wiki/` 文件前，记录该文件的 `before_hash` 和 `before_content`。
- 对话结束时，记录该对话内所有 raw/wiki 修改文件的 `after_hash` 和 `after_content`。
- 只修改 `system/`、`purpose.md` 或其他非 `raw/` / `wiki/` 文件的对话不创建 journal entry，不作为 MVP 回退对象。
- 只保留最近 2 条修改了 `raw/` / `wiki/` 的对话作为可回退记录。
- 回退前校验当前 hash 必须等于 `after_hash`。
- 任一文件 hash 不一致，整次回退失败，不做部分回退。
- 写入时记录 task event；对话级 journal entry 记录 diff。

交付物：

- journal entry schema。
- rollback API。
- hash 校验回退逻辑。
- index update 规则。
- log append 规则。
- write rollback / failure report。
- rollback 集成测试。

验收标准：

- agent 对话真实修改 `raw/` 或 `wiki/` 后会形成 journal entry。
- `AGENTS.md` 不会被 agent 写入。
- vault 外路径绝不会被写入。
- 写入后 `wiki/index.md` 和 `wiki/log.md` 被正确更新。
- 所有 affected files 可追踪。
- 最近一条和倒数第二条 raw/wiki 修改对话可回退。
- 当前 hash 与记录不一致时，回退失败并保留原因。
- 写入失败不会破坏 vault。

暂不做：

- 不做自动 commit。
- 不做复杂分支管理。
- 不做批量大重写。

## 阶段 7：Source Manifest 与 Update Queue

目标：把 source 变化纳入可持续管理，不依赖用户逐条审核。

范围：

- 支持 source hashing，避免重复 ingest。
- 支持 source change scan。
- source 变化后进入 update queue，而不是直接静默改 wiki。
- 支持 `check_after`，用于维护复查而不是用户审核。
- 低置信度和冲突内容写入页面明确标记。

交付物：

- `system/queues/update.jsonl` 或 SQLite update queue。
- source manifest 扩展字段。
- source change scan 规则。
- maintenance marker 规则。

验收标准：

- 同一 source 未变化时不会重复处理。
- source 内容变化会进入 update queue；后续由单 source ingest 或阶段 8 的显式小批处理入口逐条走 analyze -> generate -> write -> journal entry。
- 低置信度、冲突和待复查内容能在 wiki 中被明确看到。

暂不做：

- 不做用户审核队列。
- 不做复杂权限系统。
- 不做全自动批量 ingest 一切；批量也应保留逐条对话级 journal entry。

## 阶段 8：Ingest Queue 与批量 Capture

目标：在单文件 intake 跑通后，让多个资料能可靠排队进入 source normalization 和 ingest write。

范围：

- 建立 ingest queue。
- 支持 queue 状态：pending、processing、failed、retry、cancelled、completed。
- 失败时记录原因，允许重试。
- 产品打开或手动 rescan 时扫描 source manifest。
- 支持简单批量 capture。

交付物：

- ingest queue。
- 队列状态 API。
- 错误重试机制。

验收标准：

- 用户能把文件放入 inbox 并加入 ingest queue。
- 队列任务能进入 ingest write。
- 批量任务默认逐条或小批量执行，便于定位和回退错误。
- 失败任务不会破坏 vault，并且可以看到失败原因。

暂不做：

- 不做浏览器插件。
- 不做复杂网页剪藏。
- 不做所有格式导入。

## 阶段 9：Lint 与维护

目标：让知识库长期不腐烂，持续发现断链、重复、过期和知识缺口。

范围：

- deterministic-first lint workflow；SDK 辅助总结可后续增强。
- Frontmatter 检查。
- 断链检查。
- 孤儿页检查。
- 重复概念检查。
- 缺失索引检查。
- 模板缺失检查。
- Stale scan：根据 `check_after` 找待复查内容。
- Knowledge gaps：识别高频但无页面的概念、用户关心但资料不足的领域。
- 低风险修复可直接写入；若修改 `wiki/`，则记录对话级 journal entry。

交付物：

- `LintResult` structured output。
- lint report。
- broken link checker。
- orphan page checker。
- stale scan report。
- knowledge gap report。
- lint-fix direct write。

验收标准：

- 用户能一键看到 wiki 健康问题。
- 可自动执行低风险结构修复；若修改 `wiki/`，则记录对话级 journal entry。
- 高风险内容问题写入明确标记和维护日志。

暂不做：

- 不做复杂图聚类。
- 不做“惊喜连接”评分。

## 阶段 10：Mac 客户端 MVP

目标：提供一个普通用户愿意每天打开的个人记忆工作台。

说明：客户端可以在阶段 1 后并行做壳层，但完整 MVP 验收应放在核心 agent service、query、ingest、change journal/rollback 和 lint 闭环之后。

范围：

- Vault picker：选择或创建本地 vault。
- Inbox：查看待处理资料，添加文件或文本。
- Ingest queue：查看状态、失败原因、重试。
- Rollback：查看最近 journal entry，并执行 hash 校验回退。
- Explore：浏览 source、concept、entity、domain、synthesis。
- Ask：对知识库提问，答案带引用。
- Maintenance：查看 lint、孤儿页、过期页、知识缺口。
- 本地服务生命周期：开发期支持手动 `uvicorn` 服务连接；产品期由 Mac App 检查并拉起 bundled Agent Service。
- 连接状态：启动时 `/health`、定期 health、设置页 Test Connection、断开/错误提示。
- 任务流：Ask 调用 `POST /tasks`，并通过 SSE 渲染 task events 和最终回复。
- 推荐三栏布局：左侧知识树/队列，中间对话与命令，右侧页面预览和引用。

交付物：

- Mac app shell。
- Vault onboarding。
- Inbox/queue/rollback/explore/ask/maintenance 基础页面。
- 本地 Agent Service 连接层。
- Local Service Manager：复用已有健康服务，缺失时拉起 `agent-service/piki-agent-service`，退出时停止自己拉起的服务。
- 基础设置页：模型、vault 路径、回退保留策略、检索偏好。

验收标准：

- 用户可以完成一次完整闭环：导入资料 -> 编译 -> 查看变更 -> 必要时回退 -> 提问 -> 维护检查。
- 开发期手动启动 `uvicorn agent_service.app:app --host 127.0.0.1 --port 8000` 后，Mac App 能显示 connected 并完成一次 Ask。
- 未选择 vault 时，Mac App 不会调用 `POST /tasks`，并提示用户先选择 vault。
- 产品期没有运行中的服务时，Mac App 会尝试拉起 bundled Agent Service；如果 bundle 可执行文件缺失或端口不可用，会显示明确错误。
- 用户不需要理解文件结构也能使用核心能力。
- 用户仍然可以直接打开 Markdown vault 查看所有数据。

暂不做：

- 不做移动端。
- 不做多人协作。
- 不做云同步。
- 不做复杂富文本编辑器。

## 阶段 11：播客 Source 工作流

目标：接入已有小宇宙/听悟工具，让播客 source 成为正式 ingest 输入。

范围：

- 输入小宇宙 episode URL 或 RSS URL。
- 提取音频直链。
- 提取 `show notes`，生成 `官方节目概览.md`。
- 请求听悟，获取转写全文、章节摘要、大模型摘要。
- 将官方节目概览、转写全文、章节摘要、大模型摘要打包成 source package。
- ingest 时以官方节目概览优先校对实体名、节目名、作者名和核心观点。

交付物：

- podcast source normalizer。
- source package manifest。
- 官方节目概览优先规则。
- RSS / episode URL capture。
- 播客 ingest golden tests。

验收标准：

- 一期播客可以从 URL 变成可 ingest 的 source package。
- `官方节目概览.md`、`转写全文.md`、`章节摘要.md`、`大模型摘要.md` 可以联动预览。
- 后续 wiki 编译能优先参考官方节目概览处理名词冲突。

暂不做：

- 不做批量订阅自动转写。
- 不做音频本地上传。

## 阶段 12：Dogfooding 与 MVP 打磨

目标：用 Piki 维护 Piki 自己，验证它是否真的能帮助“记住”和“回忆”。

范围：

- 用 Piki ingest 项目文档、roadmap、产品笔记、设计讨论。
- 记录一周真实使用中的失败 case。
- 优化中文 recall。
- 优化 rollback 和变更查看摩擦。
- 补齐最小测试和备份策略。

交付物：

- 自用 dogfooding vault。
- MVP 使用报告。
- bug/体验问题清单。
- 发布前 checklist。

验收标准：

- Piki 能回答“我们为什么这样设计”“某个功能阶段是什么”“之前讨论过什么取舍”等项目记忆问题。
- 用户一周内愿意持续 capture 和 query。
- 核心数据没有被 app 锁死。

## P0 / P1 / P2 摘要

### P0：最小可运行闭环

- Vault 协议与 golden vault。
- 本地 Agent Service。
- 只读 query。
- 单文件 source intake 与 Markdown normalization。
- OpenAI Agents SDK runtime 真接入。
- 单 source ingest write。
- change journal 和最近两条 raw/wiki 修改对话 rollback。

### P1：可日常使用闭环

- Source manifest / update queue。
- Source manifest。
- Ingest queue 与批量 capture。
- Lint。
- Mac 客户端 MVP。

### P2：扩展 source 与体验打磨

- 播客 source package。
- 更强中文检索。
- graph neighbor recall。
- 可恢复长任务。
- dogfooding 优化。

## MVP 总体不做事项

- 不做账户系统。
- 不做云同步。
- 不做多人协作。
- 不做移动端。
- 不把向量数据库作为必需内核。
- 不一开始支持所有复杂文件格式。
- 不做写入前用户审核流。
- 不把 Mac 客户端变成唯一数据入口。
- 不在第一版做多 agent handoff。
- 不在第一版做非 OpenAI provider 完整兼容。

## MVP 最终成功标准

- 用户可以把资料放进 vault，先形成可追踪 source，再可靠地编译成 wiki。
- 用户可以问问题，系统能从已有 wiki 中回忆并引用依据。
- Agent 不确定的内容会被明确标记，并可通过最近 journal entry 回退。
- 中文资料可以被基本召回。
- 所有重要操作都有 log，可追踪。
- 用户即使不用 Mac 客户端，也能直接打开 Markdown vault 阅读和迁移数据。
