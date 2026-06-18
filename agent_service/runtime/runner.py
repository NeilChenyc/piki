from __future__ import annotations

import asyncio
import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from types import SimpleNamespace
from typing import Any

from agent_service.agents.prompts import build_piki_instructions
from agent_service.application.events import EventPublisher
from agent_service.application.task_control import TaskRunControl
from agent_service.config import ServiceConfig, anthropic_auth_token
from agent_service.models import AgentResult, EventType, TaskStatus
from agent_service.runtime.event_mapper import (
    extract_text_delta,
    extract_text_snapshot,
    extract_thinking_delta,
    extract_thinking_snapshot,
    map_stream_event,
)
from agent_service.runtime.journal_tracker import JournalTracker
from agent_service.runtime.transcript_mirror import ClaudeTranscriptMirror
from agent_service.store import SQLiteStore
from agent_service.vault import Vault


WRITE_BLOCKLIST_TOKENS = (" >", ">>", "tee ", "mv ", "cp ", "rm ", "sed -i", "perl -i", "git reset", "git checkout --")
ALLOWED_TOOL_NAMES = ["Read", "Write", "Edit", "Glob", "Grep", "Bash", "AskUserQuestion"]
DISALLOWED_TOOL_NAMES = ["WebSearch", "WebFetch", "Task", "TodoWrite", "NotebookRead", "NotebookEdit", "Agent", "MultiEdit"]


@dataclass(frozen=True)
class RunnerStatus:
    available: bool
    detail: str
    provider: str = "claude"


@dataclass(frozen=True)
class SmokeTestResult:
    ok: bool
    output: str | None = None
    error: str | None = None


class _FallbackOptions(SimpleNamespace):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)


class _FallbackHookMatcher(SimpleNamespace):
    def __init__(self, matcher: str | None = None, hooks: list | None = None, timeout: float | None = None):
        super().__init__(matcher=matcher, hooks=hooks or [], timeout=timeout)


