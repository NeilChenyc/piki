#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import tarfile
import json
import hashlib
import os
import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_DIR = ROOT / "PikiApp"
BUNDLE_ROOT = APP_DIR / ".build" / "runtime-bundle"
CACHE_ROOT = APP_DIR / ".build" / "runtime-cache"
PYTHON_VERSION = "3.12.13"
RELEASE_TAG = "20260610"
BUILD_STATE_FILENAME = "runtime-build-state.json"
BUILD_STATE_VERSION = 1
RUNTIME_SOURCE_PATHS = (
    Path("agent_service"),
    Path("xiaoyuzhou_tingwu_tool.py"),
)


def main(argv: list[str] | None = None) -> int:
    argv = [] if argv is None else argv
    parser = argparse.ArgumentParser(description="Build or refresh the bundled Piki Python runtime.")
    parser.add_argument("--copy-to", type=Path, help="Copy or refresh runtime resources into an app Resources directory.")
    parser.add_argument("--force", action="store_true", help="Force a full runtime rebuild.")
    args = parser.parse_args(argv)

    arch = detect_arch()
    python_url = release_url(arch)
    staging_root = BUNDLE_ROOT.with_name(f"{BUNDLE_ROOT.name}.staging")

    if args.force or not runtime_base_is_usable(BUNDLE_ROOT, arch=arch, python_url=python_url):
        shutil.rmtree(staging_root, ignore_errors=True)
        try:
            build_bundle(staging_root, arch=arch, python_url=python_url)
            replace_bundle(staging_root, BUNDLE_ROOT)
        except Exception:
            shutil.rmtree(staging_root, ignore_errors=True)
            raise
    else:
        print(f"Reusing runtime base at {BUNDLE_ROOT}")

    sync_project_sources(BUNDLE_ROOT)
    write_metadata(arch, bundle_root=BUNDLE_ROOT)
    write_build_state(arch, python_url, bundle_root=BUNDLE_ROOT)

    if args.copy_to is not None:
        copy_bundle_resources(BUNDLE_ROOT, args.copy_to)

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
    subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check", "--upgrade", "pip"], check=True)
    with tempfile.TemporaryDirectory() as tmpdir:
        staged_source = prepare_clean_source_tree(Path(tmpdir))
        subprocess.run(
            [
                str(python),
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "--target",
                str(site_packages),
                str(staged_source),
            ],
            check=True,
        )


def prepare_clean_source_tree(destination_root: Path) -> Path:
    staged_root = destination_root / "piki-source"
    staged_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "pyproject.toml", staged_root / "pyproject.toml")
    for relative_path in RUNTIME_SOURCE_PATHS:
        copy_runtime_source(ROOT / relative_path, staged_root / relative_path)
    return staged_root


def copy_runtime_source(source: Path, destination: Path) -> None:
    if source.is_dir():
        shutil.rmtree(destination, ignore_errors=True)
        shutil.copytree(source, destination, ignore=_ignore_runtime_source_artifacts)
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def _ignore_runtime_source_artifacts(current_dir: str, names: list[str]) -> set[str]:
    return {
        name
        for name in names
        if name in {
            "__pycache__",
        }
        or name.endswith((".pyc", ".pyo"))
    }


def sync_project_sources(bundle_root: Path) -> None:
    sync_project_sources_into(runtime_site_packages(bundle_resources_root(bundle_root)))


def sync_project_sources_into(site_packages: Path) -> None:
    site_packages.mkdir(parents=True, exist_ok=True)
    for relative_path in RUNTIME_SOURCE_PATHS:
        copy_runtime_source(ROOT / relative_path, site_packages / relative_path.name)


def copy_bundle_resources(bundle_root: Path, app_resources: Path) -> None:
    source_resources = bundle_resources_root(bundle_root)
    source_runtime = source_resources / "PikiRuntime"
    destination_runtime = app_resources / "PikiRuntime"
    source_state = read_build_state_from_resources(source_resources)
    destination_state = read_build_state_from_resources(app_resources)
    app_resources.mkdir(parents=True, exist_ok=True)

    if (
        destination_runtime.exists()
        and source_state
        and destination_state
        and source_state == destination_state
        and (app_resources / "runtime-paths.json").exists()
    ):
        print(f"Runtime resources already current at {app_resources}")
        return

    if (
        destination_runtime.exists()
        and source_state
        and destination_state
        and source_state.get("base_fingerprint") == destination_state.get("base_fingerprint")
    ):
        sync_project_sources_into(runtime_site_packages(app_resources))
        copy_runtime_metadata(source_resources, app_resources)
        print(f"Refreshed runtime sources at {app_resources}")
        return

    shutil.rmtree(destination_runtime, ignore_errors=True)
    shutil.copytree(source_runtime, destination_runtime)
    copy_runtime_metadata(source_resources, app_resources)
    print(f"Copied runtime bundle to {app_resources}")


def copy_runtime_metadata(source_resources: Path, destination_resources: Path) -> None:
    destination_resources.mkdir(parents=True, exist_ok=True)
    for name in ("runtime-paths.json", BUILD_STATE_FILENAME):
        source = source_resources / name
        if source.exists():
            shutil.copy2(source, destination_resources / name)


