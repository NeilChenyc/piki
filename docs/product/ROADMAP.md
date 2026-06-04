# Piki MVP 开发路线图

Piki 是一个面向个人的本地优先知识库产品，核心目标是帮助用户更可靠地“记住”和更自然地“回忆”。MVP 不追求大而全的研究套件，而是先跑通一条稳定闭环：

```text
Capture -> Ingest Queue -> Analyze -> Review -> Generate -> Recall -> Save to Wiki -> Maintain
```

底层真相始终是本地 Markdown vault。Mac 客户端、CLI、API 和 agent 对话都只是操作这套 vault 的不同入口。

## 开发原则

- 本地优先：原始资料、wiki 页面、日志、索引都在用户本地。
- Markdown 为真相：即使不用 Piki App，也能用 Obsidian、Git 或编辑器打开。
- Agent 负责维护：用户负责选择资料和判断价值，agent 负责摘要、链接、更新、检查。
- MVP agent 承载优先复用 Codex CLI：先借它跑通本地 agent loop，再决定何时下沉为自有 runtime。
- 先审核后沉淀：低置信度、冲突、敏感和重大判断进入 review queue。
- 记住和回忆闭环：高价值对话内容必须能 Save to Wiki，让回忆结果反过来增强记忆。
- 单一 operation model：自然语言、slash command、CLI、本地 API、Mac 客户端共享同一套操作语义。
- 中文检索从 MVP 开始考虑：不能等产品后期才补中文召回。

## 阶段 0：Vault 内核与项目基础

目标：把 LLM Wiki 内核作为可执行的本地协议固定下来。

范围：

- 创建 `piki-vault/`。
- 建立 `raw/ + wiki/ + AGENTS.md`。
- 建立 `wiki/index.md` 和 `wiki/log.md`。
- 建立 `sources/concepts/entities/domains/synthesis` 五类 wiki 页面。
- 增加 `purpose.md`，描述这个个人记忆库的目标、记忆范围、回忆偏好、维护偏好和使用节奏。

交付物：

- `piki-vault/AGENTS.md`：agent 维护协议。
- `piki-vault/purpose.md`：个人记忆目标说明。
- `piki-vault/raw/inbox/`、`raw/sources/`、`raw/assets/`。
- `piki-vault/wiki/index.md`、`wiki/log.md`。
- 至少一组 seed wiki 页面：source、concept、entity、domain、synthesis。

验收标准：

- 任意 coding agent 进入 `piki-vault/` 后，先读 `AGENTS.md` 就能理解如何维护知识库。
- 用户能直接用 Markdown/Obsidian 浏览 vault。
- `llm-wiki.md` seed source 已经被编译进 wiki 网络。

暂不做：

- 不做 UI。
- 不做自动 ingest。
- 不做复杂数据库。

## 阶段 1：Operation Model 与命令层

目标：定义所有入口共享的底层操作语义，让自然语言和 slash command 都能稳定映射到同一套动作。

范围：

- 定义 operation 类型：capture、ingest、compile、query、file-back、lint、review。
- 设计 slash command：
  - `/wiki:ingest <source>`
  - `/wiki:compile <source-or-inbox>`
  - `/wiki:query "<question>"`
  - `/wiki:file-back`
  - `/wiki:lint`
  - `/wiki:research "<topic>"`
- 设计自然语言到 operation 的解析规则。
- 设计风险等级：只读、低风险写入、高风险写入、必须审核。
- 设计操作确认格式：将执行什么、目标是什么、预计改哪些页面、是否需要 review。

交付物：

- operation model 文档。
- command spec 文档。
- 自然语言 intent mapping 规则。
- agent 可遵循的操作确认模板。

验收标准：

- 同一个任务用自然语言和 slash command 表达时，能解析到同一个 operation。
- 写操作在有歧义或风险时不会直接执行。
- 后续 CLI/API/Mac 客户端可以复用这套 operation model。

