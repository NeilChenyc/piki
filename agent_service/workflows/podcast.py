from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

from agent_service.errors import UserFacingError
from agent_service.config import ServiceConfig
from agent_service.models import EventType
from agent_service.vault import Vault
from agent_service.workflows.ingest import read_source_meta, validate_canonical_source


PODCAST_URL_PATTERN = re.compile(r"^https://www\.xiaoyuzhoufm\.com/episode/[A-Za-z0-9]+/?$")
TOOL_ERROR_PREFIX = "PIKI_TOOL_ERROR:"


class PodcastWorkflowError(ValueError):
    def __init__(self, message: str | None = None, *, user_error: UserFacingError | None = None):
        self.user_error = user_error or _podcast_user_error(
            code="podcast.failed",
            title="播客转录失败",
            message=message or "播客转录失败。",
            recovery_suggestion="请稍后重试；如果问题持续，请检查播客链接和转录配置。",
        )
        super().__init__(f"{self.user_error.title}：{self.user_error.message}")


def validate_episode_url(url: str) -> str:
    normalized = str(url or "").strip()
    if not normalized:
        raise PodcastWorkflowError(
            user_error=_podcast_user_error(
                code="podcast.missing_episode_url",
                title="缺少播客单集链接",
                message="请先粘贴一条小宇宙单集链接。",
                recovery_suggestion="目前支持形如 https://www.xiaoyuzhoufm.com/episode/... 的单集页面。",
            )
        )
    if not PODCAST_URL_PATTERN.match(normalized):
        raise PodcastWorkflowError(
            user_error=_podcast_user_error(
                code="podcast.unsupported_url",
                title="暂不支持这个播客链接",
                message="当前只支持小宇宙单集页面链接。",
                recovery_suggestion="请确认链接来自小宇宙单集页面，而不是节目主页、RSS 或其他播客平台。",
            )
        )
    return normalized.rstrip("/")


