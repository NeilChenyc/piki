---
title: Agent 工作流
type: concept
---

# Agent 工作流

Piki 的标准任务流是：

1. 装配上下文
2. 让 Agent 决定读取哪些页面
3. 在需要时执行写入
4. 生成可观察事件
5. 如有修改则记录到 journal

它和 [[entities/孟岩]] 当前推进的工作直接相关。
