from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.models import RiskLevel, TaskKind, TaskStatus
from agent_service.runtime import RunnerStatus
from agent_service.store import SQLiteStore


def make_vault(tmp_path: Path) -> Path:
    vault = tmp_path / "vault"
    (vault / "raw/inbox").mkdir(parents=True)
    (vault / "raw/sources").mkdir(parents=True)
    (vault / "raw/assets").mkdir(parents=True)
    (vault / "wiki/sources").mkdir(parents=True)
    (vault / "wiki/concepts").mkdir(parents=True)
    (vault / "wiki/entities").mkdir(parents=True)
    (vault / "wiki/domains").mkdir(parents=True)
    (vault / "wiki/synthesis").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent 规则\n", encoding="utf-8")
    (vault / "purpose.md").write_text("# 目的\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text("# 索引\n", encoding="utf-8")
    (vault / "wiki/log.md").write_text("# 日志\n", encoding="utf-8")
    return vault


def make_client(tmp_path: Path, *, enable_agent_runtime: bool = False) -> TestClient:
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            staging_root=tmp_path / ".piki/task-staging",
            enable_agent_runtime=enable_agent_runtime,
            agent_model="claude-test",
        ),
        store=store,
    )
    return TestClient(app)


def mark_inspiration_processing(
    vault: Path,
    memo: dict,
    *,
    task_id: str,
    source_path: str = "raw/sources/inspirations-test.md",
) -> None:
    path = vault / memo["path"]
    text = path.read_text(encoding="utf-8")
    text = text.replace('compile_status: "pending"', 'compile_status: "processing"')
    text = text.replace("compile_task_id: null", f'compile_task_id: "{task_id}"')
    text = text.replace("source_path: null", f'source_path: "{source_path}"')
    path.write_text(text, encoding="utf-8")


def test_inspiration_create_list_search_and_update_write_markdown_files(tmp_path: Path):
    vault = make_vault(tmp_path)
    client = make_client(tmp_path)

    created = client.post(
        "/inspirations",
        json={
            "vault_path": str(vault),
            "content": "搭 harness：先定义团队 context，再让 agent 迭代。",
            "attachments": [],
        },
    )

    assert created.status_code == 200
    memo = created.json()
    assert memo["id"].startswith("insp_")
    assert memo["compile_status"] == "pending"
    assert memo["content_hash"]
    assert memo["path"].startswith("raw/inspirations/")
    memo_path = vault / memo["path"]
    assert memo_path.exists()
    text = memo_path.read_text(encoding="utf-8")
    assert 'type: "inspiration"' in text
    assert "搭 harness" in text

    listed = client.get("/inspirations", params={"vault_path": str(vault)})
    assert listed.status_code == 200
    assert [item["id"] for item in listed.json()["items"]] == [memo["id"]]

    searched = client.get(
        "/inspirations",
        params={"vault_path": str(vault), "query": "harness"},
    )
    assert searched.status_code == 200
    assert [item["id"] for item in searched.json()["items"]] == [memo["id"]]

    updated = client.patch(
        f"/inspirations/{memo['id']}",
        json={
            "vault_path": str(vault),
            "content": "搭 harness：团队给 context，agent 负责执行和复盘。",
            "attachments": [],
        },
    )

    assert updated.status_code == 200
    updated_payload = updated.json()
    assert updated_payload["compile_status"] == "pending"
    assert updated_payload["updated_at"] != memo["updated_at"]
    assert updated_payload["content_hash"] != memo["content_hash"]
    assert "复盘" in (vault / updated_payload["path"]).read_text(encoding="utf-8")


