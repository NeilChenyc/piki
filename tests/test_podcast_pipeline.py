from pathlib import Path
from types import SimpleNamespace

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


def test_podcast_workflow_requires_tingwu_config_before_running_tool(tmp_path: Path, monkeypatch):
    from agent_service.workflows import podcast
    from agent_service.vault import Vault

    for name in (
        "ALIBABA_CLOUD_ACCESS_KEY_ID",
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET",
        "ALIYUN_ACCESS_KEY_ID",
        "ALIYUN_ACCESS_KEY_SECRET",
        "TINGWU_APP_KEY",
        "TINGWU_REGION_ID",
        "appkey",
        "app_key",
        "region_id",
    ):
        monkeypatch.delenv(name, raising=False)
    vault = _make_vault(tmp_path)

    def fail_if_called(*args, **kwargs):
        raise AssertionError("podcast tool should not run without Tingwu config")

    monkeypatch.setattr(podcast.subprocess, "run", fail_if_called)

    with pytest.raises(podcast.PodcastWorkflowError, match="播客转录功能尚未配置"):
        podcast.run_podcast_transcription(
            vault=Vault(vault),
            episode_url="https://www.xiaoyuzhoufm.com/episode/abc",
            config=ServiceConfig(
                db_path=tmp_path / "agent.sqlite3",
                runtime_config_path=tmp_path / "runtime-config.json",
                enable_agent_runtime=False,
            ),
        )


def test_podcast_workflow_checks_tingwu_config_before_episode_url(tmp_path: Path, monkeypatch):
    from agent_service.workflows import podcast
    from agent_service.vault import Vault

    for name in (
        "ALIBABA_CLOUD_ACCESS_KEY_ID",
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET",
        "ALIYUN_ACCESS_KEY_ID",
        "ALIYUN_ACCESS_KEY_SECRET",
        "TINGWU_APP_KEY",
        "TINGWU_REGION_ID",
        "appkey",
        "app_key",
        "region_id",
    ):
        monkeypatch.delenv(name, raising=False)
    vault = _make_vault(tmp_path)

    with pytest.raises(podcast.PodcastWorkflowError, match="播客转录功能尚未配置"):
        podcast.run_podcast_transcription(
            vault=Vault(vault),
            episode_url="",
            config=ServiceConfig(
                db_path=tmp_path / "agent.sqlite3",
                runtime_config_path=tmp_path / "runtime-config.json",
                enable_agent_runtime=False,
            ),
        )


def test_podcast_workflow_reports_missing_episode_url_after_configured(tmp_path: Path):
    from agent_service.workflows import podcast
    from agent_service.vault import Vault

    vault = _make_vault(tmp_path)

    with pytest.raises(podcast.PodcastWorkflowError, match="缺少播客单集链接"):
        podcast.run_podcast_transcription(
            vault=Vault(vault),
            episode_url="",
            config=ServiceConfig(
                db_path=tmp_path / "agent.sqlite3",
                runtime_config_path=tmp_path / "runtime-config.json",
                enable_agent_runtime=False,
                aliyun_access_key_id="LTAI-test-access",
                aliyun_access_key_secret="aliyun-secret-value",
                tingwu_app_key="tingwu-app-key",
                tingwu_region_id="cn-beijing",
            ),
        )


def test_podcast_workflow_injects_tingwu_env_and_emits_waiting_progress(tmp_path: Path, monkeypatch):
    from agent_service.workflows import podcast
    from agent_service.vault import Vault

    vault = _make_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    events = EventPublisher(store)
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.LOW,
        vault_path=str(vault),
        user_input="请转录这个播客",
        status=TaskStatus.RUNNING,
        summary="podcast test",
    )
    captured_env = {}

    def fake_run(command, cwd, capture_output, text, env):
        captured_env.update(env)
        out_root = Path(command[command.index("--out-dir") + 1])
        out_dir = out_root / "abc-test-podcast"
        out_dir.mkdir(parents=True)
        (out_dir / "episode.json").write_text(
            '{"title": "测试播客", "audio_url": "https://example.com/audio.m4a"}',
            encoding="utf-8",
        )
        (out_dir / "转写全文.md").write_text("# 转写全文\n\n你好，Piki。", encoding="utf-8")
        return SimpleNamespace(returncode=0, stdout=f"[OK] 输出目录: {out_dir}\n", stderr="")

    monkeypatch.setattr(podcast.subprocess, "run", fake_run)

    result = podcast.run_podcast_transcription(
        vault=Vault(vault),
        episode_url="https://www.xiaoyuzhoufm.com/episode/abc",
        events=events,
        task_id=task.id,
        config=ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            enable_agent_runtime=False,
            aliyun_access_key_id="LTAI-test-access",
            aliyun_access_key_secret="aliyun-secret-value",
            tingwu_app_key="tingwu-app-key",
            tingwu_region_id="cn-shanghai",
        ),
    )

    assert result["source_path"].startswith("raw/sources/")
    assert captured_env["ALIBABA_CLOUD_ACCESS_KEY_ID"] == "LTAI-test-access"
    assert captured_env["ALIBABA_CLOUD_ACCESS_KEY_SECRET"] == "aliyun-secret-value"
    assert captured_env["TINGWU_APP_KEY"] == "tingwu-app-key"
    assert captured_env["TINGWU_REGION_ID"] == "cn-shanghai"
    progress_events = [event for event in store.list_events(task.id) if event.type == "agent.progress"]
    assert any("预计耗时几分钟" in str(event.payload.get("detail", "")) for event in progress_events)


