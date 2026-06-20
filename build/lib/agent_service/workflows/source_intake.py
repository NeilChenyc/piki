from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from agent_service.models import (
    SourceFormat,
    SourceIntakeResult,
    SourceManifestRecord,
    utc_now_iso,
)
from agent_service.vault import Vault, VaultAccessError


SUPPORTED_SUFFIXES = {
    ".md": SourceFormat.MARKDOWN,
    ".markdown": SourceFormat.MARKDOWN,
    ".txt": SourceFormat.TEXT,
    ".pdf": SourceFormat.PDF,
    ".docx": SourceFormat.DOCX,
}
MANIFEST_PATH = "system/source_manifest.json"
SENSITIVE_SOURCE_NAMES = {".env", ".env.local", "id_rsa", "id_ed25519"}


class SourceIntakeError(ValueError):
    pass


def run_source_intake(vault: Vault, selected_path: str | Path) -> SourceIntakeResult:
    source_file = Path(selected_path).expanduser().resolve()
    _validate_source_file(source_file)
    source_format = detect_source_format(source_file)
    file_hash = hash_file(source_file)
    manifest = read_source_manifest(vault)
    existing = manifest.get(file_hash)
    if existing and _vault_file_exists(vault, existing.source_path):
        return SourceIntakeResult(
            title=existing.title,
            format=existing.format,
            hash=existing.hash,
            original_path=existing.original_path,
            asset_path=existing.asset_path,
            source_path=existing.source_path,
            size_bytes=existing.size_bytes,
            reused=True,
            captured_at=existing.created_at,
            body_preview="",
        )

    extracted = extract_text(source_file, source_format)
    title = extract_title(source_file, extracted)
    slug = build_source_slug(title, file_hash)
    asset_path = f"raw/assets/{slug}/original{source_file.suffix.lower()}"
    source_path = f"raw/sources/{slug}.md"
    copied_asset_path = vault.copy_into_vault(source_file, asset_path)
    now = utc_now_iso()
    markdown = render_canonical_source(
        title=title,
        source_format=source_format,
        file_hash=file_hash,
        original_path=str(source_file),
        asset_path=copied_asset_path,
        source_path=source_path,
        captured_at=now,
        body=extracted,
    )
    written_source_path = vault.write_text(source_path, markdown)
    record = SourceManifestRecord(
        hash=file_hash,
        title=title,
        format=source_format,
        original_path=str(source_file),
        asset_path=copied_asset_path,
        source_path=written_source_path,
        size_bytes=source_file.stat().st_size,
        created_at=now,
        updated_at=now,
    )
    manifest[file_hash] = record
    write_source_manifest(vault, manifest)
    return SourceIntakeResult(
        title=title,
        format=source_format,
        hash=file_hash,
        original_path=str(source_file),
        asset_path=copied_asset_path,
        source_path=written_source_path,
        size_bytes=record.size_bytes,
        reused=False,
        captured_at=now,
        body_preview=extracted[:500],
    )


def detect_source_format(path: Path) -> SourceFormat:
    suffix = path.suffix.lower()
    if suffix not in SUPPORTED_SUFFIXES:
        raise SourceIntakeError(f"Unsupported source format: {suffix or '(none)'}")
    return SUPPORTED_SUFFIXES[suffix]


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def extract_text(path: Path, source_format: SourceFormat) -> str:
    if source_format in {SourceFormat.MARKDOWN, SourceFormat.TEXT}:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    if source_format == SourceFormat.DOCX:
        return _extract_docx(path)
    if source_format == SourceFormat.PDF:
        return _extract_pdf(path)
    raise SourceIntakeError(f"Unsupported source format: {source_format}")


def extract_title(path: Path, body: str) -> str:
    heading_match = re.search(r"^#\s+(.+)$", body, flags=re.MULTILINE)
    if heading_match:
        return heading_match.group(1).strip()
    for line in body.splitlines():
        stripped = line.strip()
        if stripped and len(stripped) <= 80:
            return stripped.lstrip("#").strip()
    return path.stem


