# Piki 个人记忆库目的

## 这个 vault 为什么存在

这个 vault 用来验证和承载 Piki 的核心产品假设：个人知识库不应该只是资料堆放处，而应该是一个由 agent 持续维护、可回忆、可追溯、可审核的本地 Markdown 维基。

它首先服务 Piki 项目自身的 dogfooding：记录产品判断、技术路线、agent 设计、开发过程、播客和长文资料的摄入结果，以及围绕这些材料形成的长期理解。

## 记忆范围

优先记住这些内容：

- Piki 的产品定位、MVP 范围、路线图和关键取舍。
- LLM Wiki、个人记忆系统、agent runtime、review queue 等核心概念。
- 与 Piki 设计相关的重要来源、播客、文章、对话和开发记录。
- 用户明确认为未来还会复用的判断、框架、问题和结论。
- 对既有理解产生挑战的新来源、冲突和不确定内容。

暂时不主动扩张到这些内容：

- 与 Piki 无关的日常杂项。
- 没有长期复用价值的临时聊天。
- 未经用户确认的敏感个人信息。
- 纯工具缓存、构建产物和可重新生成的中间文件。

## 回忆偏好

回答知识库问题时，优先做到：

- 先读 `wiki/index.md`，再搜索相关 wiki 页面。
- 尽量从已编译 wiki 页面回答，而不是每次重读所有 raw source。
- 给出引用，说明依据来自哪些 wiki 页面或 source page。
- 对不确定、冲突或过期内容明确标注，不把它们包装成确定事实。
- 用中文回答，必要的产品名、路径、命令和代码标识可以保留英文。

## 维护偏好

维护这个 vault 时，agent 应该：

- 对主张保守，对链接慷慨。
- 保留 raw source 不可变，除非用户明确要求修改。
- 高风险写入先生成 diff proposal，再等待用户确认。
- 低置信度、冲突、敏感或重大判断进入 review queue。
- 每次重要 ingest、query、lint 或结构调整都追加 `wiki/log.md`。
- 有意义的 wiki 变更后同步维护 `wiki/index.md`。

## 使用节奏

推荐节奏：

- 新资料先进入 `raw/inbox/`。
- 每次只处理一个或少量 source，优先保证质量。
- 每周至少做一次 `lint`，检查断链、孤立页、重复概念、过期内容和索引问题。
- 重要设计讨论优先沉淀为明确的 source、synthesis 或产品文档更新，不使用独立保存流程。
- 阶段性路线变化要同步到产品文档和 wiki synthesis。

## 当前阶段

当前 vault 处于 MVP 阶段 0：Vault 协议与 Golden Vault。

阶段 0 的目标是保证 vault 协议足够清晰，后续本地 Agent Service 可以稳定读取 `AGENTS.md`、`purpose.md` 和 `wiki/index.md`，并用现有 seed 页面验证 `query`、`ingest proposal` 和 `lint` 的最小闭环。
