import ast
import contextlib
import importlib.abc
import io
import json
import runpy
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CLI_PATH = REPO_ROOT / "agent_service/runtime/cli.py"
RUNTIME_INIT_PATH = REPO_ROOT / "agent_service/runtime/__init__.py"
LINT_COMPAT_MODEL_PATH = REPO_ROOT / "agent_service/models/lint_compat.py"
LINT_COMPAT_WORKFLOW_PATH = REPO_ROOT / "agent_service/workflows/lint_compat.py"


def make_vault(tmp_path: Path) -> Path:
    vault = tmp_path / "vault"
    (vault / "wiki").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent rules\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text("# Index\n", encoding="utf-8")
    (vault / "wiki/log.md").write_text("# Log\n", encoding="utf-8")
    (vault / "wiki/concepts").mkdir(parents=True)
    (vault / "wiki/concepts/example.md").write_text(
        "---\ntitle: Example\n---\n\n# Example\n\nBody text that is long enough to avoid thin-page lint.\n",
        encoding="utf-8",
    )
    return vault


class BlockingFinder(importlib.abc.MetaPathFinder):
    def __init__(self, blocked_prefixes: tuple[str, ...]):
        self.blocked_prefixes = blocked_prefixes

    def find_spec(self, fullname, path=None, target=None):
        for prefix in self.blocked_prefixes:
            if fullname == prefix or fullname.startswith(prefix + "."):
                raise AssertionError(f"blocked import: {fullname}")
        return None


def test_lint_compat_modules_parse_as_python39():
    for path in (
        CLI_PATH,
        RUNTIME_INIT_PATH,
        LINT_COMPAT_MODEL_PATH,
        LINT_COMPAT_WORKFLOW_PATH,
    ):
        ast.parse(path.read_text(encoding="utf-8"), filename=str(path), feature_version=(3, 9))


def test_lint_cli_path_avoids_runtime_and_system_heavy_imports(tmp_path: Path, monkeypatch):
    vault = make_vault(tmp_path)
    blocked = BlockingFinder(
        (
            "agent_service.runtime.runner",
            "agent_service.runtime.worker",
            "agent_service.system",
            "agent_service.models.core",
        )
    )
    monkeypatch.setenv("PYTHONIOENCODING", "utf-8")
    monkeypatch.setattr(sys, "argv", ["agent_service.runtime.cli", "lint", "--vault", str(vault)])
    monkeypatch.syspath_prepend(str(REPO_ROOT))

    removed_modules = {}
    for name in list(sys.modules):
        if (
            name == "agent_service.runtime"
            or name.startswith("agent_service.runtime.")
            or name == "agent_service.system"
            or name.startswith("agent_service.system.")
        ):
            removed_modules[name] = sys.modules.pop(name)

    stdout = io.StringIO()
    sys.meta_path.insert(0, blocked)
    try:
        with contextlib.redirect_stdout(stdout):
            with contextlib.suppress(SystemExit):
                runpy.run_module("agent_service.runtime.cli", run_name="__main__")
    finally:
        sys.meta_path.remove(blocked)
        sys.modules.update(removed_modules)

    payload = json.loads(stdout.getvalue())
    assert payload["scanned_files"] >= 1
    assert "issues" in payload
    assert "fixable_issue_ids" in payload