def test_inspiration_attachment_copy_is_limited_to_staging_root(tmp_path: Path):
    vault = make_vault(tmp_path)
    client = make_client(tmp_path)
    staged_image = tmp_path / ".piki/task-staging/uploads/upload-1/clip.png"
    staged_image.parent.mkdir(parents=True)
    staged_image.write_bytes(b"fake-png")

    created = client.post(
        "/inspirations",
        json={
            "vault_path": str(vault),
            "content": "配图灵感",
            "attachments": [
                {
                    "filename": "clip.png",
                    "buffered_path": str(staged_image),
                    "mime_type": "image/png",
                }
            ],
        },
    )

    assert created.status_code == 200
    attachment = created.json()["attachments"][0]
    assert attachment["path"].startswith("raw/assets/inspirations/")
    assert (vault / attachment["path"]).read_bytes() == b"fake-png"

    outside_file = tmp_path / "outside.png"
    outside_file.write_bytes(b"outside")
    rejected = client.post(
        "/inspirations",
        json={
            "vault_path": str(vault),
            "content": "不应复制",
            "attachments": [
                {
                    "filename": "outside.png",
                    "buffered_path": str(outside_file),
                    "mime_type": "image/png",
                }
            ],
        },
    )

    assert rejected.status_code == 400
    assert "staging" in rejected.text.lower()


def test_inspiration_delete_removes_markdown_and_attachment_directory(tmp_path: Path):
    vault = make_vault(tmp_path)
    client = make_client(tmp_path)
    staged_image = tmp_path / ".piki/task-staging/uploads/upload-1/clip.png"
    staged_image.parent.mkdir(parents=True)
    staged_image.write_bytes(b"fake-png")
    created = client.post(
        "/inspirations",
        json={
            "vault_path": str(vault),
            "content": "准备删除的灵感",
            "attachments": [
                {
                    "filename": "clip.png",
                    "buffered_path": str(staged_image),
                    "mime_type": "image/png",
                }
            ],
        },
    ).json()
    memo_path = vault / created["path"]
    attachment_dir = vault / "raw/assets/inspirations" / created["id"]

    response = client.delete(
        f"/inspirations/{created['id']}",
        params={"vault_path": str(vault)},
    )

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert not memo_path.exists()
    assert not attachment_dir.exists()
    listed = client.get("/inspirations", params={"vault_path": str(vault)})
    assert listed.json()["items"] == []


def test_inspiration_delete_missing_memo_returns_404(tmp_path: Path):
    vault = make_vault(tmp_path)
    client = make_client(tmp_path)

    response = client.delete(
        "/inspirations/insp_missing",
        params={"vault_path": str(vault)},
    )

    assert response.status_code == 404


def test_inspiration_compile_leaves_pending_when_runtime_unconfigured(tmp_path: Path):
    vault = make_vault(tmp_path)
    client = make_client(tmp_path, enable_agent_runtime=False)
    created = client.post(
        "/inspirations",
        json={"vault_path": str(vault), "content": "一个待编译灵感", "attachments": []},
    ).json()

    response = client.post("/inspirations/compile", json={"vault_path": str(vault)})

    assert response.status_code == 200
    payload = response.json()
    assert payload["compiled_count"] == 0
    assert payload["task_id"] is None
    assert payload["source_path"] is None
    assert "runtime" in payload["error"].lower()
    reloaded = client.get("/inspirations", params={"vault_path": str(vault)}).json()["items"][0]
    assert reloaded["id"] == created["id"]
    assert reloaded["compile_status"] == "pending"
    assert not list((vault / "raw/sources").glob("inspirations-*.md"))


def test_inspiration_list_reconciles_completed_processing_memo(tmp_path: Path):
    vault = make_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            staging_root=tmp_path / ".piki/task-staging",
            enable_agent_runtime=False,
            agent_model="claude-test",
        ),
        store=store,
    )
    client = TestClient(app)
    memo = client.post(
        "/inspirations",
        json={"vault_path": str(vault), "content": "已经整理完成的灵感", "attachments": []},
    ).json()
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.LOW,
        vault_path=str(vault),
        user_input="整理随手记",
        status=TaskStatus.COMPLETED,
        summary="done",
    )
    mark_inspiration_processing(vault, memo, task_id=task.id)

    reloaded = client.get("/inspirations", params={"vault_path": str(vault)}).json()["items"][0]

    assert reloaded["compile_status"] == "compiled"
    assert reloaded["compiled_hash"] == memo["content_hash"]
    assert reloaded["compile_task_id"] == task.id


