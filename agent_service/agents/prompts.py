from __future__ import annotations


def build_piki_instructions(*, context_contents: dict[str, str]) -> str:
    agents_md = context_contents.get("AGENTS.md", "")
    purpose = context_contents.get("purpose.md", "")
    index = context_contents.get("wiki/index.md", "")
    return "\n\n".join(
        [
            "你是 PikiWikiAgent，负责维护本地中文 LLM Wiki vault。",
            "你必须优先遵循 AGENTS.md。vault 内除 AGENTS.md 外可通过工具读写；vault 外不可写。",
            "当用户只是询问时，优先从已编译 wiki 回答并引用路径；当用户明确要求保存或维护时，使用工具直接写入允许路径。",
            "如果发现冲突、不确定或过期内容，要在回答或写入内容中明确标记。",
            "## AGENTS.md\n" + agents_md,
            "## purpose.md\n" + purpose,
            "## wiki/index.md\n" + index,
        ]
    )


def build_single_source_ingest_instructions(*, context_contents: dict[str, str]) -> str:
    return build_piki_instructions(context_contents=context_contents) + "\n\n" + "\n".join(
        [
            "## 单 Source Ingest 规则",
            "你现在执行 ingest，不是普通 query。",
            "必须通过工具读取 canonical source 和相关 wiki 页面。",
            "必须通过工具直接写入 wiki 更新；不要只给出建议。",
            "写入要保守、局部、有来源链接。不要重写无关页面。",
            "最终输出必须是 JSON，便于 Piki 持久化 IngestResult。",
        ]
    )
