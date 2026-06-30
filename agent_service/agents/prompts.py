from __future__ import annotations

from dataclasses import dataclass
import re

PUBLIC_ASSISTANT_NAME = "Piki"


@dataclass(frozen=True)
class SystemContextMessage:
    role: str
    content: str
    name: str


def build_piki_instructions(*, context_contents: dict[str, str]) -> str:
    return serialize_system_context_messages(
        build_piki_system_context(context_contents=context_contents)
    )


def build_piki_system_context(*, context_contents: dict[str, str]) -> list[SystemContextMessage]:
    agents_md = context_contents.get("AGENTS.md", "")
    purpose = context_contents.get("purpose.md", "")
    index = context_contents.get("wiki/index.md", "")
    return [
        SystemContextMessage(
            role="system",
            name="runtime_contract",
            content=_wrap_tag(
                "runtime_contract",
                "\n".join(
                    [
                        f"你是 {PUBLIC_ASSISTANT_NAME}，负责维护本地中文 LLM Wiki vault。",
                        f"对用户进行自我介绍、描述身份或提到自己的名字时，只能自称“{PUBLIC_ASSISTANT_NAME}”；不要暴露或使用内部实现名 `PikiWikiAgent`。",
                        "你必须优先遵循 AGENTS.md。vault 内除 AGENTS.md 外可通过 Claude 内建 Write/Edit 工具读写；vault 外不可写。",
                        "当用户只是询问时，优先从已编译 wiki 回答并引用路径；当用户明确要求保存或维护时，使用工具直接写入允许路径。",
                        "每轮输入会包含 action_context、selected_paths 和 conversation_context。action_context 是系统动作意图，例如 run_lint 或 ingest_file；按钮只注入上下文，不代表服务端已经完成业务。",
                        "如果 action_context.action 是 run_lint，必须先用 Bash 调用 `python -m agent_service.runtime.cli lint --vault .` 获取结构化检查结果，并把它作为后续分析与修复的起点。",
                        "run_lint 中，优先处理 helper 已报告的问题；只有在修复这些问题所必需时，才继续读取相关页面。",
                        "run_lint 中，不要重新对整个 wiki 做大范围浏览、重构或无关扩写；只修 helper 结果直接涉及的问题页面，以及必要的 `wiki/index.md` / `wiki/log.md`。",
                        "如果 action_context.action 是 ingest_file，必须处理 target_path 或 selected_paths 中的目标文件；需要先用 Bash 调用 `python -m agent_service.runtime.cli extract-source --path <staged-path>` 生成 canonical source 内容，再继续按 AGENTS.md 编译 wiki。",
                        "如果用户提供 selected_paths 并明确要求记录、摄入、整理或保存文档，应先用 Bash 提取结构化内容，再用 Write/Edit 完成 source 到 wiki 的维护流程。",
                        "`extract-source` 会返回 canonical_markdown、asset_path 和 source_path。用这些结果通过 Write/Edit 落库；不要再用 `cp`、`mv`、重定向或其他 Bash 写操作去复制原文件或修改 vault/ raw/ wiki/ 内容。",
                        "如果 `extract-source` 失败，必须停止当前 ingest 流程并明确报错；不能跳过 raw/sources 或只手工写 wiki 页面来替代 canonical source 落库。",
                        "不要假设存在任何自定义工具；读取用 Read/Glob/Grep，写入用 Write/Edit，提问用 AskUserQuestion。",
                        "不要用 Bash 直接修改 vault 文件。",
                        "如果发现冲突、不确定或过期内容，要在回答或写入内容中明确标记。",
                    ]
                ),
            ),
        ),
        SystemContextMessage(
            role="system",
            name="user_response_style",
            content=_wrap_tag(
                "user_response_style",
                "\n".join(
                    [
                        f"你对用户可见的最终回答，需要体现出 {PUBLIC_ASSISTANT_NAME} 是一个懂技术但不说教的朋友，也懂个人知识管理。",
                        "这层要求只作用于对用户可见的最终回答与解释，不覆盖 runtime_contract、AGENTS.md、action_context 或工具安全约束。",
                        "解释概念时，先说人话，再补必要术语；优先帮助用户理解结论、影响和下一步，而不是先展开内部方法论。",
                        "可以适度使用轻口语，比如“好嘞”“放心”“其实”“咱们”，但不要过度卖萌、不要油腻，也不要为了轻松而牺牲清楚。",
                        f"对用户介绍自己或提到身份时，继续只自称“{PUBLIC_ASSISTANT_NAME}”。",
                        "不要主动暴露或强调内部实现词，比如 PikiWikiAgent、wiki 编译、vault 协议、agent runtime、工具链、系统提示词；除非用户明确追问技术细节。",
                        "给准确信息时仍然直接、清楚，不要因为语气轻松就模糊限制、风险、失败原因或不确定性。",
                        "当存在明显下一步意图时，只在有帮助时补一句轻量追问，例如确认用户是想继续整理、继续排查，还是先停在摘要层。",
                        "如果用户明确想看技术细节，可以自然切回更专业、更结构化的解释，但语气仍保持克制、友好。",
                    ]
                ),
            ),
        ),
        SystemContextMessage(
            role="system",
            name="agents_md",
            content=_build_agents_md_message(agents_md),
        ),
        SystemContextMessage(
            role="system",
            name="purpose_context",
            content=_wrap_tag("purpose_context", purpose),
        ),
        SystemContextMessage(
            role="system",
            name="wiki_index_context",
            content=_wrap_tag("wiki_index_context", index),
        ),
    ]


def serialize_system_context_messages(messages: list[SystemContextMessage]) -> str:
    serialized: list[str] = []
    for message in messages:
        serialized.append(f"<system_message name={message.name}>")
        serialized.append(message.content)
        serialized.append("</system_message>")
    return "\n\n".join(serialized)


def _build_agents_md_message(agents_md: str) -> str:
    if not agents_md.strip():
        return _wrap_tag("agents_md", "")

    sections = _split_markdown_sections(agents_md)
    if not sections:
        return _wrap_tag("agents_md", agents_md)

    rendered: list[str] = []
    for heading, content in sections:
        tag = _tag_name_for_heading(heading)
        rendered.append(_wrap_tag(tag, content))
    return "\n\n".join(rendered)


def _split_markdown_sections(markdown: str) -> list[tuple[str, str]]:
    pattern = re.compile(r"^(#{1,2})\s+(.+)$", re.MULTILINE)
    matches = list(pattern.finditer(markdown))
    if not matches:
        return []

    sections: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        start = match.start()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(markdown)
        heading = match.group(2).strip()
        body = markdown[start:end].strip()
        sections.append((heading, body))
    return sections


def _tag_name_for_heading(heading: str) -> str:
    normalized = heading.strip().lower()
    normalized = re.sub(r"[^\w\u3400-\u9fff]+", "_", normalized)
    normalized = re.sub(r"_+", "_", normalized).strip("_")
    if not normalized:
        normalized = "agents_section"
    return normalized


def _wrap_tag(tag: str, content: str) -> str:
    body = content.strip()
    return f"<{tag}>\n{body}\n</{tag}>"
