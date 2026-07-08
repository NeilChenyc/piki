from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
from uuid import uuid4

from agent_service.config import ServiceConfig
from agent_service.application.task_service import TaskService
from agent_service.models import (
    InspirationAttachment,
    InspirationCompileRequest,
    InspirationCompileResponse,
    InspirationCreateRequest,
    InspirationDTO,
    InspirationListResponse,
    InspirationUpdateRequest,
    TaskCreateRequest,
    utc_now_iso,
)
from agent_service.runtime import PikiWikiAgentRunner
from agent_service.vault import Vault, VaultAccessError


INSPIRATIONS_ROOT = "raw/inspirations"
INSPIRATION_ASSETS_ROOT = "raw/assets/inspirations"
FRONTMATTER_PATTERN = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
BODY_MARKER = "\n## 正文\n\n"


class InspirationService:
    def __init__(
        self,
        *,
        config: ServiceConfig,
        task_service: TaskService,
        runner: PikiWikiAgentRunner,
    ):
        self.config = config
        self.task_service = task_service
        self.runner = runner

    def list(self, *, vault_path: str | Path, query: str | None = None) -> InspirationListResponse:
        vault = _validated_vault(vault_path)
        items = self._load_all(vault)
        normalized_query = (query or "").strip().casefold()
        if normalized_query:
            items = [
                item
                for item in items
                if normalized_query in item.content.casefold()
                or normalized_query in item.id.casefold()
                or any(normalized_query in attachment.filename.casefold() for attachment in item.attachments)
            ]
        items.sort(key=lambda item: (item.created_at, item.id), reverse=True)
        return InspirationListResponse(items=items)

    def create(self, request: InspirationCreateRequest) -> InspirationDTO:
        vault = _validated_vault(request.vault_path)
        _ensure_inspiration_root(vault)
        memo_id = f"insp_{uuid4().hex}"
        now = utc_now_iso()
        content = request.content.strip()
        attachments = self._materialize_attachments(
            vault=vault,
            memo_id=memo_id,
            attachments=request.attachments,
        )
        relative_path = _new_inspiration_path(memo_id)
        dto = InspirationDTO(
            id=memo_id,
            path=relative_path,
            content=content,
            attachments=attachments,
            created_at=now,
            updated_at=now,
            content_hash=_content_hash(content, attachments),
            compile_status="pending",
        )
        _write_inspiration(vault, dto)
        return dto

    def update(self, memo_id: str, request: InspirationUpdateRequest) -> InspirationDTO:
        vault = _validated_vault(request.vault_path)
        existing = self._get(vault, memo_id)
        content = request.content.strip()
        attachments = self._materialize_attachments(
            vault=vault,
            memo_id=memo_id,
            attachments=request.attachments,
        )
        updated = InspirationDTO(
            id=existing.id,
            path=existing.path,
            content=content,
            attachments=attachments,
            created_at=existing.created_at,
            updated_at=utc_now_iso(),
            content_hash=_content_hash(content, attachments),
            compile_status="pending",
            compile_task_id=None,
            compiled_hash=None,
            source_path=None,
        )
        _write_inspiration(vault, updated)
        return updated

    def delete(self, memo_id: str, *, vault_path: str | Path) -> None:
        vault = _validated_vault(vault_path)
        existing = self._get(vault, memo_id)
        target = vault.resolve_path(existing.path)
        if target.exists():
            target.unlink()
        asset_dir = vault.resolve_path(f"{INSPIRATION_ASSETS_ROOT}/{memo_id}")
        if asset_dir.exists() and asset_dir.is_dir():
            shutil.rmtree(asset_dir)

    def compile(self, request: InspirationCompileRequest) -> InspirationCompileResponse:
        vault = _validated_vault(request.vault_path)
        pending = [
            item
            for item in self._load_all(vault)
            if item.compile_status == "pending" and item.content_hash != item.compiled_hash
        ][: request.max_items]
        if not pending:
            return InspirationCompileResponse()
        if not self.runner.can_run(self.config):
            return InspirationCompileResponse(error="Agent runtime is not configured.")

        source_path, source_hash = _write_inspiration_source(vault, pending)
        task_request = TaskCreateRequest(
            vault_path=vault.root,
            user_input=(
                f"请把随手记 canonical source `{source_path}` 编译进知识库，"
                "提炼其中的实体、概念、判断和可复用观点。\n\n/wiki:ingest"
            ),
            action_context={
                "action": "ingest_inspirations",
                "inspiration_source_path": source_path,
                "inspiration_source_hash": source_hash,
            },
            async_mode=True,
        )
        try:
            task = self.task_service.create_task(task_request)
        except Exception as exc:
            return InspirationCompileResponse(
                compiled_count=0,
                source_path=source_path,
                error=str(exc) or exc.__class__.__name__,
            )

        for item in pending:
            processing = item.model_copy(
                update={
                    "compile_status": "processing",
                    "compile_task_id": task.task_id,
                    "source_path": source_path,
                    "updated_at": utc_now_iso(),
                }
            )
            _write_inspiration(vault, processing)

        return InspirationCompileResponse(
            compiled_count=len(pending),
            task_id=task.task_id,
            source_path=source_path,
        )

    def _get(self, vault: Vault, memo_id: str) -> InspirationDTO:
        for item in self._load_all(vault):
            if item.id == memo_id:
                return item
        raise KeyError(f"Inspiration not found: {memo_id}")

    def _load_all(self, vault: Vault) -> list[InspirationDTO]:
        root = vault.resolve_path(INSPIRATIONS_ROOT)
        if not root.exists():
            return []
        items: list[InspirationDTO] = []
        for path in sorted(root.glob("**/*.md")):
            if path.is_file():
                try:
                    items.append(_read_inspiration(vault, path))
                except (OSError, ValueError):
                    continue
        return items

    def _materialize_attachments(
        self,
        *,
        vault: Vault,
        memo_id: str,
        attachments: list[InspirationAttachment],
    ) -> list[InspirationAttachment]:
        materialized: list[InspirationAttachment] = []
        for attachment in attachments:
            if attachment.buffered_path:
                materialized.append(
                    _copy_staged_attachment(
                        vault=vault,
                        config=self.config,
                        memo_id=memo_id,
                        attachment=attachment,
                    )
                )
                continue
            if attachment.path:
                materialized.append(_validate_existing_attachment(vault, memo_id, attachment))
        return materialized


