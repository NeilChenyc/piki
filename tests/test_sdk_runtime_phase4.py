from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.models import RiskLevel, TaskKind
from agent_service.runtime import PikiWikiAgentRunner
from agent_service.store import SQLiteStore
from agent_service.tools import VaultToolRegistry
from agent_service.vault import Vault


def make_runtime_vault(tmp_path: Path) -> Path:
    vault = tmp_path / "vault"
    (vault / "raw/sources").mkdir(parents=True)
    (vault / "wiki").mkdir(parents=True)
    (vault / "system").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent 规则\n", encoding="utf-8")
    (vault / "purpose.md").write_text("# 目的\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text("# 索引\n", encoding="utf-8")
    (vault / "wiki/log.md").write_text("# 日志\n", encoding="utf-8")
    return vault


def test_direct_write_tools_create_conversation_journal_entry(tmp_path: Path):
    vault_path = make_runtime_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.LOW,
        vault_path=str(vault_path),
        user_input="写入测试",
    )
    tools = VaultToolRegistry(vault=Vault(vault_path), store=store, task_id=task.id)

    result = tools.write_file("wiki/log.md", "# 日志\n\n- SDK 写入测试\n", reason="test")
    journal_entry = tools.commit_journal_entry(conversation_id="conv_test", reason="test")

    assert result.ok
    assert journal_entry is not None
    assert journal_entry.conversation_id == "conv_test"
    assert journal_entry.affected_files == ["wiki/log.md"]
    assert journal_entry.snapshots[0].before_hash != journal_entry.snapshots[0].after_hash
    events = [event.type for event in store.list_events(task.id)]
    assert "tool.started" in events
    assert "tool.finished" in events
    assert "file.changed" in events
    assert "journal_entry.created" in events


def test_write_tools_do_not_journal_system_only_changes_and_block_agents(tmp_path: Path):
    vault_path = make_runtime_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.LOW,
        vault_path=str(vault_path),
        user_input="写入测试",
    )
    tools = VaultToolRegistry(vault=Vault(vault_path), store=store, task_id=task.id)

    system_result = tools.write_file("system/runtime.json", "{}", reason="system state")
    agents_result = tools.write_file("AGENTS.md", "# hacked\n", reason="must fail")
    journal_entry = tools.commit_journal_entry(conversation_id="conv_test", reason="test")

    assert system_result.ok
    assert agents_result.ok is False
    assert "read-only" in agents_result.error
    assert journal_entry is None
    assert (vault_path / "AGENTS.md").read_text(encoding="utf-8") == "# Agent 规则\n"


class FakeRunner:
    @staticmethod
    def run_sync(agent, user_input, *, max_turns, run_config):
        return SimpleNamespace(final_output=f"fake sdk answer: {user_input}", new_items=[], raw_responses=[])


class FakeStreamingResult:
    final_output = "fake streamed answer"

    async def stream_events(self):
        for delta in ["fake ", "streamed ", "answer"]:
            yield SimpleNamespace(
                type="raw_response_event",
                data=SimpleNamespace(type="response.output_text.delta", delta=delta),
            )


class FakeStreamingRunner:
    @staticmethod
    def run_streamed(agent, user_input, *, max_turns, run_config):
        return FakeStreamingResult()


def test_sdk_agent_task_uses_runner_when_configured(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_sdk_runtime=True,
        agent_model="test-model",
        openai_base_url="https://example.test/v1",
    )
    app = create_app(config, store=store)
    app.state.runner._runner_cls = FakeRunner
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "你好",
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "completed"
    assert task["output"]["answer"] == "fake sdk answer: 你好"
    events = client.get(f"/tasks/{response.json()['task_id']}/events").text
    assert "event: sdk.run.started" in events
    assert "event: sdk.run.completed" in events


def test_sdk_agent_task_maps_streaming_text_delta(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_sdk_runtime=True,
        agent_model="test-model",
        openai_base_url="https://example.test/v1",
    )
    app = create_app(config, store=store)
    app.state.runner._runner_cls = FakeStreamingRunner
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "你好",
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    task = client.get(f"/tasks/{task_id}").json()
    assert task["output"]["answer"] == "fake streamed answer"
    events = client.get(f"/tasks/{task_id}/events").text
    assert "event: message.delta" in events
    assert '"delta": "fake "' in events


def test_smoke_test_uses_configured_runner(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    runner = PikiWikiAgentRunner()
    runner._runner_cls = FakeRunner
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_sdk_runtime=True,
        agent_model="test-model",
        openai_base_url="https://example.test/v1",
    )

    result = runner.smoke_test(config=config)

    assert result.ok is True
    assert result.output == "fake sdk answer: 请返回：Piki SDK smoke test ok."
