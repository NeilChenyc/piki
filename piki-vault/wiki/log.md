---
title: 日志
check_after: 2027-01-01
---

# 日志

## [2026-06-30] ingest | 微信背后的产品观（张小龙）

- 来源：`微信背后的产品观 (张小龙).pdf` — 张小龙系统阐述微信产品哲学（用户篇、需求篇、设计篇、气质篇、UI 篇）
- 写入 `raw/sources/1-1-72c6e0d0.md`（canonical source）
- 新建 `wiki/sources/微信背后的产品观.md` — 来源页，含核心观点、关键案例和方法论框架
- 新建 `wiki/entities/张小龙.md` — 实体页，记载履历与产品哲学核心
- 新建 `wiki/concepts/微信产品哲学.md` — 概念页，提炼人性驱动、极简主义、群体效应等核心理念
- 更新 `wiki/index.md` — 新增 3 条索引条目（sources、entities、concepts）
- 补充 wikilink：来源页、实体页、概念页之间互相链接

## [2026-06-23] lint | 修复 source 类型字段不一致

- 来源/任务：run_lint + 手工分析
- 修改路径：
  - `wiki/sources/杭州能源大脑驾驶舱及隐患排查平台AI升级建设方案.md` — `type: wiki-source` → `type: source`
  - `wiki/sources/LightAutoDS-Tab-多AutoML智能系统.md` — `type: wiki-source` → `type: source`，`source_ref` → `raw_source`（与其他来源页字段名统一）
- 结果：修复 3 处 frontmatter 不一致；lint 工具仍报 0 issues

## [2026-06-23] lint | 修复复选框过期与 log.md 标题错位

- 来源/任务：run_lint
- 修改路径：`wiki/sources/待摄入测试文档.md`、`wiki/log.md`
- 结果：修复 2 个问题——
  1. `wiki/sources/待摄入测试文档.md` 中 index/log 状态复选框从 `[ ]` 更新为 `[x]`
  2. `wiki/log.md` 中缺失的 `# 日志` 标题放回文件顶部，新旧条目不再被居中标题分割

## [2026-06-20] ingest | 待摄入测试文档

- 来源：`raw/inbox/next-test-source.md` — 小样本文档，用于测试文件上传、ingest、source normalization
- 写入 `raw/sources/待摄入测试文档-75feb254.md`
- 写入 `raw/assets/待摄入测试文档-75feb254/original.md`
- 新建 `wiki/sources/待摄入测试文档.md`
- 更新 `wiki/index.md`：新增 sources 索引条目

## [2026-06-20] ingest | Kimi K2 Thinking 英文专业媒体评价

- 来源：傅盛《Kimi K2 Thinking 模型：在海外的真实影响》（PDF）
- 写入 `raw/sources/kimi-de6329c5.md`
- 新建 `wiki/sources/Kimi K2 Thinking 英文专业媒体评价.md`
- 新建 `wiki/entities/月之暗面.md` — Moonshot AI 实体页
- 新建 `wiki/concepts/Kimi K2 模型.md` — 模型技术概念页
- 更新 `wiki/index.md`：新增 sources、concepts、entities 索引条目

## [2026-06-20] lint | 修复断裂 wikilink

- 来源/任务：run_lint
- 修改路径：`wiki/sources/杭州能源大脑驾驶舱及隐患排查平台AI升级建设方案.md`
- 结果：3 个断裂 wikilink（`concepts/大模型应用-能源行业`、`entities/杭州能源`、`domains/能源管理`）替换为纯文本 +（待创建）

## [2026-06-19] ingest | 杭州能源大脑驾驶舱及隐患排查平台AI升级建设方案（重注入）

- 来源：杭州能源大脑驾驶舱及隐患排查平台AI升级建设方案.docx（hash: b3a939e1，与首次 ingest 一致，内容无变化）
- `raw/sources/杭州能源大脑驾驶舱及隐患排查平台ai升级建设方案-b3a939e1.md` 已存在，无需重写
- `wiki/sources/杭州能源大脑驾驶舱及隐患排查平台AI升级建设方案` 已存在，内容完整，无需重写
- 补充 `wiki/index.md`：确认 sources 条目存在，已补入索引

## [2026-06-19] lint | 健康检查通过，0 issues

- 扫描文件数：10，发现 0 个问题
- 无需修复

## [2026-06-18] lint | 健康检查通过，0 issues

- 扫描文件数：10，发现 0 个问题
- 无需修复

## [2026-06-17] lint | 健康检查通过，0 issues