@pytest.mark.parametrize(
    "status",
    [TaskStatus.FAILED, TaskStatus.CANCELLED, TaskStatus.INPUT_REQUIRED, TaskStatus.NEEDS_APPROVAL],
)
def test_inspiration_compile_retries_failed_processing_memo(tmp_path: Path, monkeypatch, status: TaskStatus):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    vault = make_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            staging_root=tmp_path / ".piki/task-staging",
            enable_agent_runtime=True,
            agent_model="claude-test",
        ),
        store=store,
    )

    async def fake_query(*, prompt, options):
        yield SimpleNamespace(content=[SimpleNamespace(text="重新整理随手记。")], session_id="sess_retry")

    app.state.runner._query_impl = fake_query
    app.state.runner.status = RunnerStatus(True, "Claude Agent SDK available")
    client = TestClient(app)
    memo = client.post(
        "/inspirations",
        json={"vault_path": str(vault), "content": "需要重试的灵感", "attachments": []},
    ).json()
    old_task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.LOW,
        vault_path=str(vault),
        user_input="整理随手记",
        status=status,
        summary="terminal",
    )
    mark_inspiration_processing(vault, memo, task_id=old_task.id)

    reconciled = client.get("/inspirations", params={"vault_path": str(vault)}).json()["items"][0]
    response = client.post("/inspirations/compile", json={"vault_path": str(vault)})
    payload = response.json()

    assert reconciled["compile_status"] == "failed"
    assert response.status_code == 200
    assert payload["compiled_count"] == 1
    assert payload["task_id"] != old_task.id


def test_inspiration_compile_recovers_processing_memo_with_missing_task(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    vault = make_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            staging_root=tmp_path / ".piki/task-staging",
            enable_agent_runtime=True,
            agent_model="claude-test",
        ),
        store=store,
    )

    async def fake_query(*, prompt, options):
        yield SimpleNamespace(content=[SimpleNamespace(text="重新整理缺失任务。")], session_id="sess_missing")

    app.state.runner._query_impl = fake_query
    app.state.runner.status = RunnerStatus(True, "Claude Agent SDK available")
    client = TestClient(app)
    memo = client.post(
        "/inspirations",
        json={"vault_path": str(vault), "content": "任务丢失的灵感", "attachments": []},
    ).json()
    mark_inspiration_processing(vault, memo, task_id="task_missing")

    recovered = client.get("/inspirations", params={"vault_path": str(vault)}).json()["items"][0]
    response = client.post("/inspirations/compile", json={"vault_path": str(vault)})

    assert recovered["compile_status"] == "pending"
    assert recovered["compile_task_id"] is None
    assert response.json()["compiled_count"] == 1


def test_inspiration_compile_creates_source_and_async_agent_task(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    vault = make_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(
        ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            staging_root=tmp_path / ".piki/task-staging",
            enable_agent_runtime=True,
            agent_model="claude-test",
        ),
        store=store,
    )
    app.state.task_service.executor.execute = lambda *args, **kwargs: None
    app.state.runner.status = RunnerStatus(True, "Claude Agent SDK available")
    client = TestClient(app)
    created = client.post(
        "/inspirations",
        json={"vault_path": str(vault), "content": "需要进入 wiki 的灵感", "attachments": []},
    ).json()

    response = client.post("/inspirations/compile", json={"vault_path": str(vault)})

    assert response.status_code == 200
    payload = response.json()
    assert payload["compiled_count"] == 1
    assert payload["task_id"].startswith("task_")
    assert payload["source_path"].startswith("raw/sources/inspirations-")
    source_text = (vault / payload["source_path"]).read_text(encoding="utf-8")
    assert created["id"] in source_text
    assert "需要进入 wiki 的灵感" in source_text

    processing_text = (vault / created["path"]).read_text(encoding="utf-8")
    assert 'compile_status: "processing"' in processing_text
    assert f'compile_task_id: "{payload["task_id"]}"' in processing_text
    assert f'source_path: "{payload["source_path"]}"' in processing_text

    store.update_task(payload["task_id"], status=TaskStatus.COMPLETED, summary="done")
    reloaded = client.get("/inspirations", params={"vault_path": str(vault)}).json()["items"][0]
    assert reloaded["compile_status"] == "compiled"
    assert reloaded["compiled_hash"] == created["content_hash"]
