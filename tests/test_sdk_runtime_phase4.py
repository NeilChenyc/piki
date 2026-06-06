import json
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.runtime import PikiWikiAgentRunner, RunnerStatus
from agent_service.runtime.runner import _collect_outputs
from agent_service.store import SQLiteStore


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


def make_configured_client(tmp_path: Path, monkeypatch, fake_query) -> TestClient:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_agent_runtime=True,
        agent_model="claude-test",
    )
    app = create_app(config, store=store)
    app.state.runner._query_impl = fake_query
    app.state.runner.status = RunnerStatus(True, "Claude Agent SDK available")
    return TestClient(app)


def _result_message(*, session_id: str, result: str = "", deferred_tool_use=None, is_error: bool = False, errors=None):
    return type(
        "ResultMessage",
        (),
        {
            "session_id": session_id,
            "result": result,
            "deferred_tool_use": deferred_tool_use,
            "is_error": is_error,
            "errors": errors,
        },
    )()


def test_claude_agent_task_uses_provider_neutral_events(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)

    async def fake_query(*, prompt, options):
        assert options.setting_sources == []
        assert options.strict_mcp_config is True
        assert options.env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] == "1"
        yield SimpleNamespace(
            event={"type": "content_block_delta", "delta": {"text": "hello "}},
            session_id="sess_1",
        )
        yield SimpleNamespace(
            content=[SimpleNamespace(text="hello from Claude")],
            session_id="sess_1",
        )
        yield _result_message(session_id="sess_1", result="hello from Claude")

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

    response = client.post("/tasks", json={"vault_path": str(vault_path), "user_input": "你好"})

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "completed"
    assert task["output"]["answer"] == "hello from Claude"
    assert task["output"]["session_id"] == "sess_1"
    events = client.get(f"/tasks/{response.json()['task_id']}/events").text
    assert "event: agent.run.started" in events
    assert "event: message.delta" in events
    assert "event: agent.run.completed" in events


def test_claude_hooks_record_write_and_create_single_journal(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)

    async def fake_query(*, prompt, options):
        tool_input = {"file_path": str(vault_path / "wiki/log.md")}
        for matcher in options.hooks["PreToolUse"]:
            for hook in matcher.hooks:
                await hook({"tool_name": "Write", "tool_input": tool_input}, None, None)
        (vault_path / "wiki/log.md").write_text("# 日志\n\n- Claude 写入测试\n", encoding="utf-8")
        for matcher in options.hooks["PostToolUse"]:
            for hook in matcher.hooks:
                await hook({"tool_name": "Write", "tool_input": tool_input}, {"ok": True}, None)
        yield SimpleNamespace(content=[SimpleNamespace(text="已写入 wiki/log.md")], session_id="sess_write")
        yield _result_message(session_id="sess_write", result="已写入 wiki/log.md")

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

    response = client.post("/tasks", json={"vault_path": str(vault_path), "user_input": "记录一下"})

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    task = client.get(f"/tasks/{task_id}").json()
    assert task["status"] == "completed"
    assert task["output"]["journal_entry"] is not None
    assert task["output"]["affected_files"] == ["wiki/log.md"]
    events = client.get(f"/tasks/{task_id}/events").text
    assert "event: tool.finished" in events
    assert "event: file.changed" in events
    assert "event: journal.created" in events


def test_claude_blocks_writes_to_agents_md(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)

    async def fake_query(*, prompt, options):
        for matcher in options.hooks["PreToolUse"]:
            for hook in matcher.hooks:
                result = await hook(
                    {"tool_name": "Write", "tool_input": {"file_path": str(vault_path / "AGENTS.md")}},
                    None,
                    None,
                )
                assert result["permissionDecision"] == "deny"
        yield _result_message(session_id="sess_block", result="denied")

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

    response = client.post("/tasks", json={"vault_path": str(vault_path), "user_input": "修改协议"})

    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "failed"
    assert "AGENTS.md is read-only" in task["summary"]
    assert (vault_path / "AGENTS.md").read_text(encoding="utf-8") == "# Agent 规则\n"