class PikiWikiAgentRunner:
    def __init__(self):
        try:
            from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKClient, HookMatcher, query  # type: ignore
        except Exception as exc:  # pragma: no cover - depends on optional package
            self._options_cls = _FallbackOptions
            self._hook_matcher_cls = _FallbackHookMatcher
            self._client_cls = None
            self._sdk_query_impl = None
            self._query_impl = None
            self.status = RunnerStatus(False, f"Claude Agent SDK unavailable: {exc}")
        else:
            self._options_cls = ClaudeAgentOptions
            self._hook_matcher_cls = HookMatcher
            self._client_cls = ClaudeSDKClient
            self._sdk_query_impl = query
            self._query_impl = query
            self.status = RunnerStatus(True, "Claude Agent SDK available")

    def build_instructions(self, *, context_contents: dict[str, str]) -> str:
        return build_piki_instructions(context_contents=context_contents)

    def can_run(self, config: ServiceConfig) -> bool:
        return self.status.available and config.agent_runtime_configured

    def run_task(
        self,
        *,
        config: ServiceConfig,
        store: SQLiteStore,
        events: EventPublisher,
        task_id: str,
        conversation_id: str,
        user_input: str,
        agent_input: str | None,
        context_contents: dict[str, str],
        vault: Vault,
        selected_paths: list[str] | None = None,
        action_context: dict[str, Any] | None = None,
        resume_session_id: str | None = None,
        run_control: TaskRunControl | None = None,
    ) -> AgentResult:
        if not self.can_run(config):
            raise RuntimeError("Claude Agent runtime is not configured.")
        return asyncio.run(
            self._run_task_async(
                config=config,
                store=store,
                events=events,
                task_id=task_id,
                conversation_id=conversation_id,
                user_input=user_input,
                agent_input=agent_input,
                context_contents=context_contents,
                vault=vault,
                selected_paths=selected_paths or [],
                action_context=action_context or {},
                resume_session_id=resume_session_id,
                run_control=run_control,
            )
        )

    def smoke_test(self, *, config: ServiceConfig) -> SmokeTestResult:
        if not self.can_run(config):
            return SmokeTestResult(ok=False, error="Claude Agent runtime is not configured.")

        async def _smoke() -> SmokeTestResult:
            try:
                options = self._options_cls(
                    system_prompt="Return exactly this sentence: Piki Claude smoke test ok.",
                    model=config.agent_model or None,
                    max_turns=1,
                    permission_mode="dontAsk",
                    setting_sources=[],
                    strict_mcp_config=True,
                    include_partial_messages=True,
                    env=self._runtime_env(config),
                    cwd=str(Path.cwd()),
                )
                messages = [message async for message in self._query_impl(prompt="请返回：Piki Claude smoke test ok.", options=options)]
            except Exception as exc:
                return SmokeTestResult(ok=False, error=str(exc))
            output, _, _ = _collect_outputs(messages)
            return SmokeTestResult(ok=True, output=output)

        return asyncio.run(_smoke())

    async def _run_task_async(
        self,
        *,
        config: ServiceConfig,
        store: SQLiteStore,
        events: EventPublisher,
        task_id: str,
        conversation_id: str,
        user_input: str,
        agent_input: str | None,
        context_contents: dict[str, str],
        vault: Vault,
        selected_paths: list[str],
        action_context: dict[str, Any],
        resume_session_id: str | None,
        run_control: TaskRunControl | None,
    ) -> AgentResult:
        if run_control is not None and run_control.cancel_requested:
            return AgentResult(status=TaskStatus.CANCELLED, summary="任务已停止。", answer="")
        staged_files = _stage_selected_paths(config.staging_root, task_id, selected_paths)
        prompt = self._build_prompt(
            base_instructions=self.build_instructions(context_contents=context_contents),
            agent_input=agent_input or user_input,
            staged_files=staged_files,
        )
        tracker = JournalTracker(
            vault=vault,
            store=store,
            events=events,
            task_id=task_id,
            action_context=action_context,
        )
        hooks = self._build_hooks(config=config, events=events, tracker=tracker, staged_files=staged_files)
        max_turns = _resolve_max_turns(config=config, action_context=action_context)
        options = self._options_cls(
            system_prompt=prompt,
            model=config.agent_model or None,
            cwd=str(vault.root),
            add_dirs=[str(entry["staged_path"]) for entry in staged_files] if staged_files else [],
            allowed_tools=ALLOWED_TOOL_NAMES,
            disallowed_tools=DISALLOWED_TOOL_NAMES,
            permission_mode="acceptEdits",
            setting_sources=[],
            strict_mcp_config=True,
            include_partial_messages=True,
            include_hook_events=False,
            hooks=hooks,
            env=self._runtime_env(config),
            max_turns=max_turns,
            continue_conversation=bool(resume_session_id),
            resume=resume_session_id,
            enable_file_checkpointing=config.enable_file_checkpointing,
            thinking={"type": "adaptive", "display": "summarized"},
        )
        events.emit(
            task_id,
            EventType.AGENT_RUN_STARTED,
            {
                "provider": config.runtime_provider,
                "model": config.agent_model or None,
                "tool_names": ALLOWED_TOOL_NAMES,
                "staged_file_count": len(staged_files),
                "resume_session_id": resume_session_id,
                "max_turns": max_turns,
            },
        )
        messages = []
        streamed_text = ""
        streamed_thinking = ""

        def emit_text_snapshot(snapshot: str) -> None:
            nonlocal streamed_text
            if not snapshot or not snapshot.startswith(streamed_text) or snapshot == streamed_text:
                return
            delta = snapshot[len(streamed_text):]
            events.message_delta(task_id, delta=delta, content=delta)
            streamed_text = snapshot

        def emit_text_delta(delta: str) -> None:
            nonlocal streamed_text
            if not delta:
                return
            events.message_delta(task_id, delta=delta, content=delta)
            streamed_text += delta

        def emit_thinking_snapshot(snapshot: str) -> None:
            nonlocal streamed_thinking
            if not snapshot or not snapshot.startswith(streamed_thinking) or snapshot == streamed_thinking:
                return
            delta = snapshot[len(streamed_thinking):]
            events.trace_delta(task_id, delta=delta, content=delta)
            streamed_thinking = snapshot

        def emit_thinking_delta(delta: str) -> None:
            nonlocal streamed_thinking
            if not delta:
                return
            events.trace_delta(task_id, delta=delta, content=delta)
            streamed_thinking += delta

        transcript_stop = asyncio.Event()
        transcript_mirror = ClaudeTranscriptMirror(
            claude_config_dir=config.claude_config_dir,
            cwd=vault.root,
            task_id=task_id,
            user_input=user_input,
            events=events,
            emit_message_snapshot=emit_text_snapshot,
            emit_trace_snapshot=emit_thinking_snapshot,
            resume_session_id=resume_session_id,
        )
        transcript_task = asyncio.create_task(transcript_mirror.run(transcript_stop))
        run_task = asyncio.current_task()
        if run_control is not None and run_task is not None:
            run_control.bind_async_task(asyncio.get_running_loop(), run_task)
        try:
            if self._client_cls is not None and self._query_impl is self._sdk_query_impl:
                client = self._client_cls(options=options)
                await client.connect(user_input)
                try:
                    async for message in client.receive_messages():
                        if run_control is not None and run_control.cancel_requested:
                            await _stop_active_sdk_task(client=client, messages=messages)
                            raise asyncio.CancelledError
                        _consume_stream_message(
                            events=events,
                            messages=messages,
                            message=message,
                            task_id=task_id,
                            transcript_mirror_active=transcript_mirror.active,
                            emit_text_snapshot=emit_text_snapshot,
                            emit_text_delta=emit_text_delta,
                            emit_thinking_snapshot=emit_thinking_snapshot,
                            emit_thinking_delta=emit_thinking_delta,
                        )
                        if _is_terminal_result_message(message):
                            break
                        if _is_stopped_task_notification(message):
                            if run_control is not None:
                                run_control.request_cancel()
                            raise asyncio.CancelledError
                finally:
                    await client.disconnect()
            else:
                async for message in self._query_impl(prompt=user_input, options=options):
                    if run_control is not None and run_control.cancel_requested:
                        raise asyncio.CancelledError
                    _consume_stream_message(
                        events=events,
                        messages=messages,
                        message=message,
                        task_id=task_id,
                        transcript_mirror_active=transcript_mirror.active,
                        emit_text_snapshot=emit_text_snapshot,
                        emit_text_delta=emit_text_delta,
                        emit_thinking_snapshot=emit_thinking_snapshot,
                        emit_thinking_delta=emit_thinking_delta,
                    )
        except asyncio.CancelledError:
            transcript_stop.set()
            await transcript_task
            return AgentResult(status=TaskStatus.CANCELLED, summary="任务已停止。", answer=streamed_text.strip() or None)
        except Exception as exc:
            transcript_stop.set()
            await transcript_task
            return AgentResult(status=TaskStatus.FAILED, summary=str(exc), answer=str(exc))
        transcript_stop.set()
        await transcript_task

        final_output, result_message, session_id = _collect_outputs(messages)
        if run_control is not None and run_control.cancel_requested:
            return AgentResult(status=TaskStatus.CANCELLED, summary="任务已停止。", answer=streamed_text.strip() or final_output or None)
        pending_input = _pending_input_payload(result_message)
        journal_entry = tracker.commit(
            conversation_id=conversation_id,
            reason=f"Claude agent task {task_id}: {user_input[:120]}",
        )
        status = TaskStatus.COMPLETED
        summary = final_output[:500] or "Claude agent task completed."
        if pending_input:
            status = TaskStatus.INPUT_REQUIRED
            summary = pending_input.get("prompt") or "Claude 需要你的输入。"
        elif tracker.illegal_attempts:
            status = TaskStatus.FAILED
            summary = tracker.illegal_attempts[0]
        elif tracker.is_lint_task and tracker.lint_result is None:
            status = TaskStatus.FAILED
            summary = "Lint helper did not return a structured lint result."
        elif getattr(result_message, "is_error", False):
            status = TaskStatus.FAILED
            summary = _result_error_text(result_message) or "Claude agent task failed."
        events.emit(
            task_id,
            EventType.AGENT_RUN_COMPLETED,
            {
                "provider": config.runtime_provider,
                "final_output_preview": final_output[:500],
                "session_id": session_id,
                "journal_entry_id": journal_entry.id if journal_entry else None,
                "affected_files": tracker.changed_files,
                "pending_input": pending_input,
            },
        )
        return AgentResult(
            status=status,
            summary=summary,
            answer=final_output if status == TaskStatus.COMPLETED else None,
            lint_result=tracker.lint_result,
            affected_files=tracker.changed_files,
            journal_entry=journal_entry,
            session_id=session_id,
            checkpoint_id=None,
            pending_input=pending_input,
        )

    def _build_prompt(self, *, base_instructions: str, agent_input: str, staged_files: list[dict[str, Any]]) -> str:
        extra = [
            "你运行在 Piki 的 Claude Agent runtime 中。",
            "可用工具只有 Claude 内建工具：Read、Write、Edit、Glob、Grep、Bash、AskUserQuestion。",
            "不要假设有自定义工具。需要 lint 或 source 提取时，请使用 Bash 调用 `python -m agent_service.runtime.cli ...`。",
            "Bash 只用于读取、分析、提取和输出 JSON，不要用 Bash 直接写 vault 文件；所有 vault 修改都必须通过 Write 或 Edit。",
            "如果你需要用户确认或补充，请调用 AskUserQuestion。",
            "调用 Read/Write/Edit/Glob/Grep 时，优先使用相对当前 vault 根目录的路径，例如 `wiki/index.md`；不要使用 `/home/user/vault/...` 这类占位绝对路径。",
            "同一个文件读取成功后，优先复用你已经看到的内容，除非确实需要重新确认；不要因为路径风格不同而重复读取同一份文档。",
        ]
        if staged_files:
            extra.extend(
                [
                    "下面这些 staged files 是本轮允许读取的外部资料；不要读取其他 vault 外路径。",
                    "```json",
                    json.dumps(staged_files, ensure_ascii=False, indent=2),
                    "```",
                ]
            )
        return "\n\n".join([base_instructions, *extra, agent_input])

    def _build_hooks(self, *, config: ServiceConfig, events: EventPublisher, tracker: JournalTracker, staged_files: list[dict[str, Any]]):
        staged_roots = {Path(entry["staged_path"]).resolve() for entry in staged_files}
        protected_roots = {
            config.claude_config_dir.expanduser().resolve(),
            config.staging_root.expanduser().resolve(),
            config.db_path.expanduser().resolve(),
        }

        async def pre_tool_use(data, tool_output, context):
            tool_name = data["tool_name"]
            tool_input = data.get("tool_input", {})
            if tracker.is_lint_task:
                lint_decision = _lint_tool_permission_decision(
                    tracker=tracker,
                    tool_name=tool_name,
                    tool_input=tool_input,
                )
                if lint_decision is not None:
                    if lint_decision.get("permissionDecision") == "deny":
                        tracker.note_illegal_attempt(str(lint_decision.get("permissionDecisionReason") or ""))
                    return lint_decision
            if tool_name == "AskUserQuestion":
                payload = _pending_input_from_tool_input(tool_input)
                events.emit(tracker.task_id, EventType.AGENT_INPUT_REQUESTED, payload)
                return {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "defer",
                    "permissionDecisionReason": payload.get("prompt") or "Waiting for user input.",
                }
            if tool_name == "Bash":
                command = str(tool_input.get("command") or "")
                if _bash_writes_files(command):
                    reason = "Bash cannot modify files in Piki runtime. Use Write/Edit for vault changes."
                    tracker.note_illegal_attempt(reason)
                    return {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": reason,
                    }
            if tool_name in {"Write", "Edit", "MultiEdit"}:
                target = str(tool_input.get("file_path") or tool_input.get("path") or "")
                allowed, reason = _validate_write_path(target, tracker.vault.root, protected_roots, staged_roots)
                if not allowed:
                    tracker.note_illegal_attempt(reason)
                    return {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": reason,
                    }
                tracker.before_write(target)
            return {}

        async def post_tool_use(data, tool_output, context):
            tool_name = data["tool_name"]
            tool_input = data.get("tool_input", {})
            tool_use_id = str(data.get("tool_use_id") or "")
            actual_tool_output = data.get("tool_response", tool_output)
            if tracker.is_lint_task and tool_name == "Bash":
                command = str(tool_input.get("command") or "")
                lint_payload = _extract_lint_payload(command=command, tool_output=actual_tool_output)
                if lint_payload is not None:
                    tracker.record_lint_helper(command=command, payload=lint_payload)
            if tool_name in {"Write", "Edit", "MultiEdit"}:
                target = str(tool_input.get("file_path") or tool_input.get("path") or "")
                tracker.after_write(target)
            if tracker.is_lint_task and tracker.lint_helper_completed and tool_name in {"Read", "Write", "Edit", "MultiEdit"}:
                tracker.clear_lint_policy_violations()
            payload = {
                "tool": tool_name,
                "tool_use_id": tool_use_id,
                "title": _tool_title(tool_name),
                "summary": _tool_summary(tool_name, tool_input, actual_tool_output),
                "source_path": _tool_path(tool_name, tool_input),
                "category": _tool_category(tool_name),
                "status": "completed",
            }
            events.tool_finished(tracker.task_id, tool_name, payload)
            if tool_name == "AskUserQuestion":
                events.emit(tracker.task_id, EventType.AGENT_INPUT_RESOLVED, {"tool": tool_name})
            return {}

        return {
            "PreToolUse": [self._hook_matcher_cls(hooks=[pre_tool_use])],
            "PostToolUse": [self._hook_matcher_cls(hooks=[post_tool_use])],
        }

    def _runtime_env(self, config: ServiceConfig) -> dict[str, str]:
        config.claude_config_dir.mkdir(parents=True, exist_ok=True)
        config.staging_root.mkdir(parents=True, exist_ok=True)
        repo_root = Path(__file__).resolve().parents[2]
        pythonpath_entries = [str(repo_root)]
        existing_pythonpath = os.environ.get("PYTHONPATH", "").strip()
        if existing_pythonpath:
            pythonpath_entries.append(existing_pythonpath)
        env = dict(
            CLAUDE_CONFIG_DIR=str(config.claude_config_dir.resolve()),
            CLAUDE_CODE_DISABLE_AUTO_MEMORY="1",
            PIKI_AGENT_RUNTIME_PROVIDER=config.runtime_provider,
            PIKI_REPO_ROOT=str(repo_root),
            PYTHONPATH=os.pathsep.join(pythonpath_entries),
        )
        if config.anthropic_base_url:
            env["ANTHROPIC_BASE_URL"] = config.anthropic_base_url
        token = anthropic_auth_token()
        if token:
            # Claude-compatible gateways vary between API_KEY and AUTH_TOKEN naming.
            env["ANTHROPIC_AUTH_TOKEN"] = token
            env["ANTHROPIC_API_KEY"] = token
        return env


