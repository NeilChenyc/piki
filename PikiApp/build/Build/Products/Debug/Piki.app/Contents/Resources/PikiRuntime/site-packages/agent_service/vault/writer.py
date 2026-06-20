from __future__ import annotations

import hashlib
from dataclasses import dataclass

from agent_service.models import FileSnapshot
from agent_service.vault import Vault, VaultAccessError


@dataclass(frozen=True)
class VaultWrite:
    path: str
    changed: bool
    before_content: str | None
    after_content: str
    before_hash: str | None
    after_hash: str
    action: str


class VaultWriter:
    def __init__(self, vault: Vault):
        self.vault = vault

    def write(self, path: str, content: str) -> VaultWrite:
        relative_path = self._validate_write_path(path)
        before_content = self._read_existing(relative_path)
        before_hash = _content_hash(before_content) if before_content is not None else None
        after_hash = _content_hash(content)
        if before_content == content:
            return VaultWrite(relative_path, False, before_content, content, after_hash, after_hash, "write")
        written_path = self.vault.write_text(relative_path, content)
        return VaultWrite(written_path, True, before_content, content, before_hash, after_hash, "write")

    def append(self, path: str, content: str) -> VaultWrite:
        relative_path = self._validate_write_path(path)
        before_content = self._read_existing(relative_path)
        existing = before_content or ""
        after_content = existing + content
        before_hash = _content_hash(before_content) if before_content is not None else None
        after_hash = _content_hash(after_content)
        if before_content == after_content:
            return VaultWrite(relative_path, False, before_content, after_content, after_hash, after_hash, "append")
        written_path = self.vault.write_text(relative_path, after_content)
        return VaultWrite(written_path, True, before_content, after_content, before_hash, after_hash, "append")

    def snapshot_for(self, write: VaultWrite) -> FileSnapshot:
        return FileSnapshot(
            path=write.path,
            before_hash=write.before_hash,
            after_hash=write.after_hash,
            before_content=write.before_content,
            after_content=write.after_content,
        )

    def _validate_write_path(self, path: str) -> str:
        resolved = self.vault.resolve_path(path)
        relative = str(resolved.relative_to(self.vault.root))
        if relative == "AGENTS.md":
            raise VaultAccessError("AGENTS.md is read-only for agent tools.")
        return relative

    def _read_existing(self, relative_path: str) -> str | None:
        path = self.vault.resolve_path(relative_path)
        if not path.exists():
            return None
        if not path.is_file():
            raise VaultAccessError(f"Path is not a file: {relative_path}")
        return path.read_text(encoding="utf-8", errors="replace")


def _content_hash(content: str) -> str:
    return "sha256:" + hashlib.sha256(content.encode("utf-8")).hexdigest()
