from __future__ import annotations

import hashlib
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from agent_service.models import (
    LintIssue,
    LintIssueKind,
    LintResult,
    LintSeverity,
    utc_now_iso,
)
from agent_service.vault import Vault


WIKILINK_PATTERN = re.compile(r"\[\[([^\]]+)\]\]")
HEADING_PATTERN = re.compile(r"^#\s+(.+)$", re.MULTILINE)
FRONTMATTER_TITLE_PATTERN = re.compile(r"^title:\s*(.+)$", re.MULTILINE)
CHECK_AFTER_PATTERN = re.compile(r"check_after:\s*[\"']?(\d{4}-\d{2}-\d{2})[\"']?")
BRACKETED_CONCEPT_PATTERN = re.compile(r"[「《]([^」》]{2,30})[」》]")


@dataclass(frozen=True)
class LintPage:
    path: str
    title: str
    content: str
    wikilinks: list[str]


def run_wiki_lint(vault: Vault) -> LintResult:
    pages = _load_pages(vault)
    path_map = {page.path: page for page in pages}
    stem_map = _build_stem_map(pages)
    index_text = path_map.get("wiki/index.md").content if "wiki/index.md" in path_map else ""
    incoming: dict[str, set[str]] = defaultdict(set)
    issues: list[LintIssue] = []

    for page in pages:
        if not page.content.startswith("---\n"):
            issues.append(
                _issue(
                    kind=LintIssueKind.MISSING_FRONTMATTER,
                    severity=LintSeverity.WARNING,
                    path=page.path,
                    message="页面缺少 YAML frontmatter。",
                )
            )
        if not HEADING_PATTERN.search(_body_without_frontmatter(page.content)):
            issues.append(
                _issue(
                    kind=LintIssueKind.MISSING_HEADING,
                    severity=LintSeverity.WARNING,
                    path=page.path,
                    message="页面缺少一级标题。",
                )
            )
        for target in page.wikilinks:
            resolved = _resolve_wikilink(target, path_map, stem_map)
            if resolved is None:
                issues.append(
                    _issue(
                        kind=LintIssueKind.BROKEN_LINK,
                        severity=LintSeverity.ERROR,
                        path=page.path,
                        message=f"页面包含断裂 wikilink：[[{target}]]。",
                        details={"target": target},
                    )
                )
            else:
                incoming[resolved.path].add(page.path)
        check_after = _extract_check_after(page.content)
        if check_after and check_after <= date.today():
            issues.append(
                _issue(
                    kind=LintIssueKind.STALE_PAGE,
                    severity=LintSeverity.WARNING,
                    path=page.path,
                    message=f"页面已到复查日期：{check_after.isoformat()}。",
                    details={"check_after": check_after.isoformat()},
                )
            )
        if len(_body_without_frontmatter(page.content).strip()) < 80 and page.path not in {"wiki/index.md", "wiki/log.md"}:
            issues.append(
                _issue(
                    kind=LintIssueKind.THIN_PAGE,
                    severity=LintSeverity.INFO,
                    path=page.path,
                    message="页面内容偏薄，可能需要补充来源、上下文或链接。",
                )
            )

    for page in pages:
        if page.path in {"wiki/index.md", "wiki/log.md"}:
            continue
        if not incoming.get(page.path):
            issues.append(
                _issue(
                    kind=LintIssueKind.ORPHAN_PAGE,
                    severity=LintSeverity.INFO,
                    path=page.path,
                    message="页面没有入链。",
                )
            )
        if not _index_mentions_page(index_text, page):
            link_path = page.path.removeprefix("wiki/").removesuffix(".md")
            issues.append(
                _issue(
                    kind=LintIssueKind.MISSING_INDEX_ENTRY,
                    severity=LintSeverity.WARNING,
                    path=page.path,
                    message="页面没有出现在 wiki/index.md 中。",
                    details={"link_path": link_path, "title": page.title},
                    fixable=True,
                )
            )

    title_map: dict[str, list[str]] = defaultdict(list)
    for page in pages:
        title_map[page.title].append(page.path)
    for title, paths in title_map.items():
        if title and len(paths) > 1:
            for path in paths:
                issues.append(
                    _issue(
                        kind=LintIssueKind.DUPLICATE_TITLE,
                        severity=LintSeverity.WARNING,
                        path=path,
                        message=f"页面标题重复：{title}。",
                        details={"title": title, "paths": paths},
                    )
                )

    concept_counts = Counter()
    for page in pages:
        concept_counts.update(BRACKETED_CONCEPT_PATTERN.findall(page.content))
    for concept, count in concept_counts.items():
        if count < 2 or concept in stem_map:
            continue
        issues.append(
            _issue(
                kind=LintIssueKind.KNOWLEDGE_GAP,
                severity=LintSeverity.INFO,
                path="wiki/index.md",
                message=f"反复出现但没有独立页面的重要概念：{concept}。",
                details={"concept": concept, "count": count},
            )
        )

    issue_counts = Counter(issue.kind.value for issue in issues)
    return LintResult(
        generated_at=utc_now_iso(),
        scanned_files=len(pages),
        issues=issues,
        issue_counts=dict(sorted(issue_counts.items())),
        fixable_issue_ids=[issue.id for issue in issues if issue.fixable],
    )