def _stage_selected_paths(staging_root: Path, task_id: str, selected_paths: list[str]) -> list[dict[str, Any]]:
    if not selected_paths:
        return []
    target_root = staging_root.expanduser().resolve() / task_id
    if target_root.exists():
        shutil.rmtree(target_root)
    target_root.mkdir(parents=True, exist_ok=True)
    staged = []
    for index, raw_path in enumerate(selected_paths):
        source = Path(raw_path).expanduser().resolve()
        target = target_root / f"{index:02d}-{source.name}"
        if source.is_file():
            shutil.copy2(source, target)
        elif source.is_dir():
            shutil.copytree(source, target)
        else:
            raise FileNotFoundError(f"Selected path not found: {source}")
        staged.append(
            {
                "original_path": str(source),
                "staged_path": str(target.resolve()),
                "name": source.name,
                "is_dir": source.is_dir(),
            }
        )
    return staged


def _validate_write_path(path: str, vault_root: Path, protected_roots: set[Path], staged_roots: set[Path]) -> tuple[bool, str]:
    target = Path(path).expanduser().resolve()
    try:
        relative = str(target.relative_to(vault_root))
    except ValueError:
        return False, f"Claude may only write inside the vault: {path}"
    if relative == "AGENTS.md":
        return False, "AGENTS.md is read-only."
    for protected in protected_roots | staged_roots:
        if protected == target or protected in target.parents:
            return False, f"Claude may not write protected runtime paths: {path}"
    return True, ""


