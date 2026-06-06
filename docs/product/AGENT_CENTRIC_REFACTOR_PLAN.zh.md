# Piki Agent-Centric 重构原则与计划

## 1. 当前结论

Piki 的方向没有错，问题在于旧实现曾经把太多判断拆成服务端 workflow、fallback 和自定义工具，导致：

- 运行时语义与产品语义混在一起
- UI 状态依赖 provider 事件名
- agent 像是在“借用”产品，而不是成为产品主循环

这次重构的目标不是继续加兼容层，而是把系统重新收敛为 agent-first。

## 2. 重构后的基本原则

### 2.1 服务端变薄

服务端只保留五件事：

1. 任务生命周期与 SSE
2. vault 运行时隔离与权限策略
3. Claude hooks / approvals / pause-resume
4. 对话级 journal / rollback
5. 附件 staging 与少量确定性后处理

### 2.2 agent 变强

- 不再由服务端先判断 query / ingest / lint / repair
- 不再维护自定义 agent-visible toolset
- 通过 Claude built-in tools 直接完成阅读、修改、检索、提问和 Bash 辅助

### 2.3 产品边界更硬

- `AGENTS.md` 只读
- vault 外无写入
- Bash 无文件副作用
- journal 只看真实 `raw/` / `wiki/` 变化

## 3. 新的统一任务模型

```text
POST /tasks
  -> assemble context envelope
  -> stage selected paths
  -> start Claude session
  -> stream message/tool/input events
  -> commit journal if raw/wiki changed
  -> complete or pause task
```

`POST /tasks/{id}/input` 用于恢复被 `AskUserQuestion` 或审批暂停的任务。

## 4. 上下文设计

每轮注入的上下文应该稳定且产品化：

- `AGENTS.md`
- `purpose.md`
- `wiki/index.md`
- `action_context`
- 最近对话
- 当前附件的 staging manifest

按钮不是第二套工作流，而是为标准 agent task 补充 `action_context`。

例如：

- `Run Lint` -> `action=run_lint`
- `Ingest File` -> `action=ingest_file`
- `Summarize Page` -> `action=summarize_current_page`

## 5. 能力分工

### 5.1 交给 agent 的事

- 判断是否需要读 wiki / raw / staging 文件
- 判断是否需要运行 lint / extract helper
- 判断写哪些页面、怎么组织内容
- 判断是否需要向用户追问

### 5.2 保留为系统代码的事

- source normalization
- source manifest 维护
- ingest/update queue 管理
- journal 提交
- rollback 执行
- runtime health / smoke test

这不是“服务端替 agent 做判断”，而是保留那些天然需要确定性的职责。

## 6. UI 协议

客户端不展示隐藏思维链，只展示可观察事件：

- 文本流
- 工具开始/结束
- checklist / task rail
- 输入中断
- journal 创建
- 完成 / 失败

provider-specific 事件名不应该直接出现在 UI 上。

## 7. 迁移后的删除原则

以下能力不再作为产品主路径保留：

- OpenAI runtime 主路径
- `VaultToolRegistry + function_tool` 作为 agent 工具面
- 普通 `/tasks` 的静默 query fallback
- `openai_*` 对外契约
- `sdk.run.*` 事件协议

## 8. 收尾标准

可以认为本轮重构完成，当且仅当：

- Claude runtime 成为唯一主路径
- 文档、API、测试和前端文案全部 provider-neutral 或 Claude-only
- agent-visible 工具只剩 Claude built-ins
- 普通任务不再静默退回旧 query fallback
- journal / rollback / input resume 在 Claude runtime 下闭环可用
