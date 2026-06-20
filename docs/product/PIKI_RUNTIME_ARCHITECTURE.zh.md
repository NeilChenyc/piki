# Piki 运行时架构总览

## 1. 目标

Piki 的当前目标架构是：

```text
SwiftUI App -> PikiRuntimeHost -> internal Python worker -> Claude Agent SDK -> Claude built-in tools
```

这里的核心原则很简单：

- App 负责 UI、状态和交互
- Runtime Host 负责生命周期、恢复、连接和进程托管
- Python worker 负责任务、journal、rollback、lint、ingest 和 Claude runtime
- 不再把 localhost HTTP/SSE 作为产品真相

## 2. 组件划分

### 2.1 SwiftUI App

位置：
- `PikiApp/PikiApp/`

职责：
- 渲染 Home / Inbox / Health / Settings / Wiki
- 维护 `AppState`
- 调用 `RuntimeServiceProtocol`
- 把任务与运行时状态渲染成用户可见界面

### 2.2 PikiRuntimeHost

位置：
- `PikiApp/PikiRuntimeHost/main.swift`

职责：
- 作为 app bundle 内的 native runtime host
- 启动并守住 Python worker
- 负责 host 退出时一起停止 worker
- 把 worker 的 JSON-RPC 风格请求/响应桥接给 Swift 侧
- 管理运行时资源目录
- 接收 worker 的事件 notification，并驱动 Swift 侧的 task event 拉取

### 2.3 internal Python worker

位置：
- `agent_service/runtime/worker.py`
- `agent_service/runtime/cli.py`

职责：
- 维护 SQLite 状态
- 执行 task create/input/cancel
- 生成 task events
- 提供 journal / rollback / ingest queue / lint
- 调用 Claude Agent SDK runner
- 作为 deterministic runtime core

### 2.4 私有 Python runtime bundle

位置：
- `PikiApp/.build/runtime-bundle/`

内容：
- standalone Python interpreter
- `site-packages`
- worker entrypoint
- `runtime-paths.json`

这部分由 app build 时自动生成，目的是让 `build -> run` 不依赖系统 Python。

## 3. 数据流

### 3.1 启动

1. 用户 build 或运行 App
2. Xcode build step 生成 runtime bundle
3. App 启动后定位 `PikiRuntimeHost`
4. Host 启动 bundle 内 Python worker
5. App 通过 `RuntimeServiceProtocol` 发起 health/config/task 请求

### 3.2 任务执行

1. UI 创建 task
2. Host 转发到 worker
3. Worker 进入 task service / executor
4. Worker 写入 SQLite 并生成事件
5. App 通过 `taskEvents(taskId:)` 拉取增量事件
6. UI 更新消息流、工具状态和输入提示

### 3.3 输入恢复

当任务进入 `AskUserQuestion` 或输入暂停：

1. Worker 把 task 标成 `input_required`
2. App 显示输入提示
3. 用户提交 input
4. Worker 恢复同一任务继续执行

## 4. 事件桥

现在的事件桥是：

- worker 侧按 `created_at + id` 提供增量事件 envelope
- host 侧维护 per-task cursor
- worker 侧在事件入库后会主动通知 host
- 空闲时 host 仍保留长轮询与 cursor 回放作为兜底

这比一次次全量扫 SQLite 更接近成熟 macOS app 的常见做法，也保留了后续替换成 XPC/push bridge 的空间。

## 5. 持久化

SQLite 仍然是 worker 的核心状态存储：

- tasks
- task_events
- approvals
- sessions
- journal_entries
- update_queue
- ingest_queue

这些表和当前业务逻辑都保留，迁移重点在托管层，不在业务数据模型本身。

## 6. 安全边界

- `AGENTS.md` 只读
- vault 外禁止写入
- `Bash` 只用于 deterministic helper
- runtime 私有目录和数据库由 worker 自己管理
- app 退出时，活跃任务一起结束

## 7. 现在已经落地的东西

- Swift app 不再直接依赖 localhost HTTP 作为主路径
- native host 已经接上 internal worker
- worker 仍然复用现有 task/journal/rollback/lint/ingest 逻辑
- app build 会生成私有 runtime bundle
- 产品文案和架构文档已经切到 runtime host 语义
- 事件桥已经从纯轮询推进到 notification + cursor 回放的混合模式

## 8. 当前实现的文件映射

### Swift 侧

- `PikiApp/PikiApp/Core/Runtime/RuntimeServiceProtocol.swift`
- `PikiApp/PikiApp/Core/Runtime/NativeRuntimeService.swift`
- `PikiApp/PikiApp/Core/Runtime/RuntimeHostConnection.swift`
- `PikiApp/PikiApp/Core/LocalServiceManager.swift`
- `PikiApp/PikiRuntimeHost/main.swift`

### Python 侧

- `agent_service/runtime/worker.py`
- `agent_service/runtime/cli.py`
- `agent_service/application/events.py`
- `agent_service/application/event_stream.py`

### Build 侧

- `PikiApp/project.yml`
- `scripts/build_runtime_bundle.py`

## 9. 仍可继续演进的方向

- 用 XPC service 替代 executable proxy
- 把长轮询事件桥替换成更直接的 push 通道
- 把 worker 打包链路进一步收紧成正式签名产物
- 逐步把少数 deterministic helper 下沉到更清晰的独立模块

当前版本已经满足“成熟但不过度堆叠”的原则：主 App、native host、internal Python worker 三层清晰，职责分离明确，build/run 也可以从 Xcode 直接起。