def _resolve_max_turns(*, config: ServiceConfig, action_context: dict[str, Any]) -> int:
    action = str(action_context.get("action") or "").strip()
    if action in {"run_lint", "ingest_file"}:
        return max(1, config.agent_max_turns)
    if config.agent_max_turns_configured:
        return max(1, config.agent_max_turns)
    return 12


def _bash_writes_files(command: str) -> bool:
    normalized = f" {command.strip()} "
    return any(token in normalized for token in WRITE_BLOCKLIST_TOKENS)


def _lint_tool_permission_decision(*, tracker: JournalTracker, tool_name: str, tool_input: dict[str, Any]) -> dict[str, str] | None:
    if tool_name == "AskUserQuestion":
        return None
    if not tracker.lint_helper_completed:
        if tool_name == "Bash" and _is_lint_helper_command(str(tool_input.get("command") or "")):
            return None
        return {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "run_lint must start by calling the lint helper and using its structured result.",
        }

    if tool_name == "Bash":
        return {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "run_lint already has a helper result; continue with targeted Read/Write/Edit only.",
        }
    if tool_name in {"Glob", "Grep"}:
        return {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "run_lint may not do broad Glob/Grep after the helper result is available.",
        }
    if tool_name in {"Read", "Write", "Edit", "MultiEdit"}:
        target = str(tool_input.get("file_path") or tool_input.get("path") or "")
        if target and tracker.lint_allows_path(target):
            return None
        return {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "run_lint may only touch pages directly implicated by the lint result plus wiki/index.md and wiki/log.md.",
        }
    return None


