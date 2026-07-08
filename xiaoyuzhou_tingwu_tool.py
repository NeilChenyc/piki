#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from html import unescape
from pathlib import Path
from typing import Any

import requests


DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/125.0.0.0 Safari/537.36"
    )
}

M4A_PATTERN = re.compile(r"https://media\.xyzcdn\.net/[^\s\"'<>]+?\.m4a")
TITLE_PATTERN = re.compile(r"<title>(.*?)</title>", re.IGNORECASE | re.DOTALL)
JSON_LD_PATTERN = re.compile(
    r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
    re.IGNORECASE | re.DOTALL,
)
TOOL_ERROR_PREFIX = "PIKI_TOOL_ERROR:"


@dataclass
class TingwuConfig:
    access_key_id: str
    access_key_secret: str
    app_key: str
    region_id: str = "cn-beijing"


def load_env_file(path: Path):
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def getenv_any(*keys: str, default: str = "") -> str:
    for key in keys:
        value = os.getenv(key)
        if value:
            return value.strip()
    return default


def sanitize_name(value: str) -> str:
    value = re.sub(r"[\\/:*?\"<>|]+", "-", value).strip()
    value = re.sub(r"\s+", " ", value)
    return value[:80] or "episode"


def fetch_episode_html(url: str) -> str:
    response = requests.get(url, headers=DEFAULT_HEADERS, timeout=30)
    response.raise_for_status()
    return response.text


def extract_title(html: str) -> str | None:
    match = TITLE_PATTERN.search(html)
    if not match:
        return None
    title = unescape(match.group(1)).strip()
    title = re.sub(r"\s*[|-]\s*小宇宙.*$", "", title)
    return title or None


def _extract_from_json_ld(html: str) -> str | None:
    for raw_block in JSON_LD_PATTERN.findall(html):
        try:
            payload = json.loads(unescape(raw_block.strip()))
        except json.JSONDecodeError:
            continue
        items = payload if isinstance(payload, list) else [payload]
        for item in items:
            media = item.get("associatedMedia") if isinstance(item, dict) else None
            if isinstance(media, dict):
                url = media.get("contentUrl")
                if isinstance(url, str) and url.endswith(".m4a"):
                    return url
    return None


def extract_episode_json_ld(html: str) -> dict[str, Any] | None:
    for raw_block in JSON_LD_PATTERN.findall(html):
        try:
            payload = json.loads(unescape(raw_block.strip()))
        except json.JSONDecodeError:
            continue
        items = payload if isinstance(payload, list) else [payload]
        for item in items:
            if isinstance(item, dict) and item.get("@type") == "PodcastEpisode":
                return item
    return None


def extract_m4a_url(html: str) -> str:
    og_audio = re.search(
        r'<meta[^>]+property=["\']og:audio["\'][^>]+content=["\']([^"\']+\.m4a)["\']',
        html,
        re.IGNORECASE,
    )
    if og_audio:
        return og_audio.group(1)

    json_ld_url = _extract_from_json_ld(html)
    if json_ld_url:
        return json_ld_url

    regex_match = M4A_PATTERN.search(html)
    if regex_match:
        return regex_match.group(0)

    raise ValueError("未能在网页源码中找到 .m4a 链接")


def extract_show_notes(html: str) -> str | None:
    episode = extract_episode_json_ld(html)
    if not episode:
        return None
    description = episode.get("description")
    if not isinstance(description, str):
        return None
    description = description.replace("\r\n", "\n").strip()
    if not description:
        return None
    return description


def render_show_notes_markdown(title: str | None, episode_url: str, show_notes: str) -> str:
    heading = title or "未命名单集"
    prompt = (
        "以下为作者/节目方撰写的整期内容官方概览，后续做 wiki 归档、实体识别、"
        "书名节目名校对、时间线整理或主题总结时，可以参考他表达的核心观点，"
        "如果它和摘要与转写全文（这些为语音转录的内容）出现名词上的冲突"
        "（如作者名不一致），以这份内容为准。"
    )
    return (
        f"# 官方节目概览说明（供 Wiki / LLM Agent 使用）\n\n"
        f"## 单集\n\n{heading}\n\n"
        f"## 来源\n\n{episode_url}\n\n"
        f"## 使用提示\n\n{prompt}\n\n"
        f"## 作者撰写的整期概览内容\n\n{show_notes}\n"
    )


