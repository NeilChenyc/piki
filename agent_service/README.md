# Piki Agent Service

`agent_service/` 是 Piki 的 Python 后端服务，通过 HTTP + SSE 与 macOS 客户端通信。

## 架构

```text
SwiftUI App (HTTPRuntimeService)
    │
    ├─ HTTP REST  → POST /tasks, GET /health, PUT /runtime/config ...
    └─ SSE stream → GET /tasks/{id}/events
    │
    ▼
uvicorn (agent_service.app:app) on 127.0.0.1:8782
    │
    ├─ FastAPI routes (api/routes/)
    ├─ TaskService → TaskExecutor → PikiWikiAgentRunner
    └─ Claude Agent SDK → Anthropic API
```

macOS 客户端通过 `LocalServiceManager` 自动启动 uvicorn 子进程并管理其生命周期。

## 目录职责

| 目录 | 说明 |
| --- | --- |
| `api/routes/` | FastAPI HTTP 端点（tasks, health, journal, ingest, lint）|
| `application/` | 任务执行、事件发布、系统动作协调 |
| `config.py` | 服务配置、环境变量与运行时开关 |
| `models/` | Pydantic 数据模型和枚举 |
| `runtime/` | Claude Agent runner、CLI 工具 |
| `store/` | SQLite 持久化（任务、事件、journal、queue）|
| `vault/` | vault 路径校验和安全读写封装 |
| `workflows/` | 确定性系统工作流（ingest、lint、rollback）|

## 开发运行

```bash
cd /path/to/piki
python -m uvicorn agent_service.app:app --host 127.0.0.1 --port 8782 --reload
```

验证服务状态：

```bash
curl http://127.0.0.1:8782/health
```

## 开发者分发

当前默认分发方式是面向开发者的 GitHub Release ZIP：

- 维护者运行 `./scripts/build_macos_dev_release.sh`
- 产出 `Piki.app.zip` 与 `SHA256SUMS`
- 开发者运行 `./scripts/install_piki_dev_release.sh --version <tag>` 安装

`.app` bundle 内会包含 Python runtime、依赖与 `agent_service`。`LocalServiceManager` 会优先选择 Bundle 内 Python，并在首次启动时准备 `~/.piki` 目录。
