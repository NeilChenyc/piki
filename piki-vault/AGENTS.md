# Piki 大模型维基维护指南

本 vault 遵循 `raw/sources/llm-wiki.md` 描述的大模型维基模式。

用户负责策展来源和提出问题。大模型负责维护维基：摘要、链接、索引、矛盾、综合和日志。

## 核心约定

有三层：

- `raw/`：不可变的原始来源。只能读取这一层；除非用户明确要求，不要在摄入后改写、就地总结或重组来源。
- `wiki/`：由大模型维护的编译知识层。负责创建、更新、交叉链接和维护这些 Markdown 页面。
- `AGENTS.md`：后续大模型会话使用的结构约定和操作规则。只有当用户和大模型共同确认维基约定需要改变时，才更新本文件。

维基应该复利。不要把摄入当成一次性总结。每个有意义的来源都应该更新所有相关的维基页面。

## 中文维基规则

维护的 `wiki/` 必须使用中文。

- vault 骨架目录名保持英文：`raw/inbox/`、`raw/sources/`、`raw/assets/`、`wiki/sources/`、`wiki/entities/`、`wiki/concepts/`、`wiki/domains/`、`wiki/synthesis/`。
- vault 骨架文件名保持英文：`wiki/index.md`、`wiki/log.md`、`AGENTS.md`。
- 普通维基页面文件名必须使用中文，必要时用中文短横线连接，例如 `sources/第四十五期-孟岩对话纪纲-人何以自处.md`。
- 一级标题、二级标题、正文、列表说明、索引说明和日志内容必须使用中文。
- 内部链接必须指向英文骨架目录加中文页面名，例如 `[[concepts/结构思维]]`。
- 可保留必要的专有名词、产品名、文件路径、命令、代码标识和通用缩写，例如 `Piki`、`Markdown`、`DOCX`、`AGENTS.md`、`raw/sources/example.md`。
- YAML frontmatter 的字段名和受控枚举值可以保持英文，便于工具解析；但 `title`、`tags` 等面向人的字段内容应优先使用中文。

## 目录结构

```text
raw/
  inbox/       等待摄入的新材料。
  sources/     已接受进入 vault 的不可变原始来源。
  assets/      本地图片、附件和支持文件。

wiki/
  index.md      已编译维基的内容目录，内容使用中文。
  log.md        维基操作的追加式时间记录，内容使用中文。
  sources/      每个已摄入来源一页，页面文件名和内容使用中文。
  entities/     人物、组织、工具、地点、项目和具名事物，页面文件名和内容使用中文。
  concepts/     概念、模式、方法、主张和抽象，页面文件名和内容使用中文。
  domains/      主题级地图和持续演化的领域摘要，页面文件名和内容使用中文。
  synthesis/    跨来源分析、比较、回答和论题，页面文件名和内容使用中文。
```

## 页面元数据

每个维基页面都应该以 YAML frontmatter 开头：

```yaml
---
title:
type:
created:
updated:
sources: []
tags: []
status: active
confidence: medium
review_after:
---
```

`type` 尽量使用这些值：

- `source`
- `entity`
- `concept`
- `domain`
- `synthesis`
- `index`
- `log`

`confidence` 使用这些值：

- `low`
- `medium`
- `high`

`status` 使用这些值：

- `active`
- `draft`
- `stale`
- `superseded`
- `needs-review`

## 链接约定

- 优先使用 Obsidian 风格的维基链接：`[[concepts/示例概念]]`。
- 依赖某个来源提出主张时，链接到对应来源页。
- 除非页面专门记录来源出处，不要直接链接原始文件。
- 某个概念、实体或领域反复出现时，创建或更新它自己的页面。
- 页面名使用中文，简洁、可读、描述性强；必要时用短横线分隔。

## 来源页模板

`wiki/sources/*.md` 使用这个结构：

```markdown
---
title:
type: source
created:
updated:
sources:
  - raw/sources/example.md
tags: []
status: active
confidence: medium
review_after:
---

# 标题

## 来源

- 路径：
- 作者：
- 日期：
- 格式：

## 摘要

## 关键想法

## 重要细节

## 进入维基的链接

## 未决问题

## 维护备注
```

## 概念页模板

`wiki/concepts/*.md` 使用这个结构：

