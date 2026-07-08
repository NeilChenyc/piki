#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import mimetypes
import shutil
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CASES_PATH = ROOT / "docs/development/agent_regression_cases.json"
DEFAULT_VAULT_PATH = ROOT / "piki-vault"
DEFAULT_OUTPUT_DIR = ROOT / "outputs/agent-regression"
UTC = timezone.utc


@dataclass
class HttpResponse:
    status: int
    body: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run real agent regression cases against the local Agent Service.")
    parser.add_argument("--service-url", default="http://127.0.0.1:8000")
    parser.add_argument("--vault-path", type=Path, default=DEFAULT_VAULT_PATH)
    parser.add_argument("--cases-path", type=Path, default=DEFAULT_CASES_PATH)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--timeout-seconds", type=int, default=240)
    parser.add_argument("--poll-interval", type=float, default=1.0)
    parser.add_argument("--case-id", action="append", dest="case_ids", default=[])
    parser.add_argument("--keep-temp-vault", action="store_true")
    return parser.parse_args()


def request_json(
    method: str,
    url: str,
    *,
    payload: dict | None = None,
    headers: dict[str, str] | None = None,
) -> dict:
    data = None
    merged_headers = {"Accept": "application/json"}
    if headers:
        merged_headers.update(headers)
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        merged_headers["Content-Type"] = "application/json"
    response = request(method, url, data=data, headers=merged_headers)
    return json.loads(response.body)


