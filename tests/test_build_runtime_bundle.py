from pathlib import Path

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
    (repo_root / "agent_service" / "agents" / "prompts.py").write_text("fresh prompts", encoding="utf-8")
    (repo_root / "build" / "lib" / "prompts.py").write_text("stale prompts", encoding="utf-8")
    (repo_root / "piki.egg-info" / "SOURCES.txt").write_text("stale metadata", encoding="utf-8")
    (repo_root / "dist" / "artifact.txt").write_text("artifact", encoding="utf-8")

    monkeypatch.setattr(runtime_bundle, "ROOT", repo_root)

    staged_root = runtime_bundle.prepare_clean_source_tree(tmp_path / "stage")

    assert (staged_root / "agent_service" / "agents" / "prompts.py").read_text(encoding="utf-8") == "fresh prompts"
    assert not (staged_root / "build").exists()
    assert not (staged_root / "dist").exists()
    assert not (staged_root / "piki.egg-info").exists()
