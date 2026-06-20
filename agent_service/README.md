# Runtime Worker 目录说明

`agent_service/` 现在是 Piki 的内部 Python worker 实现，不再是产品对外的 HTTP 服务。

当前产品链路是：

```text
SwiftUI App -> PikiRuntimeHost -> internal Python worker -> Claude Agent SDK / deterministic helpers
```

这个 Python 层保留的职责是：

- task 生命周期与状态持久化
- journal / rollback / ingest queue / lint
- Claude runtime 装配与事件生成
- 安全的 vault 访问与附件 staging
- 内部 worker RPC 的 deterministic 行为

## 目录职责

| 目录 | 说明 |
| --- | --- |
| `application/` | 任务执行、事件发布、系统动作协调。 |
| `config.py` | worker 配置、环境变量与运行时开关。 |
| `models/` | Pydantic 数据模型和枚举。 |
| `runtime/` | worker CLI、stdio 入口、任务事件桥。 |
| `store/` | SQLite schema 初始化和任务、事件、journal、queue 读写。 |
| `vault/` | vault 路径校验和安全读写封装。 |
| `workflows/` | 确定性系统工作流，例如 source intake、ingest queue、lint、rollback。 |

## 运行方式

- 开发和打包都通过 Piki app 启动
- worker 不再作为独立产品入口运行
- app bundle 内包含私有 Python runtime、site-packages 和 worker entrypoint

## 现阶段约定

- 不再保留 FastAPI / localhost HTTP 作为正式产品协议
- 不再把 `agent_service/` 当成可独立部署的后端应用
- worker 输出的事件语义保持稳定，供 Swift 端消费
- 旧的 `app.py` / `api/routes/` 仅保留为历史兼容与内部测试参考，不进入产品主路径
