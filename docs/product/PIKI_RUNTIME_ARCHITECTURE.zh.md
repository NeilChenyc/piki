# Piki 运行时架构总览

## 1. 目标

Piki 的当前目标架构是：

```text
SwiftUI App -> HTTP+SSE (localhost:8782) -> FastAPI/uvicorn -> Claude Agent SDK -> Claude built-in tools
```

核心原则：

- App 负责 UI、状态和交互
- Python Agent Service 通过 HTTP+SSE 提供所有后端能力
- App 自动管理 uvicorn 进程生命周期
- 标准 HTTP 协议，可用 curl 直接调试

## 2. 组件划分

### 2.1 SwiftUI App

位置：`PikiApp/PikiApp/`

职责：
- 渲染 Home / Inbox / Health / Settings / Wiki
- 维护 `AppState`
- 通过 `RuntimeServiceProtocol` → `HTTPRuntimeService` 调用后端
- 通过 `SSEClient` 接收实时任务事件流
- 通过 `LocalServiceManager` 管理 uvicorn 子进程

### 2.2 Python Agent Service

位置：`agent_service/`

职责：
- FastAPI HTTP 端点（tasks, health, journal, ingest, lint）
- 任务执行与 Claude Agent SDK 调用
- SQLite 状态持久化
- SSE 事件流推送
- Journal / rollback / ingest queue / lint
