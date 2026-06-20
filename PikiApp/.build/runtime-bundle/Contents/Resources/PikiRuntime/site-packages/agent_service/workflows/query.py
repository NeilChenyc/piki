from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from agent_service.models import (
    Citation,
    ContextManifest,
    QueryConfidence,
    QueryMode,
    QueryResult,
)
from agent_service.vault import Vault


ASCII_TOKEN_PATTERN = re.compile(r"[a-z0-9][a-z0-9_-]*", re.IGNORECASE)
CJK_PATTERN = re.compile(r"[\u3400-\u9fff]")
FRONTMATTER_TITLE_PATTERN = re.compile(r"^title:\s*(.+)$", re.MULTILINE)
HEADING_PATTERN = re.compile(r"^#\s+(.+)$", re.MULTILINE)
WIKILINK_PATTERN = re.compile(r"\[\[([^\]]+)\]\]")


@dataclass(frozen=True)
class WikiPage:
    path: str
    title: str
    content: str
    lines: list[str]


@dataclass(frozen=True)
class SearchHit:
    page: WikiPage
    score: float
    line: int | None
    snippet: str
    reason: str


def resolve_query_mode(mode: str | None) -> QueryMode:
    normalized = (mode or "").strip().lower()
    if normalized in {"deep", "深入", "detailed"}:
        return QueryMode.DEEP
    if normalized in {"related", "pages", "相关", "related-pages"}:
        return QueryMode.RELATED
    return QueryMode.QUICK


def run_read_only_query(vault: Vault, question: str, mode: str | None = None) -> QueryResult:
    query_mode = resolve_query_mode(mode)
    pages = load_wiki_pages(vault)
    direct_hits = search_pages(question, pages)
    expanded_hits = expand_wikilinks(direct_hits, pages)
    all_hits = _merge_hits(direct_hits, expanded_hits)
    citations = [
        Citation(
            path=hit.page.path,
            title=hit.page.title,
            line=hit.line,
            snippet=hit.snippet,
        )
        for hit in all_hits[:6]
        if hit.reason != "wikilink"
    ]
    related_pages = _related_pages(all_hits)
    manifest = ContextManifest(
        loaded_files=_loaded_files(all_hits),
        search_terms=tokenize_query(question),
    )
    answer = build_answer(question, query_mode, citations, related_pages)
    confidence = _confidence(citations, all_hits)
    return QueryResult(
        answer=answer,
        citations=citations,
        related_pages=related_pages,
        confidence=confidence,
        mode=query_mode,
        context_manifest=manifest,
    )


def load_wiki_pages(vault: Vault) -> list[WikiPage]:
    wiki_root = vault.resolve_path("wiki")
    pages: list[WikiPage] = []
    for path in sorted(wiki_root.rglob("*.md")):
        relative_path = str(path.relative_to(vault.root))
        content = path.read_text(encoding="utf-8", errors="replace")
        pages.append(
            WikiPage(
                path=relative_path,
                title=_extract_title(path, content),
                content=content,
                lines=content.splitlines(),
            )
        )
    return pages


def tokenize_query(text: str) -> list[str]:
    normalized = text.lower()
    tokens = set(match.group(0).lower() for match in ASCII_TOKEN_PATTERN.finditer(normalized))
    cjk_chars = CJK_PATTERN.findall(normalized)
    tokens.update(cjk_chars)
    tokens.update(
        "".join(pair)
        for pair in zip(cjk_chars, cjk_chars[1:], strict=False)
    )
    compact_cjk = "".join(cjk_chars)
    if len(compact_cjk) >= 3:
        tokens.add(compact_cjk)
    return sorted(token for token in tokens if token.strip())


def search_pages(question: str, pages: list[WikiPage], limit: int = 8) -> list[SearchHit]:
    query_tokens = tokenize_query(question)
    normalized_question = _normalize(question)
    hits: list[SearchHit] = []
    for page in pages:
        score, line_number, snippet = _score_page(page, normalized_question, query_tokens)
        if page.path == "wiki/index.md":
            score += 2.0
        if score >= 3.0:
            hits.append(SearchHit(page=page, score=score, line=line_number, snippet=snippet, reason="direct"))
    return sorted(hits, key=lambda hit: (-hit.score, hit.page.path))[:limit]


def expand_wikilinks(hits: list[SearchHit], pages: list[WikiPage], limit: int = 8) -> list[SearchHit]:
    path_map = {page.path: page for page in pages}
    stem_map = _build_stem_map(pages)
    expanded: list[SearchHit] = []
    seen = {hit.page.path for hit in hits}
    for hit in hits:
        for raw_target in WIKILINK_PATTERN.findall(hit.page.content):
            page = _resolve_wikilink(raw_target, path_map, stem_map)
            if page is None or page.path in seen:
                continue
            seen.add(page.path)
            expanded.append(
                SearchHit(
                    page=page,
                    score=max(hit.score - 1.0, 0.5),
                    line=None,
                    snippet=f"由 {hit.page.title} 的 wikilink 关联。",
                    reason="wikilink",
                )
            )
            if len(expanded) >= limit:
                return expanded
    return expanded


