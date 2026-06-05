import hashlib
import asyncio
import json
import re
from pathlib import Path
from types import SimpleNamespace

from agents.tool_context import ToolContext
from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.workflows.source_intake import run_source_intake
from agent_service.store import SQLiteStore
from agent_service.vault import Vault


def make_intake_vault(tmp_path: Path) -> Path:
    vault = tmp_path / "vault"
    (vault / "raw/inbox").mkdir(parents=True)
    (vault / "raw/sources").mkdir(parents=True)
    (vault / "raw/assets").mkdir(parents=True)
    (vault / "wiki").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent 规则\n", encoding="utf-8")
    (vault / "purpose.md").write_text("# 目的\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text("# 索引\n", encoding="utf-8")
    (vault / "wiki/log.md").write_text("# 日志\n", encoding="utf-8")
    return vault


def make_client(tmp_path: Path) -> TestClient:
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(ServiceConfig(db_path=tmp_path / "agent.sqlite3", enable_sdk_runtime=False), store=store)
    return TestClient(app)


def wiki_fingerprint(vault_path: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted((vault_path / "wiki").rglob("*")):
        if path.is_file():
            digest.update(str(path.relative_to(vault_path)).encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def test_markdown_source_intake_generates_canonical_source(tmp_path: Path):
    vault_path = make_intake_vault(tmp_path)
    input_path = tmp_path / "article.md"
    input_path.write_text("# 个人知识库\n\n这是一篇 Markdown 来源。", encoding="utf-8")
    wiki_before = wiki_fingerprint(vault_path)

    result = run_source_intake(Vault(vault_path), input_path)

    assert result.title == "个人知识库"
    assert result.format == "markdown"
    assert result.source_path.startswith("raw/sources/")
    assert result.asset_path.startswith("raw/assets/")
    assert (vault_path / result.source_path).exists()
    assert (vault_path / result.asset_path).exists()
    source_text = (vault_path / result.source_path).read_text(encoding="utf-8")
    assert 'format: "markdown"' in source_text
    assert "hash:" in source_text
    assert "## 正文" in source_text
    assert "这是一篇 Markdown 来源。" in source_text
    assert (vault_path / "system/source_manifest.json").exists()
    assert wiki_fingerprint(vault_path) == wiki_before


def test_docx_source_intake_extracts_text(tmp_path: Path):
    from docx import Document

    vault_path = make_intake_vault(tmp_path)
    input_path = tmp_path / "note.docx"
    document = Document()
    document.add_heading("DOCX 来源标题", level=1)
    document.add_paragraph("这是 DOCX 正文。")
    document.save(input_path)

    result = run_source_intake(Vault(vault_path), input_path)

    assert result.title == "DOCX 来源标题"
    assert result.format == "docx"
    source_text = (vault_path / result.source_path).read_text(encoding="utf-8")
    assert "这是 DOCX 正文。" in source_text


def test_capture_api_persists_output_and_reuses_duplicate(tmp_path: Path):
    vault_path = make_intake_vault(tmp_path)
    input_path = tmp_path / "clip.txt"
    input_path.write_text("文本来源标题\n\n正文内容。", encoding="utf-8")
    client = make_client(tmp_path)

    first = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "保存来源",
            "selected_paths": [str(input_path)],
        },
    )
    assert first.status_code == 200
    first_task = client.get(f"/tasks/{first.json()['task_id']}").json()
    first_output = first_task["output"]
    assert first_task["task_kind"] == "source-intake"
    assert first_task["status"] == "completed"
    assert first_output["source_path"].startswith("raw/sources/")
    assert first_output["reused"] is False

    second = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "保存来源",
            "selected_paths": [str(input_path)],
        },
    )
    second_task = client.get(f"/tasks/{second.json()['task_id']}").json()
    assert second_task["output"]["source_path"] == first_output["source_path"]
    assert second_task["output"]["reused"] is True

    events = client.get(f"/tasks/{first.json()['task_id']}/events").text
    assert "event: source_intake.started" in events
    assert "event: source_intake.normalized" in events


class FakePipelineIngestRunner:
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
                    "path": "wiki/sources/记录文档.md",
                    "content": f"# 记录文档\n\n来源：`{source_path}`\n",
                    "reason": "记录上传文档",
                },
            )
            await invoke(
                "append_file",
                {
                    "path": "wiki/log.md",
                    "content": f"\n## [2026-06-05] ingest | 记录文档\n\n- 来源：`{source_path}`\n",
                    "reason": "记录 ingest 日志",
                },
            )

        asyncio.run(run_tools())
        return SimpleNamespace(
            final_output=json.dumps(
                {
                    "source_title": "记录文档",
                    "source_meta": {
                        "path": source_path,
                        "title": "记录文档",
                        "format": "markdown",
                        "source_path": source_path,
                    },
                    "summary": "已记录上传文档。",
                    "entities": [],
                    "concepts": [],
                    "claims": [],
                    "conflicts": [],
                    "changed_pages": ["wiki/sources/记录文档.md", "wiki/log.md"],
                    "next_actions": [],
                },
                ensure_ascii=False,
            ),
            new_items=[],
            raw_responses=[],
        )


def test_capture_api_runs_source_intake_then_wiki_ingest_when_sdk_configured(tmp_path: Path, monkeypatch):
    vault_path = make_intake_vault(tmp_path)
    input_path = tmp_path / "record.md"
    input_path.write_text("# 记录文档\n\n这是一份需要进入 wiki 的文档。", encoding="utf-8")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            enable_sdk_runtime=True,
            agent_model="test-model",
            openai_base_url="https://example.test/v1",
        ),
        store=store,
    )
    app.state.runner._runner_cls = FakePipelineIngestRunner
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "帮我记录一下这个文档",
            "selected_paths": [str(input_path)],
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["task_kind"] == "source-intake"
    assert task["status"] == "completed"
    assert task["output"]["source_path"].startswith("raw/sources/")
    assert task["output"]["ingest"]["summary"] == "已记录上传文档。"
    assert (vault_path / "wiki/sources/记录文档.md").exists()
    assert "ingest | 记录文档" in (vault_path / "wiki/log.md").read_text(encoding="utf-8")

    events = client.get(f"/tasks/{response.json()['task_id']}/events").text
    assert "event: source_intake.started" in events
    assert "event: source_intake.normalized" in events
    assert "event: ingest.started" in events
    assert "event: file.changed" in events
    assert "event: journal_entry.created" in events
    assert "正在编译进 Wiki" in events


def test_unsupported_format_fails_without_modifying_wiki(tmp_path: Path):
    vault_path = make_intake_vault(tmp_path)
    input_path = tmp_path / "data.csv"
    input_path.write_text("a,b\n1,2\n", encoding="utf-8")
    client = make_client(tmp_path)
    wiki_before = wiki_fingerprint(vault_path)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "保存来源",
            "selected_paths": [str(input_path)],
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "failed"
    assert "Unsupported source format" in task["summary"]
    assert wiki_fingerprint(vault_path) == wiki_before
