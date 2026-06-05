from __future__ import annotations

from agent_service.models import ContextManifest
from agent_service.vault import Vault, VaultAccessError


BASELINE_FILES = ["AGENTS.md", "purpose.md", "wiki/index.md"]


def assemble_baseline_context(vault: Vault) -> tuple[ContextManifest, dict[str, str]]:
    manifest = ContextManifest()
    contents: dict[str, str] = {}
    for relative_path in BASELINE_FILES:
        try:
            content, truncated = vault.read_text(relative_path)
        except VaultAccessError:
            if relative_path == "purpose.md":
                manifest.missing_optional_files.append(relative_path)
                continue
            raise
        contents[relative_path] = content
        manifest.loaded_files.append(relative_path)
        if truncated:
            manifest.skipped_files.append(
                {"path": relative_path, "reason": "file truncated by max_bytes limit"}
            )
    return manifest, contents

