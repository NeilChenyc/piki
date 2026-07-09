import asyncio
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from agent_service.app import create_app
from agent_service.config import ServiceConfig
from agent_service.runtime import PikiWikiAgentRunner, RunnerStatus
from agent_service.runtime.transcript_mirror import ClaudeTranscriptMirror
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
        assert isinstance(prompt, list)
        assert len(prompt) == 1
        assert prompt[0]["role"] == "user"
        assert "conversation_context" in prompt[0]["content"]
        assert "<runtime_contract>" in options.system_prompt
        assert "<user_response_style>" in options.system_prompt
        assert options.system_prompt.index("<runtime_contract>") < options.system_prompt.index("<user_response_style>")
        assert "<agent_规则>" in options.system_prompt
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


def test_default_query_max_turns_is_50(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)

    async def fake_query(*, prompt, options):
        assert options.max_turns == 50
        yield SimpleNamespace(content=[SimpleNamespace(text="hello")], session_id="sess_turns_default")
        yield _result_message(session_id="sess_turns_default", result="hello")

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

    response = client.post("/tasks", json={"vault_path": str(vault_path), "user_input": "你好"})

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "completed"


def test_explicit_agent_max_turns_overrides_default_query_limit(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    monkeypatch.setenv("PIKI_AGENT_MAX_TURNS", "45")

    async def fake_query(*, prompt, options):
        assert options.max_turns == 45
        yield SimpleNamespace(content=[SimpleNamespace(text="hello")], session_id="sess_turns_override")
        yield _result_message(session_id="sess_turns_override", result="hello")

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

    response = client.post("/tasks", json={"vault_path": str(vault_path), "user_input": "你好"})

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "completed"


def test_runtime_uses_staged_parent_dir_for_single_file_access(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    selected_file = tmp_path / "upload.md"
    selected_file.write_text("# 上传文档\n\n内容", encoding="utf-8")

    async def fake_query(*, prompt, options):
        allowed_dirs = {Path(path) for path in options.add_dirs}
        assert vault_path in allowed_dirs
        staged_only_dirs = [path for path in allowed_dirs if path != vault_path]
        assert len(staged_only_dirs) == 1
        allowed_dir = staged_only_dirs[0]
        assert allowed_dir.is_dir()
        assert allowed_dir.name.startswith("task_")
        assert [path.name for path in allowed_dir.iterdir()] == ["00-upload.md"]
        yield SimpleNamespace(content=[SimpleNamespace(text="已读取上传文档。")], session_id="sess_staged_dir")
        yield _result_message(session_id="sess_staged_dir", result="已读取上传文档。")

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "处理这个上传文件",
            "selected_paths": [str(selected_file)],
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "completed"


def test_runtime_disables_partial_and_thinking_streams_for_sdk_compatibility(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)

    async def fake_query(*, prompt, options):
        assert options.include_partial_messages is False
        assert getattr(options, "thinking", None) == {"type": "disabled"}
        yield SimpleNamespace(content=[SimpleNamespace(text="稳定输出")], session_id="sess_no_thinking")
        yield _result_message(session_id="sess_no_thinking", result="稳定输出")

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

    response = client.post("/tasks", json={"vault_path": str(vault_path), "user_input": "你好"})

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "completed"


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
    assert task["output"]["journal_entry"]["snapshots"] == []
    assert task["output"]["affected_files"] == ["wiki/log.md"]
    events = client.get(f"/tasks/{task_id}/events").text
    assert "event: tool.finished" in events
    assert "event: file.changed" in events
    assert "event: journal.created" in events


def test_run_lint_action_returns_deterministic_lint_result(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)

    async def fake_query(*, prompt, options):
        raise AssertionError("run_lint should not enter the agent runtime")

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "Run vault lint.",
            "action_context": {"action": "run_lint"},
        },
    )

    assert response.status_code == 200
    task_id = response.json()["task_id"]
    task = client.get(f"/tasks/{task_id}").json()
    assert task["status"] == "completed"
    assert task["output"]["lint_result"]["scanned_files"] >= 2
    assert task["output"]["action_context"]["action"] == "run_lint"
    events = client.get(f"/tasks/{task_id}/events").text
    assert "event: lint.started" in events
    assert "event: lint.completed" in events


def test_run_lint_action_uses_deterministic_executor_even_when_runtime_is_configured(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)

    async def fake_query(*, prompt, options):
        raise AssertionError("run_lint should not enter the agent runtime")

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

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
    assert task["status"] == "completed"
    assert task["output"]["lint_result"]["scanned_files"] >= 2


def test_run_lint_natural_language_prompt_uses_deterministic_executor_when_runtime_is_configured(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)

    async def fake_query(*, prompt, options):
        raise AssertionError("natural-language lint intent should not enter the agent runtime")

    client = make_configured_client(tmp_path, monkeypatch, fake_query)

    response = client.post(
        "/tasks",
        json={
            "vault_path": str(vault_path),
            "user_input": "请帮我做一次知识库健康检查。",
        },
    )

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "completed"
    assert task["output"]["action_context"]["action"] == "run_lint"
    assert task["output"]["lint_result"]["scanned_files"] >= 2


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


def test_sdk_client_runtime_stops_after_result_message_even_if_stream_stays_open(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")

    class FakeClient:
        def __init__(self, *, options):
            self.options = options

        async def connect(self, user_input):
            return None

        async def disconnect(self):
            return None

        async def receive_messages(self):
            yield SimpleNamespace(
                content=[SimpleNamespace(text="最终答案")],
                session_id="sess_sdk_client",
            )
            yield _result_message(session_id="sess_sdk_client", result="最终答案")
            while True:
                yield SimpleNamespace(event={"type": "noop"})

    store = SQLiteStore(tmp_path / "agent.sqlite3")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_agent_runtime=True,
        agent_model="claude-test",
    )
    app = create_app(config, store=store)
    app.state.runner._client_cls = FakeClient
    app.state.runner._query_impl = app.state.runner._sdk_query_impl
    app.state.runner.status = RunnerStatus(True, "Claude Agent SDK available")
    client = TestClient(app)

    response = client.post("/tasks", json={"vault_path": str(vault_path), "user_input": "你好"})

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "completed"
    assert task["output"]["answer"] == "最终答案"