暂不做：

- 不做完整 NLU 引擎。
- 不做深度 research automation。

## 阶段 1.5：Codex CLI 接入与客户端壳层

目标：在不自研 agent runtime 的前提下，让 Piki 客户端可以稳定承载 Codex CLI 作为 MVP agent 层。

范围：

- 约定客户端如何启动和附着到 Codex CLI 会话。
- 明确文档注入顺序：`AGENTS.md`、`purpose.md`、`wiki/index.md`、相关产品文档、相关 source。
- 设计客户端如何渲染 CLI 的结构化输出：消息、工具动作、文件改动、任务状态、错误。
- 定义最小审批流：写入前确认、review queue 跳转、失败重试。
- 定义哪些体验保留为 CLI 原貌，哪些体验由客户端重渲染。

交付物：

- Codex CLI 接入说明。
- 客户端会话承载方案。
- CLI 输出到 UI 视图模型的映射规则。
- MVP 审批流和状态流说明。

验收标准：

- 用户能在 Piki 客户端内发起一次 ingest、query 或 file-back。
- 用户能看到 agent 当前在读什么、改什么、为什么停下。
- 文件变更、转写结果、节目概览、章节摘要等可以在客户端里联动预览。

暂不做：

- 不做自有 agent runtime。
- 不做完全脱离 Codex CLI 的协议层。

## 阶段 2：Capture、Source 管理与 Ingest Queue

目标：让资料可靠进入知识库，先成为可追踪 source，而不是立刻污染长期记忆。

范围：

- 支持 Markdown、纯文本、PDF 的基础导入。
- 支持把资料放入 `raw/inbox/`。
- 支持 source normalization：标题、路径、来源、日期、格式、hash。
- 支持 source hashing，避免重复 ingest。
- 支持打开产品时或手动 rescan 时扫描 source manifest。
- source 变化后进入 update queue，而不是直接静默改 wiki。
- 建立 ingest queue。
- 支持 queue 状态：pending、processing、failed、retry、cancelled、completed。
- 失败时记录原因，允许重试。

交付物：

- `system/queues/ingest.jsonl` 或等价队列文件。
- `system/queues/update.jsonl` 或等价更新队列文件。
- source manifest。
- source hash 计算规则。
- source change scan 规则：新增、修改、移动、删除、未变化。
- 基础导入脚本或 CLI 原型。
- 队列状态查看命令。

验收标准：

- 用户能把文件放入 inbox 并加入 ingest queue。
- 同一 source 未变化时不会重复处理。
- 产品打开或手动 rescan 后，能发现 `raw/sources/` 中新增、修改、移动或删除的 source。
- source 内容变化会进入 update queue，并走 Analyze -> Review -> Generate，而不是直接静默重写 wiki。
- 失败任务不会破坏 vault，并且可以看到失败原因。

暂不做：

- 不做浏览器插件。
- 不做 DOCX/PPTX/音频/视频/OCR 全量支持。
- 不做完全自动批量 ingest 一切。

## 阶段 3：Analyze -> Generate 两阶段编译

目标：让资料先被分析，再经过确认或规则判断后写入正式 wiki。

范围：

- Analyze 阶段不直接写正式 wiki。
- Analyze 输出包括摘要、实体、概念、主张、证据、冲突、低置信度内容、候选链接、建议更新页面。
- Generate 阶段创建或更新 source、concept、entity、domain、synthesis。
- 每次正式写入后更新 `wiki/index.md` 和追加 `wiki/log.md`。
- 写入前提供变更摘要或 diff preview。

交付物：

- analyze result schema。
- generate patch schema。
- source page 生成规则。
- concept/entity/domain/synthesis 更新规则。
- diff preview 或变更摘要格式。

验收标准：

- 单个 source 可以稳定完成 analyze。
- 用户可以看懂将新增/修改哪些页面。
- generate 后 wiki/index 和 wiki/log 被正确更新。
- 新信息与旧信息冲突时，不会静默覆盖。