def build_answer(
    question: str,
    mode: QueryMode,
    citations: list[Citation],
    related_pages: list[str],
) -> str:
    if mode == QueryMode.RELATED:
        return "已按要求只返回相关页面。"
    if not citations:
        return "我没有在已编译 wiki 中找到足够相关的内容。默认 query 不会重读 raw 原始来源。"
    if mode == QueryMode.DEEP:
        lines = ["根据已编译 wiki，相关内容可以这样理解："]
        for citation in citations[:4]:
            lines.append(f"- {citation.title}：{citation.snippet}")
        return "\n".join(lines)
    lead = citations[0]
    if len(citations) == 1:
        return f"根据已编译 wiki，{lead.snippet}"
    supporting = "；".join(citation.title for citation in citations[1:3])
    return f"根据已编译 wiki，{lead.snippet} 相关页面还包括：{supporting}。"


def _score_page(page: WikiPage, normalized_question: str, query_tokens: list[str]) -> tuple[float, int | None, str]:
    normalized_content = _normalize(page.content)
    compact_question_match_allowed = _allow_compact_match(normalized_question)
    content_ascii_tokens = _ascii_tokens(page.content)
    title_ascii_tokens = _ascii_tokens(page.title)
    score = 0.0
    if compact_question_match_allowed and normalized_question in normalized_content:
        score += 20.0
    best_line = None
    best_line_score = 0.0
    best_snippet = ""
    title_normalized = _normalize(page.title)
    for token in query_tokens:
        if _token_matches(token, title_normalized, title_ascii_tokens):
            score += 0.5 if len(token) == 1 else 4.0
        if _token_matches(token, normalized_content, content_ascii_tokens):
            score += 0.25 if len(token) == 1 else 1.0
    for line_number, line in enumerate(page.lines, start=1):
        line_normalized = _normalize(line)
        line_ascii_tokens = _ascii_tokens(line)
        line_score = 0.0
        if compact_question_match_allowed and normalized_question in line_normalized:
            line_score += 20.0
        for token in query_tokens:
            if _token_matches(token, line_normalized, line_ascii_tokens):
                line_score += 0.25 if len(token) == 1 else 2.0
        if line_score > best_line_score:
            best_line_score = line_score
            best_line = line_number
            best_snippet = line.strip()
    score += min(best_line_score, 16.0)
    return score, best_line, best_snippet or page.title


def _extract_title(path: Path, content: str) -> str:
    frontmatter_match = FRONTMATTER_TITLE_PATTERN.search(content)
    if frontmatter_match:
        return frontmatter_match.group(1).strip().strip('"')
    heading_match = HEADING_PATTERN.search(content)
    if heading_match:
        return heading_match.group(1).strip()
    return path.stem


def _normalize(text: str) -> str:
    return re.sub(r"\s+", "", text.lower())


def _ascii_tokens(text: str) -> set[str]:
    return {match.group(0).lower() for match in ASCII_TOKEN_PATTERN.finditer(text)}


def _is_ascii_token(token: str) -> bool:
    return bool(ASCII_TOKEN_PATTERN.fullmatch(token)) and token.isascii()


def _token_matches(token: str, normalized_text: str, ascii_tokens: set[str]) -> bool:
    if _is_ascii_token(token):
        return token in ascii_tokens
    return token in normalized_text


def _allow_compact_match(normalized_question: str) -> bool:
    if not normalized_question:
        return False
    if CJK_PATTERN.search(normalized_question):
        return True
    return len(normalized_question) >= 3


def _build_stem_map(pages: list[WikiPage]) -> dict[str, WikiPage]:
    stem_map = {}
    for page in pages:
        without_prefix = page.path.removeprefix("wiki/").removesuffix(".md")
        stem_map[without_prefix] = page
        stem_map[Path(page.path).stem] = page
        stem_map[page.title] = page
    return stem_map


def _resolve_wikilink(
    raw_target: str,
    path_map: dict[str, WikiPage],
    stem_map: dict[str, WikiPage],
) -> WikiPage | None:
    target = raw_target.split("|", 1)[0].strip()
    if not target:
        return None
    path_candidate = target if target.endswith(".md") else f"{target}.md"
    if not path_candidate.startswith("wiki/"):
        path_candidate = f"wiki/{path_candidate}"
    if path_candidate in path_map:
        return path_map[path_candidate]
    return stem_map.get(target)


def _merge_hits(direct_hits: list[SearchHit], expanded_hits: list[SearchHit]) -> list[SearchHit]:
    merged = []
    seen = set()
    for hit in [*direct_hits, *expanded_hits]:
        if hit.page.path in seen:
            continue
        seen.add(hit.page.path)
        merged.append(hit)
    return merged


def _related_pages(hits: list[SearchHit]) -> list[str]:
    return [hit.page.path for hit in hits if hit.page.path != "wiki/index.md"]


def _loaded_files(hits: list[SearchHit]) -> list[str]:
    files = ["AGENTS.md", "purpose.md", "wiki/index.md"]
    for hit in hits:
        if hit.page.path not in files:
            files.append(hit.page.path)
    return files


def _confidence(citations: list[Citation], hits: list[SearchHit]) -> QueryConfidence:
    if len(citations) >= 2 and hits and hits[0].score >= 12:
        return QueryConfidence.HIGH
    if citations:
        return QueryConfidence.MEDIUM
    return QueryConfidence.LOW
