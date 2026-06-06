from pathlib import Path

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.store import SQLiteStore
from agent_service.vault import Vault
from agent_service.workflows.query import run_read_only_query


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
    return vault


def test_query_recalls_chinese_wiki_page_and_wikilink(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)

    result = run_read_only_query(Vault(vault_path), "个人记忆如何帮助自然回忆？")

    citation_paths = {citation.path for citation in result.citations}
    assert "wiki/concepts/个人记忆系统.md" in citation_paths
    assert "wiki/entities/孟岩.md" in result.related_pages
    assert result.confidence in {"medium", "high"}


def test_tasks_do_not_silently_fallback_when_runtime_unconfigured(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(ServiceConfig(db_path=tmp_path / "agent.sqlite3", enable_agent_runtime=False), store=store)
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "个人记忆如何帮助自然回忆？",
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "failed"
    assert "Claude Agent runtime is not configured" in task["summary"]
