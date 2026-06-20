# Piki 路线图

## 0. 当前主线

Piki 已完成一次关键架构转向：从 OpenAI 时代的半定制 runtime，迁移到 Claude Agent SDK + agent-first 的统一主循环。

当前路线图不再围绕“把某个 SDK 接上”，而是围绕三件事：

1. 把 Claude 主链路打磨到稳定
2. 把 UI 做成真正可观察、可恢复的知识工作流
3. 在不破坏 agent-first 的前提下补齐确定性系统能力

## 1. 已完成

- Python `agent_service` 保留为本地运行宿主
- 旧 localhost HTTP/SSE 已从主构建路径退出，仅保留为历史兼容与测试参考
- Claude Agent SDK 成为唯一主 runtime 方向
- `/health` 改为 provider-neutral 状态输出
- `/tasks/{id}/input` 支持 AskUserQuestion / approval 恢复
- 事件协议收敛为 `agent.run.*`、`message.delta`、`tool.*`、`journal.created`
- runtime 默认 hermetic，不读取宿主 `.claude` 和记忆
- journal / rollback 继续由 Piki 负责
- 前端基础 DTO 和状态文案已改为 provider-neutral

## 2. 近期任务

### 2.1 运行时稳定化

- 安装并锁定可用的 `claude-agent-sdk`
- 验证真实 session 持久化行为
- 补强 Bash 写副作用阻断与审计日志
- 完成 smoke test、失败诊断和恢复提示

### 2.2 UI 可观察性

- 将 `message.delta` 渲染为稳定流式消息
- 将 `tool.started/finished` 映射为用户可理解的状态
- 把 `AskUserQuestion` 做成 Home 内联恢复交互
- 把 task/todo 事件渲染为 checklist / progress rail

### 2.3 Journal 与维护体验

- Home 的 Recent Activity 完整切到 journal 视图
- 强化 rollback 的失败原因展示
- 把 lint、source rescan、queue 状态做成“系统动作”，而不是第二套 agent runtime

## 3. 下一阶段

### 3.1 Capture 与 Ingest 体验

- 更顺滑的文件拖拽、Finder 选择和 staging 可视化
- 单文件 ingest 的状态可视化
- canonical source 与 wiki page 的联动预览

### 3.2 研究模式

- 在显式 research 模式下选择性开启 `WebSearch` / `WebFetch`
- 明确区分“查外部世界”和“整理本地记忆”
- 把引用来源和写入范围做成更清晰的 UI

### 3.3 维护自动化

- 更强的 lint / repair CLI helper
- source update queue 的节流与批处理策略
- knowledge gap、orphan、stale page 的定向修复体验

## 4. 明确不做

- 不恢复 OpenAI runtime 双轨主路径
- 不回到自定义 function_tool 中心架构
- 不把服务端 workflow 重新做成意图分流总控
- 不让 repo `.claude`、用户 `~/.claude` 或宿主 MCP 污染产品 vault agent