def runtime_base_is_usable(bundle_root: Path, *, arch: str, python_url: str) -> bool:
    resources_root = bundle_resources_root(bundle_root)
    runtime_root = resources_root / "PikiRuntime"
    python = runtime_root / "Python" / "bin" / "python3"
    site_packages = runtime_root / "site-packages"
    if not python.exists() or not site_packages.exists():
        return False

    state = read_build_state_from_resources(resources_root)
    if state is not None:
        return (
            state.get("base_fingerprint") == base_fingerprint(arch, python_url)
            and state.get("dependency_fingerprint") == dependency_fingerprint()
        )

    return legacy_runtime_base_is_usable(python, site_packages)


def legacy_runtime_base_is_usable(python: Path, site_packages: Path) -> bool:
    dependency_names = project_dependency_names()
    if not dependency_names:
        return True
    check_script = """
import importlib.metadata
import json
import sys

missing = []
for name in json.loads(sys.argv[1]):
    try:
        importlib.metadata.distribution(name)
    except importlib.metadata.PackageNotFoundError:
        missing.append(name)

if missing:
    print("missing runtime distributions: " + ", ".join(missing), file=sys.stderr)
    raise SystemExit(1)
"""
    env = os.environ.copy()
    env["PYTHONPATH"] = str(site_packages)
    result = subprocess.run(
        [str(python), "-c", check_script, json.dumps(dependency_names)],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    if result.returncode != 0:
        if result.stderr:
            print(result.stderr.strip(), file=sys.stderr)
        return False
    return True


def project_dependency_names() -> list[str]:
    pyproject = ROOT / "pyproject.toml"
    if not pyproject.exists():
        return []
    text = pyproject.read_text(encoding="utf-8")
    match = re.search(r"(?ms)^dependencies\s*=\s*\[(.*?)^\]", text)
    if not match:
        return []
    names: list[str] = []
    for line in match.group(1).splitlines():
        dependency = line.strip().rstrip(",").strip("\"'")
        if not dependency or dependency.startswith("#"):
            continue
        name_match = re.match(r"([A-Za-z0-9_.-]+)", dependency)
        if name_match:
            names.append(name_match.group(1))
    return names


def bundle_resources_root(bundle_root: Path) -> Path:
    return bundle_root / "Contents" / "Resources"


def runtime_site_packages(resources_root: Path) -> Path:
    return resources_root / "PikiRuntime" / "site-packages"


def read_build_state_from_resources(resources_root: Path) -> dict[str, object] | None:
    state_path = resources_root / BUILD_STATE_FILENAME
    if not state_path.exists():
        return None
    try:
        return json.loads(state_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def write_build_state(arch: str, python_url: str, *, bundle_root: Path) -> None:
    resources_root = bundle_resources_root(bundle_root)
    state_path = resources_root / BUILD_STATE_FILENAME
    state_path.write_text(
        json.dumps(build_state(arch, python_url), sort_keys=True, separators=(",", ":")),
        encoding="utf-8",
    )


def build_state(arch: str, python_url: str) -> dict[str, object]:
    return {
        "version": BUILD_STATE_VERSION,
        "arch": arch,
        "python_version": PYTHON_VERSION,
        "release_tag": RELEASE_TAG,
        "base_fingerprint": base_fingerprint(arch, python_url),
        "dependency_fingerprint": dependency_fingerprint(),
        "source_fingerprint": runtime_source_fingerprint(),
    }


def base_fingerprint(arch: str, python_url: str) -> str:
    payload = json.dumps(
        {
            "arch": arch,
            "python_version": PYTHON_VERSION,
            "release_tag": RELEASE_TAG,
            "python_url": python_url,
        },
        sort_keys=True,
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def dependency_fingerprint() -> str:
    return file_fingerprint(ROOT / "pyproject.toml")


def runtime_source_fingerprint() -> str:
    digest = hashlib.sha256()
    for relative_path in RUNTIME_SOURCE_PATHS:
        update_path_fingerprint(digest, ROOT / relative_path, relative_path)
    return digest.hexdigest()


def update_path_fingerprint(digest: "hashlib._Hash", path: Path, relative_path: Path) -> None:
    if path.is_dir():
        for child in sorted(path.rglob("*")):
            if child.is_file() and not should_ignore_runtime_file(child):
                update_file_fingerprint(digest, child, child.relative_to(ROOT))
        return
    update_file_fingerprint(digest, path, relative_path)


def update_file_fingerprint(digest: "hashlib._Hash", path: Path, relative_path: Path) -> None:
    digest.update(relative_path.as_posix().encode("utf-8"))
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")


def file_fingerprint(path: Path) -> str:
    digest = hashlib.sha256()
    update_file_fingerprint(digest, path, path.relative_to(ROOT))
    return digest.hexdigest()


def should_ignore_runtime_file(path: Path) -> bool:
    return "__pycache__" in path.parts or path.suffix in {".pyc", ".pyo"}


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
    raise SystemExit(main(sys.argv[1:]))
