from pathlib import Path

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.store import SQLiteStore


def make_vault(tmp_path: Path) -> Path:
    vault = tmp_path / "vault"
    (vault / "raw/inbox").mkdir(parents=True)
    (vault / "raw/sources").mkdir(parents=True)
    (vault / "raw/assets").mkdir(parents=True)
    (vault / "wiki/concepts").mkdir(parents=True)
    (vault / "wiki/entities").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent 规则\n", encoding="utf-8")
    (vault / "purpose.md").write_text("# 目的\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text("---\ntitle: 索引\n---\n\n# 索引\n", encoding="utf-8")
    (vault / "wiki/log.md").write_text("---\ntitle: 日志\n---\n\n# 日志\n", encoding="utf-8")
    return vault


def make_client(tmp_path: Path) -> TestClient:
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(ServiceConfig(db_path=tmp_path / "agent.sqlite3", enable_agent_runtime=False), store=store)
    return TestClient(app)


def test_ingest_queue_public_api_is_removed(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    source = tmp_path / "article.md"
    source.write_text("# 队列来源\n\n正文内容。", encoding="utf-8")
    client = make_client(tmp_path)

    enqueued = client.post(
        "/ingest-queue/enqueue",
        json={"vault_path": str(vault_path), "selected_paths": [str(source), str(source)]},
    )
    assert enqueued.status_code == 404
    assert client.get("/ingest-queue").status_code == 404
    assert client.post("/ingest-queue/process", json={"vault_path": str(vault_path)}).status_code == 404
    assert client.post("/ingest-queue/deadbeef/retry").status_code == 404
    assert client.post("/ingest-queue/deadbeef/cancel").status_code == 404


def write_page(vault: Path, relative: str, content: str):
    path = vault / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def test_lint_reports_structural_and_maintenance_issues_via_agent_task(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    write_page(
        vault_path,
        "wiki/concepts/已有.md",
        "---\ntitle: 已有\n---\n\n# 已有\n\n这是已经在索引中的页面，内容稍微长一点以避免薄页面提示。\n",
    )
    write_page(
        vault_path,
        "wiki/index.md",
        "---\ntitle: 索引\n---\n\n# 索引\n\n- [[concepts/已有]]\n",
    )
    write_page(
        vault_path,
        "wiki/concepts/孤立.md",
        "---\ntitle: 重复标题\ncheck_after: 2020-01-01\n---\n\n# 重复标题\n\n[[不存在]]\n\n「潜在概念」需要整理。「潜在概念」再次出现。\n",
    )
    write_page(
        vault_path,
        "wiki/entities/重复.md",
        "---\ntitle: 重复标题\n---\n\n# 重复标题\n\n短。\n",
    )
    write_page(vault_path, "wiki/concepts/无头.md", "没有 frontmatter，也没有标题。")
    client = make_client(tmp_path)

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
    assert task["status"] == "completed"
    issues = task["output"]["lint_result"]["issues"]
    kinds = {issue["kind"] for issue in issues}
    assert "missing_frontmatter" in kinds
    assert "missing_heading" in kinds
    assert "broken_link" in kinds
    assert "orphan_page" in kinds
    assert "duplicate_title" in kinds
    assert "missing_index_entry" in kinds
    assert "stale_page" in kinds
    assert "knowledge_gap" in kinds


def test_lint_fix_adds_missing_index_entries_and_journal(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    write_page(
        vault_path,
        "wiki/concepts/待索引.md",
        "---\ntitle: 待索引\n---\n\n# 待索引\n\n这个页面应该被补充到索引中。\n",
    )
    client = make_client(tmp_path)
    lint_task = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "请检查知识库健康状态。",
            "action_context": {"action": "run_lint"},
        },
    )
    assert lint_task.status_code == 200
    report = client.get(f"/tasks/{lint_task.json()['task_id']}").json()["output"]["lint_result"]
    missing_ids = [
        issue["id"]
        for issue in report["issues"]
        if issue["kind"] == "missing_index_entry" and issue["path"] == "wiki/concepts/待索引.md"
    ]
    assert missing_ids

    fixed = client.post(
        "/lint/fix",
        json={"vault_path": str(vault_path), "issue_ids": missing_ids},
    )

    assert fixed.status_code == 200
    payload = fixed.json()
    assert payload["fixed_issue_ids"] == missing_ids
    assert "wiki/index.md" in payload["affected_files"]
    assert "wiki/log.md" in payload["affected_files"]
    assert payload["journal_entry"] is not None
    assert payload["journal_entry"]["snapshots"] == []
    assert "[[concepts/待索引]]" in (vault_path / "wiki/index.md").read_text(encoding="utf-8")
    assert "自动补充索引" in (vault_path / "wiki/log.md").read_text(encoding="utf-8")