def _validated_vault(vault_path: str | Path) -> Vault:
    vault = Vault(vault_path)
    vault.validate()
    return vault


def _ensure_inspiration_root(vault: Vault) -> None:
    vault.resolve_path(INSPIRATIONS_ROOT).mkdir(parents=True, exist_ok=True)


def _new_inspiration_path(memo_id: str) -> str:
    month = datetime.now(timezone.utc).strftime("%Y-%m")
    return f"{INSPIRATIONS_ROOT}/{month}/{memo_id}.md"


def _content_hash(content: str, attachments: list[InspirationAttachment]) -> str:
    payload = {
        "content": content,
        "attachments": [
            attachment.model_dump(mode="json", exclude={"buffered_path"})
            for attachment in attachments
        ],
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def _render_inspiration(dto: InspirationDTO) -> str:
    frontmatter = {
        "id": dto.id,
        "type": "inspiration",
        "created_at": dto.created_at,
        "updated_at": dto.updated_at,
        "attachments": [
            attachment.model_dump(mode="json", exclude_none=True, exclude={"buffered_path"})
            for attachment in dto.attachments
        ],
        "content_hash": dto.content_hash,
        "compile_status": dto.compile_status,
        "compile_task_id": dto.compile_task_id,
        "compiled_hash": dto.compiled_hash,
        "source_path": dto.source_path,
    }
    lines = ["---"]
    for key, value in frontmatter.items():
        lines.append(f"{key}: {json.dumps(value, ensure_ascii=False)}")
    lines.extend(["---", "", "# 随手记", "", "## 正文", "", dto.content.strip(), ""])
    return "\n".join(lines)


def _write_inspiration(vault: Vault, dto: InspirationDTO) -> None:
    target = vault.resolve_path(dto.path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.with_name(f".{target.name}.tmp")
    temp.write_text(_render_inspiration(dto), encoding="utf-8")
    temp.replace(target)


def _read_inspiration(vault: Vault, path: Path) -> InspirationDTO:
    content = path.read_text(encoding="utf-8", errors="replace")
    frontmatter = _parse_frontmatter(content)
    body = _parse_body(content)
    relative = str(path.relative_to(vault.root))
    attachments = [
        InspirationAttachment.model_validate(item)
        for item in frontmatter.get("attachments", [])
        if isinstance(item, dict)
    ]
    memo_id = str(frontmatter.get("id") or path.stem)
    return InspirationDTO(
        id=memo_id,
        path=relative,
        content=body,
        attachments=attachments,
        created_at=str(frontmatter.get("created_at") or ""),
        updated_at=str(frontmatter.get("updated_at") or frontmatter.get("created_at") or ""),
        content_hash=str(frontmatter.get("content_hash") or _content_hash(body, attachments)),
        compile_status=str(frontmatter.get("compile_status") or "pending"),
        compile_task_id=frontmatter.get("compile_task_id"),
        compiled_hash=frontmatter.get("compiled_hash"),
        source_path=frontmatter.get("source_path"),
    )


def _parse_frontmatter(content: str) -> dict:
    match = FRONTMATTER_PATTERN.search(content)
    if not match:
        return {}
    data: dict = {}
    for line in match.group(1).splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        raw = value.strip()
        try:
            data[key.strip()] = json.loads(raw)
        except json.JSONDecodeError:
            data[key.strip()] = raw.strip('"')
    return data


def _parse_body(content: str) -> str:
    if BODY_MARKER in content:
        return content.split(BODY_MARKER, 1)[1].strip()
    stripped = FRONTMATTER_PATTERN.sub("", content, count=1).strip()
    lines = stripped.splitlines()
    if lines and lines[0].startswith("#"):
        lines = lines[1:]
    return "\n".join(lines).strip()


def _copy_staged_attachment(
    *,
    vault: Vault,
    config: ServiceConfig,
    memo_id: str,
    attachment: InspirationAttachment,
) -> InspirationAttachment:
    source = Path(attachment.buffered_path or "").expanduser().resolve()
    staging_root = config.staging_root.expanduser().resolve()
    try:
        source.relative_to(staging_root)
    except ValueError as exc:
        raise VaultAccessError("Attachment must come from the Piki staging root.") from exc
    if not source.exists() or not source.is_file():
        raise VaultAccessError(f"Attachment file not found: {source}")

    safe_name = _safe_filename(attachment.filename or source.name)
    relative_path = f"{INSPIRATION_ASSETS_ROOT}/{memo_id}/{safe_name}"
    target = vault.resolve_path(relative_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    return InspirationAttachment(
        filename=safe_name,
        path=relative_path,
        mime_type=attachment.mime_type,
        size_bytes=target.stat().st_size,
    )


def _validate_existing_attachment(
    vault: Vault,
    memo_id: str,
    attachment: InspirationAttachment,
) -> InspirationAttachment:
    path = attachment.path or ""
    expected_prefix = f"{INSPIRATION_ASSETS_ROOT}/{memo_id}/"
    if not path.startswith(expected_prefix):
        raise VaultAccessError(f"Attachment is outside this inspiration asset directory: {path}")
    resolved = vault.resolve_path(path)
    if not resolved.exists() or not resolved.is_file():
        raise VaultAccessError(f"Attachment file not found: {path}")
    return InspirationAttachment(
        filename=attachment.filename or resolved.name,
        path=path,
        mime_type=attachment.mime_type,
        size_bytes=attachment.size_bytes or resolved.stat().st_size,
    )


def _safe_filename(filename: str) -> str:
    name = Path(filename).name.strip() or "attachment"
    return re.sub(r"[^A-Za-z0-9._\-\u3400-\u9fff]+", "-", name).strip(".-") or "attachment"


def _write_inspiration_source(vault: Vault, items: list[InspirationDTO]) -> tuple[str, str]:
    now = utc_now_iso()
    body = _render_inspiration_source_body(items)
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    source_path = f"raw/sources/inspirations-{timestamp}-{digest[:8]}.md"
    frontmatter = {
        "title": f"随手记 {timestamp}",
        "type": "raw-source",
        "format": "markdown",
        "hash": digest,
        "original_path": INSPIRATIONS_ROOT,
        "asset_path": INSPIRATION_ASSETS_ROOT,
        "source_path": source_path,
        "captured_at": now,
    }
    lines = ["---"]
    for key, value in frontmatter.items():
        lines.append(f"{key}: {json.dumps(value, ensure_ascii=False)}")
    lines.extend(["---", "", f"# 随手记 {timestamp}", "", "## 来源元数据", ""])
    lines.extend(
        [
            "- 原始格式：`markdown`",
            f"- 内容哈希：`{digest}`",
            f"- 原始路径：`{INSPIRATIONS_ROOT}`",
            f"- Source 路径：`{source_path}`",
            f"- 捕获时间：`{now}`",
            "",
            "## 正文",
            "",
            body,
            "",
        ]
    )
    vault.write_text(source_path, "\n".join(lines))
    return source_path, "sha256:" + digest


def _render_inspiration_source_body(items: list[InspirationDTO]) -> str:
    sections: list[str] = []
    for item in items:
        section = [
            f"### {item.created_at} · {item.id}",
            "",
            f"- 原始记录：`{item.path}`",
            f"- 内容哈希：`{item.content_hash}`",
        ]
        if item.attachments:
            paths = "、".join(f"`{attachment.path}`" for attachment in item.attachments if attachment.path)
            section.append(f"- 附件：{paths}")
        section.extend(["", item.content.strip(), ""])
        sections.append("\n".join(section))
    return "\n".join(sections).strip()