def test_sdk_client_runtime_sends_string_prompt_to_connect(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    captured_prompts: list[object] = []

    class FakeClient:
        def __init__(self, *, options):
            self.options = options

        async def connect(self, user_input):
            captured_prompts.append(user_input)
            return None

        async def disconnect(self):
            return None

        async def receive_messages(self):
            yield SimpleNamespace(
                content=[SimpleNamespace(text="最终答案")],
                session_id="sess_sdk_prompt",
            )
            yield _result_message(session_id="sess_sdk_prompt", result="最终答案")

    store = SQLiteStore(tmp_path / "agent.sqlite3")
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_agent_runtime=True,
        agent_model="claude-test",
    )
    app = create_app(config, store=store)
    app.state.runner._client_cls = FakeClient
    app.state.runner._query_impl = app.state.runner._sdk_query_impl
    app.state.runner.status = RunnerStatus(True, "Claude Agent SDK available")
    client = TestClient(app)

    response = client.post("/tasks", json={"vault_path": str(vault_path), "user_input": "你好"})

    assert response.status_code == 200
    assert len(captured_prompts) == 1
    assert isinstance(captured_prompts[0], str)
    assert "你好" in captured_prompts[0]


def test_sdk_client_runtime_fails_after_stream_idle_timeout(tmp_path: Path, monkeypatch):
    vault_path = make_runtime_vault(tmp_path)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    monkeypatch.setenv("PIKI_AGENT_STREAM_IDLE_TIMEOUT_SECONDS", "1")

    class FakeClient:
        def __init__(self, *, options):
            self.options = options

        async def connect(self, user_input):
            return None

        async def disconnect(self):
            return None

        async def receive_messages(self):
            while True:
                await asyncio.sleep(60)
                yield SimpleNamespace(event={"type": "noop"})

    runner = PikiWikiAgentRunner()
    runner._client_cls = FakeClient
    runner._query_impl = runner._sdk_query_impl
    runner.status = RunnerStatus(True, "Claude Agent SDK available")

    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        runtime_config_path=tmp_path / "runtime-config.json",
        claude_config_dir=tmp_path / ".piki/claude-runtime",
        enable_agent_runtime=True,
        agent_model="claude-test",
    )
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    app = create_app(config, store=store)
    app.state.runner._client_cls = FakeClient
    app.state.runner._query_impl = app.state.runner._sdk_query_impl
    app.state.runner.status = RunnerStatus(True, "Claude Agent SDK available")
    client = TestClient(app)

    started_at = time.monotonic()
    response = client.post("/tasks", json={"vault_path": str(vault_path), "user_input": "你好"})
    elapsed = time.monotonic() - started_at

    assert response.status_code == 200
    task = client.get(f"/tasks/{response.json()['task_id']}").json()
    assert task["status"] == "failed"
    assert "idle timeout" in task["summary"]
    assert elapsed < 10


def test_transcript_mirror_matches_prompt_when_user_content_is_block_list(tmp_path: Path):
    project_root = tmp_path / ".piki" / "claude-runtime" / "projects"
    project_dir = project_root / "-tmp-vault"
    project_dir.mkdir(parents=True)
    transcript_path = project_dir / "session.jsonl"
    transcript_path.write_text(
        "\n".join(
            [
                json.dumps({"type": "queue-operation"}),
                json.dumps({"type": "queue-operation"}),
                json.dumps(
                    {
                        "type": "user",
                        "timestamp": "2026-06-30T06:46:37.600000+00:00",
                        "message": {
                            "content": [
                                {"type": "text", "text": "system preface"},
                                {"type": "text", "text": "hi"},
                            ]
                        },
                    },
                    ensure_ascii=False,
                ),
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    mirror = ClaudeTranscriptMirror(
        claude_config_dir=tmp_path / ".piki" / "claude-runtime",
        cwd=Path("/tmp/vault"),
        task_id="task_test",
        user_input="hi",
        events=SimpleNamespace(),
    )

    assert mirror._matches_prompt(transcript_path) is True


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


def test_runtime_env_exports_current_python_for_agent_cli_helpers(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")

    runner = PikiWikiAgentRunner()
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        enable_agent_runtime=True,
        agent_model="claude-test",
        staging_root=tmp_path / ".piki/task-staging",
        claude_config_dir=tmp_path / ".piki/claude-runtime",
    )

    env = runner._runtime_env(config)

    assert env["PIKI_RUNTIME_PYTHON"] == sys.executable


def test_runtime_env_exports_anthropic_auth_token_alias(tmp_path: Path, monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("ANTHROPIC_AUTH_TOKEN", "packy-token")

    runner = PikiWikiAgentRunner()
    config = ServiceConfig(
        db_path=tmp_path / "agent.sqlite3",
        runtime_config_path=tmp_path / "runtime-config.json",
        enable_agent_runtime=True,
        agent_model="claude-test",
        anthropic_base_url="https://www.packyapi.com",
    )

    env = runner._runtime_env(config)

    assert env["ANTHROPIC_BASE_URL"] == "https://www.packyapi.com"
    assert env["ANTHROPIC_AUTH_TOKEN"] == "packy-token"
    assert env["ANTHROPIC_API_KEY"] == "packy-token"