def test_claude_input_request_can_resume_session(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)

    async def fake_query(*, prompt, options):
        if getattr(options, "resume", None):
            yield SimpleNamespace(content=[SimpleNamespace(text="好的，我已经继续执行。")], session_id="sess_resume")
            yield _result_message(session_id="sess_resume", result="好的，我已经继续执行。")
            return
        for matcher in options.hooks["PreToolUse"]:
            for hook in matcher.hooks:
                result = await hook(
                    {
                        "tool_name": "AskUserQuestion",
                        "tool_input": {"question": "要写进 wiki 吗？", "options": ["是", "否"]},
                    },
                    None,
                    None,
                )
                assert result["permissionDecision"] == "defer"
        yield _result_message(
            session_id="sess_resume",
            result="需要你的输入",
            deferred_tool_use=SimpleNamespace(
                id="toolu_ask",
                name="AskUserQuestion",
                input={"question": "要写进 wiki 吗？", "options": ["是", "否"]},
            ),
        )

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

    response = client.post("/tasks", json={"vault_path": str(vault_path), "user_input": "帮我整理一下"})
    task_id = response.json()["task_id"]
    waiting = client.get(f"/tasks/{task_id}").json()
    assert waiting["status"] == "input_required"
    assert waiting["output"]["pending_input"]["prompt"] == "要写进 wiki 吗？"

    resumed = client.post(f"/tasks/{task_id}/input", json={"message": "是"})
    assert resumed.status_code == 200
    finished = client.get(f"/tasks/{task_id}").json()
    assert finished["status"] == "completed"
    assert finished["output"]["answer"] == "好的，我已经继续执行。"


def test_smoke_test_uses_claude_query(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    runner = PikiWikiAgentRunner()
    runner._query_impl = lambda *, prompt, options: _single_message_stream("Piki Claude smoke test ok.")
    runner.status = RunnerStatus(True, "Claude Agent SDK available")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_agent_runtime=True,
        agent_model="claude-test",
    )

    result = runner.smoke_test(config=config)

    assert result.ok is True
    assert result.output == "Piki Claude smoke test ok."


async def _single_message_stream(text: str):
    yield SimpleNamespace(content=[SimpleNamespace(text=text)], session_id="sess_smoke")
    yield _result_message(session_id="sess_smoke", result=text)


def test_collect_outputs_prefers_final_result_over_tool_preamble():
    messages = [
        SimpleNamespace(
            content=[SimpleNamespace(text="让我先查一下。")],
            stop_reason="tool_use",
            session_id="sess_collect",
        ),
        SimpleNamespace(
            content=[SimpleNamespace(text="真正的最终答案")],
            stop_reason="end_turn",
            session_id="sess_collect",
        ),
        _result_message(session_id="sess_collect", result="真正的最终答案"),
    ]

    output, result_message, session_id = _collect_outputs(messages)

    assert output == "真正的最终答案"
    assert result_message is not None
    assert session_id == "sess_collect"


def test_runtime_env_allows_cli_module_from_vault_cwd(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    vault_path = make_runtime_vault(tmp_path)
    source = tmp_path / "sample.md"
    source.write_text("# Sample\nhello", encoding="utf-8")

    runner = PikiWikiAgentRunner()
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_agent_runtime=True,
        agent_model="claude-test",
        staging_root=tmp_path / ".piki/task-staging",
        claude_config_dir=tmp_path / ".piki/claude-runtime",
    )
    env = os.environ.copy()
    env.update(runner._runtime_env(config))

    result = subprocess.run(
        [sys.executable, "-m", "agent_service.runtime.cli", "extract-source", "--path", str(source)],
        cwd=vault_path,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout)
    assert payload["source_path"].startswith("raw/sources/")
    assert "canonical_markdown" in payload
