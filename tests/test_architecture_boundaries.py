import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "agent_service"


def test_api_routes_do_not_import_workflows():
    offenders = _imports_matching(ROOT / "api", "agent_service.workflows")
    assert offenders == []


def test_runtime_and_workflows_do_not_import_fastapi():
    offenders = _imports_matching(ROOT / "runtime", "fastapi") + _imports_matching(ROOT / "workflows", "fastapi")
    assert offenders == []


def test_tools_do_not_import_api_or_app_layers():
    offenders = _imports_matching(ROOT / "tools", "agent_service.api") + _imports_matching(
        ROOT / "tools",
        "agent_service.app",
    )
    assert offenders == []


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
