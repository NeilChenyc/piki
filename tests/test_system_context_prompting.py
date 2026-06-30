from __future__ import annotations

from pathlib import Path

from agent_service.agents.prompts import (
    PUBLIC_ASSISTANT_NAME,
    SystemContextMessage,
    build_piki_system_context,
    serialize_system_context_messages,
)
from agent_service.context.assembler import AgentTaskInput


def test_system_context_wraps_agents_markdown_with_semantic_tags():
    context_contents = {
        "AGENTS.md": "# Writing Rules\nKeep wiki links stable.\n\n## Ingest Workflow\nNormalize first.",
        "purpose.md": "Build a local-first wiki.",
        "wiki/index.md": "# Index\n- Home",
    }

    messages = build_piki_system_context(context_contents=context_contents)

    assert [message.role for message in messages] == ["system", "system", "system", "system", "system"]
    assert messages[0].name == "runtime_contract"
    assert "<runtime_contract>" in messages[0].content
    assert messages[1].name == "user_response_style"
    assert "<user_response_style>" in messages[1].content
    assert messages[2].name == "agents_md"
    assert "<writing_rules>" in messages[2].content
    assert "<ingest_workflow>" in messages[2].content
    assert "Keep wiki links stable." in messages[2].content
    assert messages[3].name == "purpose_context"
    assert "<purpose_context>" in messages[3].content
    assert messages[4].name == "wiki_index_context"
    assert "<wiki_index_context>" in messages[4].content


def test_runtime_contract_exposes_public_identity_as_piki_only():
    context_contents = {
        "AGENTS.md": "",
        "purpose.md": "",
        "wiki/index.md": "",
    }

    messages = build_piki_system_context(context_contents=context_contents)
    runtime_contract = messages[0].content

    assert f"你是 {PUBLIC_ASSISTANT_NAME}" in runtime_contract
    assert "只能自称“Piki”" in runtime_contract
    assert "不要暴露或使用内部实现名 `PikiWikiAgent`" in runtime_contract


def test_user_response_style_is_layered_after_runtime_contract_without_overriding_it():
    context_contents = {
        "AGENTS.md": "",
        "purpose.md": "",
        "wiki/index.md": "",
    }

    messages = build_piki_system_context(context_contents=context_contents)

    assert messages[0].name == "runtime_contract"
    assert messages[1].name == "user_response_style"
    style = messages[1].content

    assert "对用户可见的最终回答" in style
    assert "先说人话，再补必要术语" in style
    assert "可以适度使用轻口语" in style
    assert "不要主动暴露" in style
    assert "PikiWikiAgent" in style


def test_user_response_style_encodes_relaxed_but_professional_friend_voice():
    context_contents = {
        "AGENTS.md": "",
        "purpose.md": "",
        "wiki/index.md": "",
    }

    messages = build_piki_system_context(context_contents=context_contents)
    style = messages[1].content

    assert "懂技术但不说教的朋友" in style
    assert "给准确信息时仍然直接、清楚" in style
    assert "只在有帮助时补一句轻量追问" in style


def test_runtime_contract_forbids_manual_ingest_fallback_when_extract_source_fails():
    context_contents = {
        "AGENTS.md": "",
        "purpose.md": "",
        "wiki/index.md": "",
    }

    messages = build_piki_system_context(context_contents=context_contents)
    runtime_contract = messages[0].content

    assert "如果 `extract-source` 失败" in runtime_contract
    assert "必须停止当前 ingest 流程并明确报错" in runtime_contract
    assert "不能跳过 raw/sources" in runtime_contract


def test_system_context_serialization_preserves_order_and_content():
    messages = [
        SystemContextMessage(role="system", content="<runtime_contract>alpha</runtime_contract>", name="runtime_contract"),
        SystemContextMessage(role="system", content="<agents_md>beta</agents_md>", name="agents_md"),
    ]

    serialized = serialize_system_context_messages(messages)

    assert serialized.index("<runtime_contract>alpha</runtime_contract>") < serialized.index("<agents_md>beta</agents_md>")
    assert "name=runtime_contract" in serialized
    assert "name=agents_md" in serialized


def test_agent_task_input_only_renders_user_envelope():
    task_input = AgentTaskInput(
        user_input="Summarize this source",
        selected_paths=["/tmp/source.md"],
        action_context={"action": "ingest_file"},
        conversation_messages=[{"role": "assistant", "content": "Prior answer"}],
    )

    prompt = task_input.render_prompt()

    assert "Summarize this source" in prompt
    assert "ingest_file" in prompt
    assert "/tmp/source.md" in prompt
    assert "conversation_context" in prompt
    assert "AGENTS.md" not in prompt
