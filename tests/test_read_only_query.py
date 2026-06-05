from pathlib import Path

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.workflows.query import run_read_only_query
from agent_service.store import SQLiteStore
from agent_service.vault import Vault


def make_query_vault(tmp_path: Path) -> Path:
    vault = tmp_path / "vault"
    (vault / "wiki/concepts").mkdir(parents=True)
    (vault / "wiki/entities").mkdir(parents=True)
    (vault / "raw/sources").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent 规则\n", encoding="utf-8")
    (vault / "purpose.md").write_text("# 目的\n用于测试个人记忆查询。\n", encoding="utf-8")
    (vault / "wiki/log.md").write_text("# 日志\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text(
        """---
title: 测试索引
---

# 测试索引

- [[concepts/个人记忆系统]] — 关于个人记忆和自然回忆。
""",
        encoding="utf-8",
    )
    (vault / "wiki/concepts/个人记忆系统.md").write_text(
        """---
title: 个人记忆系统
---

# 个人记忆系统

个人记忆系统帮助用户把资料编译成可回忆的长期知识，并通过 [[entities/孟岩]] 这样的实体页面保持链接。
""",
        encoding="utf-8",
    )
    (vault / "wiki/entities/孟岩.md").write_text(
        """---
title: 孟岩
---

# 孟岩

孟岩是测试维基里的一个实体页面。
""",
        encoding="utf-8",
    )
    (vault / "raw/sources/raw-only.md").write_text(
        "隐藏召回词只存在于 raw source。",
        encoding="utf-8",
    )
    return vault


def make_client(tmp_path: Path) -> TestClient:
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(ServiceConfig(db_path=tmp_path / "agent.sqlite3", enable_sdk_runtime=False), store=store)
    return TestClient(app)


def test_query_recalls_chinese_wiki_page_and_wikilink(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)

    result = run_read_only_query(Vault(vault_path), "个人记忆如何帮助自然回忆？")

    citation_paths = {citation.path for citation in result.citations}
    assert "wiki/concepts/个人记忆系统.md" in citation_paths
    assert "wiki/entities/孟岩.md" in result.related_pages
    assert result.confidence in {"medium", "high"}
    assert all(path.startswith("wiki/") for path in result.related_pages)


def test_query_related_mode_and_raw_source_avoidance(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)
    log_before = (vault_path / "wiki/log.md").read_text(encoding="utf-8")

    result = run_read_only_query(Vault(vault_path), "隐藏召回词", mode="related")

    assert result.answer == "已按要求只返回相关页面。"
    assert result.citations == []
    assert all(not path.startswith("raw/") for path in result.context_manifest.loaded_files)
    assert (vault_path / "wiki/log.md").read_text(encoding="utf-8") == log_before


def test_query_does_not_match_short_english_substrings(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)
    (vault_path / "wiki/concepts/confidence.md").write_text(
        "# Confidence\n\nconfidence: high\n",
        encoding="utf-8",
    )

    result = run_read_only_query(Vault(vault_path), "hi")

    assert result.citations == []
    assert result.confidence == "low"
    assert "没有在已编译 wiki 中找到足够相关的内容" in result.answer


def test_query_task_persists_structured_output(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)
    client = make_client(tmp_path)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "个人记忆如何帮助自然回忆？",
            "mode": "deep",
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    task = client.get(f"/tasks/{task_id}").json()
    output = task["output"]

    assert task["status"] == "completed"
    assert output["mode"] == "deep"
    assert output["citations"]
    assert output["citations"][0]["path"].startswith("wiki/")
    assert "answer" in output
    assert "wiki/index.md" in output["context_manifest"]["loaded_files"]

    events_response = client.get(f"/tasks/{task_id}/events")
    assert "event: query.searched" in events_response.text
    assert "event: query.completed" in events_response.text
