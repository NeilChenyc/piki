# Piki 总体产品文档

## 1. 产品定位

Piki 是一个面向高密度知识工作者的本地优先个人记忆系统。

它不是普通笔记工具，也不是“加了搜索的聊天壳”，而是把用户分散的资料、对话、判断和长期主题持续编译成一个可维护、可回忆、可追溯的个人 Wiki。

一句话定位：

> Piki 帮助资料很多、经常复用信息、但不想再手动维护知识库的人，把零散输入变成长期可调用的个人记忆。

## 2. 核心用户

- AI 产品经理、研究员、咨询顾问
- 独立开发者、工程师、技术博主
- 创业者、投资与行业分析人员
- 研究型学习者和长期写作者

这类用户的共同特征是：输入密度高、复用频率高、上下文损耗昂贵。

## 3. 核心痛点

- 信息堆积很快，但不会自动变成可复用知识
- 收藏和搜索只能找到片段，不能维持长期理解
- 每次问 AI 都要重新解释背景，个人上下文无法自然延续
- 原始资料、AI 判断和最终结论之间缺少可追溯链路
- 自动化写入一旦出错，普通用户很难修复

## 4. 产品真相源

Piki 的底层真相始终是本地 Markdown vault：

- `raw/` 保存原始资料
- `wiki/` 保存编译后的知识页面
- `AGENTS.md` 约束 agent 如何维护知识库
- `purpose.md` 说明这个 vault 为什么存在
- `wiki/index.md` 和 `wiki/log.md` 负责导航与变更追踪

Piki App 不是数据本体，而是这套本地知识系统的工作台。

## 5. 当前架构判断

Piki 现在采用：

```text
SwiftUI App -> HTTP+SSE (localhost:8782) -> FastAPI/uvicorn -> Claude Agent SDK -> Claude built-in tools
```

这次迁移后的产品原则是：

- Claude Agent SDK 是唯一主 runtime
- Python Agent Service 通过 HTTP+SSE 提供后端能力，App 自动管理 uvicorn 进程
- Python 服务负责任务持久化、事件生成、hooks、journal、rollback、staging 和少量确定性后处理
- 不再维护自定义 agent-visible toolset
- 需要判断的事交给 agent
- 需要确定性的事变成本地 CLI 或系统工作流

## 5.1 当前实现形态

- Swift App 通过 `RuntimeServiceProtocol` → `HTTPRuntimeService` 访问后端 REST API
- SSE (`GET /tasks/{id}/events`) 提供实时事件流推送
- `LocalServiceManager` 自动启动 uvicorn 子进程，带健康探测和崩溃重启
- App 退出时优雅关闭后端进程
- 打包 DMG 时可嵌入 Python runtime，用户无需本地安装 Python

## 6. Agent-first 设计哲学

Piki 的产品内核不是“服务端先分流，再让模型补文案”，而是：

- 用户通过自然语言、命令和附件触发一轮标准 agent task
- 服务端统一装配上下文，不替用户预判 query / ingest / lint / repair
- agent 使用内建工具读取、对比、编辑和提问
- Piki 通过 hooks 和 journal 保证边界、安全和可回退

因此，Piki 的服务端应该越来越薄，产品能力越来越多地表现为：

- 更好的上下文协议
- 更好的工具使用边界
- 更强的可观察性
- 更可靠的 journal / rollback

## 7. MVP 范围

MVP 聚焦以下闭环：

- 本地 vault 初始化和浏览
- 文件导入与 source normalization
- 基于 Claude runtime 的统一 agent 任务入口
- wiki 问答、资料整理、单轮多文件写入
- 对话级 journal 与最近两条回退
- 基础 lint / 低风险修复
- 简洁但可观察的 Mac 客户端

MVP 不追求：

- 云同步、多用户、移动端
- 大而全的 research suite
- 自定义 MCP 工具矩阵
- 写入前逐条人工审批
- 把所有聊天默认沉淀为长期记忆

## 8. 安全与控制权

Piki 必须保留用户控制权：

- `AGENTS.md` 只读
- vault 外绝不允许 agent 写入
- `Bash` 默认不能做文件副作用
- 只有真实修改 `raw/` 或 `wiki/` 的对话才进入 journal
- 用户可查看最近 journal，并对最近两条 active 记录执行回退

回退的产品真相源是 Piki journal，而不是直接暴露 Claude checkpoint 作为用户功能。

## 9. 客户端定位

Piki 客户端不伪装成终端，也不展示隐藏推理链。它应该把 agent 工作流渲染成：

- 对话消息流
- 工具与阶段状态
- 文件引用与预览
- journal / rollback 入口
- inbox、queue、lint 和维护视图

用户看到的是“系统正在读什么、改了什么、卡在哪里”，而不是某个 provider 的底层事件名。

## 10. 成功标准

- 用户愿意持续把资料放进 Piki
- 用户能在需要时问回自己的旧知识，并拿到带引用答案
- 用户能信任自动写入，因为改动可追踪、可回退
- 高价值对话能顺滑沉淀进 wiki，而不是留在聊天黑箱里
- 即使不用 App，用户仍可直接打开 Markdown vault 阅读和迁移数据