def build_source_slug(title: str, file_hash: str) -> str:
    normalized = re.sub(r"[^\w\u3400-\u9fff]+", "-", title.lower()).strip("-_")
    normalized = re.sub(r"-+", "-", normalized)[:48].strip("-")
    if not normalized:
        normalized = "source"
    return f"{normalized}-{file_hash[:8]}"


def render_canonical_source(
    *,
    title: str,
    source_format: SourceFormat,
    file_hash: str,
    original_path: str,
    asset_path: str,
    source_path: str,
    captured_at: str,
    body: str,
) -> str:
    frontmatter = {
        "title": title,
        "type": "raw-source",
        "format": source_format.value,
        "hash": file_hash,
        "original_path": original_path,
        "asset_path": asset_path,
        "source_path": source_path,
        "captured_at": captured_at,
    }
    lines = ["---"]
    for key, value in frontmatter.items():
        lines.append(f"{key}: {json.dumps(value, ensure_ascii=False)}")
    lines.extend(
        [
            "---",
            "",
            f"# {title}",
            "",
            "## 来源元数据",
            "",
            f"- 原始格式：`{source_format.value}`",
            f"- 内容哈希：`{file_hash}`",
            f"- 原始路径：`{original_path}`",
            f"- 资产路径：`{asset_path}`",
            f"- Source 路径：`{source_path}`",
            f"- 捕获时间：`{captured_at}`",
            "",
            "## 正文",
            "",
            body.strip(),
            "",
        ]
    )
    return "\n".join(lines)


def read_source_manifest(vault: Vault) -> dict[str, SourceManifestRecord]:
    path = vault.resolve_path(MANIFEST_PATH)
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    records = data.get("sources", {})
    return {
        source_hash: SourceManifestRecord.model_validate(record)
        for source_hash, record in records.items()
    }


def write_source_manifest(vault: Vault, manifest: dict[str, SourceManifestRecord]) -> str:
    payload = {
        "version": 1,
        "updated_at": utc_now_iso(),
        "sources": {
            source_hash: record.model_dump(mode="json")
            for source_hash, record in sorted(manifest.items())
        },
    }
    return vault.write_text(MANIFEST_PATH, json.dumps(payload, ensure_ascii=False, indent=2) + "\n")


def _extract_docx(path: Path) -> str:
    try:
        from docx import Document
    except Exception as exc:  # pragma: no cover - depends on environment
        raise SourceIntakeError(f"DOCX extraction dependency unavailable: {exc}") from exc
    try:
        document = Document(str(path))
    except Exception as exc:
        raise SourceIntakeError(f"Failed to read DOCX: {exc}") from exc
    paragraphs = [paragraph.text.strip() for paragraph in document.paragraphs if paragraph.text.strip()]
    if not paragraphs:
        raise SourceIntakeError("DOCX did not contain extractable text")
    return "\n\n".join(paragraphs)


def _extract_pdf(path: Path) -> str:
    try:
        from pypdf import PdfReader
    except Exception as exc:  # pragma: no cover - depends on environment
        raise SourceIntakeError(f"PDF extraction dependency unavailable: {exc}") from exc
    try:
        reader = PdfReader(str(path))
        pages = [page.extract_text() or "" for page in reader.pages]
    except Exception as exc:
        raise SourceIntakeError(f"Failed to read PDF: {exc}") from exc
    text = "\n\n".join(page.strip() for page in pages if page.strip()).strip()
    if not text:
        raise SourceIntakeError("PDF did not contain extractable text")
    return text


def _validate_source_file(path: Path):
    if not path.exists() or not path.is_file():
        raise SourceIntakeError(f"Selected source file does not exist: {path}")
    if any(part in SENSITIVE_SOURCE_NAMES for part in path.parts):
        raise SourceIntakeError(f"Sensitive source file is blocked: {path}")


def _vault_file_exists(vault: Vault, relative_path: str) -> bool:
    try:
        path = vault.resolve_path(relative_path)
    except VaultAccessError:
        return False
    return path.exists() and path.is_file()
