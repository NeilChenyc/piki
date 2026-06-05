from __future__ import annotations

import difflib
import re
from uuid import uuid4

from agent_service.application.events import EventPublisher
from agent_service.journal import ChangeJournalService
from agent_service.models import FileSnapshot, JournalEntry, PatchChange, PatchProposal, RiskLevel, ToolResult
from agent_service.models import TaskStatus
from agent_service.store import SQLiteStore
from agent_service.vault import Vault, VaultAccessError
from agent_service.vault.writer import VaultWriter


WIKILINK_PATTERN = re.compile(r"\[\[([^\]]+)\]\]")
HEADING_PATTERN = re.compile(r"^(#{1,6})\s+(.+)$", re.MULTILINE)


class VaultToolRegistry:
    def __init__(self, *, vault: Vault, task_id: str, store: SQLiteStore | None = None, events: EventPublisher | None = None):
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

    def _started(self, name: str, payload: dict):
        self.events.tool_started(self.task_id, name, payload)
        progress = _progress_for_tool(name)
        if progress:
            self.events.emit(self.task_id, "agent.progress", progress)

    def _finished(self, name: str, payload: dict):
        self.events.tool_finished(self.task_id, name, payload)

    def _failed(self, name: str, error: str):
        self.events.tool_failed(self.task_id, name, error)

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
        existing.after_content = snapshot.after_content

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
            "stage": "reading_vault",
            "title": "正在读取知识库",
            "detail": "正在查找相关记忆和页面。",
        }
    if name in {"write_file", "append_file"}:
        return {
            "stage": "writing_vault",
            "title": "正在写入知识库",
            "detail": "正在更新 vault 中的文件。",
        }
    return None


def _snapshot_diff(snapshot: FileSnapshot) -> str:
    old_lines = (snapshot.before_content or "").splitlines(keepends=True)
    new_lines = (snapshot.after_content or "").splitlines(keepends=True)
    return "".join(
        difflib.unified_diff(
            old_lines,
            new_lines,
            fromfile=f"a/{snapshot.path}",
            tofile=f"b/{snapshot.path}",
        )
    )
