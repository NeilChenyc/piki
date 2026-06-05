from __future__ import annotations

import asyncio
from dataclasses import dataclass

from agent_service.agents.prompts import build_piki_instructions, build_single_source_ingest_instructions
from agent_service.application.events import EventPublisher
from agent_service.config import ServiceConfig
from agent_service.models import AgentResult, EventType, IngestResult, SourceMeta, TaskStatus
from agent_service.runtime.event_mapper import extract_text_delta
from agent_service.runtime.tool_factory import build_sdk_tools
from agent_service.tools import VaultToolRegistry
from agent_service.workflows.ingest import build_ingest_user_prompt, normalize_ingest_output


@dataclass(frozen=True)
class RunnerStatus:
    available: bool
    detail: str


@dataclass(frozen=True)
class SmokeTestResult:
    ok: bool
    output: str | None = None
    error: str | None = None


class PikiWikiAgentRunner:
    def __init__(self):
        try:
            from agents import Agent, RunConfig, Runner, function_tool  # type: ignore
            from agents.models.openai_provider import OpenAIProvider  # type: ignore
        except Exception as exc:  # pragma: no cover - depends on optional package
            self._agent_cls = None
            self._runner_cls = None
            self._run_config_cls = None
            self._function_tool = None
            self._provider_cls = None
            self.status = RunnerStatus(False, f"OpenAI Agents SDK unavailable: {exc}")
        else:
            self._agent_cls = Agent
            self._runner_cls = Runner
            self._run_config_cls = RunConfig
            self._function_tool = function_tool
            self._provider_cls = OpenAIProvider
            self.status = RunnerStatus(True, "OpenAI Agents SDK available")

    def build_agent(self, *, instructions: str, tools: list | None = None):
        if not self.status.available:
            raise RuntimeError(self.status.detail)
        return self._agent_cls(
            name="PikiWikiAgent",
            instructions=instructions,
            tools=tools or [],
        )

    def build_instructions(self, *, context_contents: dict[str, str]) -> str:
        return build_piki_instructions(context_contents=context_contents)

    def can_run(self, config: ServiceConfig) -> bool:
        return self.status.available and config.sdk_runtime_configured

    def run_task(
        self,
        *,
        config: ServiceConfig,
        events: EventPublisher,
        task_id: str,
        conversation_id: str,
        user_input: str,
        context_contents: dict[str, str],
        tool_registry: VaultToolRegistry,
    ) -> AgentResult:
        if not self.can_run(config):
            raise RuntimeError("OpenAI Agents SDK runtime is not configured.")

        instructions = self.build_instructions(context_contents=context_contents)
        tools = self.build_tools(tool_registry)
        agent = self.build_agent(instructions=instructions, tools=tools)
        run_config = self._build_run_config(config, workflow_name="Piki agent task")
        events.emit(
            task_id,
            EventType.SDK_RUN_STARTED,
            {
                "model": config.agent_model,
                "base_url": config.openai_base_url or None,
                "tool_count": len(tools),
                "tracing_enabled": config.tracing_enabled,
            },
        )
        result = self._run_with_optional_streaming(
            agent,
            user_input,
            events=events,
            task_id=task_id,
            max_turns=8,
            run_config=run_config,
            stream_messages=True,
        )
        final_output = _stringify_final_output(result)
        journal_entry = tool_registry.commit_journal_entry(
            conversation_id=conversation_id,
            reason=f"Agent task {task_id}: {user_input[:120]}",
        )
        events.emit(
            task_id,
            EventType.SDK_RUN_COMPLETED,
            {
                "final_output_preview": final_output[:500],
                "journal_entry_id": journal_entry.id if journal_entry else None,
                "affected_files": tool_registry.changed_files,
            },
        )
        return AgentResult(
            status=TaskStatus.COMPLETED,
            summary=final_output[:500] or "SDK agent task completed.",
            answer=final_output,
            affected_files=tool_registry.changed_files,
            journal_entry=journal_entry,
        )

    def run_ingest(
        self,
        *,
        config: ServiceConfig,
        events: EventPublisher,
        task_id: str,
        conversation_id: str,
        source_path: str,
        source_meta: SourceMeta,
        context_contents: dict[str, str],
        tool_registry: VaultToolRegistry,
    ) -> IngestResult:
        if not self.can_run(config):
            raise RuntimeError("OpenAI Agents SDK runtime is not configured.")

        instructions = build_single_source_ingest_instructions(context_contents=context_contents)
        tools = self.build_tools(tool_registry)
        agent = self.build_agent(instructions=instructions, tools=tools)
        ingest_prompt = build_ingest_user_prompt(source_path=source_path, source_meta=source_meta)
        run_config = self._build_run_config(config, workflow_name="Piki single source ingest")
        events.emit(
            task_id,
            EventType.SDK_RUN_STARTED,
            {
                "workflow": "ingest",
                "source_path": source_path,
                "model": config.agent_model,
                "base_url": config.openai_base_url or None,
                "tool_count": len(tools),
                "tracing_enabled": config.tracing_enabled,
            },
        )
        result = self._run_with_optional_streaming(
            agent,
            ingest_prompt,
            events=events,
            task_id=task_id,
            max_turns=12,
            run_config=run_config,
            stream_messages=False,
        )
        raw_output = getattr(result, "final_output", "")
        final_output = _stringify_final_output(result)
        journal_entry = tool_registry.commit_journal_entry(
            conversation_id=conversation_id,
            reason=f"Ingest {source_path}",
        )
        ingest_result = normalize_ingest_output(
            raw_output=raw_output,
            source_meta=source_meta,
            changed_pages=tool_registry.changed_files,
            journal_entry=journal_entry,
        )
        events.emit(
            task_id,
            EventType.SDK_RUN_COMPLETED,
            {
                "workflow": "ingest",
                "source_path": source_path,
                "final_output_preview": final_output[:500],
                "journal_entry_id": journal_entry.id if journal_entry else None,
                "affected_files": tool_registry.changed_files,
            },
        )
        return ingest_result

    def smoke_test(self, *, config: ServiceConfig) -> SmokeTestResult:
        if not self.can_run(config):
            return SmokeTestResult(ok=False, error="OpenAI Agents SDK runtime is not configured.")
        try:
            agent = self.build_agent(
                instructions="Return exactly this Chinese sentence: Piki SDK smoke test ok.",
                tools=[],
            )
            result = self._runner_cls.run_sync(
                agent,
                "请返回：Piki SDK smoke test ok.",
                max_turns=2,
                run_config=self._build_run_config(config, workflow_name="Piki SDK smoke test"),
            )
        except Exception as exc:
            return SmokeTestResult(ok=False, error=str(exc))
        return SmokeTestResult(ok=True, output=_stringify_final_output(result))

    def build_tools(self, registry: VaultToolRegistry) -> list:
        if not self.status.available:
            raise RuntimeError(self.status.detail)
        return build_sdk_tools(self._function_tool, registry)

    def _run_with_optional_streaming(
        self,
        agent,
        user_input: str,
        *,
        events: EventPublisher,
        task_id: str,
        max_turns: int,
        run_config,
        stream_messages: bool,
    ):
        if not hasattr(self._runner_cls, "run_streamed"):
            return self._runner_cls.run_sync(
                agent,
                user_input,
                max_turns=max_turns,
                run_config=run_config,
            )
        return asyncio.run(
            self._run_streamed(
                agent,
                user_input,
                events=events,
                task_id=task_id,
                max_turns=max_turns,
                run_config=run_config,
                stream_messages=stream_messages,
            )
        )

    async def _run_streamed(
        self,
        agent,
        user_input: str,
        *,
        events: EventPublisher,
        task_id: str,
        max_turns: int,
        run_config,
        stream_messages: bool,
    ):
        result = self._runner_cls.run_streamed(
            agent,
            user_input,
            max_turns=max_turns,
            run_config=run_config,
        )
        streamed_text = []
        async for event in result.stream_events():
            if not stream_messages:
                continue
            delta = extract_text_delta(event)
            if not delta:
                continue
            streamed_text.append(delta)
            events.message_delta(
                task_id,
                delta=delta,
                content="".join(streamed_text),
            )
        return result

    def _build_run_config(self, config: ServiceConfig, *, workflow_name: str):
        provider = self._provider_cls(
            api_key=None,
            base_url=config.openai_base_url or None,
            use_responses=True,
        )
        return self._run_config_cls(
            model=config.agent_model,
            model_provider=provider,
            tracing_disabled=not config.tracing_enabled,
            trace_include_sensitive_data=False,
            workflow_name=workflow_name,
        )


def _stringify_final_output(result) -> str:
    output = getattr(result, "final_output", "")
    if output is None:
        return ""
    if isinstance(output, str):
        return output
    if hasattr(output, "model_dump_json"):
        return output.model_dump_json()
    return str(output)

