from __future__ import annotations

import difflib
import re
from pathlib import Path
from uuid import uuid4

from agent_service.application.events import EventPublisher
from agent_service.journal import ChangeJournalService
from agent_service.models import FileSnapshot, JournalEntry, PatchChange, PatchProposal, RiskLevel, ToolResult, utc_now_iso
from agent_service.models import TaskStatus
from agent_service.store import SQLiteStore
from agent_service.vault import Vault, VaultAccessError
from agent_service.vault.writer import VaultWriter
from agent_service.workflows.source_intake import (
    SourceIntakeError,
    SourceManifestRecord,
    build_source_slug,
    detect_source_format,
    extract_text,
    extract_title,
    hash_file,
    read_source_manifest,
    render_canonical_source,
    write_source_manifest,
)


WIKILINK_PATTERN = re.compile(r"\[\[([^\]]+)\]\]")
HEADING_PATTERN = re.compile(r"^(#{1,6})\s+(.+)$", re.MULTILINE)


class VaultToolRegistry:
    def __init__(
        self,
        *,
        vault: Vault,
        task_id: str,
        store: SQLiteStore | None = None,
        events: EventPublisher | None = None,
        allowed_external_paths: list[str] | None = None,
    ):
        if events is None and store is None:
            raise ValueError("VaultToolRegistry requires either store or events.")
        self.vault = vault
        self.store = store or events.store
        self.events = events or EventPublisher(store)
        self.task_id = task_id
        self.writer = VaultWriter(vault)
        self.journal = ChangeJournalService(store=self.store, events=self.events)
        self._journal_snapshots: dict[str, FileSnapshot] = {}
        self._changed_files: list[str] = []
        self.allowed_external_paths = {_resolve_external_path(path) for path in allowed_external_paths or []}
        self.last_source_intake_result: dict | None = None
        self.last_lint_result: dict | None = None
        self.last_lint_fix_result: dict | None = None

    def _started(self, name: str, payload: dict):
        self.events.tool_started(self.task_id, name, payload)
        progress = _progress_for_tool(name)
        if progress:
            self.events.emit(self.task_id, "agent.progress", progress)
            self.events.trace_event(
                self.task_id,
                kind="tool_started",
                title=progress["title"],
                summary=_tool_trace_summary(name, payload),
                tool=name,
                category=progress.get("category", "tool"),
                status="running",
            )

    def _finished(self, name: str, payload: dict):
        self.events.tool_finished(self.task_id, name, payload)
        self.events.trace_event(
            self.task_id,
            kind="tool_finished",
            title="工具调用完成",
            summary=_tool_trace_summary(name, payload),
            tool=name,
            category=_tool_category(name),
            status="completed",
        )

    def _failed(self, name: str, error: str):
        self.events.tool_failed(self.task_id, name, error)
        self.events.trace_event(
            self.task_id,
            kind="tool_failed",
            title="工具调用失败",
            summary=error,
            tool=name,
            category=_tool_category(name),
            status="failed",
        )

    def read_file(self, path: str, max_bytes: int = 20000) -> ToolResult:
        self._started("read_file", {"path": path})
        try:
            content, truncated = self.vault.read_text(path, max_bytes=max_bytes)
        except VaultAccessError as exc:
            self._failed("read_file", str(exc))
            return ToolResult(ok=False, error=str(exc))
        payload = {"path": path, "content": content, "truncated": truncated}
        self._finished("read_file", {"path": path, "truncated": truncated})
        return ToolResult(ok=True, payload=payload)

    def list_files(self, path: str = ".", glob: str = "*.md", max_results: int = 200) -> ToolResult:
        self._started("list_files", {"path": path, "glob": glob})
        try:
            files = self.vault.list_files(path, glob=glob, max_results=max_results)
        except VaultAccessError as exc:
            self._failed("list_files", str(exc))
            return ToolResult(ok=False, error=str(exc))
        self._finished("list_files", {"path": path, "count": len(files)})
        return ToolResult(ok=True, payload={"files": files})

    def search_text(self, query: str, scope: str = "wiki", max_results: int = 20) -> ToolResult:
        self._started("search_text", {"query": query, "scope": scope})
        try:
            root = self.vault.resolve_path(scope)
            matches = []
            for path in sorted(root.rglob("*.md")):
                if len(matches) >= max_results:
                    break
                text = path.read_text(encoding="utf-8", errors="replace")
                for line_number, line in enumerate(text.splitlines(), start=1):
                    if query in line:
                        matches.append(
                            {
                                "path": str(path.relative_to(self.vault.root)),
                                "line": line_number,
                                "snippet": line.strip(),
                            }
                        )
                        break
        except (OSError, VaultAccessError) as exc:
            self._failed("search_text", str(exc))
            return ToolResult(ok=False, error=str(exc))
        self._finished("search_text", {"query": query, "count": len(matches)})
        return ToolResult(ok=True, payload={"matches": matches})

    def parse_markdown(self, path: str) -> ToolResult:
        result = self.read_file(path)
        if not result.ok:
            return result
        content = result.payload["content"]
        frontmatter = {}
        body = content
        if content.startswith("---\n"):
            _, raw_frontmatter, body = content.split("---", 2)
            frontmatter = _parse_simple_frontmatter(raw_frontmatter)
        headings = [match.group(2).strip() for match in HEADING_PATTERN.finditer(body)]
        wikilinks = sorted(set(match.group(1).strip() for match in WIKILINK_PATTERN.finditer(body)))
        payload = {
            "path": path,
            "frontmatter": frontmatter,
            "headings": headings,
            "wikilinks": wikilinks,
        }
        self._finished("parse_markdown", {"path": path, "heading_count": len(headings)})
        return ToolResult(ok=True, payload=payload)

    def read_external_text_file(self, path: str) -> ToolResult:
        self._started("read_external_text_file", {"path": path})
        try:
            source_file = self._allowed_external_file(path)
            source_format = detect_source_format(source_file)
            content = extract_text(source_file, source_format)
        except (SourceIntakeError, VaultAccessError) as exc:
            self._failed("read_external_text_file", str(exc))
            return ToolResult(ok=False, error=str(exc))
        payload = {
            "path": str(source_file),
            "format": source_format.value,
            "content": content,
        }
        self._finished("read_external_text_file", {"path": str(source_file), "format": source_format.value})
        return ToolResult(ok=True, payload=payload)

    def write_canonical_source(self, path: str) -> ToolResult:
        self._started("write_canonical_source", {"path": path})
        self.events.emit(self.task_id, "source_intake.started", {"selected_paths": [path], "trigger": "agent_tool"})
        try:
            source_file = self._allowed_external_file(path)
            source_format = detect_source_format(source_file)
            file_hash = hash_file(source_file)
            manifest = read_source_manifest(self.vault)
            existing = manifest.get(file_hash)
            if existing and _vault_file_exists(self.vault, existing.source_path):
                payload = {
                    "title": existing.title,
                    "format": existing.format.value,
                    "hash": existing.hash,
                    "original_path": existing.original_path,
                    "asset_path": existing.asset_path,
                    "source_path": existing.source_path,
                    "size_bytes": existing.size_bytes,
                    "reused": True,
                    "captured_at": existing.created_at,
                    "body_preview": "",
                }
                self.last_source_intake_result = payload
                self._finished("write_canonical_source", {"path": existing.source_path, "reused": True})
                self.events.emit(self.task_id, "source_intake.normalized", payload)
                return ToolResult(ok=True, payload=payload)

            extracted = extract_text(source_file, source_format)
            title = extract_title(source_file, extracted)
            slug = build_source_slug(title, file_hash)
            asset_path = f"raw/assets/{slug}/original{source_file.suffix.lower()}"
            source_path = f"raw/sources/{slug}.md"
            copied_asset_path = self.vault.copy_into_vault(source_file, asset_path)
            now = utc_now_iso()
            markdown = render_canonical_source(
                title=title,
                source_format=source_format,
                file_hash=file_hash,
                original_path=str(source_file),
                asset_path=copied_asset_path,
                source_path=source_path,
                captured_at=now,
                body=extracted,
            )
            write = self.writer.write(source_path, markdown)
            if write.changed:
                self._record_changed_file(write.path)
                self._record_write_snapshot(self.writer.snapshot_for(write))
                self.events.file_changed(
                    self.task_id,
                    {
                        "path": write.path,
                        "action": "write",
                        "before_hash": write.before_hash,
                        "after_hash": write.after_hash,
                        "journal_candidate": True,
                    },
                )
            record = SourceManifestRecord(
                hash=file_hash,
                title=title,
                format=source_format,
                original_path=str(source_file),
                asset_path=copied_asset_path,
                source_path=write.path,
                size_bytes=source_file.stat().st_size,
                created_at=now,
                updated_at=now,
            )
            manifest[file_hash] = record
            write_source_manifest(self.vault, manifest)
        except (SourceIntakeError, VaultAccessError, OSError) as exc:
            self._failed("write_canonical_source", str(exc))
            return ToolResult(ok=False, error=str(exc))

        payload = {
            "title": title,
            "format": source_format.value,
            "hash": file_hash,
            "original_path": str(source_file),
            "asset_path": copied_asset_path,
            "source_path": write.path,
            "size_bytes": record.size_bytes,
            "reused": False,
            "captured_at": now,
            "body_preview": extracted[:500],
        }
        self.last_source_intake_result = payload
        self.events.emit(self.task_id, "source_intake.copied", {"asset_path": copied_asset_path, "reused": False})
        self.events.emit(self.task_id, "source_intake.normalized", payload)
        self.events.emit(
            self.task_id,
            "source_manifest.updated",
            {"hash": file_hash, "source_path": write.path, "reused": False},
        )
        self._finished("write_canonical_source", {"path": write.path, "reused": False, "changed": write.changed})
        return ToolResult(ok=True, payload=payload)

    def write_file(self, path: str, content: str, reason: str = "") -> ToolResult:
        self._started("write_file", {"path": path, "reason": reason})
        try:
            write = self.writer.write(path, content)
            if not write.changed:
                self._finished("write_file", {"path": write.path, "changed": False})
                return ToolResult(
                    ok=True,
                    payload={
                        "path": write.path,
                        "changed": False,
                        "before_hash": write.after_hash,
                        "after_hash": write.after_hash,
                        "journal_scope": "none",
                    },
                )
            self._record_changed_file(write.path)
            self._record_write_snapshot(self.writer.snapshot_for(write))
        except VaultAccessError as exc:
            self._failed("write_file", str(exc))
            return ToolResult(ok=False, error=str(exc))
        self.events.file_changed(
            self.task_id,
            {
                "path": write.path,
                "action": "write",
                "before_hash": write.before_hash,
                "after_hash": write.after_hash,
                "journal_candidate": _is_journal_path(write.path),
            },
        )
        self._finished("write_file", {"path": write.path, "changed": True})
        return ToolResult(
            ok=True,
            payload={
                "path": write.path,
                "changed": True,
                "before_hash": write.before_hash,
                "after_hash": write.after_hash,
                "journal_scope": "conversation" if _is_journal_path(write.path) else "none",
            },
        )

    def append_file(self, path: str, content: str, reason: str = "") -> ToolResult:
        self._started("append_file", {"path": path, "reason": reason})
        try:
            write = self.writer.append(path, content)
            if not write.changed:
                self._finished("append_file", {"path": write.path, "changed": False})
                return ToolResult(
                    ok=True,
                    payload={
                        "path": write.path,
                        "changed": False,
                        "before_hash": write.after_hash,
                        "after_hash": write.after_hash,
                        "journal_scope": "none",
                    },
                )
            self._record_changed_file(write.path)
            self._record_write_snapshot(self.writer.snapshot_for(write))
        except VaultAccessError as exc:
            self._failed("append_file", str(exc))
            return ToolResult(ok=False, error=str(exc))
        self.events.file_changed(
            self.task_id,
            {
                "path": write.path,
                "action": "append",
                "before_hash": write.before_hash,
                "after_hash": write.after_hash,
                "journal_candidate": _is_journal_path(write.path),
            },
        )
        self._finished("append_file", {"path": write.path, "changed": True})
        return ToolResult(
            ok=True,
            payload={
                "path": write.path,
                "changed": True,
                "before_hash": write.before_hash,
                "after_hash": write.after_hash,
                "journal_scope": "conversation" if _is_journal_path(write.path) else "none",
            },
        )

    def run_lint(self) -> ToolResult:
        self._started("run_lint", {})
        try:
            from agent_service.workflows.lint import run_wiki_lint

            result = run_wiki_lint(self.vault)
        except Exception as exc:
            self._failed("run_lint", str(exc))
            return ToolResult(ok=False, error=str(exc))
        payload = result.model_dump(mode="json")
        self.last_lint_result = payload
        self.events.emit(self.task_id, "lint.completed", payload)
        self._finished("run_lint", {"issue_count": len(result.issues), "fixable_count": len(result.fixable_issue_ids)})
        return ToolResult(ok=True, payload=payload)

    def apply_lint_fixes(self, issue_ids: list[str] | None = None) -> ToolResult:
        self._started("apply_lint_fixes", {"issue_ids": issue_ids or []})
        try:
            from agent_service.models import LintIssueKind
            from agent_service.workflows.lint import run_wiki_lint

            report = run_wiki_lint(self.vault)
            requested = set(issue_ids or report.fixable_issue_ids)
            selected = [
                issue
                for issue in report.issues
                if issue.id in requested and issue.kind == LintIssueKind.MISSING_INDEX_ENTRY and issue.fixable
            ]
            fixed_ids: list[str] = []
            if selected:
                index_path = self.vault.resolve_path("wiki/index.md")
                index_text = (
                    index_path.read_text(encoding="utf-8", errors="replace")
                    if index_path.exists()
                    else "# 索引\n"
                )
                additions = []
                for issue in selected:
                    link_path = issue.details["link_path"]
                    title = issue.details.get("title") or Path(issue.path).stem
                    line = f"- [[{link_path}]] — {title}"
                    if line not in index_text:
                        additions.append(line)
                        fixed_ids.append(issue.id)
                if additions:
                    separator = "" if index_text.endswith("\n") else "\n"
                    self.write_file(
                        "wiki/index.md",
                        index_text + separator + "\n".join(additions) + "\n",
                        reason="lint fix missing index entries",
                    )
                    self.append_file(
                        "wiki/log.md",
                        f"\n## 自动检查 | 自动补充索引\n\n- 补充索引条目：{len(additions)} 条。\n",
                        reason="lint fix log",
                    )
        except Exception as exc:
            self._failed("apply_lint_fixes", str(exc))
            return ToolResult(ok=False, error=str(exc))
        payload = {
            "fixed_issue_ids": fixed_ids,
            "affected_files": self.changed_files,
            "task_id": self.task_id,
            "summary": f"已修复 {len(fixed_ids)} 个 lint 问题。" if fixed_ids else "没有可修复的 lint 问题。",
        }
        self.last_lint_fix_result = payload
        self.events.emit(self.task_id, "lint.fix_applied", payload)
        self._finished("apply_lint_fixes", {"fixed_count": len(fixed_ids)})
        return ToolResult(ok=True, payload=payload)

    def commit_journal_entry(self, *, conversation_id: str, reason: str) -> JournalEntry | None:
        return self.journal.commit_for_task(
            task_id=self.task_id,
            conversation_id=conversation_id,
            reason=reason,
            snapshots=list(self._journal_snapshots.values()),
        )

    @property
    def changed_files(self) -> list[str]:
        return list(self._changed_files)

    def _record_changed_file(self, path: str):
        if path not in self._changed_files:
            self._changed_files.append(path)

    def _record_write_snapshot(self, snapshot: FileSnapshot):
        if not _is_journal_path(snapshot.path):
            return
        existing = self._journal_snapshots.get(snapshot.path)
        if existing is None:
            self._journal_snapshots[snapshot.path] = snapshot
            return
        existing.after_hash = snapshot.after_hash

    def _allowed_external_file(self, path: str) -> Path:
        resolved = _resolve_external_path(path)
        if resolved not in self.allowed_external_paths:
            raise VaultAccessError(f"External file was not provided in this task: {path}")
        if not resolved.exists() or not resolved.is_file():
            raise VaultAccessError(f"External file not found: {path}")
        return resolved

    def propose_patch(self, *, reason: str, changes: list[PatchChange], risk_level: RiskLevel) -> PatchProposal:
        proposal_id = f"patch_{uuid4().hex}"
        affected_files = [change.path for change in changes]
        diff_parts = []
        for change in changes:
            diff_parts.append(self._diff_for_change(change))
        diff = "\n".join(diff_parts).strip() + "\n"
        proposal = PatchProposal(
            id=proposal_id,
            task_id=self.task_id,
            reason=reason,
            risk_level=risk_level,
            affected_files=affected_files,
            diff=diff,
            requires_approval=risk_level in {RiskLevel.HIGH, RiskLevel.MEDIUM},
        )
        self.events.emit(
            self.task_id,
            "diff.created",
            {
                "proposal_id": proposal.id,
                "risk_level": proposal.risk_level.value,
                "affected_files": proposal.affected_files,
                "requires_approval": proposal.requires_approval,
            },
        )
        if proposal.requires_approval:
            approval = self.store.create_approval(
                task_id=self.task_id,
                proposal_id=proposal.id,
                risk_level=proposal.risk_level,
                affected_files=proposal.affected_files,
                diff=proposal.diff,
            )
            self.store.update_task(
                self.task_id,
                status=TaskStatus.NEEDS_APPROVAL,
                affected_files=proposal.affected_files,
                summary=proposal.reason,
            )
            self.events.emit(
                self.task_id,
                "approval.required",
                {"approval_id": approval.id, "proposal_id": proposal.id},
            )
        return proposal

    def _diff_for_change(self, change: PatchChange) -> str:
        old_lines: list[str] = []
        new_lines: list[str] = []
        if change.action in {"update", "delete"}:
            try:
                old_content, _ = self.vault.read_text(change.path, max_bytes=500000)
                old_lines = old_content.splitlines(keepends=True)
            except VaultAccessError:
                old_lines = []
        if change.action in {"create", "update"} and change.content is not None:
            new_lines = change.content.splitlines(keepends=True)
        fromfile = f"a/{change.path}"
        tofile = f"b/{change.path}"
        return "".join(difflib.unified_diff(old_lines, new_lines, fromfile=fromfile, tofile=tofile))


