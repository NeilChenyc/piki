from __future__ import annotations

from pathlib import Path

from agent_service.application.events import EventPublisher
from agent_service.models import (
    LintFixResult,
    LintIssueKind,
    LintResult,
)
from agent_service.store import SQLiteStore
from agent_service.system.helpers import DeterministicVaultHelper, lint_log_entry
from agent_service.vault import Vault
from agent_service.workflows.lint import run_wiki_lint as _run_wiki_lint_impl


def run_wiki_lint(vault: Vault) -> LintResult:
    return _run_wiki_lint_impl(vault)


def apply_lint_fixes(
    *,
    vault: Vault,
    store: SQLiteStore,
    events: EventPublisher,
    task_id: str,
    issue_ids: list[str] | None = None,
) -> LintFixResult:
    report = run_wiki_lint(vault)
    requested = set(issue_ids or report.fixable_issue_ids)
    selected = [
        issue
        for issue in report.issues
        if issue.id in requested and issue.kind == LintIssueKind.MISSING_INDEX_ENTRY and issue.fixable
    ]

    helper = DeterministicVaultHelper(vault=vault, store=store, events=events, task_id=task_id)
    fixed_ids: list[str] = []
    if selected:
        index_path = vault.resolve_path("wiki/index.md")
        index_text = index_path.read_text(encoding="utf-8", errors="replace") if index_path.exists() else "# 索引\n"
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
            helper.write_file("wiki/index.md", index_text + separator + "\n".join(additions) + "\n")
            helper.append_file("wiki/log.md", lint_log_entry(len(additions)))

    journal_entry = helper.commit_journal_entry(conversation_id=task_id, reason="lint fix")
    return LintFixResult(
        fixed_issue_ids=fixed_ids,
        affected_files=helper.changed_files,
        journal_entry=journal_entry,
        task_id=task_id,
        summary=f"已修复 {len(fixed_ids)} 个 lint 问题。" if fixed_ids else "没有可修复的 lint 问题。",
    )
