# Piki Roadmap 2.0：稳定化与体验打磨

## 1. 目标

Roadmap 2.0 的目标不是再做一次大重构，而是在 Claude runtime 已落位的前提下，把真实用户链路调到稳定、可信、顺手。

重点是三件事：

- 让 agent 主循环可观察
- 让写入与回退可信
- 让输入中断、多轮上下文和文件协作真正好用

## 2. 阶段一：Claude Runtime 闭环验证

验收点：

- `/health` 正确显示 `provider`、`model`、runtime enabled/configured
- `/runtime/smoke-test` 能清晰报告成功或失败原因
- 普通 `POST /tasks` 走 Claude runtime，而不是静默 fallback
- AskUserQuestion 暂停后可通过 `/tasks/{id}/input` 恢复同一 session

## 3. 阶段二：Home 体验升级

验收点：

- `message.delta` 实时渲染
- `tool.started/finished` 映射为“正在读取知识库 / 正在写入知识库 / 等待你的输入”
- `pending_input` 在 Home 内联展示
- provider-specific 原始事件名不再直接显示给用户

## 4. 阶段三：Recent Activity 与 Rollback

验收点：

- Recent Activity 只展示真实 journal 记录
- 最近两条 active journal 明确显示 rollback 入口
- rollback 成功、失败、hash 不匹配都有清晰反馈
- journal.created 事件能推动 UI 局部刷新

## 5. 阶段四：文件协作体验

验收点：

- Home 支持文件选择、拖拽和 staging 提示
- Inbox 的 ingest / clear 都经由 Agent Service 执行
- canonical source、wiki page、journal diff 可以联动查看

## 6. 阶段五：研究模式与扩展能力

仅在显式研究模式下考虑：

- 开启 `WebSearch` / `WebFetch`
- 新增更强的 extract / summarise / compare CLI helper
- 增加对更多文件格式的处理能力

默认模式仍坚持本地知识维护优先，不把外部研究能力变成常驻噪音。