def _parse_simple_frontmatter(raw_frontmatter: str) -> dict:
    data = {}
    for line in raw_frontmatter.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip()
    return data


def _is_journal_path(path: str) -> bool:
    return path.startswith("raw/") or path.startswith("wiki/")


def _progress_for_tool(name: str) -> dict | None:
    if name in {"read_file", "list_files", "search_text", "parse_markdown"}:
        return {
            "stage": "reading_wiki",
            "title": "正在阅读 Wiki",
            "detail": "正在查找相关记忆和页面。",
            "category": "read",
        }
    if name in {"read_external_text_file", "write_canonical_source"}:
        return {
            "stage": "converting_document",
            "title": "正在转换文档",
            "detail": "正在把用户提供的文件转换为可维护的 Markdown source。",
            "category": "convert",
        }
    if name in {"write_file", "append_file"}:
        return {
            "stage": "writing_wiki",
            "title": "正在写入 Wiki",
            "detail": "正在更新 vault 中的文件。",
            "category": "write",
        }
    if name in {"run_lint", "apply_lint_fixes"}:
        return {
            "stage": "reading_wiki" if name == "run_lint" else "writing_wiki",
            "title": "正在阅读 Wiki" if name == "run_lint" else "正在写入 Wiki",
            "detail": "正在检查知识库结构和维护问题。",
            "category": "read" if name == "run_lint" else "write",
        }
    return None