def _load_pages(vault: Vault) -> list[LintPage]:
    wiki_root = vault.resolve_path("wiki")
    pages = []
    for path in sorted(wiki_root.rglob("*.md")):
        content = path.read_text(encoding="utf-8", errors="replace")
        relative = str(path.relative_to(vault.root))
        pages.append(
            LintPage(
                path=relative,
                title=_extract_title(path, content),
                content=content,
                wikilinks=sorted(set(_normalize_target(match) for match in WIKILINK_PATTERN.findall(content))),
            )
        )
    return pages


def _issue(
    *,
    kind: LintIssueKind,
    severity: LintSeverity,
    path: str,
    message: str,
    details: dict | None = None,
    fixable: bool = False,
) -> LintIssue:
    raw = f"{kind.value}:{path}:{message}:{details or {}}"
    issue_id = "lint_" + hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]
    return LintIssue(
        id=issue_id,
        kind=kind,
        severity=severity,
        path=path,
        message=message,
        details=details or {},
        fixable=fixable,
    )


def _build_stem_map(pages: list[LintPage]) -> dict[str, LintPage]:
    stem_map = {}
    for page in pages:
        without_prefix = page.path.removeprefix("wiki/").removesuffix(".md")
        stem_map[without_prefix] = page
        stem_map[Path(page.path).stem] = page
        stem_map[page.title] = page
    return stem_map


def _resolve_wikilink(
    raw_target: str,
    path_map: dict[str, LintPage],
    stem_map: dict[str, LintPage],
) -> LintPage | None:
    target = _normalize_target(raw_target)
    if not target:
        return None
    path_candidate = target if target.endswith(".md") else f"{target}.md"
    if not path_candidate.startswith("wiki/"):
        path_candidate = f"wiki/{path_candidate}"
    if path_candidate in path_map:
        return path_map[path_candidate]
    return stem_map.get(target)


def _normalize_target(raw_target: str) -> str:
    return raw_target.split("|", 1)[0].strip()


def _extract_title(path: Path, content: str) -> str:
    frontmatter_match = FRONTMATTER_TITLE_PATTERN.search(_frontmatter(content))
    if frontmatter_match:
        return frontmatter_match.group(1).strip().strip('"')
    heading_match = HEADING_PATTERN.search(content)
    if heading_match:
        return heading_match.group(1).strip()
    return path.stem


def _frontmatter(content: str) -> str:
    if not content.startswith("---\n"):
        return ""
    parts = content.split("---", 2)
    return parts[1] if len(parts) >= 3 else ""


def _body_without_frontmatter(content: str) -> str:
    if not content.startswith("---\n"):
        return content
    parts = content.split("---", 2)
    return parts[2] if len(parts) >= 3 else content


def _extract_check_after(content: str) -> date | None:
    match = CHECK_AFTER_PATTERN.search(content)
    if not match:
        return None
    try:
        return date.fromisoformat(match.group(1))
    except ValueError:
        return None


def _index_mentions_page(index_text: str, page: LintPage) -> bool:
    link_path = page.path.removeprefix("wiki/").removesuffix(".md")
    return f"[[{link_path}]]" in index_text or f"[[{page.path}]]" in index_text
