# Piki Vault Protocol

这个测试 vault 用于验证 Piki 的 agent、lint、Health 和轻量写入链路。

## 基本原则

- 优先从 `wiki/` 回答，不要每次重读所有 `raw/`。
- 用户明确要求写入时，才修改 `wiki/` 或 `raw/`。
- `AGENTS.md` 只读。
- 如果发现冲突或不确定性，要明确标记出来。

## query 工作流

1. 先读 `wiki/index.md`。
2. 只读取和问题直接相关的 wiki 页面。
3. 回答时尽量引用页面路径。
4. 普通查询默认不写入。

## ingest 工作流

1. 先读取新来源。
2. 产出或更新 `wiki/sources/` 页面。
3. 再按需要更新 `wiki/concepts/`、`wiki/entities/`、`wiki/domains/`。
4. 更新 `wiki/index.md`。
5. 在 `wiki/log.md` 追加记录。

## lint 工作流

lint 的目标是同时做检查和修复。

优先关注：

- 断裂链接
- 孤立页
- 缺失索引项
- 重复标题
- 过期页面
- 内容过薄的页面

lint 时应先拿到结构化检查结果，再围绕这些结果定向分析和修复。
不要因为 lint 顺手做无关的大规模知识扩写。

## 日志格式

`wiki/log.md` 使用追加式记录，标题格式：

`## [YYYY-MM-DD] 操作 | 简短标题`
