# Piki 开发约束

本文件是仓库根目录的开发约束，面向参与开发这个项目的工程代理与开发者。

它只约束本仓库的开发流程，和 [piki-vault/AGENTS.md](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/piki-vault/AGENTS.md) 那份面向知识库维护的协议无关。

## 1. 变更边界

- 纯 SwiftUI 视图样式、排版、颜色、文案微调，如果不会影响 runtime、任务链路、网络请求、文件读写、agent 上下文、服务端接口或任务执行语义，可以只做常规验证。
- 只要改动 **除了仅 SwiftUI 视图以外** 的任何逻辑，并且这类改动有可能影响服务行为，就必须补做一轮最小回归测试。

这里的“可能影响服务行为”包括但不限于：

- `agent_service/` 下的任何逻辑
- `PikiApp` 中会影响任务创建、附件上传、模板动作、runtime 调用、任务流转的逻辑
- prompt / context / runner / task / ingest / lint / source intake 相关逻辑
- API 模型、请求参数、任务事件、文件落库路径相关逻辑

## 2. 必跑回归

遇到上面的改动范围，默认至少跑一轮 **最小 ingest smoke regression**。

这个回归的目标很克制：

- 从真实页面按钮对应的产品路径出发
- 给 Agent 发出当前产品实际使用的 ingest 模板请求
- 附上一份很小的 Markdown 文件
- 验证它完成最基础的 ingest 动作，而不是做全面内容质量评审

最基础动作包括：

- 任务能正常创建并完成
- Agent 能读取附件
- 至少写入 `raw/sources/`
- 至少写入 `wiki/sources/`
- 不出现明显卡死、超时或中途崩掉

## 3. 回归入口

默认回归脚本：

- `python3 scripts/run_agent_regression.py --service-url http://127.0.0.1:8782`

最小 ingest smoke case 会包含在默认回归集里。

如果只想单跑这条最小回归，可以用对应的 case id：

- `python3 scripts/run_agent_regression.py --service-url http://127.0.0.1:8782 --case-id 6`

> 如果后续 case id 调整，以 `docs/development/agent_regression_cases.json` 中标记的最小 ingest smoke case 为准。

## 4. 结果要求

- 如果最小 ingest smoke regression 失败，不要把这类改动当作“已验证完成”。
- 如果因为外部环境、模型服务或运行时不可用而无法执行，需要在提交说明里明确写出未验证原因。
- 不要拿纯单元测试替代这条最小 ingest smoke regression；两者作用不同。
