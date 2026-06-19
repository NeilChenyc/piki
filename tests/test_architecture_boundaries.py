import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "agent_service"


def test_api_routes_do_not_import_workflows():
    offenders = _imports_matching(ROOT / "api", "agent_service.workflows")
    assert offenders == []


def test_runtime_and_workflows_do_not_import_fastapi():
    offenders = _imports_matching(ROOT / "runtime", "fastapi") + _imports_matching(ROOT / "workflows", "fastapi")
    assert offenders == []


def test_api_routes_do_not_import_legacy_tools():
    offenders = _imports_matching(ROOT / "api", "agent_service.tools")
    assert offenders == []


def test_system_workflows_do_not_import_runtime_or_tools():
    offenders = (
        _imports_matching(ROOT / "workflows", "agent_service.runtime")
        + _imports_matching(ROOT / "workflows", "agent_service.tools")
    )
    assert offenders == []


def test_runtime_entrypoints_do_not_import_workflows_package_reexports():
    offenders = _imports_matching(ROOT / "runtime", "agent_service.workflows")
    assert offenders == []


def test_critical_agent_service_entrypoints_import_without_cycles():
    entrypoints = [
        "agent_service.app",
        "agent_service.application.task_service",
        "agent_service.application.task_executor",
        "agent_service.application.maintenance",
        "agent_service.runtime.runner",
        "agent_service.runtime.cli",
    ]
    for module in entrypoints:
        __import__(module)


def _imports_matching(root: Path, forbidden_prefix: str) -> list[str]:
    offenders = []
    for path in sorted(root.rglob("*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            imported = []
            if isinstance(node, ast.Import):
                imported = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom) and node.module:
                imported = [node.module]
            for module in imported:
                if module == forbidden_prefix or module.startswith(forbidden_prefix + "."):
                    offenders.append(f"{path.relative_to(ROOT)} imports {module}")
    return offenders
