from __future__ import annotations

from typing import Any

from agent_service.tools import VaultToolRegistry


def build_sdk_tools(function_tool, registry: VaultToolRegistry) -> list:
    @function_tool(
        name_override="read_file",
        description_override="Read a UTF-8 text file from the vault.",
        use_docstring_info=False,
    )
    def read_file(path: str, max_bytes: int = 20000) -> dict[str, Any]:
        return registry.read_file(path, max_bytes=max_bytes).model_dump(mode="json")

    @function_tool(
        name_override="list_files",
        description_override="List files in a vault directory using a glob.",
        use_docstring_info=False,
    )
    def list_files(path: str = ".", glob: str = "*.md", max_results: int = 200) -> dict[str, Any]:
        return registry.list_files(path=path, glob=glob, max_results=max_results).model_dump(mode="json")

    @function_tool(
        name_override="search_text",
        description_override="Search Markdown files in a vault scope for exact text.",
        use_docstring_info=False,
    )
    def search_text(query: str, scope: str = "wiki", max_results: int = 20) -> dict[str, Any]:
        return registry.search_text(query=query, scope=scope, max_results=max_results).model_dump(mode="json")

    @function_tool(
        name_override="parse_markdown",
        description_override="Parse frontmatter, headings, and wikilinks from a Markdown file.",
        use_docstring_info=False,
    )
    def parse_markdown(path: str) -> dict[str, Any]:
        return registry.parse_markdown(path).model_dump(mode="json")

    @function_tool(
        name_override="read_external_text_file",
        description_override="Read and extract text from one external PDF/DOCX/Markdown/TXT file explicitly provided in this task.",
        use_docstring_info=False,
    )
    def read_external_text_file(path: str) -> dict[str, Any]:
        return registry.read_external_text_file(path).model_dump(mode="json")

    @function_tool(
        name_override="write_canonical_source",
        description_override="Convert one allowed external PDF/DOCX/Markdown/TXT file into a canonical raw/sources Markdown source and copy its asset into raw/assets.",
        use_docstring_info=False,
    )
    def write_canonical_source(path: str) -> dict[str, Any]:
        return registry.write_canonical_source(path).model_dump(mode="json")

    @function_tool(
        name_override="write_file",
        description_override="Write a UTF-8 text file inside the vault except AGENTS.md.",
        use_docstring_info=False,
    )
    def write_file(path: str, content: str, reason: str = "") -> dict[str, Any]:
        return registry.write_file(path=path, content=content, reason=reason).model_dump(mode="json")

    @function_tool(
        name_override="append_file",
        description_override="Append UTF-8 text to a file inside the vault except AGENTS.md.",
        use_docstring_info=False,
    )
    def append_file(path: str, content: str, reason: str = "") -> dict[str, Any]:
        return registry.append_file(path=path, content=content, reason=reason).model_dump(mode="json")

    @function_tool(
        name_override="run_lint",
        description_override="Inspect wiki structure and maintenance issues. Use this when action_context.action is run_lint.",
        use_docstring_info=False,
    )
    def run_lint() -> dict[str, Any]:
        return registry.run_lint().model_dump(mode="json")

    @function_tool(
        name_override="apply_lint_fixes",
        description_override="Apply low-risk lint fixes through vault write tools. Only call after run_lint when fixes are appropriate.",
        use_docstring_info=False,
    )
    def apply_lint_fixes(issue_ids: list[str] | None = None) -> dict[str, Any]:
        return registry.apply_lint_fixes(issue_ids=issue_ids).model_dump(mode="json")

    return [
        read_file,
        list_files,
        search_text,
        parse_markdown,
        read_external_text_file,
        write_canonical_source,
        write_file,
        append_file,
        run_lint,
        apply_lint_fixes,
    ]
