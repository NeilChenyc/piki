
# Piki MVP 功能全景

## 0. 产品定位

Piki 是一个面向个人的 **本地优先知识库产品** ，目标是帮助用户更可靠地“记住”和更自然地“回忆”。

它的核心不是把资料简单丢进一个 RAG 系统，而是基于  **LLM Wiki 模式** ，将用户的原始资料持续编译成一个：

* 可维护的个人记忆系统
* 可浏览的 Markdown Wiki
* 可追溯的知识网络
* 可审核、可增长、可回滚的长期记忆库

MVP 阶段的重点不是做复杂协作、云同步、多模态全量导入或重型 research automation，而是先跑通：

1. 个人知识库内核
2. Agent 维护流程
3. 基础检索与回忆
4. 审核与安全写入机制
5. 简易 Mac 客户端交互
6. 基于 Codex CLI 的 agent 承载层
7. 本地 API 与统一 operation model

---

# 1. MVP 总体能力地图

| 能力层                      | 核心问题                 | MVP 要支持什么                                                                |
| --------------------------- | ------------------------ | ----------------------------------------------------------------------------- |
| 个人记忆目标层              | 这个知识库为什么存在？   | 定义 vault 目的、记忆范围、回忆偏好、维护偏好和使用节奏                       |
| Vault 内核层                | 数据如何组织？           | 建立 raw + wiki 双层结构，保留原始资料，同时生成可读、可维护的 Wiki           |
| Agent 操作层                | 用户如何驱动系统？       | 支持自然语言和 slash command，并统一映射到受控 operation                      |
| Capture / Ingest 层         | 资料如何进入知识库？     | 支持 inbox、文件导入、source normalization、hash 去重、ingest queue           |
| Analyze / Generate 编译层   | 资料如何变成知识？       | 先分析、再生成，避免直接污染正式 Wiki                                         |
| Review Queue 审核层         | 不确定内容如何处理？     | 低置信度、冲突、敏感或重大判断进入审核队列                                    |
| 回忆与检索层                | 用户如何问回自己的记忆？ | 支持 index-first query、关键词检索、中文召回、wikilink 扩展、引用回答         |
| Save to Wiki / File-back 层 | 高价值对话如何沉淀？     | 将对话作为来源保存，并把高价值内容分类编译到 source、concept、entity、domain 或 synthesis 页面 |
| 维护与健康检查层            | 知识库如何长期不腐烂？   | 支持 lint、孤儿页、断链、重复概念、过期内容、知识缺口检查                     |
| 本地 API 层                 | 多入口如何共享能力？     | Mac 客户端、CLI、agent 对话都调用同一套本地 operation API                     |
| Agent 承载层                | MVP 用什么来跑 agent？   | 优先接入 Codex CLI，负责会话推进、工具执行、文档上下文加载与结果产出          |
| Mac 客户端层                | 普通用户如何使用？       | 提供 vault picker、inbox、queue、review、explore、ask、maintenance 等基础界面 |

---

# 2. 个人记忆目标层

这一层定义每个 vault 的长期目标，让 Piki 不只是一个文件夹，而是一个有明确用途的个人记忆系统。

| 功能           | 说明                                                                                  | MVP 价值                                     |
| -------------- | ------------------------------------------------------------------------------------- | -------------------------------------------- |
| `purpose.md` | 每个 vault 都有一个目的文件，描述这个记忆库为什么存在                                 | 让 agent 理解这个 vault 的长期方向           |
| 记忆范围声明   | 记录用户长期关心的领域，例如 AI、产品、投资、心理学、健康、写作、项目、个人原则和决策 | 避免知识库无限扩张，帮助系统判断什么值得记住 |
| 回忆偏好声明   | 描述用户希望系统如何回答，例如结构化、简洁、需要引用、需要反例、需要关联旧经验        | 提高问答结果的一致性                         |
| 维护偏好声明   | 描述哪些内容可以自动写入，哪些内容必须进入 review queue                               | 控制自动化写入边界                           |
| 使用节奏声明   | 记录每日 capture、每周 ingest、每月 synthesis/lint 等推荐节奏                         | 帮助用户形成长期使用习惯                     |

