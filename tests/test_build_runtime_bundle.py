from pathlib import Path
import tomllib

import scripts.build_runtime_bundle as runtime_bundle


def test_write_metadata_points_to_python_executable(tmp_path, monkeypatch):
    bundle_root = tmp_path / "runtime-bundle"
    monkeypatch.setattr(runtime_bundle, "BUNDLE_ROOT", bundle_root)

    runtime_bundle.write_metadata("aarch64")

    metadata = (bundle_root / "Contents" / "Resources" / "runtime-paths.json").read_text(encoding="utf-8")

    assert '"python":"PikiRuntime/Python/bin/python3"' in metadata
    assert '"site_packages":"PikiRuntime/site-packages"' in metadata
    assert '"arch":"aarch64"' in metadata


def test_prepare_clean_source_tree_excludes_build_artifacts(tmp_path, monkeypatch):
    repo_root = tmp_path / "repo"
    (repo_root / "agent_service" / "agents").mkdir(parents=True)
    (repo_root / "build" / "lib").mkdir(parents=True)
    (repo_root / "piki.egg-info").mkdir()
    (repo_root / "dist").mkdir()
    (repo_root / "docs").mkdir()
    (repo_root / "agent_service" / "agents" / "prompts.py").write_text("fresh prompts", encoding="utf-8")
    (repo_root / "build" / "lib" / "prompts.py").write_text("stale prompts", encoding="utf-8")
    (repo_root / "piki.egg-info" / "SOURCES.txt").write_text("stale metadata", encoding="utf-8")
    (repo_root / "dist" / "artifact.txt").write_text("artifact", encoding="utf-8")
    (repo_root / "docs" / "notes.md").write_text("not part of runtime", encoding="utf-8")
    (repo_root / "pyproject.toml").write_text("[project]\nname = \"piki\"\n", encoding="utf-8")
    (repo_root / "xiaoyuzhou_tingwu_tool.py").write_text("TOOL = True\n", encoding="utf-8")

    monkeypatch.setattr(runtime_bundle, "ROOT", repo_root)

    staged_root = runtime_bundle.prepare_clean_source_tree(tmp_path / "stage")

    assert (staged_root / "agent_service" / "agents" / "prompts.py").read_text(encoding="utf-8") == "fresh prompts"
    assert (staged_root / "pyproject.toml").exists()
    assert (staged_root / "xiaoyuzhou_tingwu_tool.py").exists()
    assert not (staged_root / "build").exists()
    assert not (staged_root / "dist").exists()
    assert not (staged_root / "docs").exists()
    assert not (staged_root / "piki.egg-info").exists()


def test_main_reuses_existing_runtime_base_and_syncs_project_sources(tmp_path, monkeypatch):
    repo_root = tmp_path / "repo"
    (repo_root / "agent_service").mkdir(parents=True)
    (repo_root / "agent_service" / "__init__.py").write_text("VALUE = 'fresh'\n", encoding="utf-8")
    (repo_root / "xiaoyuzhou_tingwu_tool.py").write_text("TOOL = 'fresh'\n", encoding="utf-8")
    (repo_root / "pyproject.toml").write_text("[project]\ndependencies = []\n", encoding="utf-8")

    bundle_root = tmp_path / "runtime-bundle"
    runtime_root = bundle_root / "Contents" / "Resources" / "PikiRuntime"
    python = runtime_root / "Python" / "bin" / "python3"
    site_packages = runtime_root / "site-packages"
    python.parent.mkdir(parents=True)
    site_packages.mkdir(parents=True)
    python.write_text("#!/bin/sh\n", encoding="utf-8")
    (site_packages / "agent_service").mkdir()
    (site_packages / "agent_service" / "__init__.py").write_text("VALUE = 'stale'\n", encoding="utf-8")

    monkeypatch.setattr(runtime_bundle, "ROOT", repo_root)
    monkeypatch.setattr(runtime_bundle, "BUNDLE_ROOT", bundle_root)
    monkeypatch.setattr(runtime_bundle, "detect_arch", lambda: "aarch64")
    monkeypatch.setattr(runtime_bundle, "release_url", lambda arch: "https://example.invalid/python.tar.gz")
    monkeypatch.setattr(runtime_bundle, "runtime_base_is_usable", lambda *args, **kwargs: True)
    monkeypatch.setattr(runtime_bundle, "build_bundle", lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("full rebuild should not run")))

    assert runtime_bundle.main() == 0

    assert (site_packages / "agent_service" / "__init__.py").read_text(encoding="utf-8") == "VALUE = 'fresh'\n"
    assert (site_packages / "xiaoyuzhou_tingwu_tool.py").read_text(encoding="utf-8") == "TOOL = 'fresh'\n"
    assert (bundle_root / "Contents" / "Resources" / "runtime-paths.json").exists()
    assert (bundle_root / "Contents" / "Resources" / "runtime-build-state.json").exists()


def test_python_distribution_includes_podcast_tool_and_tingwu_sdk_dependency():
    pyproject = tomllib.loads((runtime_bundle.ROOT / "pyproject.toml").read_text(encoding="utf-8"))

    assert "xiaoyuzhou_tingwu_tool" in pyproject["tool"]["setuptools"]["py-modules"]
    assert "aliyun-python-sdk-core>=2.16.0" in pyproject["project"]["dependencies"]
    assert "requests>=2.32.0" in pyproject["project"]["dependencies"]


def test_main_preserves_existing_runtime_bundle_when_download_fails(tmp_path, monkeypatch):
    bundle_root = tmp_path / "runtime-bundle"
    cache_root = tmp_path / "runtime-cache"
    sentinel = bundle_root / "Contents" / "Resources" / "PikiRuntime" / "sentinel.txt"
    sentinel.parent.mkdir(parents=True)
    sentinel.write_text("previous bundle", encoding="utf-8")

    monkeypatch.setattr(runtime_bundle, "BUNDLE_ROOT", bundle_root)
    monkeypatch.setattr(runtime_bundle, "CACHE_ROOT", cache_root)
    monkeypatch.setattr(runtime_bundle, "detect_arch", lambda: "aarch64")
    monkeypatch.setattr(runtime_bundle, "release_url", lambda arch: "https://example.invalid/python.tar.gz")

    def fail_download(url, target):
        raise RuntimeError("download failed")

    monkeypatch.setattr(runtime_bundle, "download_and_extract_python", fail_download)

    try:
        runtime_bundle.main()
    except RuntimeError:
        pass
    else:
        raise AssertionError("main should fail when python download fails")

    assert sentinel.read_text(encoding="utf-8") == "previous bundle"
