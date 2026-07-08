#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import tarfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_DIR = ROOT / "PikiApp"
BUNDLE_ROOT = APP_DIR / ".build" / "runtime-bundle"
CACHE_ROOT = APP_DIR / ".build" / "runtime-cache"
PYTHON_VERSION = "3.12.13"
RELEASE_TAG = "20260610"


def main() -> int:
    arch = detect_arch()
    python_url = release_url(arch)
    staging_root = BUNDLE_ROOT.with_name(f"{BUNDLE_ROOT.name}.staging")

    shutil.rmtree(staging_root, ignore_errors=True)
    try:
        build_bundle(staging_root, arch=arch, python_url=python_url)
        replace_bundle(staging_root, BUNDLE_ROOT)
    except Exception:
        shutil.rmtree(staging_root, ignore_errors=True)
        raise
    print(BUNDLE_ROOT)
    return 0


def detect_arch() -> str:
    machine = subprocess.check_output(["/usr/bin/uname", "-m"], text=True).strip()
    if machine == "arm64":
        return "aarch64"
    if machine == "x86_64":
        return "x86_64"
    raise SystemExit(f"Unsupported architecture: {machine}")


def release_url(arch: str) -> str:
    filename = f"cpython-{PYTHON_VERSION}+{RELEASE_TAG}-{arch}-apple-darwin-install_only_stripped.tar.gz"
    return f"https://github.com/astral-sh/python-build-standalone/releases/download/{RELEASE_TAG}/{filename}"


def build_bundle(bundle_root: Path, *, arch: str, python_url: str) -> None:
    resources_root = bundle_root / "Contents" / "Resources" / "PikiRuntime"
    python_root = resources_root / "Python"
    site_packages = resources_root / "site-packages"

    site_packages.mkdir(parents=True, exist_ok=True)
    download_and_extract_python(python_url, python_root)
    install_packages(python_root, site_packages)
    write_metadata(arch, bundle_root=bundle_root)


def replace_bundle(staging_root: Path, target_root: Path) -> None:
    target_root.parent.mkdir(parents=True, exist_ok=True)
    backup_root = target_root.with_name(f"{target_root.name}.previous")
    shutil.rmtree(backup_root, ignore_errors=True)
    if target_root.exists():
        shutil.move(str(target_root), str(backup_root))
    try:
        shutil.move(str(staging_root), str(target_root))
    except Exception:
        if backup_root.exists() and not target_root.exists():
            shutil.move(str(backup_root), str(target_root))
        raise
    shutil.rmtree(backup_root, ignore_errors=True)


def download_and_extract_python(url: str, target: Path) -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        archive = cached_python_archive(url)
        extract_root = Path(tmpdir) / "extract"
        extract_root.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive, mode="r:gz") as tar:
            tar.extractall(extract_root)
        source_root = next((path for path in extract_root.iterdir() if path.is_dir()), None)
        if source_root is None:
            raise SystemExit("Python archive did not contain an expected root directory.")
        shutil.move(str(source_root), str(target))


def cached_python_archive(url: str) -> Path:
    CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    archive = CACHE_ROOT / Path(url).name
    if archive.exists() and archive.stat().st_size > 0:
        return archive

    temp_archive = archive.with_name(f"{archive.name}.tmp")
    temp_archive.unlink(missing_ok=True)
    try:
        subprocess.run(["/usr/bin/curl", "-L", "--fail", "-o", str(temp_archive), url], check=True)
        temp_archive.replace(archive)
    finally:
        temp_archive.unlink(missing_ok=True)
    return archive


def install_packages(python_root: Path, site_packages: Path) -> None:
    python = python_root / "bin" / "python3"
    subprocess.run([str(python), "-m", "pip", "install", "--upgrade", "pip"], check=True)
    with tempfile.TemporaryDirectory() as tmpdir:
        staged_source = prepare_clean_source_tree(Path(tmpdir))
        subprocess.run(
            [
                str(python),
                "-m",
                "pip",
                "install",
                "--target",
                str(site_packages),
                str(staged_source),
            ],
            check=True,
        )


def prepare_clean_source_tree(destination_root: Path) -> Path:
    staged_root = destination_root / "piki-source"
    shutil.copytree(ROOT, staged_root, ignore=_ignore_workspace_artifacts)
    return staged_root


def _ignore_workspace_artifacts(current_dir: str, names: list[str]) -> set[str]:
    current_path = Path(current_dir)
    try:
        relative = current_path.relative_to(ROOT)
    except ValueError:
        relative = Path()

    ignored = {
        name
        for name in names
        if name in {
            ".git",
            ".venv",
            ".pytest_cache",
            ".mypy_cache",
            ".ruff_cache",
            "__pycache__",
            "build",
            "dist",
            "outputs",
            "piki.egg-info",
        }
    }

    if relative == Path("PikiApp"):
        ignored.update({"build", ".build"})

    return ignored


def write_metadata(arch: str, *, bundle_root: Path | None = None) -> None:
    root = bundle_root or BUNDLE_ROOT
    metadata = root / "Contents" / "Resources" / "runtime-paths.json"
    metadata.parent.mkdir(parents=True, exist_ok=True)
    metadata.write_text(
        (
            "{"
            f"\"python\":\"PikiRuntime/Python/bin/python3\","
            f"\"site_packages\":\"PikiRuntime/site-packages\","
            f"\"arch\":\"{arch}\""
            "}"
        ),
        encoding="utf-8",
    )


if __name__ == "__main__":
    raise SystemExit(main())