---

# 3. Vault 内核层

Piki 的核心数据结构是一个本地 Markdown vault。它应该让用户随时能打开、阅读、迁移，而不是被锁死在某个 App 里。

## 3.1 Vault 基础结构

| 目录 / 文件       | 作用                                                             |
| ----------------- | ---------------------------------------------------------------- |
| `raw/`          | 原始资料层，只读、不可变，用于保存真实来源                       |
| `raw/inbox/`    | 新资料暂存区，支持待处理网页、Markdown、PDF、笔记、聊天记录等    |
| `raw/sources/`  | 已确认进入知识库的原始来源                                       |
| `raw/assets/`   | 图片、附件、截图、下载资源                                       |
| `wiki/`         | LLM 维护的编译知识层                                             |
| `wiki/index.md` | 知识库索引，query 前优先读取                                     |
| `wiki/log.md`   | append-only 操作日志，记录 ingest、query、file-back、lint 等操作 |
| `AGENTS.md`     | agent 维护协议，定义目录、模板、链接和操作规则                   |

## 3.2 Wiki 编译层结构

| 目录                | 内容类型                           | 示例                                     |
| ------------------- | ---------------------------------- | ---------------------------------------- |
| `wiki/sources/`   | 每个来源对应的结构化 source page   | 某篇文章、某个 PDF、某段聊天记录         |
| `wiki/concepts/`  | 概念、方法、模型、观点、框架       | LLM Wiki、Agent Memory、Product Strategy |
| `wiki/entities/`  | 人物、公司、工具、地点、项目、产品 | OpenAI、Notion、某个项目、某个客户       |
| `wiki/domains/`   | 领域地图和持续演化的领域综述       | AI 产品、投资研究、健康管理              |
| `wiki/synthesis/` | 跨来源综合、比较、判断、回答沉淀   | “我对个人知识库产品的长期判断”         |

---

# 4. Agent 操作层

Agent 操作层解决的问题是：用户不需要理解底层目录结构，也可以自然地让 Piki 完成知识库维护。

MVP 阶段这里不自研完整 agent runtime，而是把 Codex CLI 当作 agent 承载层。Piki 自己的 UI 负责提供更适合知识工作流的可视化外壳，把 CLI 的能力映射成结构化交互。

| 功能               | 说明                                                                                                                           | MVP 要求                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------- |
| 自然语言入口       | 用户可以直接说“把这篇文章收进知识库”“帮我回忆一下某个主题”“做一次健康检查”                                               | 支持常见知识库操作意图       |
| Slash command 入口 | 支持稳定命令，如 `/wiki:ingest`、`/wiki:compile`、`/wiki:query`、`/wiki:file-back`、`/wiki:lint`、`/wiki:research` | 提供更可控、更稳定的操作方式 |
| 意图解析           | 将自然语言映射到明确操作、目标资料、写入范围、风险等级和审核要求                                                               | 避免 agent 自行乱写          |
| 操作确认           | 当存在写入风险或歧义时，展示解析结果和预计影响范围                                                                             | 让用户知道系统将改哪些内容   |
| 操作复用           | CLI、API、Mac 客户端、agent 对话都调用同一套 operation model                                                                   | 避免不同入口行为不一致       |

## 4.1 MVP 中 Codex CLI 的角色

| 能力 | 说明 |
| --- | --- |
| Agent loop | 负责推进对话、读取文档、调用本地工具、执行命令和生成结果 |
| Workspace 执行环境 | 直接面向本地 vault 与项目目录工作 |
| 文档上下文入口 | 优先读取 `AGENTS.md`、`purpose.md`、`wiki/index.md`、产品文档和相关 source |
| 非目标 | 不作为长期产品 API 契约，不要求客户端 1:1 复刻终端体验 |

## 4.2 Mac 客户端如何承载 CLI

