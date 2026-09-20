#!/usr/bin/env python3
"""Reject release evidence produced from a different or dirty source tree."""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path


def validate(manifest: dict, commit: str, hashes: dict) -> None:
    if manifest.get("gate") != "coverage":
        raise ValueError("coverage source manifest required")
    if manifest.get("workingTreeClean") is not True:
        raise ValueError("release coverage was produced from a dirty source tree")
    if manifest.get("sourceCommit") != commit:
        raise ValueError("coverage source commit differs from the release source")
    recorded = manifest.get("sourceFileSHA256")
    if not isinstance(recorded, dict) or not recorded:
        raise ValueError("coverage source hashes are missing")
    if recorded != hashes:
        changed = sorted(name for name in recorded.keys() | hashes.keys() if recorded.get(name) != hashes.get(name))
        raise ValueError(f"coverage source content differs: {changed}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify-evidence-source.py /path/to/coverage-report-or-result", file=sys.stderr)
        return 64
    root = Path(__file__).resolve().parent.parent
    manifest_path = Path(sys.argv[1]).resolve().parent / "Environment.json"
    spec = importlib.util.spec_from_file_location("evidence_metadata", root / "scripts/write-evidence-metadata.py")
    metadata = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(metadata)
    try:
        manifest = json.loads(manifest_path.read_text())
        if not isinstance(manifest, dict):
            raise ValueError("invalid source manifest")
        commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
        validate(manifest, commit, metadata.source_hashes(root))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"evidence source gate: {error}", file=sys.stderr)
        return 1
    print("evidence source gate: clean commit and complete source hashes match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