暂不做：

- 不做完全无审核自动写入。
- 不做复杂多 agent 并行编译。

## 阶段 4：Review Queue 与安全写入

目标：建立长期记忆的质量闸门，避免 agent 把不确定内容写死。

范围：

- 建立 review queue。
- 支持 review item 类型：低置信度、冲突内容、敏感个人记忆、重大判断、待复查内容。
- 支持审核动作：approve、reject、edit、defer。
- 支持 `review_after`。
- 审核决策写入 `wiki/log.md`。

交付物：

- `system/queues/review.jsonl` 或等价审核队列文件。
- review item schema。
- review decision log 格式。
- 冲突、过期、superseded 标记规范。

验收标准：

- 低置信度和冲突内容会进入 review queue。
- 用户可以批准、拒绝、编辑或延后处理。
- 审核后的写入有日志可追踪。

暂不做：

- 不做多人审核。
- 不做复杂权限系统。

## 阶段 5：回忆与检索 MVP

目标：让用户能高效问回自己的记忆，并得到可引用、可追溯的回答。

范围：

- Index-first query：回答前先读 `wiki/index.md`。
- Markdown keyword search。
- 中文友好检索：至少支持 CJK bigram 或类似策略。
- Wikilink recall：利用内部链接扩展相关页面。
- Source overlap recall：多个页面引用同一 source 时作为相关性信号。
- Graph neighbor recall：通过相邻 concept/entity/domain 扩展回忆。
- 支持 recall modes：快速回答、深入回答、列出相关页面。
- 回答必须带引用。

交付物：

- 本地搜索索引原型。
- CJK tokenization/bigram 规则。
- wiki link graph 构建规则。
- query pipeline 文档或 CLI 原型。
- citation 格式。

验收标准：

- 中文内容可以被关键词召回。
- query 能返回相关 wiki 页面和引用。
- agent 不默认重读所有 raw source，而是优先使用编译 wiki。
- 用户能选择快速回答、深入回答或只列相关页面。

暂不做：

- 不把向量数据库作为必需依赖。
- 不做复杂 reranker。
- 不做全库每次暴力读完。

## 阶段 6：Save to Wiki / File-back 闭环

目标：让高价值对话内容沉淀成长期记忆，使回忆结果继续增强知识库。

范围：

- 支持将有长期价值的对话片段保存为 conversation source。
- 根据内容性质分类更新 source、concept、entity、domain，必要时创建 synthesis。
- 保存原始问题、答案、证据、影响、相关页面、后续问题。
- 保存后更新 `wiki/index.md`、`wiki/log.md`。
- 与相关 concepts、entities、domains、sources 建立链接。
- 支持从 query 结果直接触发 file-back。

交付物：

- file-back operation。
- conversation source 模板。
- 分类编译规则：source、concept、entity、domain、synthesis。
- Save to Wiki 变更预览。
- file-back 日志格式。

验收标准：

- 用户一次问答后可以把有价值内容保存为 conversation source。
- 对话中抽取出的结论能被分类编译进相关 wiki 页面。
- 保存后的 source 和编译结果能在后续 query 中被召回。
- index/log 和相关页面链接被更新。

暂不做：

- 不做自动保存所有对话。
- 不把聊天历史当作默认长期记忆。

## 阶段 7：维护与健康检查

目标：让知识库长期不腐烂，持续发现断链、重复、过期和知识缺口。

范围：

- Lint：frontmatter、断链、孤儿页、重复概念、缺失索引、模板缺失。
- Librarian review：薄弱页面、低连接页面、需要合并的概念、内容层质量。
- Stale scan：根据 `review_after` 找待复审内容。
- Knowledge gaps：识别高频但无页面的概念、用户关心但资料不足的领域。
- 维护结果进入 log 或 review queue。