def load_tingwu_config() -> TingwuConfig | None:
    load_env_file(Path(".env"))
    access_key_id = getenv_any(
        "ALIBABA_CLOUD_ACCESS_KEY_ID",
        "ALIYUN_ACCESS_KEY_ID",
        "accessKeyId",
        "access_key_id",
    )
    access_key_secret = getenv_any(
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET",
        "ALIYUN_ACCESS_KEY_SECRET",
        "accessKeySecret",
        "access_key_secret",
    )
    app_key = getenv_any("TINGWU_APP_KEY", "appkey", "app_key")
    region_id = getenv_any("TINGWU_REGION_ID", "region_id", default="cn-beijing") or "cn-beijing"

    if not (access_key_id and access_key_secret and app_key):
        return None

    return TingwuConfig(
        access_key_id=access_key_id,
        access_key_secret=access_key_secret,
        app_key=app_key,
        region_id=region_id,
    )


def create_tingwu_client(config: TingwuConfig):
    try:
        from aliyunsdkcore.client import AcsClient
    except ImportError as exc:
        raise RuntimeError(
            "缺少 aliyunsdkcore，请先执行: pip install aliyun-python-sdk-core"
        ) from exc

    return AcsClient(config.access_key_id, config.access_key_secret, config.region_id)


def tool_error_payload(exc: Exception) -> dict[str, Any]:
    detail = str(exc)
    sdk_code = _sdk_exception_value(exc, "get_error_code")
    if sdk_code:
        detail = f"{sdk_code} {detail}".strip()
    if sdk_code == "InvalidAccessKeyId.NotFound" or "InvalidAccessKeyId.NotFound" in detail:
        return _tool_error(
            code="podcast.tingwu.invalid_access_key",
            title="阿里云 AccessKey 无效",
            message="AccessKey ID 不存在或不属于当前阿里云账号。",
            recovery_suggestion="请在设置页检查 AccessKey ID 是否复制完整、是否属于当前账号，且没有误填为 AppKey。",
            action_label="打开播客转录设置",
            action_target="settings.tingwu",
            technical_detail=_technical_detail(exc),
        )
    if any(token in detail for token in ("SignatureDoesNotMatch", "InvalidAccessKeySecret")):
        return _tool_error(
            code="podcast.tingwu.invalid_access_key_secret",
            title="阿里云 AccessKey Secret 无效",
            message="AccessKey Secret 无法通过阿里云校验。",
            recovery_suggestion="请在设置页重新粘贴 AccessKey Secret，确认没有多余空格或复制遗漏。",
            action_label="打开播客转录设置",
            action_target="settings.tingwu",
            technical_detail=_technical_detail(exc),
        )
    if any(token in detail for token in ("NoPermission", "Forbidden", "Unauthorized", "AccessDenied")):
        return _tool_error(
            code="podcast.tingwu.permission_denied",
            title="阿里云账号缺少听悟权限",
            message="当前 AccessKey 没有调用通义听悟离线转写的权限。",
            recovery_suggestion="请确认阿里云账号已开通通义听悟，并给 RAM 用户授予对应访问权限。",
            action_label="打开播客转录设置",
            action_target="settings.tingwu",
            technical_detail=_technical_detail(exc),
        )
    if "AppKey" in detail or "appkey" in detail or "app_key" in detail:
        return _tool_error(
            code="podcast.tingwu.invalid_app_key",
            title="通义听悟 AppKey 无效",
            message="通义听悟项目 AppKey 无法通过校验。",
            recovery_suggestion="请在阿里云通义听悟项目页复制项目 AppKey，不要填写 AccessKey ID。",
            action_label="打开播客转录设置",
            action_target="settings.tingwu",
            technical_detail=_technical_detail(exc),
        )
    if isinstance(exc, requests.RequestException) or any(
        token in detail.lower()
        for token in ("timeout", "timed out", "connection", "network", "ssl")
    ):
        return _tool_error(
            code="podcast.network_error",
            title="播客转录网络连接失败",
            message="连接小宇宙或阿里云通义听悟时失败。",
            recovery_suggestion="请检查网络后重试。如果阿里云服务临时不可用，可以稍后再试。",
            retryable=True,
            technical_detail=_technical_detail(exc),
        )
    return _tool_error(
        code="podcast.failed",
        title="播客转录失败",
        message="播客转录没有完成。",
        recovery_suggestion="请稍后重试；如果问题持续，请检查播客链接和转录配置。",
        retryable=True,
        technical_detail=_technical_detail(exc),
    )


def emit_tool_error(exc: Exception) -> None:
    payload = tool_error_payload(exc)
    print(f"{TOOL_ERROR_PREFIX} {json.dumps(payload, ensure_ascii=False)}", file=sys.stderr)