def _tool_category(name: str) -> str:
    progress = _progress_for_tool(name)
    return progress.get("category", "tool") if progress else "tool"


def _tool_trace_summary(name: str, payload: dict) -> str:
    target = payload.get("path") or payload.get("query") or payload.get("scope") or ""
    label = {
        "read_file": "读取文件",
        "list_files": "列出文件",
        "search_text": "搜索内容",
        "parse_markdown": "解析页面",
        "read_external_text_file": "读取外部文件",
        "write_canonical_source": "转换文档",
        "write_file": "写入文件",
        "append_file": "追加文件",
        "run_lint": "检查知识库",
        "apply_lint_fixes": "应用维护修复",
    }.get(name, name)
    return f"{label}：{target}" if target else label


def _resolve_external_path(path: str) -> Path:
    return Path(path).expanduser().resolve()


def _vault_file_exists(vault: Vault, relative_path: str) -> bool:
    try:
        path = vault.resolve_path(relative_path)
    except VaultAccessError:
        return False
    return path.exists() and path.is_file()


def _snapshot_diff(snapshot: FileSnapshot) -> str:
    old_lines: list[str] = []
    new_lines: list[str] = []
    return "".join(
        difflib.unified_diff(
            old_lines,
            new_lines,
            fromfile=f"a/{snapshot.path}",
            tofile=f"b/{snapshot.path}",
        )
    )
