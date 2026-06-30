import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_root_agents_md_declares_service_regression_rule():
    agents_path = ROOT / "AGENTS.md"
    text = agents_path.read_text(encoding="utf-8")

    assert "开发约束" in text
    assert "仅 SwiftUI" in text or "仅 SwiftUI 视图" in text
    assert "回归测试" in text
    assert "ingest" in text
    assert "scripts/run_agent_regression.py" in text


def test_default_agent_regression_cases_include_minimal_ingest_smoke_case():
    cases_path = ROOT / "docs/development/agent_regression_cases.json"
    cases = json.loads(cases_path.read_text(encoding="utf-8"))

    smoke_cases = [
        case
        for case in cases
        if case.get("conversation_group") == "ingest_smoke"
        or "ingest smoke" in case.get("intent", "").lower()
        or "最小 ingest" in case.get("intent", "")
    ]

    assert smoke_cases, "expected a dedicated minimal ingest smoke regression case"
    smoke_case = smoke_cases[0]
    assert smoke_case["prompt"].startswith("请帮我 ingest 这个文件")
    assert smoke_case.get("attachment_type") == "markdown"
    assert smoke_case.get("action_context", {}).get("action") == "ingest_file"