交付物：

- lint report。
- broken link checker。
- orphan page checker。
- stale scan report。
- knowledge gap report。

验收标准：

- 用户能一键看到 wiki 健康问题。
- 可自动修复低风险结构问题。
- 高风险内容问题进入 review queue。

暂不做：

- 不做复杂图聚类。
- 不做“惊喜连接”评分。

## 阶段 8：本地 API

目标：为 Mac 客户端、CLI 和外部 agent 提供统一能力入口。

范围：

- Read API：
  - health
  - vault info
  - page list
  - page read
  - search
  - graph
  - queue status
  - log
- Write API：
  - capture
  - ingest
  - compile
  - review decision
  - file-back
  - lint-fix
- 长任务支持 streaming progress。
- 写入前支持 diff preview 或 git checkpoint。

交付物：

- 本地 HTTP API 原型。
- API spec。
- operation runner。
- 任务进度事件格式。
- 安全写入策略。

验收标准：

- Mac 客户端无需理解底层文件细节即可读取 vault。
- 所有写操作都通过受控 operation。
- 长任务有可见进度。
- 重要写入可追踪、可回滚或至少可 diff。

暂不做：

- 不做公网服务。
- 不做账户系统。
- 不做云同步。

## 阶段 9：Mac 客户端 MVP

目标：提供一个普通用户愿意每天打开的个人记忆工作台。

范围：

- Vault picker：选择或创建本地 vault。
- Inbox：查看待处理资料，添加文件或文本。
- Ingest queue：查看状态、失败原因、重试。
- Review queue：approve、reject、edit、defer。
- Explore：浏览 source、concept、entity、domain、synthesis。
- Ask：对知识库提问，答案带引用。
- Save to Wiki：把有价值对话保存为 source，并将结论分类编译进 wiki。
- Maintenance：查看 lint、孤儿页、过期页、知识缺口。
- 推荐三栏布局：左侧知识树/队列，中间对话与命令，右侧页面预览和引用。

交付物：

- Mac app shell。
- Vault onboarding。
- Inbox/queue/review/explore/ask/maintenance 基础页面。
- 本地 API 连接层。
- 基础设置页：模型、vault 路径、写入确认偏好、检索偏好。

验收标准：

- 用户可以完成一次完整闭环：导入资料 -> 审核 -> 编译 -> 提问 -> 保存回答 -> 维护检查。
- 用户不需要理解文件结构也能使用核心能力。
- 用户仍然可以直接打开 Markdown vault 查看所有数据。

暂不做：

- 不做移动端。
- 不做多人协作。
- 不做云同步。
- 不做复杂富文本编辑器。

## 阶段 10：MVP 打磨与自用验证

目标：用 Piki 维护 Piki 自己，验证它是否真的能帮助“记住”和“回忆”。

范围：

- 用 Piki ingest 项目文档、roadmap、产品笔记、设计讨论。
- 记录一周真实使用中的失败 case。
- 优化中文 recall。
- 优化 review queue 摩擦。
- 优化 file-back 体验。
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

## MVP 总体不做事项

- 不做账户系统。
- 不做云同步。
- 不做多人协作。
- 不做移动端。
- 不把向量数据库作为必需内核。
- 不一开始支持所有复杂文件格式。
- 不做全自动无审核 ingest 一切。
- 不把 Mac 客户端变成唯一数据入口。

## MVP 最终成功标准

- 用户可以把资料放进 inbox，并可靠地编译成 wiki。
- 用户可以问问题，系统能从已有 wiki 中回忆并引用依据。
- 用户可以把高价值对话内容保存回 wiki，让记忆持续增长。
- Agent 不确定的内容会进入 review，而不是污染知识库。
- 中文资料可以被基本召回。
- 所有重要操作都有 log，可追踪。
- 用户即使不用 Mac 客户端，也能直接打开 Markdown vault 阅读和迁移数据。
