from __future__ import annotations

from agent_service.models import LintIssue, LintIssueKind, LintResult, LintSeverity
from agent_service.workflows.lint_compat import run_wiki_lint_compat
from agent_service.vault import Vault


def run_wiki_lint(vault: Vault) -> LintResult:
    compat_result = run_wiki_lint_compat(vault)
    return LintResult(
        generated_at=compat_result.generated_at,
        scanned_files=compat_result.scanned_files,
        issues=[
            LintIssue(
                id=issue.id,
                kind=LintIssueKind(issue.kind.value),
                severity=LintSeverity(issue.severity.value),
                path=issue.path,
                message=issue.message,
                details=dict(issue.details),
                fixable=issue.fixable,
            )
            for issue in compat_result.issues
        ],
        issue_counts=dict(compat_result.issue_counts),
        fixable_issue_ids=list(compat_result.fixable_issue_ids),
    )