def _is_lint_helper_command(command: str) -> bool:
    normalized = " ".join(command.strip().split())
    return normalized.startswith("python -m agent_service.runtime.cli lint --vault .")


def _extract_lint_payload(*, command: str, tool_output: Any) -> dict[str, Any] | None:
    if not _is_lint_helper_command(command):
        return None
    payload_text = _tool_output_text(tool_output)
    if not payload_text:
        return None
    return _parse_json_payload(payload_text)


def _tool_output_text(tool_output: Any) -> str:
    if isinstance(tool_output, dict):
        stdout = str(tool_output.get("stdout") or "").strip()
        if stdout:
            return stdout
        content = tool_output.get("content")
        if isinstance(content, str) and content.strip():
            return content.strip()
    if isinstance(tool_output, str):
        return tool_output.strip()
    return ""


def _parse_json_payload(payload_text: str) -> dict[str, Any] | None:
    candidates = [payload_text.strip()]
    start = payload_text.find("{")
    end = payload_text.rfind("}")
    if start != -1 and end != -1 and start < end:
        candidates.append(payload_text[start:end + 1].strip())
    for candidate in candidates:
        if not candidate:
            continue
        try:
            payload = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict) and "issues" in payload and "generated_at" in payload:
            return payload
    return None


def _tool_title(tool_name: str) -> str:
    return {
        "Read": "正在阅读 Wiki",
        "Glob": "正在浏览文件",
        "Grep": "正在搜索内容",
        "Write": "正在写入 Wiki",
        "Edit": "正在写入 Wiki",
        "Bash": "正在运行命令",
        "AskUserQuestion": "等待你的输入",
    }.get(tool_name, "正在调用工具")