| UI 区块 | MVP 要表现什么 |
| --- | --- |
| 会话区 | 消息流、状态、阶段性结论 |
| 操作区 | 当前识别出的 operation、风险等级、是否写入 |
| 文件区 | source、wiki 页面、节目概览、摘要、转写全文预览 |
| 变更区 | diff、待确认写入、review item |
| 任务区 | ingest、转写、维护检查等任务进度 |

## 4.3 MVP Command 示例

| Command             | 作用                                       |
| ------------------- | ------------------------------------------ |
| `/wiki:ingest`    | 将 inbox 或指定 source 加入处理队列        |
| `/wiki:compile`   | 对资料执行 Analyze → Generate 编译流程    |
| `/wiki:query`     | 基于现有 wiki 回答问题                     |
| `/wiki:file-back` | 将高价值对话内容保存并分类编译回 wiki      |
| `/wiki:lint`      | 检查知识库结构和内容健康度                 |
| `/wiki:research`  | 可作为后续扩展能力，MVP 可弱化或半手动支持 |

---

# 5. Capture 与 Ingest 层

这一层负责把资料可靠地放进知识库，但不急着把所有内容都变成长期记忆。

| 功能                 | 说明                                                        | MVP 要求                                                      |
| -------------------- | ----------------------------------------------------------- | ------------------------------------------------------------- |
| 文件导入             | 支持 Markdown、纯文本、PDF                                  | DOCX、PPTX、表格、音频、视频、图片 OCR 可后置                 |
| Inbox capture        | 用户可以快速把资料丢进 `raw/inbox/`                       | 不要求立刻处理                                                |
| Source normalization | 将资料整理为可追踪 source，记录标题、路径、来源、日期、格式 | 方便后续引用和追溯                                            |
| Source hashing       | 为来源计算 hash，资料未变化时跳过重复 ingest                | 避免重复处理                                                  |
| Source change scan   | 打开产品或手动 rescan 时扫描 `raw/sources/` 和 manifest hash | 发现新增、修改、删除或移动的来源                              |
| Update queue         | source 变化后进入待更新队列，而不是直接静默改 wiki          | 保证 wiki 更新可审核、可追踪                                  |
| Ingest queue         | 待处理资料进入队列                                          | 支持 pending、processing、failed、retry、cancelled、completed |
| 错误恢复             | 失败的 ingest 保留原因，并允许重试                          | 不让知识库状态变得不可理解                                    |
| 批量 ingest          | 支持简单批量处理                                            | 默认推荐逐条或小批量 review，避免污染长期记忆                 |

## 5.1 Ingest 状态流

| 状态       | 含义                   |
| ---------- | ---------------------- |
| pending    | 已进入队列，尚未处理   |
| processing | 正在处理               |
| failed     | 处理失败，保留失败原因 |
| retry      | 等待重新处理           |
| cancelled  | 用户取消处理           |
| completed  | 已处理完成             |

## 5.2 Source 变更检测

Piki 应维护 source manifest，记录每个 source 的路径、hash、大小、mtime、ingest 状态和对应 wiki source page。

| 变更类型 | 处理方式 |
| -------- | -------- |
| 新增 source | 加入 ingest queue |
| 内容 hash 变化 | 加入 update queue，触发 Analyze -> Review -> Generate |
| 路径变化但 hash 相同 | 更新 manifest 和 source page 路径引用 |
| source 删除 | 标记 missing，进入 review queue，不自动删除 wiki |
| source 未变化 | 跳过处理 |

产品打开时可以做一次轻量 scan；大型 vault 可改为后台 scan 或手动 rescan。扫描只负责发现变化和入队，不应直接静默重写 wiki。

---

# 6. Analyze → Generate 两阶段编译层

Piki 的写入不应该是“LLM 读完资料后直接改 Wiki”。MVP 应采用两阶段流程，降低错误写入和污染长期记忆的风险。

## 6.1 两阶段流程

