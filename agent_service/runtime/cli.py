from __future__ import annotations

import argparse
import json
import threading
import traceback
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(prog="python -m agent_service.runtime.cli")
    subparsers = parser.add_subparsers(dest="command", required=True)

    lint_parser = subparsers.add_parser("lint")
    lint_parser.add_argument("--vault", required=True)

    extract_parser = subparsers.add_parser("extract-source")
    extract_parser.add_argument("--path", required=True)

    stdio_parser = subparsers.add_parser("stdio")
    stdio_parser.add_argument("--db-path", default=".piki/agent_service.sqlite3")
    stdio_parser.add_argument("--runtime-config-path", default=".piki/runtime-config.json")
    stdio_parser.add_argument("--staging-root", default=".piki/task-staging")
    stdio_parser.add_argument("--enable-agent-runtime", action="store_true")

    args = parser.parse_args()
    if args.command == "lint":
        payload = _lint(args.vault)
    elif args.command == "stdio":
        from agent_service.diagnostics import runtime_log
        from agent_service.runtime.worker import RuntimeWorker

        runtime_log("cli", "stdio_start", extra={"db_path": args.db_path, "runtime_config_path": args.runtime_config_path})
        stdout_lock = threading.Lock()

        def emit_line(payload: dict) -> None:
            with stdout_lock:
                print(json.dumps(payload, ensure_ascii=False))
                import sys

                sys.stdout.flush()

        worker = RuntimeWorker(
            db_path=Path(args.db_path),
            runtime_config_path=Path(args.runtime_config_path),
            staging_root=Path(args.staging_root),
            enable_agent_runtime=args.enable_agent_runtime,
            notify=lambda event: emit_line({"kind": "event", "event": event.model_dump(mode="json")}),
        )
        import sys

        for line in iter(sys.stdin.readline, ""):
            if not line.strip():
                continue
            request_id = "<decode-error>"
            try:
                request = json.loads(line)
                request_id = str(request.get("id") or "<missing-id>")
                runtime_log("cli", "request_received", extra={"request_id": request_id, "method": request.get("method")})
                result = worker.call(request["method"], request.get("params", {}))
                emit_line({"kind": "response", "id": request_id, "result": result, "error": None})
                runtime_log("cli", "response_sent", extra={"request_id": request_id, "method": request.get("method")})
            except Exception as exc:
                runtime_log("cli", "request_failed", extra={"request_id": request_id, "error": str(exc) or exc.__class__.__name__})
                runtime_log("cli", "request_traceback", extra={"request_id": request_id, "traceback": traceback.format_exc().strip().replace("\n", " | ")})
                emit_line({"kind": "response", "id": request_id, "result": None, "error": str(exc) or exc.__class__.__name__})
        return 0
    else:
        payload = _extract_source(args.path)
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def _lint(vault_path: str) -> dict:
    from agent_service.vault import Vault
    from agent_service.workflows.lint_compat import run_wiki_lint_compat

    vault = Vault(vault_path)
    vault.validate()
    result = run_wiki_lint_compat(vault)
    return result.to_dict()


def _extract_source(path: str) -> dict:
    from agent_service.system.source_intake import (
        build_source_slug,
        detect_source_format,
        extract_text,
        extract_title,
        hash_file,
        render_canonical_source,
    )

    source_file = Path(path).expanduser().resolve()
    source_format = detect_source_format(source_file)
    file_hash = hash_file(source_file)
    body = extract_text(source_file, source_format)
    title = extract_title(source_file, body)
    slug = build_source_slug(title, file_hash)
    asset_path = f"raw/assets/{slug}/original{source_file.suffix.lower()}"
    source_path = f"raw/sources/{slug}.md"
    markdown = render_canonical_source(
        title=title,
        source_format=source_format,
        file_hash=file_hash,
        original_path=str(source_file),
        asset_path=asset_path,
        source_path=source_path,
        captured_at="PENDING_WRITE",
        body=body,
    )
    return {
        "title": title,
        "format": source_format.value,
        "hash": file_hash,
        "original_path": str(source_file),
        "asset_path": asset_path,
        "source_path": source_path,
        "body_preview": body[:500],
        "canonical_markdown": markdown,
    }


if __name__ == "__main__":
    raise SystemExit(main())