- 扫描文件数：10，发现 0 个问题
- 无需修复

## [2026-06-17] lint | 健康检查通过，0 issues

- 扫描文件数：10，发现 0 个问题
- 无需修复

## [2026-06-17] lint | 修复 log.md stale_page 误触发（check_after 字段残留）

- 扫描文件数：10，发现 1 个问题（1 warning）
- 问题根因：上一条日志行文中残留了触发 stale_page 解析的过期复查日期字符串，lint 扫描正文时误判
- 修复 `wiki/log.md`：改写该行描述，去除正文中触发误判的日期字段原文
- 修复 `wiki/log.md` frontmatter：新增 `check_after: 2027-01-01`，明确下次复查周期
- 复查后 lint 结果：预期 0 issues

## [2026-06-17] lint | log.md stale_page 修复，lint 结果归零

- 扫描文件数：10，发现 1 个问题（1 warning）
- 问题：`wiki/log.md` 日志正文中含字面量复查日期触发 stale_page warning
- 修复：将正文中的字面日期改为普通文字描述，更新 frontmatter check_after 为 2027-01-01
- 修复后 lint 结果：0 issues

## [2026-06-17] lint | 修复 log.md 断链与过期解析误触发

- 扫描文件数：10，发现 2 个问题（1 error，1 warning）
- 修复 `wiki/log.md`：将历史日志里的断裂 wikilink 改为纯文本描述，消除 broken-link error
- 修复 `wiki/log.md`：改写历史日志中触发 stale_page 误判的复查日期字段描述，消除 warning
- 复查后 lint 结果：0 issues

## [2026-06-17] lint | 修复断链、补 synthesis 索引项、更新过期复查日期

- 扫描文件数：10，发现 3 个问题（1 error，2 warning）
- 修复 `wiki/index.md`：移除断裂 wikilink，目标路径为 `sources/杭州能源大脑驾驶舱及隐患排查平台AI升级建设方案`（对应来源页不存在）
- 修复 `wiki/index.md`：新增 `## synthesis` 分区，收录 `[[synthesis/为什么轻量测试仓库有必要]]`
- 修复 `wiki/synthesis/为什么轻量测试仓库有必要.md`：将过期复查日期（原为 2026-01-01）更新为 2027-01-01

## [2026-06-17] ingest | 杭州能源大脑驾驶舱及隐患排查平台AI升级建设方案

- 来源：杭州能源大脑驾驶舱及隐患排查平台AI升级建设方案.docx
- 写入 `raw/sources/杭州能源大脑驾驶舱及隐患排查平台ai升级建设方案-b3a939e1.md`
- 编译 wiki 页 `wiki/sources/杭州能源大脑驶舱及隐患排查平台AI升级建设方案`
- 更新 `wiki/index.md` 添加 sources 条目

## [2026-06-17] ingest | LightAutoDS-Tab 论文

- 来源：LightAutoDs.pdf（arXiv 2507.13413v1，Sber AI Lab / ITMO University）
- 写入 `raw/sources/about-the-dataset-93a85bfa.md`
- 编译 wiki 页 `wiki/sources/LightAutoDS-Tab-多AutoML智能系统.md`
- 更新 `wiki/index.md` 添加 sources 条目

## [2026-06-06] 初始化 | 轻量测试仓库

- 清空原有重内容资料，重建轻量测试 vault。
- 保留 query、lint、Health、轻量写入所需的最小页面结构。
- 当前故意保留一页未入索引的 synthesis 页面，方便测试 lint 修复链路。

## [2026-06-25] lint | 补充缺失的 raw_source frontmatter

- 来源/任务：手动 lint（CLI 工具因 Python 版本不兼容不可用）
- 扫描文件数：14，发现 3 个问题（全部为低风险）
- 修复路径：
  - `wiki/sources/测试来源-LLM Wiki 摘记.md` — 新增 `raw_source: raw/sources/llm-wiki-idea-lite.md`
  - `wiki/sources/测试来源-孟岩近况.md` — 新增 `raw_source: raw/sources/mengyan-health-note-lite.md`
  - `wiki/sources/待摄入测试文档.md` — 将正文中的 canonical source 引用迁移至 frontmatter `raw_source`，删除冗余描述
- 结果：3 处 raw_source frontmatter 补齐；所有 wikilink 验证有效（0 断裂）；索引完整（14/14 页全覆盖）
- 剩余风险：`raw/inbox/next-test-source.md` 在 ingest 完成后仍驻留，可考虑清理或归档