| 阶段     | 作用                                              | 是否直接写入正式 Wiki |
| -------- | ------------------------------------------------- | --------------------- |
| Analyze  | 分析来源，提取结构化候选信息                      | 否                    |
| Generate | 在用户确认或规则允许后，生成 / 更新正式 Wiki 页面 | 是                    |

## 6.2 Analyze 阶段输出

| 输出项       | 说明                                                               |
| ------------ | ------------------------------------------------------------------ |
| 摘要         | 来源内容的核心概括                                                 |
| 实体         | 人物、公司、工具、地点、项目、产品等                               |
| 概念         | 方法、模型、观点、框架等                                           |
| 主张         | 来源中明确提出的判断或结论                                         |
| 证据         | 支撑主张的材料                                                     |
| 冲突         | 与已有 Wiki 不一致的内容                                           |
| 低置信度内容 | agent 不确定、不应直接写死的信息                                   |
| 候选链接     | 建议关联到哪些已有页面                                             |
| 建议更新页面 | 建议创建或修改哪些 source、concept、entity、domain、synthesis 页面 |

## 6.3 Generate 阶段写入范围

| 写入对象       | 说明                                         |
| -------------- | -------------------------------------------- |
| Source page    | 为每个来源生成 `wiki/sources/*`            |
| Concept page   | 将新知识编译到相关概念页                     |
| Entity page    | 更新人物、公司、工具、项目等实体页           |
| Domain page    | 更新领域地图和领域综述                       |
| Synthesis page | 当新来源改变跨来源理解时，创建或更新综合判断 |
| Index          | 更新 `wiki/index.md`                       |
| Log            | 追加 `wiki/log.md`                         |

## 6.4 写入前预览

| 功能         | 说明                               |
| ------------ | ---------------------------------- |
| Diff preview | 正式写入前尽量展示文件 diff        |
| 变更摘要     | 展示将新增、修改、关联哪些页面     |
| 风险提示     | 标记低置信度、冲突、敏感或重大判断 |

---

# 7. Review Queue 审核层

Review Queue 是 Piki MVP 的关键能力。它保证 Piki 不是一个“自动污染长期记忆”的系统。

| 功能           | 说明                                                           |
| -------------- | -------------------------------------------------------------- |
| 不确定内容入队 | 低置信度、冲突、价值判断、敏感个人记忆、重大结论不直接写入     |
| 审核动作       | 用户可以 approve、reject、edit、defer                          |
| 冲突处理       | 新来源挑战旧结论时，保留冲突标记，而不是静默覆盖               |
| 过期处理       | 对需要未来复查的内容设置 `review_after`                      |
| 人类判断保留   | review 决策写入 log，让后续 agent 理解为什么接受或拒绝某条信息 |

## 7.1 Review Queue 典型内容

| 类型         | 示例                           | 默认处理                |
| ------------ | ------------------------------ | ----------------------- |
| 低置信度内容 | 来源表达模糊、agent 推断较多   | 进入 review             |
| 冲突内容     | 新资料和旧结论不一致           | 进入 review，并保留冲突 |
| 敏感个人记忆 | 健康、财务、情绪、重大人生决策 | 进入 review             |
| 重大判断     | 投资判断、职业判断、长期原则   | 进入 review             |
| 普通事实整理 | 标题、摘要、基础实体、来源路径 | 可按规则自动写入        |

---

# 8. 回忆与检索层

Piki 的 query 不是只做向量检索，而是优先利用已经编译好的 Wiki 结构进行回忆。

| 功能                   | 说明                                                   | MVP 要求                |
| ---------------------- | ------------------------------------------------------ | ----------------------- |
| Index-first query      | 回答前先读取 `wiki/index.md`                         | 作为默认 query 策略     |
| Keyword search         | 支持关键词检索                                         | 必需                    |
| 中文友好检索           | 至少支持 CJK bigram 或类似策略                         | 避免中文内容难以召回    |
| Wikilink recall        | 利用 Wiki 内部链接扩展相关页面                         | 必需                    |
| Source overlap recall  | 多个页面引用相同 source 时，将其作为相关性信号         | 建议支持                |
| Graph neighbor recall  | 通过概念、实体、领域相邻页面帮助回忆                   | 建议支持                |
| Optional vector search | 向量检索可作为增强能力                                 | 不作为 MVP 唯一召回方式 |
| Citation               | 回答必须引用使用过的 Wiki 页面，必要时引用 source page | 必需                    |
| Recall modes           | 支持快速回答、深入回答、列出相关页面                   | 必需                    |

