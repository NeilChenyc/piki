from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum


def utc_now_iso_compat() -> str:
    return datetime.now(timezone.utc).isoformat()


class LintCompatSeverity(str, Enum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"


class LintCompatIssueKind(str, Enum):
    MISSING_FRONTMATTER = "missing_frontmatter"
    BROKEN_LINK = "broken_link"
    ORPHAN_PAGE = "orphan_page"
    DUPLICATE_TITLE = "duplicate_title"
    MISSING_INDEX_ENTRY = "missing_index_entry"
    STALE_PAGE = "stale_page"
    THIN_PAGE = "thin_page"
    KNOWLEDGE_GAP = "knowledge_gap"
    MISSING_HEADING = "missing_heading"


@dataclass(frozen=True)
class LintCompatIssue:
    id: str
    kind: LintCompatIssueKind
    severity: LintCompatSeverity
    path: str
    message: str
    details: dict[str, object] = field(default_factory=dict)
    fixable: bool = False

    def to_dict(self) -> dict[str, object]:
        return {
            "id": self.id,
            "kind": self.kind.value,
            "severity": self.severity.value,
            "path": self.path,
            "message": self.message,
            "details": dict(self.details),
            "fixable": self.fixable,
        }


@dataclass(frozen=True)
class LintCompatResult:
    generated_at: str
    scanned_files: int = 0
    issues: list[LintCompatIssue] = field(default_factory=list)
    issue_counts: dict[str, int] = field(default_factory=dict)
    fixable_issue_ids: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, object]:
        return {
            "generated_at": self.generated_at,
            "scanned_files": self.scanned_files,
            "issues": [issue.to_dict() for issue in self.issues],
            "issue_counts": dict(self.issue_counts),
            "fixable_issue_ids": list(self.fixable_issue_ids),
        }
