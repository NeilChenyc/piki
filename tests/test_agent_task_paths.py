from pathlib import Path

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.store import SQLiteStore


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


def test_tasks_fail_cleanly_when_agent_runtime_unconfigured(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            enable_agent_runtime=False,
        ),
        store=store,
    )
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


def test_lint_report_main_path_uses_agent_task_output(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            enable_agent_runtime=False,
        ),
        store=store,
    )
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "请检查知识库健康状态。",
            "action_context": {"action": "run_lint"},
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["task_kind"] == "agent"
    assert task["status"] == "completed"
    assert task["output"]["lint_result"]["scanned_files"] >= 3
    assert "missing_index_entry" in task["output"]["lint_result"]["issue_counts"]


def test_health_check_prompt_is_promoted_to_run_lint_when_runtime_unconfigured(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            enable_agent_runtime=False,
        ),
        store=store,
    )
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "请帮我做一次知识库健康检查，并告诉我结构上有什么问题。",
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "completed"
    assert task["output"]["action_context"]["action"] == "run_lint"
    assert task["output"]["lint_result"]["scanned_files"] >= 3


def test_health_check_prompt_with_selected_paths_is_not_promoted_to_run_lint(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            enable_agent_runtime=False,
        ),
        store=store,
    )
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "请帮我做一次知识库健康检查。",
            "selected_paths": [str(tmp_path / "attachment.md")],
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "failed"
    assert "Claude Agent runtime is not configured" in task["summary"]


def test_run_vault_lint_prompt_is_promoted_to_run_lint_when_runtime_unconfigured(tmp_path: Path):
    vault_path = make_query_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            enable_agent_runtime=False,
        ),
        store=store,
    )
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "Run vault lint",
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "completed"
    assert task["output"]["action_context"]["action"] == "run_lint"