## 8.1 Recall Modes

| 模式         | 适用场景               | 输出特点                                                 |
| ------------ | ---------------------- | -------------------------------------------------------- |
| 快速回答     | 用户想快速回忆一个问题 | 简洁、直接、带关键引用                                   |
| 深入回答     | 用户想做系统整理或决策 | 更完整，包含背景、关联页面、证据和不确定性               |
| 列出相关页面 | 用户想浏览知识库       | 返回相关 source、concept、entity、domain、synthesis 页面 |

---

# 9. Save to Wiki / File-back 层

Save to Wiki 是 Piki 的核心功能，不是附属按钮。它让“回忆结果”反过来增强“记住”。对 LLM Wiki 来说，对话本身首先是一种 source；对话中抽取出的长期结论、比较、决策和洞察，才根据内容类型进入 concept、entity、domain 或 synthesis。

| 功能           | 说明                                                                 |
| -------------- | -------------------------------------------------------------------- |
| 保存对话来源   | 将有长期价值的对话片段保存为 conversation source，保留问题、回答、时间和上下文 |
| 分类编译内容   | 根据内容性质更新 source、concept、entity、domain，必要时创建 synthesis |
| 记录原始问题   | 保留用户当时问了什么，避免结论脱离上下文                             |
| 记录答案与证据 | 保存回答内容、引用页面、关键依据                                     |
| 记录影响       | 标记这个回答对用户后续理解或决策的影响                               |
| 记录后续问题   | 沉淀未来值得继续探索的问题                                           |
| 更新索引与日志 | 保存后更新 `wiki/index.md` 和 `wiki/log.md`                         |
| 建立关联链接   | 与相关 source、concept、entity、domain、synthesis 建立链接           |
| 支持未来召回   | 保存后的 conversation source 和编译结果都应成为未来 query 的可检索记忆 |

## 9.1 File-back 内容建议结构

| 字段                | 说明                                      |
| ------------------- | ----------------------------------------- |
| Conversation Source | 对话片段的来源、时间和上下文              |
| Original Question   | 用户原始问题                              |
| Answer              | 当时沉淀的回答                            |
| Content Type        | source、concept、entity、domain、synthesis |
| Evidence            | 使用过的 wiki/source 页面                 |
| Impact              | 对用户理解、判断或决策的影响              |
| Related Pages       | 相关 source/concept/entity/domain/synthesis |
| Follow-up Questions | 后续值得继续追问的问题                    |
| Review Status       | 是否需要未来复审                          |

---

# 10. 维护与健康检查层

长期知识库会自然腐烂：断链、重复概念、过期结论、孤儿页、低质量页面都会逐渐出现。MVP 需要提供基础维护能力。

| 功能                  | 说明                                                                    |
| --------------------- | ----------------------------------------------------------------------- |
| Lint                  | 检查 frontmatter、断链、孤儿页、重复概念、缺失索引、模板缺失            |
| Librarian review      | 检查内容层质量，包括过时结论、薄弱页面、低连接页面、需要合并的概念      |
| Knowledge gaps        | 识别高频出现但没有页面的概念，或用户关心但资料不足的领域                |
| Stale scan            | 根据 `review_after`和来源时间检查需要复审的内容                       |
| Maintenance dashboard | 在 Mac 客户端展示待处理问题、review queue、ingest queue、孤儿页和过期页 |

## 10.1 健康检查对象

