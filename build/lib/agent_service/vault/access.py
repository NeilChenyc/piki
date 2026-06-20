from __future__ import annotations

import shutil
from pathlib import Path


SENSITIVE_NAMES = {
    ".env",
    ".env.local",
    "id_rsa",
    "id_ed25519",
    "known_hosts",
}


class VaultAccessError(ValueError):
    pass


class Vault:
    def __init__(self, root: Path | str):
        self.root = Path(root).expanduser().resolve()

    def validate(self):
        if not self.root.exists() or not self.root.is_dir():
            raise VaultAccessError(f"Vault path does not exist: {self.root}")
        for required in ["AGENTS.md", "wiki/index.md"]:
            if not (self.root / required).exists():
                raise VaultAccessError(f"Vault missing required file: {required}")

    def resolve_path(self, relative_path: str | Path) -> Path:
        raw = Path(relative_path)
        if raw.is_absolute():
            candidate = raw.expanduser().resolve()
        else:
            candidate = (self.root / raw).resolve()
        try:
            candidate.relative_to(self.root)
        except ValueError as exc:
            raise VaultAccessError(f"Path is outside vault: {relative_path}") from exc
        if any(part in SENSITIVE_NAMES for part in candidate.parts):
            raise VaultAccessError(f"Sensitive path is blocked: {relative_path}")
        return candidate

    def read_text(self, relative_path: str | Path, max_bytes: int = 20000) -> tuple[str, bool]:
        path = self.resolve_path(relative_path)
        if not path.exists() or not path.is_file():
            raise VaultAccessError(f"File not found: {relative_path}")
        try:
            data = path.read_bytes()
        except PermissionError as exc:
            raise VaultAccessError(
                f"Cannot read vault file: {relative_path}. "
                "The backend process does not have permission to access this vault path. "
                "Move the vault outside protected folders such as Downloads, or grant Full Disk Access. "
                f"Original error: {exc}"
            ) from exc
        except OSError as exc:
            raise VaultAccessError(f"Cannot read vault file: {relative_path} ({exc})") from exc
        truncated = len(data) > max_bytes
        return data[:max_bytes].decode("utf-8", errors="replace"), truncated

    def list_files(self, relative_path: str | Path = ".", glob: str = "*.md", max_results: int = 200) -> list[str]:
        path = self.resolve_path(relative_path)
        if not path.exists() or not path.is_dir():
            raise VaultAccessError(f"Directory not found: {relative_path}")
        files = []
        for item in sorted(path.glob(glob)):
            if item.is_file():
                files.append(str(item.relative_to(self.root)))
            if len(files) >= max_results:
                break
        return files

    def write_text(self, relative_path: str | Path, content: str) -> str:
        path = self.resolve_path(relative_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return str(path.relative_to(self.root))

    def copy_into_vault(self, source_path: Path | str, relative_path: str | Path) -> str:
        source = Path(source_path).expanduser().resolve()
        if not source.exists() or not source.is_file():
            raise VaultAccessError(f"Source file not found: {source_path}")
        target = self.resolve_path(relative_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        return str(target.relative_to(self.root))