def request(
    method: str,
    url: str,
    *,
    data: bytes | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = 30,
) -> HttpResponse:
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return HttpResponse(status=response.status, body=response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {url} failed with {exc.code}: {body}") from exc


def upload_file(service_url: str, file_path: Path) -> dict:
    boundary = f"----PikiBoundary{uuid.uuid4().hex}"
    file_bytes = file_path.read_bytes()
    mime_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
    parts = [
        f"--{boundary}\r\n".encode("utf-8"),
        (
            f'Content-Disposition: form-data; name="file"; filename="{file_path.name}"\r\n'
            f"Content-Type: {mime_type}\r\n\r\n"
        ).encode("utf-8"),
        file_bytes,
        b"\r\n",
        f"--{boundary}\r\n".encode("utf-8"),
        b'Content-Disposition: form-data; name="original_path"\r\n\r\n',
        str(file_path).encode("utf-8"),
        b"\r\n",
        f"--{boundary}--\r\n".encode("utf-8"),
    ]
    body = b"".join(parts)
    response = request(
        "POST",
        f"{service_url}/uploads",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    return json.loads(response.body)


def load_cases(path: Path, selected_case_ids: list[str]) -> list[dict]:
    cases = json.loads(path.read_text(encoding="utf-8"))
    if selected_case_ids:
        wanted = set(selected_case_ids)
        cases = [case for case in cases if case["case_id"] in wanted]
    return cases


def create_temp_vault(source_vault: Path) -> tuple[Path, tempfile.TemporaryDirectory[str]]:
    temp_root = tempfile.TemporaryDirectory(prefix="piki-agent-regression-")
    vault_copy = Path(temp_root.name) / "vault"
    shutil.copytree(source_vault, vault_copy)
    return vault_copy, temp_root


def build_attachment_file(temp_root: Path) -> Path:
    attachment = temp_root / "agent-eval-note.md"
    attachment.write_text(
        "\n".join(
            [
                "# Agent 测试上传文档",
                "",
                "这是一份用于 Piki Agent 回归测试的上传文档。",
                "",
                "## 要点",
                "- 本轮测试模型：claude-sonnet-4-6",
                "- 目标：验证上传文件后能够被 agent 读取、整理并写入 wiki",
                "- 期望：不要卡死，不要只读 raw，不要在最终阶段超出最大轮次",
                "",
                "## 附加说明",
                "文档中提到了 Piki 的 agent 体验、知识库 health 与回归测试集。",
            ]
        ),
        encoding="utf-8",
    )
    return attachment


def wait_for_task(service_url: str, task_id: str, *, timeout_seconds: int, poll_interval: float) -> dict:
    started = time.monotonic()
    while True:
        task = request_json("GET", f"{service_url}/tasks/{task_id}")
        if task["status"] != "running":
            return task
        if time.monotonic() - started >= timeout_seconds:
            task["_timed_out"] = True
            return task
        time.sleep(poll_interval)


def fetch_events_text(service_url: str, task_id: str, *, timeout_seconds: float = 10) -> str:
    response = request(
        "GET",
        f"{service_url}/tasks/{task_id}/events",
        headers={"Accept": "text/event-stream"},
        timeout=timeout_seconds,
    )
    return response.body


def parse_sse(events_text: str) -> list[dict]:
    events: list[dict] = []
    event_type = None
    data_lines: list[str] = []
    for raw_line in events_text.splitlines():
        if raw_line.startswith("event: "):
            event_type = raw_line[len("event: ") :]
        elif raw_line.startswith("data: "):
            data_lines.append(raw_line[len("data: ") :])
        elif not raw_line.strip():
            if event_type:
                payload = {}
                if data_lines:
                    payload = json.loads("\n".join(data_lines))
                events.append({"type": event_type, "payload": payload})
            event_type = None
            data_lines = []
    return events


def summarize_events(events: list[dict]) -> dict:
    event_types = [event["type"] for event in events]
    tool_summaries: list[str] = []
    trace_deltas: list[str] = []
    message_deltas: list[str] = []
    journal_entry_id = None
    for event in events:
        payload = event["payload"].get("payload", {})
        if event["type"] == "tool.started":
            title = payload.get("title") or payload.get("tool") or "tool"
            summary = payload.get("summary") or ""
            tool_summaries.append(f"{title}: {summary}".strip(": "))
        elif event["type"] == "agent.trace.delta":
            content = payload.get("content") or payload.get("delta") or ""
            if content:
                trace_deltas.append(content)
        elif event["type"] == "message.delta":
            content = payload.get("content") or payload.get("delta") or ""
            if content:
                message_deltas.append(content)
        elif event["type"] == "journal.created":
            journal_entry_id = payload.get("journal_entry_id")
    return {
        "event_types": event_types,
        "process_events_present": any(evt in event_types for evt in ("agent.progress", "tool.started", "tool.finished")),
        "tool_summaries": tool_summaries[:20],
        "trace_excerpt": "".join(trace_deltas)[:800],
        "message_excerpt": "".join(message_deltas)[:800],
        "journal_entry_id": journal_entry_id,
    }


def evaluate_case(case: dict, task: dict, event_summary: dict) -> dict:
    answer = ((task.get("output") or {}).get("answer")) or ""
    affected_files = (task.get("output") or {}).get("affected_files") or []
    verdict = "pass"
    issues: list[str] = []

    if task.get("_timed_out"):
        verdict = "fail"
        issues.append("timed_out")
    elif task["status"] == "failed":
        verdict = "fail"
        issues.append("task_failed")

    case_id = case["case_id"]
    if case_id in {"1", "2", "4"} and affected_files:
        verdict = "warn" if verdict == "pass" else verdict
        issues.append("unexpected_write")
    if case_id == "3" and task["status"] != "completed":
        verdict = "fail"
        issues.append("synthesis_unstable")
    if case_id == "5" and not affected_files:
        verdict = "fail"
        issues.append("record_missing_write")
    if case_id == "6":
        if task["status"] != "completed":
            verdict = "fail"
            issues.append("upload_ingest_failed")
        required_prefixes = ("raw/sources/", "raw/assets/", "wiki/sources/")
        if not any(path.startswith(required_prefixes[0]) for path in affected_files):
            verdict = "fail"
            issues.append("missing_raw_source_write")
        if not any(path.startswith(required_prefixes[2]) for path in affected_files):
            verdict = "fail"
            issues.append("missing_source_page_write")
    if case_id == "7" and not any("wiki/entities/孟岩.md" == path for path in affected_files):
        verdict = "fail"
        issues.append("target_page_not_updated")
    if case_id == "8" and "lint" not in answer.lower() and "问题" not in answer:
        verdict = "warn" if verdict == "pass" else verdict
        issues.append("lint_summary_unclear")
    if not event_summary["process_events_present"]:
        verdict = "warn" if verdict == "pass" else verdict
        issues.append("missing_process_events")
    if event_summary.get("events_fetch_timed_out"):
        verdict = "warn" if verdict == "pass" else verdict
        issues.append("events_fetch_timed_out")

    return {
        "verdict": verdict,
        "issues": issues,
    }


def run_case(
    *,
    service_url: str,
    vault_path: Path,
    case: dict,
    timeout_seconds: int,
    poll_interval: float,
    conversation_ids: dict[str, str],
    attachment_buffered_path: str | None,
) -> dict:
    payload: dict = {
        "vault_path": str(vault_path),
        "user_input": case["prompt"],
        "async_mode": True,
    }
    conversation_group = case.get("conversation_group")
    if case.get("depends_on_case_id"):
        dependency_group = next(
            (group for group, cid in conversation_ids.items() if cid == conversation_ids.get(group)),
            None,
        )
        del dependency_group
    if case.get("depends_on_case_id"):
        dependent = case["depends_on_case_id"]
        for group, conversation_id in conversation_ids.items():
            if group == cases_by_id[dependent]["conversation_group"]:
                payload["conversation_id"] = conversation_id
                break
    elif conversation_group and conversation_group in conversation_ids:
        payload["conversation_id"] = conversation_ids[conversation_group]
    if attachment_buffered_path and case.get("attachment_type"):
        payload["selected_paths"] = [attachment_buffered_path]
        action_context = dict(case.get("action_context", {}))
        action_context["target_path"] = attachment_buffered_path
        payload["action_context"] = action_context
    elif case.get("action_context"):
        payload["action_context"] = dict(case["action_context"])

    started_at = datetime.now(UTC).isoformat()
    created = request_json("POST", f"{service_url}/tasks", payload=payload)
    task_id = created["task_id"]
    task = wait_for_task(
        service_url,
        task_id,
        timeout_seconds=timeout_seconds,
        poll_interval=poll_interval,
    )
    finished_at = datetime.now(UTC).isoformat()
    event_summary = {
        "event_types": [],
        "process_events_present": False,
        "tool_summaries": [],
        "trace_excerpt": "",
        "message_excerpt": "",
        "journal_entry_id": None,
        "events_fetch_timed_out": False,
    }
    if not task.get("_timed_out"):
        try:
            events_text = fetch_events_text(service_url, task_id)
            events = parse_sse(events_text)
            event_summary = summarize_events(events)
        except TimeoutError:
            event_summary["events_fetch_timed_out"] = True
        except urllib.error.URLError as exc:
            if isinstance(exc.reason, TimeoutError):
                event_summary["events_fetch_timed_out"] = True
            else:
                raise
    else:
        event_summary["events_fetch_timed_out"] = True
    output = task.get("output") or {}
    conversation_id = output.get("conversation_id")
    if conversation_group and conversation_id:
        conversation_ids[conversation_group] = conversation_id
    evaluation = evaluate_case(case, task, event_summary)

    return {
        "case_id": case["case_id"],
        "intent": case["intent"],
        "prompt": case["prompt"],
        "task_id": task_id,
        "task_status": task["status"],
        "summary": task.get("summary", ""),
        "started_at": started_at,
        "finished_at": finished_at,
        "timed_out": bool(task.get("_timed_out")),
        "conversation_id": conversation_id,
        "answer": output.get("answer", ""),
        "affected_files": output.get("affected_files") or [],
        "journal_entry": output.get("journal_entry"),
        "event_summary": event_summary,
        "verdict": evaluation["verdict"],
        "issues": evaluation["issues"],
    }


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def print_run_summary(results: list[dict], output_path: Path) -> None:
    print(f"Saved results to: {output_path}")
    for result in results:
        print(
            f"[case {result['case_id']}] {result['task_status']} / {result['verdict']} / "
            f"{result['intent']} / issues={','.join(result['issues']) or 'none'}"
        )


def iso_timestamp_for_filename() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


if __name__ == "__main__":
    args = parse_args()
    health = request_json("GET", f"{args.service_url}/health")
    cases = load_cases(args.cases_path, args.case_ids)
    global cases_by_id
    cases_by_id = {case["case_id"]: case for case in cases}

    vault_copy, temp_root = create_temp_vault(args.vault_path)
    temp_path = Path(temp_root.name)
    attachment_path = build_attachment_file(temp_path)
    upload_payload = upload_file(args.service_url, attachment_path)

    conversation_ids: dict[str, str] = {}
    results: list[dict] = []
    try:
        for case in cases:
            buffered_path = upload_payload["buffered_path"] if case.get("attachment_type") else None
            result = run_case(
                service_url=args.service_url,
                vault_path=vault_copy,
                case=case,
                timeout_seconds=args.timeout_seconds,
                poll_interval=args.poll_interval,
                conversation_ids=conversation_ids,
                attachment_buffered_path=buffered_path,
            )
            results.append(result)
    finally:
        if args.keep_temp_vault:
            print(f"Temp vault kept at: {vault_copy}")
        else:
            temp_root.cleanup()

    run_payload = {
        "run_date": datetime.now(UTC).isoformat(),
        "service_url": args.service_url,
        "model": health.get("agent_model"),
        "provider": health.get("provider"),
        "source_vault": str(args.vault_path),
        "temp_vault_strategy": "copied-main-vault",
        "results": results,
    }
    output_path = args.output_dir / f"agent-regression-{iso_timestamp_for_filename()}.json"
    write_json(output_path, run_payload)
    print_run_summary(results, output_path)