def _tool_category(tool_name: str) -> str:
    return {
        "Read": "read",
        "Glob": "read",
        "Grep": "read",
        "Write": "write",
        "Edit": "write",
        "Bash": "command",
        "AskUserQuestion": "input",
    }.get(tool_name, "tool")


def _tool_summary(tool_name: str, tool_input: dict[str, Any], tool_output: Any) -> str:
    if tool_name in {"Read", "Write", "Edit"}:
        path = tool_input.get("file_path") or tool_input.get("path")
        return str(path or tool_name)
    if tool_name in {"Glob", "Grep"}:
        path = tool_input.get("path")
        return str(path or tool_name)
    if tool_name == "Bash":
        return str(tool_input.get("command") or "")[:160]
    if tool_name == "AskUserQuestion":
        return str(tool_input.get("question") or tool_input.get("prompt") or "")[:160]
    return tool_name


def _tool_path(tool_name: str, tool_input: dict[str, Any]) -> str | None:
    if tool_name in {"Read", "Write", "Edit"}:
        path = tool_input.get("file_path") or tool_input.get("path")
        return str(path) if path else None
    if tool_name in {"Glob", "Grep"}:
        path = tool_input.get("path")
        return str(path) if path else None
    return None


def _pending_input_from_tool_input(tool_input: dict[str, Any]) -> dict[str, Any]:
    return {
        "tool": "AskUserQuestion",
        "prompt": tool_input.get("question") or tool_input.get("prompt") or "Claude 需要你的输入。",
        "options": tool_input.get("options") or tool_input.get("choices") or [],
        "raw_input": tool_input,
    }