def _tool_error(
    *,
    code: str,
    title: str,
    message: str,
    recovery_suggestion: str | None = None,
    retryable: bool = False,
    action_label: str | None = None,
    action_target: str | None = None,
    technical_detail: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "code": code,
        "title": title,
        "message": message,
        "retryable": retryable,
    }
    if recovery_suggestion:
        payload["recovery_suggestion"] = recovery_suggestion
    if action_label:
        payload["action_label"] = action_label
    if action_target:
        payload["action_target"] = action_target
    if technical_detail:
        payload["technical_detail"] = technical_detail
    return payload


def _sdk_exception_value(exc: Exception, accessor: str) -> str:
    getter = getattr(exc, accessor, None)
    if not callable(getter):
        return ""
    try:
        return str(getter() or "").strip()
    except Exception:
        return ""


def _technical_detail(exc: Exception) -> str:
    detail = str(exc).strip() or exc.__class__.__name__
    request_id = _sdk_exception_value(exc, "get_request_id")
    if request_id and "RequestID" not in detail:
        detail = f"{detail} RequestID: {request_id}"
    return detail


def request_with_sdk(client: Any, method: str, uri_pattern: str, body: dict[str, Any] | None = None):
    from aliyunsdkcore.request import CommonRequest

    request = CommonRequest()
    request.set_protocol_type("https")
    request.set_method(method)
    request.set_domain("tingwu.cn-beijing.aliyuncs.com")
    request.set_version("2023-09-30")
    request.set_uri_pattern(uri_pattern)
    request.add_query_param("type", "offline")
    if body is not None:
        request.set_content_type("application/json")
        request.set_content(json.dumps(body).encode("utf-8"))

    raw = client.do_action_with_exception(request)
    return json.loads(raw)


def submit_task(
    client: Any,
    config: TingwuConfig,
    file_url: str,
    task_key: str,
    source_language: str,
    enable_summary: bool,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "AppKey": config.app_key,
        "Input": {
            "SourceLanguage": source_language,
            "TaskKey": task_key,
            "FileUrl": file_url,
        },
        "Parameters": {
            "AutoChaptersEnabled": True,
            "AutoChapters": {
                "ChapterGranularity": "General",
                "TitleLengthLevel": "Normal",
            },
        },
    }
    if enable_summary:
        payload["Parameters"]["SummarizationEnabled"] = True
        payload["Parameters"]["Summarization"] = {
            "Types": ["Paragraph", "Conversational", "QuestionsAnswering"]
        }

    return request_with_sdk(client, "PUT", "/openapi/tingwu/v2/tasks", payload)


def get_task_info(client: Any, task_id: str) -> dict[str, Any]:
    return request_with_sdk(client, "GET", f"/openapi/tingwu/v2/tasks/{task_id}")


def poll_task(client: Any, task_id: str, poll_interval: int, timeout: int) -> dict[str, Any]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        payload = get_task_info(client, task_id)
        data = payload.get("Data", {})
        status = data.get("TaskStatus")
        print(f"[Tingwu] 当前任务状态: {status or 'UNKNOWN'}")
        if status in {"COMPLETED", "FAILED", "INVALID"}:
            return payload
        time.sleep(poll_interval)
    raise TimeoutError(f"等待任务 {task_id} 超时")


def download_url(url: str) -> tuple[bytes, str]:
    response = requests.get(url, headers=DEFAULT_HEADERS, timeout=60)
    response.raise_for_status()
    return response.content, response.headers.get("Content-Type", "")


def try_parse_json_bytes(content: bytes) -> Any | None:
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        return None


def unwrap_result_payload(payload: Any, key: str) -> Any:
    if isinstance(payload, dict) and key in payload:
        return payload[key]
    return payload


def save_raw_result(out_dir: Path, name: str, url: str) -> Path:
    content, content_type = download_url(url)
    suffix = ".json" if "json" in content_type or try_parse_json_bytes(content) is not None else ".txt"
    target = out_dir / f"{name}{suffix}"
    target.write_bytes(content)
    return target


def find_transcript_text(payload: Any) -> list[str]:
    lines: list[str] = []

    def walk(node: Any):
        if isinstance(node, dict):
            if isinstance(node.get("Text"), str):
                lines.append(node["Text"].strip())
            if isinstance(node.get("Content"), str):
                lines.append(node["Content"].strip())
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(payload)
    return [line for line in lines if line]


