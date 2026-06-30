# Agent 回归

## 设计

| 项目 | 内容 |
| --- | --- |
| 目标 | 验证 Piki 的统一 Agent task 是否满足核心产品预期 |
| 入口 | `POST /tasks` |
| 运行方式 | 真实本地 Agent Service + 临时复制 vault |
| 主脚本 | [scripts/run_agent_regression.py](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/scripts/run_agent_regression.py) |
| Case 真相源 | [docs/development/agent_regression_cases.json](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/docs/development/agent_regression_cases.json) |
| 输出目录 | [outputs/agent-regression](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/outputs/agent-regression) |
| 默认测试仓库 | [piki-vault](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/piki-vault) |

## Cases

| Case | 意图 | 示例 |
| --- | --- | --- |
| 1 | 普通问候 / 探索式聊天 | 你好，你能做什么？ |
| 2 | 查询知识库事实 | 孟岩正在做点啥？ |
| 3 | 跨页面综合 / 分析 | 我对个人知识库产品的判断是什么？ |
| 4 | 基于回答继续追问 | 展开讲第二点 |
| 5 | 记录对话框中的内容 | 帮我记一下：…… |
| 6 | 最小 ingest smoke / 页面模板上传文件并记录 | 上传文档 + 请帮我 ingest 这个文件，并整理进知识库。 |
| 7 | 更新/修正已有 wiki 知识 | 孟岩这页有个地方不对…… |
| 8 | lint | Run vault lint. |

## 运行命令

| 场景 | 命令 |
| --- | --- |
| 全量回归 | `python3 scripts/run_agent_regression.py --service-url http://127.0.0.1:8782 --timeout-seconds 120` |
| 单 case 回归 | `python3 scripts/run_agent_regression.py --service-url http://127.0.0.1:8782 --case-id 8` |
| 结果整理表 | [agent-regression-tracker-20260606.xlsx](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/outputs/agent-regression/agent-regression-tracker-20260606.xlsx) |

> 回归测试直接走 HTTP API，与 App 使用相同的端点。

## 最小必跑项

当改动不再是“仅 SwiftUI 视图层”而开始触及可能影响服务行为的逻辑时，默认至少跑一轮 case 6。

case 6 的定位不是全面验收，而是一个很小的 ingest smoke test：

- 使用和页面模板动作一致的 ingest 请求文案
- 附上一份很小的 Markdown 文件
- 验证任务能完成最基础的附件读取与落库动作
- 重点看 `raw/sources/` 与 `wiki/sources/` 是否至少发生了正确写入

## 最近结果

| 日期 | 测试仓库 | 结果文件 | 备注 |
| --- | --- | --- | --- |
| 2026-06-06 | 历史正式仓库副本 | [agent-regression-20260606-173631.json](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/outputs/agent-regression/agent-regression-20260606-173631.json) | 上传与 lint 失败 |
| 2026-06-11 | 轻量测试仓库副本 | [agent-regression-20260611-235716.json](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/outputs/agent-regression/agent-regression-20260611-235716.json) | 1-6 通过，7/8 仍待修 |