def run_podcast_transcription(
    *,
    vault: Vault,
    episode_url: str,
    events=None,
    task_id: str | None = None,
    out_dir_name: str = "podcast-imports",
    config: ServiceConfig | None = None,
) -> dict[str, str]:
    if config is not None and not config.tingwu_configured:
        raise PodcastWorkflowError(
            user_error=_podcast_user_error(
                code="podcast.tingwu.missing_config",
                title="播客转录功能尚未配置",
                message="请先在设置页填写阿里云通义听悟 AccessKey 和 AppKey。",
                recovery_suggestion="配置完成后再发送播客转录请求，费用会走你自己的阿里云账号。",
                action_label="打开播客转录设置",
                action_target="settings.tingwu",
            )
        )
    normalized_url = validate_episode_url(episode_url)

    output_root = vault.root / "raw" / "podcast" / out_dir_name
    output_root.mkdir(parents=True, exist_ok=True)

    if events is not None and task_id is not None:
        events.emit(
            task_id,
            EventType.AGENT_PROGRESS,
            {
                "stage": "podcast_fetch",
                "title": "正在解析播客链接",
                "detail": "正在抓取节目页和音频信息。",
                "category": "command",
            },
        )

    if events is not None and task_id is not None:
        events.emit(
            task_id,
            EventType.AGENT_PROGRESS,
            {
                "stage": "podcast_transcribe",
                "title": "正在转录播客",
                "detail": "正在调用阿里云通义听悟，预计耗时几分钟，请稍后。",
                "category": "command",
            },
        )

    command = [
        sys.executable,
        str(_tool_script_path()),
        normalized_url,
        "--out-dir",
        str(output_root),
    ]
    subprocess_env = os.environ.copy()
    if config is not None:
        subprocess_env.update(config.tingwu_environment())
    completed = subprocess.run(
        command,
        cwd=str(vault.root.parent),
        capture_output=True,
        text=True,
        env=subprocess_env,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        stdout = completed.stdout.strip()
        detail = stderr or stdout or "播客转录失败。"
        raise PodcastWorkflowError(user_error=_user_error_from_tool_failure(stdout=stdout, stderr=stderr, fallback=detail))

    if events is not None and task_id is not None:
        events.emit(
            task_id,
            EventType.AGENT_PROGRESS,
            {
                "stage": "podcast_transcribe",
                "title": "正在转录播客",
                "detail": "播客预处理已完成，正在整理转录产物。",
                "category": "command",
            },
        )

    out_dir = _parse_output_dir_from_stdout(completed.stdout) or _latest_output_dir(output_root)
    if out_dir is None:
        raise PodcastWorkflowError("播客转录完成，但未找到输出目录。")

    source_path = _write_podcast_canonical_source(vault=vault, out_dir=out_dir, episode_url=normalized_url)
    source_path = validate_canonical_source(vault, source_path)
    source_meta = read_source_meta(vault, source_path)

    if events is not None and task_id is not None:
        events.emit(
            task_id,
            EventType.AGENT_PROGRESS,
            {
                "stage": "podcast_ingest_prepare",
                "title": "正在整理进知识库",
                "detail": f"已生成 canonical source：{source_path}",
                "category": "write",
            },
        )

    return {
        "episode_url": normalized_url,
        "output_dir": str(out_dir),
        "source_path": source_path,
        "source_title": source_meta.title,
    }


def _tool_script_path() -> Path:
    return Path(__file__).resolve().parents[2] / "xiaoyuzhou_tingwu_tool.py"


def _parse_output_dir_from_stdout(stdout: str) -> Path | None:
    for raw_line in stdout.splitlines():
        line = raw_line.strip()
        prefix = "[OK] 输出目录:"
        if line.startswith(prefix):
            candidate = line.removeprefix(prefix).strip()
            if candidate:
                path = Path(candidate).expanduser().resolve()
                if path.exists():
                    return path
    return None


def _latest_output_dir(output_root: Path) -> Path | None:
    if not output_root.exists():
        return None
    candidates = [path for path in output_root.iterdir() if path.is_dir()]
    if not candidates:
        return None
    return max(candidates, key=lambda item: item.stat().st_mtime)


def _write_podcast_canonical_source(*, vault: Vault, out_dir: Path, episode_url: str) -> str:
    episode = _read_json(out_dir / "episode.json")
    title = str(episode.get("title") or out_dir.name).strip() or out_dir.name
    audio_url = str(episode.get("audio_url") or "").strip()
    body_sections: list[str] = []

    official_notes = _read_text_if_exists(out_dir / "官方节目概览.md")
    transcript = _read_text_if_exists(out_dir / "转写全文.md")
    chapter_summary = _read_text_if_exists(out_dir / "章节摘要.md")
    llm_summary = _read_text_if_exists(out_dir / "大模型摘要.md")

    if official_notes:
        body_sections.append("## 官方节目概览\n\n" + official_notes.strip())
    if transcript:
        body_sections.append("## 转写全文\n\n" + _strip_title_heading(transcript).strip())
    if chapter_summary:
        body_sections.append("## 章节摘要\n\n" + _strip_title_heading(chapter_summary).strip())
    if llm_summary:
        body_sections.append("## 大模型摘要\n\n" + _strip_title_heading(llm_summary).strip())

    if not body_sections:
        raise PodcastWorkflowError("播客转录完成，但未找到可写入知识库的正文内容。")

    slug = _slugify(title)
    source_path = f"raw/sources/{slug}.md"
    payload = {
        "title": title,
        "type": "raw-source",
        "format": "podcast",
        "source_kind": "podcast_episode",
        "episode_url": episode_url,
        "audio_url": audio_url,
        "generated_from": str(out_dir),
    }
    frontmatter_lines = ["---"]
    for key, value in payload.items():
        frontmatter_lines.append(f"{key}: {json.dumps(value, ensure_ascii=False)}")
    frontmatter_lines.extend(
        [
            "---",
            "",
            f"# {title}",
            "",
            "## 来源元数据",
            "",
            f"- 单集链接：`{episode_url}`",
            f"- 音频链接：`{audio_url}`" if audio_url else "- 音频链接：`未提供`",
            f"- 预处理目录：`{out_dir}`",
            "",
        ]
    )
    markdown = "\n".join(frontmatter_lines + body_sections + [""])
    return vault.write_text(source_path, markdown)


def _read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def _read_text_if_exists(path: Path) -> str:
    if not path.exists():
        return ""
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise PodcastWorkflowError(f"读取播客产物失败：{path.name}: {exc}") from exc


def _strip_title_heading(text: str) -> str:
    lines = text.splitlines()
    if lines and lines[0].startswith("# "):
        return "\n".join(lines[1:]).lstrip()
    return text


def _slugify(title: str) -> str:
    normalized = re.sub(r"[^\w\u3400-\u9fff]+", "-", title.lower()).strip("-_")
    normalized = re.sub(r"-+", "-", normalized).strip("-")
    if not normalized:
        normalized = "podcast-episode"
    return f"{normalized[:64]}-podcast"


def _podcast_user_error(
    *,
    code: str,
    title: str,
    message: str,
    recovery_suggestion: str | None = None,
    retryable: bool = False,
    action_label: str | None = None,
    action_target: str | None = None,
    technical_detail: str | None = None,
) -> UserFacingError:
    return UserFacingError(
        code=code,
        title=title,
        message=message,
        recovery_suggestion=recovery_suggestion,
        retryable=retryable,
        action_label=action_label,
        action_target=action_target,
        technical_detail=technical_detail,
    )


def _user_error_from_tool_failure(*, stdout: str, stderr: str, fallback: str) -> UserFacingError:
    parsed = _parse_tool_error_payload(stdout=stdout, stderr=stderr)
    if parsed is not None:
        return parsed
    return _classify_tool_failure(fallback)


def _parse_tool_error_payload(*, stdout: str, stderr: str) -> UserFacingError | None:
    for line in f"{stdout}\n{stderr}".splitlines():
        marker_index = line.find(TOOL_ERROR_PREFIX)
        if marker_index == -1:
            continue
        raw_payload = line[marker_index + len(TOOL_ERROR_PREFIX):].strip()
        try:
            payload = json.loads(raw_payload)
        except json.JSONDecodeError:
            continue
        if not isinstance(payload, dict):
            continue
        message = str(payload.get("message") or payload.get("error") or "播客转录失败。").strip()
        return _podcast_user_error(
            code=str(payload.get("code") or "podcast.failed"),
            title=str(payload.get("title") or "播客转录失败"),
            message=message,
            recovery_suggestion=_optional_payload_text(payload.get("recovery_suggestion")),
            retryable=bool(payload.get("retryable")),
            action_label=_optional_payload_text(payload.get("action_label")),
            action_target=_optional_payload_text(payload.get("action_target")),
            technical_detail=_optional_payload_text(payload.get("technical_detail")),
        )
    return None


def _classify_tool_failure(detail: str) -> UserFacingError:
    normalized = detail or "播客转录失败。"
    compact_detail = _compact_technical_detail(normalized)
    if "InvalidAccessKeyId.NotFound" in normalized:
        return _invalid_access_key_error(compact_detail)
    if "SignatureDoesNotMatch" in normalized or "InvalidAccessKeySecret" in normalized:
        return _podcast_user_error(
            code="podcast.tingwu.invalid_access_key_secret",
            title="阿里云 AccessKey Secret 无效",
            message="AccessKey Secret 无法通过阿里云校验。",
            recovery_suggestion="请在设置页重新粘贴 AccessKey Secret，确认没有多余空格或复制遗漏。",
            action_label="打开播客转录设置",
            action_target="settings.tingwu",
            technical_detail=compact_detail,
        )
    if any(token in normalized for token in ("NoPermission", "Forbidden", "Unauthorized", "AccessDenied")):
        return _podcast_user_error(
            code="podcast.tingwu.permission_denied",
            title="阿里云账号缺少听悟权限",
            message="当前 AccessKey 没有调用通义听悟离线转写的权限。",
            recovery_suggestion="请确认阿里云账号已开通通义听悟，并给 RAM 用户授予对应访问权限。",
            action_label="打开播客转录设置",
            action_target="settings.tingwu",
            technical_detail=compact_detail,
        )
    if "AppKey" in normalized or "appkey" in normalized or "app_key" in normalized:
        return _podcast_user_error(
            code="podcast.tingwu.invalid_app_key",
            title="通义听悟 AppKey 无效",
            message="通义听悟项目 AppKey 无法通过校验。",
            recovery_suggestion="请在阿里云通义听悟项目页复制项目 AppKey，不要填写 AccessKey ID。",
            action_label="打开播客转录设置",
            action_target="settings.tingwu",
            technical_detail=compact_detail,
        )
    if any(token in normalized.lower() for token in ("timeout", "timed out", "connection", "network", "ssl")):
        return _podcast_user_error(
            code="podcast.network_error",
            title="播客转录网络连接失败",
            message="连接小宇宙或阿里云通义听悟时失败。",
            recovery_suggestion="请检查网络后重试。如果阿里云服务临时不可用，可以稍后再试。",
            retryable=True,
            technical_detail=compact_detail,
        )
    return _podcast_user_error(
        code="podcast.failed",
        title="播客转录失败",
        message="播客转录没有完成。",
        recovery_suggestion="请稍后重试；如果问题持续，请检查播客链接和转录配置。",
        retryable=True,
        technical_detail=compact_detail,
    )


def _invalid_access_key_error(technical_detail: str | None = None) -> UserFacingError:
    return _podcast_user_error(
        code="podcast.tingwu.invalid_access_key",
        title="阿里云 AccessKey 无效",
        message="AccessKey ID 不存在或不属于当前阿里云账号。",
        recovery_suggestion="请在设置页检查 AccessKey ID 是否复制完整、是否属于当前账号，且没有误填为 AppKey。",
        action_label="打开播客转录设置",
        action_target="settings.tingwu",
        technical_detail=technical_detail,
    )


def _compact_technical_detail(value: str) -> str:
    lines = [line.strip() for line in value.splitlines() if line.strip()]
    return " | ".join(lines)[-4000:]


def _optional_payload_text(value) -> str | None:
    text = str(value or "").strip()
    return text or None