def _pending_input_payload(result_message) -> dict[str, Any] | None:
    deferred = getattr(result_message, "deferred_tool_use", None)
    if deferred is None or getattr(deferred, "name", "") != "AskUserQuestion":
        return None
    tool_input = getattr(deferred, "input", {}) or {}
    payload = _pending_input_from_tool_input(tool_input)
    payload["tool_use_id"] = getattr(deferred, "id", None)
    return payload


def _consume_stream_message(
    *,
    events: EventPublisher,
    messages: list[Any],
    message: Any,
    task_id: str,
    transcript_mirror_active: bool,
    emit_text_snapshot,
    emit_text_delta,
    emit_thinking_snapshot,
    emit_thinking_delta,
) -> None:
    messages.append(message)
    if transcript_mirror_active:
        return
    stop_reason = str(getattr(message, "stop_reason", "") or "")

    text_snapshot = extract_text_snapshot(message)
    text_delta = extract_text_delta(message)
    if stop_reason == "tool_use":
        if text_snapshot:
            emit_thinking_snapshot(text_snapshot)
        else:
            emit_thinking_delta(text_delta)
    elif text_snapshot:
        emit_text_snapshot(text_snapshot)
    else:
        emit_text_delta(text_delta)

    thinking_snapshot = extract_thinking_snapshot(message)
    if thinking_snapshot:
        emit_thinking_snapshot(thinking_snapshot)
    else:
        emit_thinking_delta(extract_thinking_delta(message))

    _emit_system_progress(events=events, task_id=task_id, message=message)
    for mapped in map_stream_event(message):
        if mapped.event_type == "tool.started":
            events.tool_started(task_id, mapped.payload.get("tool", ""), mapped.payload)
        else:
            events.trace_event(
                task_id,
                kind=mapped.payload.get("kind", "event"),
                title=mapped.payload.get("title", "Agent 事件"),
                summary=mapped.payload.get("summary", ""),
                tool=mapped.payload.get("tool"),
                category=mapped.payload.get("category"),
                status=mapped.payload.get("status"),
            )


