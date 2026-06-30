from pathlib import Path

import pytest

from agent_service.application.events import EventPublisher
from agent_service.application.task_executor import TaskExecutor
from agent_service.application.task_router import TaskPlan
from agent_service.config import ServiceConfig
from agent_service.models import RiskLevel, TaskCreateRequest, TaskKind, TaskStatus
from agent_service.runtime import RunnerStatus
from agent_service.store import SQLiteStore


class _NeverRunner:
    status = RunnerStatus(False, "runner disabled")

    def can_run(self, config):
        return False


def _make_vault(tmp_path: Path) -> Path:
    vault = tmp_path / "vault"
    (vault / "wiki").mkdir(parents=True)
    (vault / "raw/sources").mkdir(parents=True)
    (vault / "AGENTS.md").write_text("# Agent Rules\n", encoding="utf-8")
    (vault / "purpose.md").write_text("# Purpose\nPodcast test\n", encoding="utf-8")
    (vault / "wiki/index.md").write_text("# Index\n", encoding="utf-8")
    (vault / "wiki/log.md").write_text("# Log\n", encoding="utf-8")
    return vault


def test_task_router_marks_podcast_action_as_low_risk_agent_task(tmp_path: Path):
    from agent_service.application.task_router import TaskRouter

    vault = _make_vault(tmp_path)
    request = TaskCreateRequest(
        vault_path=vault,
        user_input="请转录这个播客",
        action_context={"action": "podcast_transcribe", "podcast_url": "https://www.xiaoyuzhoufm.com/episode/abc"},
    )

    plan = TaskRouter().plan(request)

    assert plan.task_kind == TaskKind.AGENT
    assert plan.risk_level == RiskLevel.LOW
    assert "podcast_transcribe" in plan.summary


def test_podcast_task_fails_cleanly_when_runtime_unconfigured_and_no_system_handler(tmp_path: Path):
    vault = _make_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    events = EventPublisher(store)
    executor = TaskExecutor(
        config=ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            enable_agent_runtime=False,
        ),
        store=store,
        events=events,
        runner=_NeverRunner(),
    )
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.LOW,
        vault_path=str(vault),
        user_input="请转录这个播客",
        status=TaskStatus.RUNNING,
        summary="podcast test",
    )
    request = TaskCreateRequest(
        vault_path=vault,
        user_input="请转录这个播客",
        action_context={"action": "podcast_transcribe", "podcast_url": "https://www.xiaoyuzhoufm.com/episode/abc"},
    )
    plan = TaskPlan(task_kind=TaskKind.AGENT, risk_level=RiskLevel.LOW, summary="podcast")

    executor.execute(task_id=task.id, request=request, plan=plan)

    updated = store.get_task(task.id)
    assert updated.status == TaskStatus.FAILED
    assert "Claude Agent runtime is not configured" not in updated.summary


@pytest.mark.parametrize(
    "url",
    [
        "",
        "https://example.com/not-xiaoyuzhou",
    ],
)
def test_podcast_pipeline_rejects_invalid_episode_url(url: str):
    from agent_service.workflows.podcast import PodcastWorkflowError, validate_episode_url

    with pytest.raises(PodcastWorkflowError):
        validate_episode_url(url)
