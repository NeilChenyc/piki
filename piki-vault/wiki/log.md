---
title: Piki 维基日志
type: log
created: 2026-06-03
updated: 2026-06-04
sources: []
tags: [日志, 大模型维基]
status: active
confidence: high
review_after:
---

# Piki 维基日志

维基操作的追加式时间记录。

## [2026-06-03] 初始化 | 创建大模型维基内核脚手架

变更内容：

- 创建大模型维基的初始目录结构。
- 添加 `AGENTS.md` 作为维护规则和结构约定。
- 创建初始索引和日志。
- 基于 `raw/sources/llm-wiki.md` 写入第一批种子页面。

涉及页面：

- [[index]]
- [[log]]
- [[sources/大模型维基]]
- [[concepts/大模型维基]]
- [[concepts/编译知识层]]
- [[concepts/回存维基]]
- [[domains/个人知识库]]
- [[entities/安德烈-卡帕西]]
- [[entities/黑曜石]]
- [[synthesis/为什么大模型维基优于普通检索增强生成]]

未决问题：

- 哪些个人领域应该优先摄入？
- 下一个真实个人来源应该是什么？

## [2026-06-04] 摄入 | 孟岩与纪纲第四十五期对话

变更内容：

- 将原始 DOCX 逐字稿转换为新的 Markdown 原始来源：`raw/sources/e45-mengyan-duihua-jigang-ren-heyi-zichu.md`。
- 按用户要求将逐字稿说话人标签从 `发言人1` 规范为 `孟岩`，从 `发言人2` 规范为 `纪纲`。
- 创建来源摘要页，并将主要主题编译到实体、概念、领域和综合页面。
- 更新维基索引。

涉及页面：

- [[index]]
- [[log]]
- [[sources/第四十五期-孟岩对话纪纲-人何以自处]]
- [[entities/孟岩]]
- [[entities/纪纲]]
- [[concepts/取景框与重构]]
- [[concepts/结构思维]]
- [[concepts/人与人工智能协作]]
- [[concepts/人工智能原生公司]]
- [[concepts/人工智能时代教育]]
- [[concepts/品味是训练出的权重]]
- [[domains/人工智能时代的工作与生活]]
- [[domains/作为世界观的投资]]
- [[synthesis/人工智能时代人何以自处]]

未决问题：

- 需要确认“纪纲”是否为说话人 2 的标准称呼，因为 DOCX 标题和自我介绍中出现“李继刚”。
- 需要补充原始节目链接、发布渠道和准确录制日期。
- 是否需要进一步人工清理原始 Markdown 中的语音识别错误和姓名变体。

## [2026-06-04] 结构 | 补充个人记忆库目的文件

变更内容：

- 新增 `purpose.md`，说明这个 vault 的长期目的、记忆范围、回忆偏好、维护偏好和使用节奏。
- 明确当前 vault 用于 Piki 项目 dogfooding，并作为后续本地 Agent Service 的基础上下文。

涉及页面：

- [[log]]

涉及文件：

- `purpose.md`

未决问题：

- 阶段 1 开始实现本地 Agent Service 时，需要决定是否从当前 vault 裁剪一个更小的 golden vault 测试 fixture。
