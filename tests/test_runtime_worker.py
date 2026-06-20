import base64
from pathlib import Path

from agent_service.runtime.worker import RuntimeWorker


def make_runtime_worker(tmp_path: Path) -> RuntimeWorker:
    return RuntimeWorker(
        db_path=tmp_path / "agent.sqlite3",
        runtime_config_path=tmp_path / "runtime-config.json",
        staging_root=tmp_path / ".piki/task-staging",
        enable_agent_runtime=False,
    )


def make_vault(tmp_path: Path) -> Path:
    vault = tmp_path / "vault"
    (vault / "wiki").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent rules\n", encoding="utf-8")
    (vault / "purpose.md").write_text("# Purpose\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text("# Index\n", encoding="utf-8")
    return vault


def test_worker_health_and_runtime_config(tmp_path: Path):
    worker = make_runtime_worker(tmp_path)

    health = worker.call("health", {})
    config = worker.call(
        "update_runtime_config",
        {
            "agent_model": "claude-test",
            "anthropic_base_url": "https://gateway.example",
            "api_key": "sk-ant-worker-1234",
        },
    )

    assert health["ok"] is True
    assert health["provider"] == "claude"
    assert config["agent_model"] == "claude-test"
    assert config["anthropic_base_url"] == "https://gateway.example"
    assert config["api_key_configured"] is True
    assert config["api_key_preview"] == "sk-a...1234"
    assert "sk-ant-worker-1234" not in repr(config)
    assert worker.call("get_runtime_config", {})["api_key_source"] == "persisted"


def test_worker_create_task_and_streams_existing_events(tmp_path: Path):
    worker = make_runtime_worker(tmp_path)
    vault = make_vault(tmp_path)

    response = worker.call(
        "create_task",
        {
            "vault_path": str(vault),
            "user_input": "hello",
            "async_mode": False,
        },
    )
    events = list(worker.events(response["task_id"]))
    task = worker.call("get_task", {"task_id": response["task_id"]})

    assert response["status"] == "failed"
    assert task["status"] == "failed"
    assert any(event["type"] == "task.created" for event in events)
    assert any(event["type"] == "task.failed" for event in events)


def test_worker_run_lint_returns_lint_report(tmp_path: Path):
    worker = make_runtime_worker(tmp_path)
    vault = make_vault(tmp_path)

    report = worker.call("run_lint", {"vault_path": str(vault)})

    assert "issues" in report
    assert "fixable_issue_ids" in report
    assert report["generated_at"]


def test_worker_upload_file_buffers_base64_attachment(tmp_path: Path):
    worker = make_runtime_worker(tmp_path)

    response = worker.call(
        "upload_file",
        {
            "filename": "note.md",
            "original_path": "/Users/a99/Downloads/note.md",
            "content_base64": base64.b64encode(b"# note\nhello").decode("ascii"),
        },
    )

    buffered_path = Path(response["buffered_path"])
    assert response["filename"] == "note.md"
    assert response["original_path"] == "/Users/a99/Downloads/note.md"
    assert buffered_path.exists()
    assert buffered_path.read_text(encoding="utf-8") == "# note\nhello"
