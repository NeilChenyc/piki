from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

from agent_service.models import EventType
from agent_service.vault import Vault
from agent_service.workflows.ingest import read_source_meta, validate_canonical_source


PODCAST_URL_PATTERN = re.compile(r"^https://www\.xiaoyuzhoufm\.com/episode/[A-Za-z0-9]+/?$")


class PodcastWorkflowError(ValueError):
    pass


def validate_episode_url(url: str) -> str:
    normalized = str(url or "").strip()
    if not normalized:
        raise PodcastWorkflowError("缺少播客单集链接。")
    if not PODCAST_URL_PATTERN.match(normalized):
        raise PodcastWorkflowError("当前只支持小宇宙单集页面链接。")
    return normalized.rstrip("/")


def run_podcast_transcription(
    *,
    vault: Vault,
    episode_url: str,
    events=None,
    task_id: str | None = None,
    out_dir_name: str = "podcast-imports",
) -> dict[str, str]:
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

    command = [
        sys.executable,
        str(_tool_script_path()),
        normalized_url,
        "--out-dir",
        str(output_root),
    ]
    completed = subprocess.run(
        command,
        cwd=str(vault.root.parent),
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        stdout = completed.stdout.strip()
        detail = stderr or stdout or "播客转录失败。"
        raise PodcastWorkflowError(detail)

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