def render_transcription_from_paragraphs(paragraphs: list[dict[str, Any]]) -> str:
    blocks = ["# 转写全文", ""]

    for paragraph in paragraphs:
        words = paragraph.get("Words")
        if not isinstance(words, list) or not words:
            continue

        speaker_id = str(paragraph.get("SpeakerId", "")).strip()
        sentences: list[str] = []
        current_sentence_id = None
        current_parts: list[str] = []

        for word in words:
            if not isinstance(word, dict):
                continue
            sentence_id = word.get("SentenceId")
            text = word.get("Text")
            if not isinstance(text, str) or not text:
                continue

            if current_sentence_id is None:
                current_sentence_id = sentence_id

            if sentence_id != current_sentence_id:
                sentence = "".join(current_parts).strip()
                if sentence:
                    sentences.append(sentence)
                current_sentence_id = sentence_id
                current_parts = []

            current_parts.append(text)

        tail = "".join(current_parts).strip()
        if tail:
            sentences.append(tail)

        if not sentences:
            continue

        paragraph_text = "".join(sentences)
        if speaker_id:
            blocks.append(f"## 说话人 {speaker_id}\n")
        blocks.append(paragraph_text)
        blocks.append("")

    return "\n".join(blocks).strip() + "\n"


def render_transcription_markdown(payload: Any) -> str:
    payload = unwrap_result_payload(payload, "Transcription")
    if isinstance(payload, dict):
        paragraphs = payload.get("Paragraphs")
        if isinstance(paragraphs, list) and paragraphs:
            return render_transcription_from_paragraphs(paragraphs)
    lines = find_transcript_text(payload)
    if not lines:
        return "# 转写全文\n\n未能从返回 JSON 中提取正文，请查看原始结果文件。"
    body = "\n\n".join(lines)
    return f"# 转写全文\n\n{body}\n"


def render_chapters_markdown(payload: Any) -> str:
    payload = unwrap_result_payload(payload, "AutoChapters")
    chapters = []
    if isinstance(payload, dict):
        chapters = payload.get("AutoChapters") or payload.get("Chapters") or []
    elif isinstance(payload, list):
        chapters = payload

    if not isinstance(chapters, list) or not chapters:
        return "# 章节摘要\n\n未能从返回 JSON 中提取章节，请查看原始结果文件。"

    parts = ["# 章节摘要", ""]
    for idx, chapter in enumerate(chapters, start=1):
        headline = chapter.get("Headline") or chapter.get("Title") or f"第 {idx} 章"
        summary = chapter.get("Summary") or "暂无摘要"
        start = chapter.get("Start")
        end = chapter.get("End")
        timerange = ""
        if start is not None and end is not None:
            timerange = f"\n\n时间范围: {start} - {end} ms"
        parts.append(f"## {idx}. {headline}\n\n{summary}{timerange}\n")
    return "\n".join(parts)


def render_summary_markdown(payload: Any) -> str:
    payload = unwrap_result_payload(payload, "Summarization")
    if not isinstance(payload, dict):
        return "# 大模型摘要\n\n未能解析摘要结果。"

    blocks = ["# 大模型摘要", ""]
    paragraph = payload.get("ParagraphSummary")
    if paragraph:
        blocks.append("## 段落摘要\n")
        blocks.append(str(paragraph).strip())
        blocks.append("")

    for key, title in [
        ("ConversationalSummary", "对话式摘要"),
        ("QuestionsAnsweringSummary", "问答摘要"),
        ("MindMapSummary", "脑图摘要"),
    ]:
        items = payload.get(key)
        if items:
            blocks.append(f"## {title}\n")
            if isinstance(items, list):
                for item in items:
                    blocks.append(f"- {json.dumps(item, ensure_ascii=False)}")
            else:
                blocks.append(str(items))
            blocks.append("")

    return "\n".join(blocks).strip() + "\n"


def write_markdown(path: Path, content: str):
    path.write_text(content, encoding="utf-8")