```markdown
---
title:
type: concept
created:
updated:
sources: []
tags: []
status: active
confidence: medium
review_after:
---

# 标题

## 定义

## 为什么重要

## 支持来源

## 相关概念

## 未决问题

## 修订历史
```

## 实体页模板

`wiki/entities/*.md` 使用这个结构：

```markdown
---
title:
type: entity
created:
updated:
sources: []
tags: []
status: active
confidence: medium
review_after:
---

# 标题

## 这是什么

## 相关性

## 相关页面

## 来源备注

## 未决问题
```

## 领域页模板

`wiki/domains/*.md` 使用这个结构：

```markdown
---
title:
type: domain
created:
updated:
sources: []
tags: []
status: active
confidence: medium
review_after:
---

# 标题

## 概览

## 核心概念

## 关键来源

## 当前综合

## 矛盾与张力

## 下一步问题
```

## 综合页模板

`wiki/synthesis/*.md` 使用这个结构：

```markdown
---
title:
type: synthesis
created:
updated:
sources: []
tags: []
status: active
confidence: medium
review_after:
---

# 标题

## 问题

## 答案

## 证据

## 含义

## 相关页面

## 后续问题
```

## 摄入工作流

当用户要求摄入一个来源时：

1. 从 `raw/inbox/`、`raw/sources/` 或用户提供的其他路径读取来源。
2. 识别来源标题、作者、日期、格式和出处。
3. 在 `wiki/sources/` 中创建或更新一个来源页。
4. 更新所有相关的 `wiki/entities/`、`wiki/concepts/` 和 `wiki/domains/` 页面。
5. 当新来源显著改变跨来源理解时，创建或更新 `wiki/synthesis/` 页面。
6. 更新 `wiki/index.md`。
7. 在 `wiki/log.md` 追加记录。
8. 明确暴露冲突、过期说法或不确定性，不要把它们隐藏起来。

摄入时，对主张要保守，对链接要慷慨。

## 查询工作流

当用户询问知识库问题时：

1. 先读 `wiki/index.md`。
2. 搜索相关维基页面。
3. 尽量从已编译维基页面回答。
4. 引用用到的维基页面。
5. 如果答案有长期价值，询问是否回存；如果用户明确要求保存综合，则直接创建 `wiki/synthesis/` 页面。
6. 对重要查询或回存活动，在 `wiki/log.md` 追加记录。

不要默认为了每次查询重读所有原始来源。只有当已编译维基不足、有争议或用户明确要求时，才读取原始来源。

## 检查工作流

定期检查维基：

- 缺少入链的孤立页面。
- 断裂的维基链接。
- 反复出现但没有独立页面的重要概念。
- 重复或重叠的概念页。
- 需要复查的过期说法。
- 来源或综合页面之间的矛盾。
- 缺少 frontmatter 或必要章节的页面。
- 缺失、过期或误导性的索引条目。

检查后，在 `wiki/log.md` 追加记录；如果页面状态变化，同步更新 `wiki/index.md`。

## 冲突与过期标记

当新信息挑战旧信息时，不要静默覆盖旧主张。使用明确标记：

```markdown
> 冲突：这个说法受到 [[sources/示例来源]] 的挑战。
```

```markdown
> 过期：这个部分应在 YYYY-MM-DD 后复查，因为……
```

```markdown
> 已被替代：由 [[synthesis/新的页面]] 替代。
```

## 日志

`wiki/log.md` 是追加式记录。使用这个标题格式：

```markdown
## [YYYY-MM-DD] 操作 | 简短标题
```

常用操作值：

- `初始化`
- `摄入`
- `查询`
- `回存`
- `检查`
- `结构`
- `维护`

每条日志应包含：

- 发生了什么变化。
- 涉及哪些页面。
- 未决问题或后续动作。

## 索引

`wiki/index.md` 是主要导航页。每次有意义的维基变更后，都要保持它最新。

每个页面条目应包含：

- 链接。
- 类型。
- 一句话说明。
- 如果状态不是 `active`，标出状态。

## 维护姿态

优先做小而连贯的更新，不做失控的大重写。维基应该容易通过 Git diff 检查。

如果未来工作流需要新约定，先提出变更；用户确认后，再更新 `AGENTS.md`。
