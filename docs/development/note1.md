
我们目前比较乱 我们先来理清几个点 你最简的回答我们几个点就行

1. 这个openai agents 是本地的能力包对吧 我只要配置好key和端点 服务就仅限于我们系统和端点的api侧对吧 而且我澄清下这个端点是可以response接口的https://timicc.cc/tutorial#codex
2. 我们提到的对llm vault的 “操作”  按照现有的计划和推荐的实现 是不是部分几个封装为tools 供agent调用，部分几个agent 只需按照agent.md自主调用基础工具（读写工具）就能实现，你整理个list
3. 目前agent层的实现 是基于 **AGENT_RUNTIME_DESIGN.zh.md**  openai agents sdk的部分必须实现 还是降级的备选？根据这里的设计要求 对应的实现gap和todo是什么


**1. 是，本地能力包**
`openai-agents` 是本地 Python SDK。它本身跑在我们的本地 `agent_service` 里。

配置好：

```env
OPENAI_API_KEY=...
OPENAI_BASE_URL=https://timicc.cc/...
PIKI_AGENT_MODEL=...
```

之后链路就是：

```text
Piki 本地服务 -> OpenAI Agents SDK -> timicc.cc 这个兼容端点
```

不会自动接入别的服务。但注意：模型输入、工具结果、上下文内容会发给这个端点，所以 vault 里被 agent 读进上下文的内容会经过 API。

如果 `timicc.cc` 支持 Responses API，那 Agents SDK 更匹配；我们需要确认 base URL 是不是 `/v1` 结尾，以及模型名怎么填。

2. **LLM vault 操作怎么拆**

建议明确分三类：

**A. 封装成 tools 给 agent 调用**

```text
read_file
list_files
search_text
parse_markdown
read_source
search_related_wiki
propose_patch
queue_review_item
```

这些是 agent 分析和生成 proposal 必须用的基础能力。

**B. 不给 agent 直接调用，由 Piki 系统代码执行**

```text
apply_patch
write_file
delete_file
update_index
append_log
update_source_manifest
copy_uploaded_file
normalize_source_file
```

原因：这些会真实改文件或改变 vault 状态，应该由 Piki 在 approval / policy 后执行。

**C. agent 按 AGENTS.md 自主完成，但底层仍用 tools**

```text
ingest source
query wiki
lint wiki
detect conflicts
extract entities/concepts/claims
suggest synthesis
```

这些不是单个 tool，而是 agent workflow。agent 读 `AGENTS.md` 后，通过 A 类 tools 读取/分析，通过 `propose_patch` 提交结果。

3. **Agents SDK 是主实现，不是备选**

按 [AGENT_RUNTIME_DESIGN.zh.md](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/docs/product/AGENT_RUNTIME_DESIGN.zh.md) 的设计，OpenAI Agents SDK 是 agent runtime 的主路径，不是降级备选。

现在实际状态：

```text
已完成：
- SDK 已安装
- runner scaffold 有了
- /health 能识别 SDK available
- query / capture 已用 Piki 本地 pipeline 实现

未完成 gap：
- 没有配置 OPENAI_BASE_URL / model 到 runner
- 没有 Runner.run / Runner.run_streamed
- 没有 SDK function_tool
- 没有 SDK streaming event -> Piki event 映射
- 没有 SDK session 接 SQLite
- 没有 SDK output_type 结构化输出
- 没有 SDK human-in-the-loop 和 Piki approval 打通
- 没有 tracing 策略
```

下一步 todo 最小闭环：

```text
1. 配好 timicc.cc endpoint + model
2. 做 Runner.run smoke test
3. 把 read/list/search/parse/propose_patch 注册成 SDK tools
4. 让 ingest proposal 通过 SDK agent 跑
5. 把 SDK events 映射到 Piki task events
```

一句话：**现在是 Piki service 已成型，SDK 已装好但还没真正成为 agent loop；下一步要把阶段 4 ingest proposal 作为第一个 SDK 驱动 workflow。**