| 检查对象 | 典型问题                                 |
| -------- | ---------------------------------------- |
| 结构     | 目录缺失、模板缺失、frontmatter 不规范   |
| 链接     | 断链、孤儿页、低连接页面                 |
| 内容     | 页面太薄、重复概念、过期结论、冲突未处理 |
| 队列     | ingest 失败、review 堆积、长期 defer     |
| 索引     | index 未更新、页面无法被正常召回         |

---

# 11. 本地 API 层

本地 API 应尽早出现。它的目的不是做云服务，而是让 Mac 客户端、CLI、外部 agent 能共享同一套能力。

## 11.1 API 设计原则

| 原则     | 说明                                             |
| -------- | ------------------------------------------------ |
| 本地优先 | API 面向本地 vault，不依赖云端账户系统           |
| 受控写入 | 写操作必须通过 operation，不提供任意覆盖文件 API |
| 可追踪   | 所有重要写入都要进入 log                         |
| 可预览   | 重要写入前生成 diff preview                      |
| 可回滚   | 重要写入前支持 git checkpoint 或类似机制         |
| 可复用   | Mac、CLI、agent 对话调用同一套 API               |

## 11.2 Read API

| API 类型     | 能力                        |
| ------------ | --------------------------- |
| health       | 查看 vault 健康状态         |
| vault info   | 获取 vault 基础信息         |
| page list    | 获取页面列表                |
| page read    | 读取指定页面                |
| search       | 执行关键词 / Wiki 检索      |
| graph        | 获取页面链接关系            |
| queue status | 查看 ingest/review 队列状态 |
| log          | 查看操作日志                |

## 11.3 Write API

| API 类型      | 能力                                          |
| ------------- | --------------------------------------------- |
| ingest        | 将资料加入 ingest 流程                        |
| compile       | 执行 Analyze → Generate                      |
| file-back     | 保存高价值对话内容并分类编译到 Wiki           |
| lint-fix      | 对部分 lint 问题执行修复                      |
| review action | approve、reject、edit、defer                  |
| checkpoint    | 重要写入前创建 git checkpoint 或 diff preview |

## 11.4 长任务进度

| 功能               | 说明                                           |
| ------------------ | ---------------------------------------------- |
| Streaming progress | ingest、compile、research 等长任务需要返回进度 |
| Task status        | 客户端可展示当前处理阶段、失败原因和下一步动作 |
| Retry support      | 失败任务可重试，不需要用户重新导入资料         |

---

# 12. Mac 客户端层

Mac 客户端不是唯一入口，但它是 MVP 中让普通用户理解和操作 Piki 的主要界面。

## 12.1 核心页面

| 页面         | 作用                                                     |
| ------------ | -------------------------------------------------------- |
| Vault Picker | 选择或创建本地 `piki-vault`                            |
| Inbox        | 查看待处理资料，添加文件或文本                           |
| Ingest Queue | 展示处理状态、失败原因、重试入口                         |
| Review Queue | 展示 agent 不确定内容，支持 approve/reject/edit/defer    |
| Explore      | 按 source、concept、entity、domain、synthesis 浏览知识库 |
| Ask          | 面向知识库提问，答案带引用                               |
| Save to Wiki | 把有价值对话保存为 source，并将结论分类编译进 wiki        |
| Maintenance  | 查看 lint、孤儿页、过期页、知识缺口                      |

## 12.2 建议布局

| 区域 | 内容                                                            |
| ---- | --------------------------------------------------------------- |
| 左侧 | 知识树、source/concept/entity/domain/synthesis 分类、queue 入口 |
| 中间 | 对话、命令、任务状态、问答结果                                  |
| 右侧 | 页面预览、引用来源、diff preview、关联页面                      |

---

# 13. MVP 不做什么

为了保持 MVP 聚焦，以下能力暂不作为第一阶段目标。