def _collect_outputs(messages: list[Any]) -> tuple[str, Any | None, str | None]:
    text_parts: list[str] = []
    latest_assistant_text = ""
    result_message = None
    session_id = None
    for message in messages:
        if getattr(message, "session_id", None):
            session_id = getattr(message, "session_id", None)
        content = getattr(message, "content", None)
        if isinstance(content, list):
            assistant_text_parts: list[str] = []
            for block in content:
                if hasattr(block, "text") and getattr(block, "text"):
                    text = str(getattr(block, "text"))
                    text_parts.append(text)
                    assistant_text_parts.append(text)
            if assistant_text_parts:
                latest_assistant_text = "".join(assistant_text_parts).strip()
        if message.__class__.__name__ == "ResultMessage" or hasattr(message, "deferred_tool_use") or hasattr(message, "result"):
            result_message = message
    result_text = latest_assistant_text
    if result_message is not None:
        result_value = str(getattr(result_message, "result", "") or "").strip()
        if result_value:
            result_text = result_value
    if not result_text:
        result_text = "".join(text_parts).strip()
    return result_text, result_message, session_id


def _emit_system_progress(*, events: EventPublisher, task_id: str, message: Any) -> None:
    class_name = message.__class__.__name__
    if class_name == "TaskStartedMessage":
        description = str(getattr(message, "description", "") or "").strip()
        events.progress(task_id, "task_started", "正在思考", description or "Agent 已启动。")
        return
    if class_name == "TaskProgressMessage":
        description = str(getattr(message, "description", "") or "").strip()
        last_tool_name = str(getattr(message, "last_tool_name", "") or "").strip()
        title = _progress_title_from_tool(last_tool_name)
        detail = description or _tool_summary(last_tool_name or "task_progress", {}, None)
        events.progress(task_id, "task_progress", title, detail)
        return
    if class_name == "TaskNotificationMessage":
        summary = str(getattr(message, "summary", "") or "").strip()
        status = str(getattr(message, "status", "") or "").strip()
        events.trace_event(
            task_id,
            kind="task_notification",
            title="阶段完成" if status == "completed" else "阶段更新",
            summary=summary,
            category="model",
            status=status or "completed",
        )


def _progress_title_from_tool(tool_name: str) -> str:
    return {
        "Read": "正在阅读 Wiki",
        "Glob": "正在浏览文件",
        "Grep": "正在搜索内容",
        "Write": "正在写入 Wiki",
        "Edit": "正在写入 Wiki",
        "Bash": "正在转换文档",
        "AskUserQuestion": "等待你的输入",
    }.get(tool_name, "正在思考")


def _result_error_text(result_message) -> str:
    if result_message is None:
        return ""
    errors = getattr(result_message, "errors", None) or []
    if errors:
        return str(errors[0])
    result = getattr(result_message, "result", None)
    return str(result or "")


def _is_stopped_task_notification(message: Any) -> bool:
    return message.__class__.__name__ == "TaskNotificationMessage" and str(getattr(message, "status", "") or "") == "stopped"


def _is_terminal_result_message(message: Any) -> bool:
    if message.__class__.__name__ == "ResultMessage":
        return True
    if hasattr(message, "result"):
        return True
    deferred = getattr(message, "deferred_tool_use", None)
    return deferred is not None


async def _stop_active_sdk_task(*, client, messages: list[Any]) -> None:
    task_id = _latest_sdk_task_id(messages)
    if task_id:
        await client.stop_task(task_id)
    else:
        await client.interrupt()


def _latest_sdk_task_id(messages: list[Any]) -> str | None:
    for message in reversed(messages):
        if getattr(message, "__class__", None).__name__ in {"TaskStartedMessage", "TaskProgressMessage", "TaskNotificationMessage"}:
            task_id = getattr(message, "task_id", None)
            if isinstance(task_id, str) and task_id:
                return task_id
    return None