def save_episode_metadata(out_dir: Path, episode_url: str, title: str | None, audio_url: str):
    payload = {
        "episode_url": episode_url,
        "title": title,
        "audio_url": audio_url,
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    (out_dir / "episode.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def save_show_notes(out_dir: Path, title: str | None, episode_url: str, show_notes: str | None):
    if not show_notes:
        return
    (out_dir / "show_notes.txt").write_text(show_notes, encoding="utf-8")
    for old_name in ["作者概览.md", "节目概览.md"]:
        old_markdown = out_dir / old_name
        if old_markdown.exists():
            old_markdown.unlink()
    write_markdown(
        out_dir / "官方节目概览.md",
        render_show_notes_markdown(title, episode_url, show_notes),
    )


def build_out_dir(base_dir: Path, episode_url: str, title: str | None) -> Path:
    episode_id = episode_url.rstrip("/").split("/")[-1]
    name = sanitize_name(title or episode_id)
    out_dir = base_dir / f"{episode_id}-{name}"
    out_dir.mkdir(parents=True, exist_ok=True)
    return out_dir


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="提取小宇宙音频链接，并在配置好听悟后获取转写全文与章节摘要。"
    )
    parser.add_argument("episode_url", help="小宇宙单集页面 URL")
    parser.add_argument(
        "--out-dir",
        default="outputs",
        help="输出目录，默认写入 ./outputs",
    )
    parser.add_argument(
        "--source-language",
        default="cn",
        help="听悟 SourceLanguage，默认 cn",
    )
    parser.add_argument(
        "--poll-interval",
        type=int,
        default=60,
        help="轮询任务状态的间隔秒数，默认 60",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=7200,
        help="等待任务完成的超时时间，默认 7200 秒",
    )
    parser.add_argument(
        "--task-id",
        help="已有听悟任务 ID；传入后将跳过创建任务，直接查询",
    )
    parser.add_argument(
        "--skip-tingwu",
        action="store_true",
        help="只提取 .m4a，不请求听悟",
    )
    parser.add_argument(
        "--without-summary",
        action="store_true",
        help="提交听悟任务时不启用大模型摘要",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    html = fetch_episode_html(args.episode_url)
    title = extract_title(html)
    audio_url = extract_m4a_url(html)
    show_notes = extract_show_notes(html)

    base_dir = Path(args.out_dir).resolve()
    out_dir = build_out_dir(base_dir, args.episode_url, title)
    save_episode_metadata(out_dir, args.episode_url, title, audio_url)
    save_show_notes(out_dir, title, args.episode_url, show_notes)

    print(f"[OK] 标题: {title or '未知'}")
    print(f"[OK] 音频链接: {audio_url}")
    print(f"[OK] Show notes: {'已提取' if show_notes else '未找到'}")
    print(f"[OK] 输出目录: {out_dir}")

    if args.skip_tingwu:
        return 0

    config = load_tingwu_config()
    if config is None:
        print(
            "[提示] 未检测到完整听悟配置。请设置环境变量 "
            "ALIBABA_CLOUD_ACCESS_KEY_ID / ALIBABA_CLOUD_ACCESS_KEY_SECRET / TINGWU_APP_KEY，"
            "或使用 --skip-tingwu 仅提取音频链接。"
        )
        return 0

    try:
        client = create_tingwu_client(config)
    except RuntimeError as exc:
        print(f"[提示] {exc}")
        return 0

    if args.task_id:
        task_id = args.task_id
        print(f"[Tingwu] 使用已有任务: {task_id}")
    else:
        task_key = f"xiaoyuzhou-{int(time.time())}"
        created = submit_task(
            client=client,
            config=config,
            file_url=audio_url,
            task_key=task_key,
            source_language=args.source_language,
            enable_summary=not args.without_summary,
        )
        data = created.get("Data", {})
        task_id = data.get("TaskId")
        if not task_id:
            print(json.dumps(created, ensure_ascii=False, indent=2))
            raise RuntimeError("创建听悟任务失败，返回中未找到 TaskId")
        print(f"[Tingwu] 已创建任务: {task_id}")
        (out_dir / "tingwu_create_task.json").write_text(
            json.dumps(created, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    task_info = poll_task(client, task_id, args.poll_interval, args.timeout)
    (out_dir / "tingwu_task_info.json").write_text(
        json.dumps(task_info, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    data = task_info.get("Data", {})
    status = data.get("TaskStatus")
    if status != "COMPLETED":
        print(f"[Tingwu] 任务未成功完成，状态: {status}")
        return 1

    result = data.get("Result", {}) or {}
    for key, renderer, md_name in [
        ("Transcription", render_transcription_markdown, "转写全文.md"),
        ("AutoChapters", render_chapters_markdown, "章节摘要.md"),
        ("Summarization", render_summary_markdown, "大模型摘要.md"),
    ]:
        result_url = result.get(key)
        if not result_url:
            continue
        raw_path = save_raw_result(out_dir, key.lower(), result_url)
        parsed = try_parse_json_bytes(raw_path.read_bytes())
        if parsed is not None:
            write_markdown(out_dir / md_name, renderer(parsed))
        print(f"[Tingwu] 已保存 {key}: {raw_path}")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("\n[中断] 已取消")
        raise SystemExit(130)
    except Exception as exc:
        emit_tool_error(exc)
        raise SystemExit(1)
