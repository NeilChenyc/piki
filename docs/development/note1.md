# Runtime Migration Note

这份开发笔记原本记录的是 OpenAI Agents SDK 方案，现已被 Claude Agent SDK 主路径替代。

当前有效结论：

- `agent_service` 仍是本地 Python 运行宿主
- 主 runtime 改为 Claude Agent SDK
- 主配置改为 `ANTHROPIC_API_KEY` 与 `PIKI_AGENT_MODEL`
- 运行时默认使用私有 `CLAUDE_CONFIG_DIR`，并关闭 auto memory
- 普通 `/tasks` 不再静默 fallback 到旧 query pipeline

如果需要了解当前架构，请以这些文档为准：

- [AGENT_RUNTIME_DESIGN.zh.md](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/docs/product/AGENT_RUNTIME_DESIGN.zh.md)
- [AGENT_CENTRIC_REFACTOR_PLAN.zh.md](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/docs/product/AGENT_CENTRIC_REFACTOR_PLAN.zh.md)
- [agent_service/README.md](/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/agent_service/README.md)
