from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from agent_service.models import (
    IngestResult,
    JournalEntry,
    SourceMeta,
)
from agent_service.vault import Vault, VaultAccessError


SOURCE_PATH_PATTERN = re.compile(r"raw/sources/[^\s\"'`]+\.md")
INGEST_HINT_PATTERN = re.compile(r"(^|\s)/(wiki:ingest|wiki:compile)\b")
FRONTMATTER_PATTERN = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
TITLE_PATTERN = re.compile(r"^#\s+(.+)$", re.MULTILINE)


class IngestWorkflowError(ValueError):
    pass


def detect_ingest_source_path(user_input: str) -> str | None:
    paths = SOURCE_PATH_PATTERN.findall(user_input)
    has_hint = bool(INGEST_HINT_PATTERN.search(user_input))
    unique_paths = sorted(set(paths))
    if not has_hint and not unique_paths:
        return None
    if len(unique_paths) != 1:
        raise IngestWorkflowError("Single source ingest requires exactly one raw/sources/*.md path.")
    return unique_paths[0]


def validate_canonical_source(vault: Vault, source_path: str) -> str:
    relative = source_path.strip()
    if not relative.startswith("raw/sources/") or not relative.endswith(".md"):
        raise IngestWorkflowError("Ingest source must be a Markdown file under raw/sources/.")
    try:
        path = vault.resolve_path(relative)
    except VaultAccessError as exc:
        raise IngestWorkflowError(str(exc)) from exc
    if not path.exists() or not path.is_file():
        raise IngestWorkflowError(f"Ingest source not found: {relative}")
    return str(path.relative_to(vault.root))


def read_source_meta(vault: Vault, source_path: str) -> SourceMeta:
    content, _ = vault.read_text(source_path, max_bytes=200000)
    frontmatter = _parse_frontmatter(content)
    title = str(frontmatter.get("title") or _extract_title(content) or Path(source_path).stem)
    return SourceMeta(
        path=source_path,
        title=title,
        format=str(frontmatter.get("format") or "markdown"),
        hash=frontmatter.get("hash"),
        source_path=str(frontmatter.get("source_path") or source_path),
    )


def build_ingest_user_prompt(*, source_path: str, source_meta: SourceMeta) -> str:
    return f"""请执行单 Source ingest workflow。

目标 canonical source：`{source_path}`
来源标题：{source_meta.title}

必须遵守：
1. 先用工具读取 `{source_path}`、`wiki/index.md`，并搜索/读取明显相关的既有 wiki 页面。
2. 创建或更新一个 `wiki/sources/` 下的中文来源页。页面必须引用 `{source_path}`。
3. 对明确相关的 `wiki/concepts/`、`wiki/entities/`、`wiki/domains/` 做保守、局部更新；不要为了凑数量创建页面。
4. 只有当这个来源显著改变跨来源理解时，才创建或更新 `wiki/synthesis/`。
5. 更新 `wiki/index.md`。
6. 追加 `wiki/log.md`，记录本次 ingest、来源、主要变更、冲突或不确定性。
7. 冲突、过期说法、低置信度内容必须明确写出，不要静默覆盖。
8. 所有普通 wiki 页面文件名、标题和正文使用中文；骨架目录和 `index.md`、`log.md` 保持英文。

完成所有必要写入后，最后只返回一个 JSON 对象，字段为：
`source_title`, `source_meta`, `summary`, `entities`, `concepts`, `claims`, `conflicts`, `changed_pages`, `next_actions`。
"""


def normalize_ingest_output(
    *,
    raw_output: Any,
    source_meta: SourceMeta,
    changed_pages: list[str],
    journal_entry: JournalEntry | None,
) -> IngestResult:
    data = _coerce_output_dict(raw_output)
    changed = sorted(set(data.get("changed_pages") or changed_pages))
    return IngestResult(
        source_title=str(data.get("source_title") or source_meta.title),
        source_meta=SourceMeta.model_validate(data.get("source_meta") or source_meta.model_dump()),
        summary=str(data.get("summary") or _fallback_summary(source_meta, changed)),
        entities=data.get("entities") or [],
        concepts=data.get("concepts") or [],
        claims=data.get("claims") or [],
        conflicts=data.get("conflicts") or [],
        changed_pages=changed,
        journal_entry=journal_entry,
        next_actions=data.get("next_actions") or [],
    )


def _coerce_output_dict(raw_output: Any) -> dict[str, Any]:
    if isinstance(raw_output, IngestResult):
        return raw_output.model_dump(mode="json")
    if isinstance(raw_output, dict):
        return raw_output
    if hasattr(raw_output, "model_dump"):
        return raw_output.model_dump(mode="json")
    if isinstance(raw_output, str):
        stripped = raw_output.strip()
        if stripped.startswith("```"):
            stripped = re.sub(r"^```(?:json)?\s*", "", stripped)
            stripped = re.sub(r"\s*```$", "", stripped)
        try:
            parsed = json.loads(stripped)
        except json.JSONDecodeError:
            return {"summary": stripped}
        if isinstance(parsed, dict):
            return parsed
    return {"summary": str(raw_output or "")}


def _parse_frontmatter(content: str) -> dict[str, Any]:
    match = FRONTMATTER_PATTERN.search(content)
    if not match:
        return {}
    data: dict[str, Any] = {}
    for line in match.group(1).splitlines():
        if ":" not in line:
            continue
        key, raw_value = line.split(":", 1)
        value = raw_value.strip()
        try:
            data[key.strip()] = json.loads(value)
        except json.JSONDecodeError:
            data[key.strip()] = value.strip('"')
    return data


def _extract_title(content: str) -> str:
    match = TITLE_PATTERN.search(content)
    return match.group(1).strip() if match else ""


def _fallback_summary(source_meta: SourceMeta, changed_pages: list[str]) -> str:
    if changed_pages:
        return f"已将 {source_meta.title} 编译进 wiki，修改 {len(changed_pages)} 个页面。"
    return f"已处理来源 {source_meta.title}。"
