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


def test_worker_runtime_config_supports_tingwu_credentials(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    for name in (
        "ALIBABA_CLOUD_ACCESS_KEY_ID",
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET",
        "ALIYUN_ACCESS_KEY_ID",
        "ALIYUN_ACCESS_KEY_SECRET",
        "TINGWU_APP_KEY",
        "TINGWU_REGION_ID",
        "appkey",
        "app_key",
        "region_id",
    ):
        monkeypatch.delenv(name, raising=False)
    worker = make_runtime_worker(tmp_path)

    config = worker.call(
        "update_runtime_config",
        {
            "aliyun_access_key_id": "LTAI-worker-access",
            "aliyun_access_key_secret": "worker-secret-value",
            "tingwu_app_key": "worker-tingwu-app-key",
            "tingwu_region_id": "cn-shanghai",
        },
    )

    assert config["tingwu_configured"] is True
    assert config["tingwu_region_id"] == "cn-shanghai"
    assert config["aliyun_access_key_id_preview"] == "LTAI...cess"
    assert config["aliyun_access_key_secret_configured"] is True
    assert config["tingwu_app_key_preview"] == "work...-key"
    assert "worker-secret-value" not in repr(config)
    assert "worker-tingwu-app-key" not in repr(config)

    cleared = worker.call("update_runtime_config", {"clear_tingwu_config": True})
    assert cleared["tingwu_configured"] is False
    assert cleared["tingwu_region_id"] == "cn-beijing"


def test_worker_emits_event_notifications(tmp_path: Path):
    emitted = []
    worker = RuntimeWorker(
        db_path=tmp_path / "agent.sqlite3",
        runtime_config_path=tmp_path / "runtime-config.json",
        staging_root=tmp_path / ".piki/task-staging",
        enable_agent_runtime=False,
        notify=emitted.append,
    )
    vault = make_vault(tmp_path)

    worker.call(
        "create_task",
        {
            "vault_path": str(vault),
            "user_input": "hello",
            "async_mode": False,
        },
    )

    assert any(event.type == "task.created" for event in emitted)
    assert any(event.type == "task.failed" for event in emitted)


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