| 不做                            | 原因                                              |
| ------------------------------- | ------------------------------------------------- |
| 不做账户系统                    | Piki 是本地优先产品，MVP 不需要账户体系           |
| 不做云同步                      | 避免过早引入权限、冲突合并、数据安全复杂度        |
| 不做多人协作                    | MVP 面向个人记忆库                                |
| 不做移动端                      | 先跑通 Mac 本地交互和 vault 内核                  |
| 不把向量数据库作为必需内核      | Wiki 结构、索引、链接、关键词检索应先成立         |
| 不一开始支持所有复杂文件格式    | MVP 先支持 Markdown、文本、PDF                    |
| 不做全自动无审核 ingest         | 避免污染长期记忆                                  |
| 不把 Mac 客户端变成唯一数据入口 | Markdown vault 仍然是真相，用户可以直接打开和迁移 |

---

# 14. MVP 成功标准

| 成功标准                 | 判断方式                                                                |
| ------------------------ | ----------------------------------------------------------------------- |
| 资料能可靠进入知识库     | 用户可以把资料放进 inbox，并编译成 wiki 页面                            |
| Wiki 可读、可追溯        | 用户可以直接打开 Markdown vault 阅读 source、concept、domain、synthesis |
| 能回答已有记忆           | 用户提问时，系统能从已有 wiki 中回忆并引用依据                          |
| 高价值对话能沉淀         | 用户可以把有价值对话保存回 wiki，并将结论编译成可召回记忆               |
| 不确定内容不会污染知识库 | 低置信度、冲突、敏感或重大判断会进入 review queue                       |
| 中文资料可基本召回       | 中文内容能通过关键词 / CJK 友好策略被检索到                             |
| 操作可追踪               | 重要 ingest、compile、file-back、lint 都有 log                          |
| 不依赖单一客户端         | 用户即使不用 Mac 客户端，也能直接打开 Markdown vault 阅读和迁移数据     |

---

# 15. MVP 优先级建议

## P0：必须跑通的核心闭环

| 模块             | 能力                                                         |
| ---------------- | ------------------------------------------------------------ |
| Vault 内核       | raw/wiki 结构、index、log、AGENTS.md                         |
| Capture/Ingest   | inbox、Markdown/文本/PDF、source normalization、ingest queue |
| Analyze/Generate | 两阶段编译、source/concept/domain/index/log 更新             |
| Query            | index-first、关键词检索、中文召回、引用回答                  |
| Review Queue     | approve/reject/edit/defer，冲突和低置信度入队                |
| File-back        | 将高价值对话保存为 source，并按类型更新 wiki                 |
| Mac 基础界面     | Vault picker、Inbox、Ask、Review、Explore                    |
| 本地 API         | 基础 read/write operation                                    |

## P1：MVP 中后段增强

| 模块                  | 能力                                            |
| --------------------- | ----------------------------------------------- |
| Graph recall          | wikilink、source overlap、graph neighbor recall |
| Maintenance           | lint、孤儿页、断链、重复概念、知识缺口          |
| Diff preview          | 写入前展示变更摘要和文件 diff                   |
| Git checkpoint        | 重要写入前创建 checkpoint                       |
| Librarian review      | 检查薄弱页面、过期结论、低连接页面              |
| Maintenance dashboard | 展示 review queue、ingest queue、孤儿页、过期页 |

## P2：后续版本再做

| 模块                     | 能力                                   |
| ------------------------ | -------------------------------------- |
| 云同步                   | 多设备同步、冲突合并                   |
| 多人协作                 | 权限、共享、协同编辑                   |
| 移动端                   | iOS/Android capture 和轻量回忆         |
| 多模态扩展               | 图片 OCR、音频、视频、PPTX、DOCX、表格 |
| 高级 research automation | 自动研究、跨来源深度调研、定期报告     |
| 向量数据库增强           | 作为召回增强，而不是替代 Wiki 内核     |

---

# 16. 一句话总结

Piki MVP 要先证明一个核心闭环：

> 用户可以把资料放进本地 vault，Piki 将其编译成可读、可追溯、可审核的 Wiki；用户之后可以自然提问、获得带引用的回忆，并把高价值对话内容继续保存回 Wiki，让个人记忆系统持续增长。
>
