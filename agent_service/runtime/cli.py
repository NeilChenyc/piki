from __future__ import annotations

import argparse
import json
from pathlib import Path

from agent_service.vault import Vault
from agent_service.workflows.lint import run_wiki_lint
from agent_service.workflows.source_intake import (
    build_source_slug,
    detect_source_format,
    extract_text,
    extract_title,
    hash_file,
    render_canonical_source,
)


def main() -> int:
    parser = argparse.ArgumentParser(prog="python -m agent_service.runtime.cli")
    subparsers = parser.add_subparsers(dest="command", required=True)

    lint_parser = subparsers.add_parser("lint")
    lint_parser.add_argument("--vault", required=True)

    extract_parser = subparsers.add_parser("extract-source")
    extract_parser.add_argument("--path", required=True)

    args = parser.parse_args()
    if args.command == "lint":
        payload = _lint(args.vault)
    else:
        payload = _extract_source(args.path)
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def _lint(vault_path: str) -> dict:
    vault = Vault(vault_path)
    vault.validate()
    result = run_wiki_lint(vault)
    return result.model_dump(mode="json")


def _extract_source(path: str) -> dict:
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
