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
