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
    app = create_app(ServiceConfig(db_path=tmp_path / "agent.sqlite3", enable_sdk_runtime=False), store=store)
    return TestClient(app)


def test_ingest_queue_processes_files_and_dedupes_pending_items(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    source = tmp_path / "article.md"
    source.write_text("# 队列来源\n\n正文内容。", encoding="utf-8")
    client = make_client(tmp_path)

    enqueued = client.post(
        "/ingest-queue/enqueue",
        json={"vault_path": str(vault_path), "selected_paths": [str(source), str(source)]},
    )
    assert enqueued.status_code == 200
    items = enqueued.json()["items"]
    assert len({item["id"] for item in items}) == 1

    processed = client.post(
        "/ingest-queue/process",
        json={"vault_path": str(vault_path), "max_items": 5},
    )

    assert processed.status_code == 200
    payload = processed.json()
    assert payload["processed"] == 1
    assert len(payload["completed"]) == 1
    item = payload["completed"][0]
    assert item["status"] == "completed"
    assert item["task_id"].startswith("task_")
    assert item["source_path"].startswith("raw/sources/")
    assert (vault_path / item["source_path"]).exists()


def test_ingest_queue_records_failure_retry_and_cancel(tmp_path: Path):
    vault_path = make_vault(tmp_path)
    bad_source = tmp_path / "data.csv"
    bad_source.write_text("a,b\n1,2\n", encoding="utf-8")
    later_source = tmp_path / "later.md"
    later_source.write_text("# 稍后处理\n\n正文。", encoding="utf-8")
    client = make_client(tmp_path)

    enqueued = client.post(
        "/ingest-queue/enqueue",
        json={"vault_path": str(vault_path), "selected_paths": [str(bad_source), str(later_source)]},
    ).json()["items"]
    bad_id, later_id = enqueued[0]["id"], enqueued[1]["id"]

    cancelled = client.post(f"/ingest-queue/{later_id}/cancel")
    assert cancelled.status_code == 200
    assert cancelled.json()["status"] == "cancelled"

    processed = client.post(
        "/ingest-queue/process",
        json={"vault_path": str(vault_path), "max_items": 5},
    ).json()
    assert processed["processed"] == 1
    assert processed["failed"][0]["id"] == bad_id
    assert "Unsupported source format" in processed["failed"][0]["error"]

    retried = client.post(f"/ingest-queue/{bad_id}/retry")
    assert retried.status_code == 200
    assert retried.json()["status"] == "pending"
    assert retried.json()["error"] is None


def write_page(vault: Path, relative: str, content: str):
    path = vault / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def test_lint_reports_structural_and_maintenance_issues(tmp_path: Path):
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

    response = client.post("/lint", json={"vault_path": str(vault_path)})

    assert response.status_code == 200
    kinds = {issue["kind"] for issue in response.json()["issues"]}
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
    report = client.post("/lint", json={"vault_path": str(vault_path)}).json()
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
    assert "[[concepts/待索引]]" in (vault_path / "wiki/index.md").read_text(encoding="utf-8")
    assert "自动补充索引" in (vault_path / "wiki/log.md").read_text(encoding="utf-8")
