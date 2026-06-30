# Piki 项目记忆

## 项目定位
Piki 是本地优先的个人记忆系统，核心承诺：文件输入 -> agent 处理 -> wiki 写入 -> journal 记录 -> rollback 回退。

## 技术架构
SwiftUI App -> HTTP+SSE (localhost:8782) -> FastAPI/uvicorn -> Claude Agent SDK -> Claude built-in tools

## 当前状态（2026-06-24）
- Python 后端基本完整：API 端点、任务系统、Agent runner、Hooks、Journal、SQLite 存储
- Mac 客户端 UI 五个页面（Home/Inbox/Wiki/Health/Settings）已搭建
- Agent 回归 case 1-6 通过，case 7（知识更新修正）和 8（lint）失败
- 核心缺口：流式渲染未做、AskUserQuestion 内联恢复未做、工具状态映射未做、长文 ingest 无编译流水线

## 关键决策记录
- Claude Agent SDK 是唯一主 runtime，不再维护自定义 toolset
- Runtime 必须 hermetic，不读取宿主 .claude 和记忆
- Piki 自己负责 vault 协议、hooks、journal、rollback、staging
- MVP 不做云同步、多用户、移动端、自定义 MCP
