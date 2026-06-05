import asyncio
import json
from pathlib import Path
from types import SimpleNamespace

from agents.tool_context import ToolContext
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


class FakeToolStreamResult:
    final_output = "tool streamed answer"

    async def stream_events(self):
        yield SimpleNamespace(
            type="run_item_stream_event",
            name="tool_called",
            item=SimpleNamespace(raw_item=SimpleNamespace(name="read_file")),
        )
        yield SimpleNamespace(
            type="run_item_stream_event",
            name="tool_output",
            item=SimpleNamespace(raw_item=SimpleNamespace(name="read_file"), output="read ok"),
        )
        yield SimpleNamespace(
            type="run_item_stream_event",
            name="reasoning_item_created",
            item=SimpleNamespace(),
        )


class FakeToolStreamingRunner:
    @staticmethod
    def run_streamed(agent, user_input, *, max_turns, run_config):
        return FakeToolStreamResult()


class FakeTimeoutResult:
    final_output = ""
    cancelled = False

    async def stream_events(self):
        await asyncio.sleep(2)
        yield SimpleNamespace(
            type="raw_response_event",
            data=SimpleNamespace(type="response.output_text.delta", delta="late"),
        )

    def cancel(self):
        self.cancelled = True


class FakeTimeoutRunner:
    @staticmethod
    def run_streamed(agent, user_input, *, max_turns, run_config):
        return FakeTimeoutResult()


class FakeLintToolRunner:
    @staticmethod
    def run_sync(agent, user_input, *, max_turns, run_config):
        tools = {tool.name: tool for tool in agent.tools}

        async def run_tool():
            tool = tools["run_lint"]
            raw = await tool.on_invoke_tool(
                ToolContext(
                    context=None,
                    tool_name="run_lint",
                    tool_call_id="fake_run_lint",
                    tool_arguments="{}",
                ),
                "{}",
            )
            data = raw if isinstance(raw, dict) else json.loads(raw)
            if not data.get("ok"):
                raise RuntimeError(data.get("error") or "run_lint failed")
            return data["payload"]

        lint_result = asyncio.run(run_tool())
        return SimpleNamespace(
            final_output=f"lint completed: {len(lint_result['issues'])} issues",
            new_items=[],
            raw_responses=[],
        )


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
    assert task["output"]["answer"].startswith("fake sdk answer:")
    assert '"user_input": "你好"' in task["output"]["answer"]
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
    assert "event: agent.trace.delta" in events
    assert '"delta": "fake "' in events


def test_sdk_agent_task_maps_tool_stream_events_to_trace(tmp_path: Path, monkeypatch):
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
    app.state.runner._runner_cls = FakeToolStreamingRunner
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "孟岩说了什么",
        },
    )

    assert response.status_code == 200
    events = client.get(f"/tasks/{response.json()['task_id']}/events").text
    assert "event: agent.trace.event" in events
    assert '"kind": "tool_started"' in events
    assert '"title": "正在阅读 Wiki"' in events
    assert '"kind": "tool_finished"' in events
    assert '"kind": "reasoning"' in events


def test_sdk_agent_query_timeout_falls_back_to_read_only_query(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    (vault_path / "wiki/mengyan.md").write_text("# 孟岩\n\n孟岩在讨论 AI 和知识库。\n", encoding="utf-8")
    (vault_path / "wiki/index.md").write_text("# 索引\n\n- [[mengyan|孟岩]]\n", encoding="utf-8")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_sdk_runtime=True,
        agent_model="test-model",
        openai_base_url="https://example.test/v1",
        agent_task_timeout_seconds=1,
    )
    app = create_app(config, store=store)
    app.state.runner._runner_cls = FakeTimeoutRunner
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "孟岩说了什么",
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    task = client.get(f"/tasks/{task_id}").json()
    assert task["status"] == "completed"
    assert "孟岩" in task["summary"]
    events = client.get(f"/tasks/{task_id}/events").text
    assert "sdk_timeout_fallback" in events
    assert '"title": "正在阅读 Wiki"' in events
    assert "event: task.completed" in events


def test_sdk_agent_idle_timeout_falls_back_to_read_only_query(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    (vault_path / "wiki/mengyan.md").write_text("# 孟岩\n\n孟岩在讨论 AI 和知识库。\n", encoding="utf-8")
    (vault_path / "wiki/index.md").write_text("# 索引\n\n- [[mengyan|孟岩]]\n", encoding="utf-8")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_sdk_runtime=True,
        agent_model="test-model",
        openai_base_url="https://example.test/v1",
        agent_task_timeout_seconds=60,
        agent_stream_idle_timeout_seconds=1,
    )
    app = create_app(config, store=store)
    app.state.runner._runner_cls = FakeTimeoutRunner
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "孟岩说了什么",
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    task = client.get(f"/tasks/{task_id}").json()
    assert task["status"] == "completed"
    events = client.get(f"/tasks/{task_id}/events").text
    assert "Agent stream idle timed out after 1 seconds" in events
    assert "event: query.completed" in events


def test_sdk_agent_idle_timeout_for_small_talk_does_not_query_wiki(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_sdk_runtime=True,
        agent_model="test-model",
        openai_base_url="https://example.test/v1",
        agent_task_timeout_seconds=60,
        agent_stream_idle_timeout_seconds=1,
    )
    app = create_app(config, store=store)
    app.state.runner._runner_cls = FakeTimeoutRunner
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "hi",
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    task = client.get(f"/tasks/{task_id}").json()
    assert task["status"] == "completed"
    assert "你好，我在" in task["summary"]
    assert task["output"]["fallback"] == "small_talk"
    events = client.get(f"/tasks/{task_id}/events").text
    assert "Agent stream idle timed out after 1 seconds" in events
    assert "event: query.completed" not in events
    assert "event: task.failed" not in events
    assert "event: task.completed" in events


def test_sdk_agent_required_task_timeout_marks_failed(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    selected_file = tmp_path / "source.md"
    selected_file.write_text("# Source\n", encoding="utf-8")
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_sdk_runtime=True,
        agent_model="test-model",
        openai_base_url="https://example.test/v1",
        agent_task_timeout_seconds=1,
    )
    app = create_app(config, store=store)
    app.state.runner._runner_cls = FakeTimeoutRunner
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "帮我记录这个文档",
            "selected_paths": [str(selected_file)],
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "failed"
    assert "Agent task timed out after 1 seconds" in task["summary"]


def test_run_lint_action_context_uses_agent_tool(tmp_path: Path, monkeypatch):
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
    app.state.runner._runner_cls = FakeLintToolRunner
    client = TestClient(app)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "Run vault lint.",
            "action_context": {"action": "run_lint"},
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["task_kind"] == "agent"
    assert task["status"] == "completed"
    assert task["output"]["action_context"] == {"action": "run_lint"}
    assert task["output"]["lint_result"]["scanned_files"] >= 2
    events = client.get(f"/tasks/{response.json()['task_id']}/events").text
    assert "event: tool.started" in events
    assert '"tool": "run_lint"' in events
    assert "event: lint.completed" in events


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
