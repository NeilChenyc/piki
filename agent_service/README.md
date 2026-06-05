# Agent Service 目录说明

`agent_service/` 是 Piki 的本地 Agent Service，负责接收任务、装配 vault 上下文、执行 source intake、ingest queue、lint、只读 query fallback 和后续 SDK agent workflow，并把状态、事件、对话级 journal entry 和回退记录持久化。

## 顶层文件

| 路径 | 说明 |
| --- | --- |
| `__init__.py` | Python package 标记文件。 |
| `app.py` | FastAPI 应用入口，定义 task、event、ingest queue、lint、rollback、health 等本地 API。 |
| `config.py` | 服务配置与 `.env` 加载逻辑，例如数据库路径、OpenAI key、OpenAI-compatible endpoint、model 和 SDK runtime 状态。 |
| `README.md` | 本目录结构和职责说明。 |

## 子目录

| 目录 | 说明 |
| --- | --- |
| `context/` | 负责为任务装配基础上下文，例如 `AGENTS.md`、`purpose.md`、`wiki/index.md`。 |
| `models/` | 放 Pydantic 数据模型和枚举，包括 task、event、query、source intake、ingest queue、lint、journal entry、rollback。 |
| `workflows/` | 放本地确定性 workflow，例如只读 query fallback、source intake、ingest queue、lint、journal rollback 和 source rescan。 |
| `runtime/` | 放 OpenAI Agents SDK runner 相关封装，后续承载 `PikiWikiAgent` 的真实 agent loop。 |
| `store/` | 放持久化实现，目前是 SQLite task/event/session 存储，后续扩展 journal entry。 |
| `tools/` | 放可暴露给 agent 的受控工具，例如 vault 读取、搜索、Markdown 解析、写入和回退。 |
| `vault/` | 放 vault 路径安全、读写、复制等底层访问封装。 |

## 关键文件

| 路径 | 说明 |
| --- | --- |
| `context/assembler.py` | 加载任务默认上下文，并记录哪些文件被加载或跳过。 |
| `models/core.py` | 定义核心 API 和运行时数据结构，包括 task/event、source manifest、ingest queue、update queue、lint、journal/rollback。 |
| `workflows/query.py` | 本地只读 query fallback，负责中文友好检索、wikilink 扩展和引用输出。 |
| `workflows/ingest.py` | 单 source ingest workflow helper，负责识别显式 ingest hint、校验 canonical source、生成 ingest prompt 和规范化 `IngestResult`。 |
| `workflows/source_intake.py` | 单文件 source intake workflow，负责 MD/TXT/PDF/DOCX 到 `raw/sources/*.md` 的规范化。 |
| `workflows/ingest_queue.py` | Ingest queue workflow，负责批量文件入队、同步小批处理、失败记录、重试和取消。 |
| `workflows/lint.py` | 确定性 lint workflow，负责 frontmatter、断链、孤儿页、重复标题、索引缺失、过期和知识缺口检查，并支持低风险修复。 |
| `workflows/rollback.py` | 根据最近两条 active journal entry 做 hash 校验回退，任一文件不匹配则整次失败。 |
| `workflows/source_scan.py` | 扫描 `raw/sources/*.md`，更新 `system/source_manifest.json` 并为新增、修改、缺失 source 创建 update queue item。 |
| `runtime/runner.py` | OpenAI Agents SDK runner、smoke test、动态 instructions 和 function tool 注册入口。 |
| `store/sqlite.py` | SQLite schema 初始化和 task/event/session/journal/ingest queue/update queue 的读写方法。 |
| `tools/vault_tools.py` | 面向 agent 的 vault-safe 工具集合，当前包含读文件、列文件、搜索和解析；后续加入直接写入和对话级 journal entry。 |
| `vault/access.py` | vault-relative 路径校验、敏感文件阻断、文本读写和文件复制。 |

## 当前边界

- 开发期可以从仓库根目录手动启动本地服务：

  ```bash
  uvicorn agent_service.app:app --host 127.0.0.1 --port 8000
  ```

- Mac 客户端默认连接 `http://127.0.0.1:8000` 或 `http://localhost:8000`，通过 `/health` 判断服务状态，通过 `POST /tasks` 创建任务，并通过 `/tasks/{task_id}/events` 订阅 SSE。
- 产品 MVP 约定由 Mac App 拉起 App bundle 内的 `agent-service/piki-agent-service` 可执行文件，参数固定为 `--host 127.0.0.1 --port 8000`；App 退出时只停止自己拉起的服务。
- 带 `selected_paths` 的任务进入 source intake；显式 `/wiki:ingest`、`/wiki:compile` 或 `raw/sources/*.md` 路径进入 SDK-backed 单 source ingest；其他纯自然语言任务进入统一 agent 入口，未配置 SDK runtime 时由本地只读 query fallback 执行。
- OpenAI Agents SDK runtime 已可在 `PIKI_ENABLE_SDK_RUNTIME=1`、`OPENAI_API_KEY`、`PIKI_AGENT_MODEL` 配齐后执行真实 `Runner.run_sync`；endpoint 优先读取 `OPENAI_BASE_URL`，并兼容 `OPENAI_API_BASE`、`OPENAI_API_BASE_URL`；未配置时保留本地只读 query fallback。
- 最新产品规则要求：vault 内除 `AGENTS.md` 外可由 agent 直接读写；vault 外绝不开放写入；只有真实修改 `raw/` 或 `wiki/` 的对话才进入 change journal，并通过最近两条 journal entry 回退兜底。旧 approval/proposal 兼容接口仍保留，但新 SDK 写入路径不依赖写入前审批。
- Rollback API 当前为 `GET /journal/recent` 和 `POST /journal/{journal_entry_id}/rollback`；回退由 Piki 系统代码执行并记录 task event，不通过 LLM 工具推理。
- Source update scan 当前为 `POST /sources/rescan` 和 `GET /update-queue`；阶段 7 只负责发现变化和入队，不自动批量 ingest 或静默改写 wiki。
- Ingest queue API 当前为 `POST /ingest-queue/enqueue`、`GET /ingest-queue`、`POST /ingest-queue/process`、`POST /ingest-queue/{id}/retry`、`POST /ingest-queue/{id}/cancel`；处理方式是显式同步小批量执行，不启动后台 worker。
- Lint API 当前为 `POST /lint` 和 `POST /lint/fix`；MVP 先做确定性结构检查和低风险 index/log 修复，SDK 辅助总结可后续增强。
