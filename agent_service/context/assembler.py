from __future__ import annotations

from dataclasses import dataclass, field
import json

from agent_service.models import ContextManifest
from agent_service.models import TaskCreateRequest
from agent_service.vault import Vault, VaultAccessError


BASELINE_FILES = ["AGENTS.md", "purpose.md", "wiki/index.md"]


@dataclass(frozen=True)
class AgentTaskInput:
    user_input: str
    selected_paths: list[str] = field(default_factory=list)
    action_context: dict = field(default_factory=dict)
    conversation_messages: list[dict] = field(default_factory=list)

    def render_prompt(self) -> str:
        payload = {
            "user_input": self.user_input,
            "selected_paths": self.selected_paths,
            "action_context": self.action_context,
            "conversation_context": self.conversation_messages,
        }
        return "\n\n".join(
            [
                "下面是本轮 Piki agent task 的上下文信封。请遵循 action_context；如果没有 action_context，则根据用户输入自主判断是否需要调用工具。",
                "selected_paths 是本轮用户明确提供、允许读取的外部文件路径；不能读取其他 vault 外路径。",
                "conversation_context 是近几轮对话，仅用于理解指代，不默认写入长期记忆。",
                "```json",
                json.dumps(payload, ensure_ascii=False, indent=2),
                "```",
            ]
        )


def assemble_baseline_context(vault: Vault) -> tuple[ContextManifest, dict[str, str]]:
    manifest = ContextManifest()
    contents: dict[str, str] = {}
    for relative_path in BASELINE_FILES:
        try:
            content, truncated = vault.read_text(relative_path)
        except VaultAccessError:
            if relative_path == "purpose.md":
                manifest.missing_optional_files.append(relative_path)
                continue
            raise
        contents[relative_path] = content
        manifest.loaded_files.append(relative_path)
        if truncated:
            manifest.skipped_files.append(
                {"path": relative_path, "reason": "file truncated by max_bytes limit"}
            )
    return manifest, contents


def assemble_agent_task_input(
    *,
    request: TaskCreateRequest,
    conversation_messages: list[dict] | None = None,
) -> AgentTaskInput:
    action_context = dict(request.action_context or {})
    if request.mode == "clear-inbox-item" and "action" not in action_context:
        action_context["action"] = "clear_inbox_item"
        if request.selected_paths:
            action_context.setdefault("target_path", request.selected_paths[0])
    return AgentTaskInput(
        user_input=request.user_input,
        selected_paths=list(request.selected_paths),
        action_context=action_context,
        conversation_messages=list(conversation_messages or []),
    )