def test_podcast_workflow_maps_invalid_access_key_to_user_facing_error(tmp_path: Path, monkeypatch):
    from agent_service.workflows import podcast
    from agent_service.vault import Vault

    vault = _make_vault(tmp_path)

    def fake_run(command, cwd, capture_output, text, env):
        return SimpleNamespace(
            returncode=1,
            stdout="",
            stderr=(
                'PIKI_TOOL_ERROR: {"code":"podcast.tingwu.invalid_access_key",'
                '"title":"阿里云 AccessKey 无效",'
                '"message":"AccessKey ID 不存在或不属于当前阿里云账号。",'
                '"recovery_suggestion":"请在设置页检查 AccessKey ID 是否复制完整，且没有误填为 AppKey。",'
                '"retryable":false,'
                '"action_label":"打开播客转录设置",'
                '"action_target":"settings.tingwu",'
                '"technical_detail":"HTTP Status: 404 Error:InvalidAccessKeyId.NotFound RequestID: req-1"}'
            ),
        )

    monkeypatch.setattr(podcast.subprocess, "run", fake_run)

    with pytest.raises(podcast.PodcastWorkflowError) as exc_info:
        podcast.run_podcast_transcription(
            vault=Vault(vault),
            episode_url="https://www.xiaoyuzhoufm.com/episode/abc",
            config=ServiceConfig(
                db_path=tmp_path / "agent.sqlite3",
                runtime_config_path=tmp_path / "runtime-config.json",
                enable_agent_runtime=False,
                aliyun_access_key_id="bad-access-key",
                aliyun_access_key_secret="aliyun-secret-value",
                tingwu_app_key="tingwu-app-key",
                tingwu_region_id="cn-beijing",
            ),
        )

    error = exc_info.value.user_error
    assert error.code == "podcast.tingwu.invalid_access_key"
    assert error.title == "阿里云 AccessKey 无效"
    assert error.action_target == "settings.tingwu"
    assert "Traceback" not in str(exc_info.value)


def test_podcast_tool_classifies_aliyun_invalid_access_key_without_traceback():
    from aliyunsdkcore.acs_exception.exceptions import ServerException
    from xiaoyuzhou_tingwu_tool import tool_error_payload

    payload = tool_error_payload(
        ServerException(
            "InvalidAccessKeyId.NotFound",
            "Specified access key is not found.",
            404,
            "req-1",
        )
    )

    assert payload["code"] == "podcast.tingwu.invalid_access_key"
    assert payload["action_target"] == "settings.tingwu"
    assert "Traceback" not in payload["message"]
    assert "req-1" in payload["technical_detail"]


def test_podcast_task_failed_event_uses_structured_user_error(tmp_path: Path, monkeypatch):
    from agent_service.system.actions import DeterministicActionExecutor
    from agent_service.workflows import podcast

    vault = _make_vault(tmp_path)
    store = SQLiteStore(tmp_path / "agent.sqlite3")
    events = EventPublisher(store)
    task = store.create_task(
        task_kind=TaskKind.AGENT,
        risk_level=RiskLevel.LOW,
        vault_path=str(vault),
        user_input="请播客转录",
        status=TaskStatus.RUNNING,
        summary="podcast test",
    )

    def fake_run(command, cwd, capture_output, text, env):
        return SimpleNamespace(
            returncode=1,
            stdout="",
            stderr=(
                "Traceback (most recent call last):\n"
                "aliyunsdkcore.acs_exception.exceptions.ServerException: "
                "HTTP Status: 404 Error:InvalidAccessKeyId.NotFound "
                "Specified access key is not found. RequestID: req-1"
            ),
        )

    monkeypatch.setattr(podcast.subprocess, "run", fake_run)
    executor = DeterministicActionExecutor(
        store=store,
        events=events,
        config=ServiceConfig(
            db_path=tmp_path / "agent.sqlite3",
            runtime_config_path=tmp_path / "runtime-config.json",
            enable_agent_runtime=False,
            aliyun_access_key_id="bad-access-key",
            aliyun_access_key_secret="aliyun-secret-value",
            tingwu_app_key="tingwu-app-key",
            tingwu_region_id="cn-beijing",
        ),
    )

    executor.execute(
        task_id=task.id,
        request=TaskCreateRequest(
            vault_path=vault,
            user_input="请播客转录",
            action_context={"action": "podcast_transcribe", "podcast_url": "https://www.xiaoyuzhoufm.com/episode/abc"},
        ),
    )

    updated = store.get_task(task.id)
    failed_events = [event for event in store.list_events(task.id) if event.type == "task.failed"]

    assert updated.status == TaskStatus.FAILED
    assert failed_events[-1].payload["error_code"] == "podcast.tingwu.invalid_access_key"
    assert failed_events[-1].payload["action_target"] == "settings.tingwu"
    assert "Traceback" not in failed_events[-1].payload["error"]
    assert "Traceback" not in updated.summary


def test_task_service_normalizes_podcast_keyword_and_episode_url():
    from agent_service.application.task_service import _normalize_task_request

    request = TaskCreateRequest(
        vault_path=Path("/tmp/vault"),
        user_input="请帮我播客转录 https://www.xiaoyuzhoufm.com/episode/abc123",
    )

    normalized = _normalize_task_request(request)

    assert normalized.action_context["action"] == "podcast_transcribe"
    assert normalized.action_context["podcast_url"] == "https://www.xiaoyuzhoufm.com/episode/abc123"


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
