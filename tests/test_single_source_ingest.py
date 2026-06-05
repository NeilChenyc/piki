import asyncio
import json
import re
from pathlib import Path
from types import SimpleNamespace

from agents.tool_context import ToolContext
from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.store import SQLiteStore


def make_ingest_vault(tmp_path: Path) -> Path:
    vault = tmp_path / "vault"
    (vault / "raw/sources").mkdir(parents=True)
    (vault / "wiki/sources").mkdir(parents=True)
    (vault / "wiki/concepts").mkdir(parents=True)
    (vault / "wiki/entities").mkdir(parents=True)
    (vault / "wiki/domains").mkdir(parents=True)
    (vault / "wiki/synthesis").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent 规则\n", encoding="utf-8")
    (vault / "purpose.md").write_text("# 目的\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text("# 索引\n", encoding="utf-8")
    (vault / "wiki/log.md").write_text("# 日志\n", encoding="utf-8")
    (vault / "raw/sources/测试来源.md").write_text(
        """---
title: "测试来源"
format: "markdown"
hash: "abc123"
source_path: "raw/sources/测试来源.md"
---

# 测试来源

这个来源讨论个人知识库、LLM Wiki 和持续编译。
""",
        encoding="utf-8",
    )
    return vault


class FakeIngestRunner:
    @staticmethod
    def run_sync(agent, user_input, *, max_turns, run_config):
        source_path = re.search(r"raw/sources/[^\s`]+\.md", user_input).group(0)
        tools = {tool.name: tool for tool in agent.tools}

        async def invoke(tool_name: str, payload: dict):
            tool = tools[tool_name]
            return await tool.on_invoke_tool(
                ToolContext(
                    context=None,
                    tool_name=tool_name,
                    tool_call_id=f"fake_{tool_name}",
                    tool_arguments=json.dumps(payload, ensure_ascii=False),
                ),
                json.dumps(payload, ensure_ascii=False),
            )

        async def run_tools():
            await invoke("read_file", {"path": source_path, "max_bytes": 20000})
            await invoke(
                "write_file",
                {
                    "path": "wiki/sources/测试来源.md",
                    "content": """---
title: 测试来源
type: source
sources:
  - raw/sources/测试来源.md
status: active
confidence: medium
check_after:
---

# 测试来源

## 摘要

这个来源说明个人知识库可以通过 LLM Wiki 持续编译。

## 关键内容

- 关联 [[concepts/个人知识库]]。

## 相关页面

- [[concepts/个人知识库]]
""",
                    "reason": "创建来源页",
                },
            )
            await invoke(
                "write_file",
                {
                    "path": "wiki/concepts/个人知识库.md",
                    "content": """---
title: 个人知识库
type: concept
sources:
  - raw/sources/测试来源.md
status: active
confidence: medium
check_after:
---

# 个人知识库

## 概要

个人知识库可以通过 LLM Wiki 将来源持续编译成可回忆的结构化页面。
""",
                    "reason": "更新概念页",
                },
            )
            await invoke(
                "write_file",
                {
                    "path": "wiki/index.md",
                    "content": "# 索引\n\n- [[sources/测试来源]] - 测试来源。\n- [[concepts/个人知识库]] - 个人知识库。\n",
                    "reason": "更新索引",
                },
            )
            await invoke(
                "append_file",
                {
                    "path": "wiki/log.md",
                    "content": "\n## [2026-06-04] ingest | 测试来源\n\n- 来源：`raw/sources/测试来源.md`\n- 更新：来源页、个人知识库概念页、索引。\n",
                    "reason": "追加 ingest 日志",
                },
            )

        asyncio.run(run_tools())
        return SimpleNamespace(
            final_output=json.dumps(
                {
                    "source_title": "测试来源",
                    "source_meta": {
                        "path": source_path,
                        "title": "测试来源",
                        "format": "markdown",
                        "hash": "abc123",
                        "source_path": source_path,
                    },
                    "summary": "已将测试来源编译进 wiki。",
                    "entities": [],
                    "concepts": [{"name": "个人知识库", "summary": "持续编译的个人知识系统。"}],
                    "claims": [{"text": "LLM Wiki 可以让来源持续编译成结构化页面。", "evidence": "测试来源"}],
                    "conflicts": [],
                    "changed_pages": [
                        "wiki/sources/测试来源.md",
                        "wiki/concepts/个人知识库.md",
                        "wiki/index.md",
                        "wiki/log.md",
                    ],
                    "next_actions": [],
                },
                ensure_ascii=False,
            ),
            new_items=[],
            raw_responses=[],
        )


def make_configured_client(tmp_path: Path, monkeypatch) -> TestClient:
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_sdk_runtime=True,
        agent_model="test-model",
        openai_base_url="https://example.test/v1",
    )
    app = create_app(config, store=store)
    app.state.runner._runner_cls = FakeIngestRunner
    return TestClient(app)


def test_single_source_ingest_writes_wiki_and_persists_result(tmp_path: Path, monkeypatch):
    vault_path = make_ingest_vault(tmp_path)
    client = make_configured_client(tmp_path, monkeypatch)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "/wiki:ingest raw/sources/测试来源.md",
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    task = client.get(f"/tasks/{task_id}").json()

    assert task["task_kind"] == "ingest"
    assert task["status"] == "completed"
    assert task["output"]["source_title"] == "测试来源"
    assert "wiki/sources/测试来源.md" in task["output"]["changed_pages"]
    assert task["output"]["journal_entry"] is not None
    assert (vault_path / "wiki/sources/测试来源.md").exists()
    assert (vault_path / "wiki/concepts/个人知识库.md").exists()
    assert "测试来源" in (vault_path / "wiki/index.md").read_text(encoding="utf-8")
    assert "ingest | 测试来源" in (vault_path / "wiki/log.md").read_text(encoding="utf-8")

    events = client.get(f"/tasks/{task_id}/events").text
    assert "event: ingest.started" in events
    assert "event: sdk.run.started" in events
    assert "event: file.changed" in events
    assert "event: journal_entry.created" in events
    assert "event: ingest.completed" in events


def test_ingest_requires_configured_sdk_runtime(tmp_path: Path):
    vault_path = make_ingest_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(ServiceConfig(db_path=tmp_path / "agent.sqlite3", enable_sdk_runtime=False), store=store)
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "/wiki:ingest raw/sources/测试来源.md",
        },
    )

    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "failed"
    assert "requires configured OpenAI Agents SDK runtime" in task["summary"]
    assert not (vault_path / "wiki/sources/测试来源.md").exists()


def test_ingest_invalid_source_fails_without_wiki_changes(tmp_path: Path, monkeypatch):
    vault_path = make_ingest_vault(tmp_path)
    client = make_configured_client(tmp_path, monkeypatch)
    index_before = (vault_path / "wiki/index.md").read_text(encoding="utf-8")

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "/wiki:ingest raw/sources/不存在.md",
        },
    )

    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "failed"
    assert "not found" in task["summary"]
    assert (vault_path / "wiki/index.md").read_text(encoding="utf-8") == index_before
