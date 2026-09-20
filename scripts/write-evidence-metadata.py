#!/usr/bin/env python3
"""Record the source and host that produced a release-gate artifact."""

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def optional_run(*args: str) -> Optional[str]:
    try:
        return run(*args)
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None


def source_hashes(root: Path) -> dict[str, Optional[str]]:
    paths = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
    ).decode().split("\0")
    hashes = {}
    for name in sorted(set(paths) - {""}):
        path = root / name
        if path.is_symlink():
            hashes[name] = hashlib.sha256(os.fsencode(os.readlink(path))).hexdigest()
        elif path.is_file():
            digest = hashlib.sha256()
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
            hashes[name] = digest.hexdigest()
        elif not path.exists():
            hashes[name] = None
        else:
            raise ValueError(f"unsupported source entry: {name}")
    return hashes


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print("usage: write-evidence-metadata.py output.json gate [artifact]", file=sys.stderr)
        return 64
    output = Path(sys.argv[1])
    root = Path(__file__).resolve().parent.parent
    artifact = Path(sys.argv[3]) if len(sys.argv) == 4 else None
    status = subprocess.check_output(
        ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=all"],
        text=True,
    ).splitlines()
    metadata = {
        "createdAtUTC": datetime.now(timezone.utc).isoformat(),
        "sourceCommit": run("git", "-C", str(root), "rev-parse", "HEAD"),
        "workingTreeClean": not status,
        "workingTreePaths": [line[3:] for line in status],
        "sourceFileSHA256": source_hashes(root),
        "gate": sys.argv[2],
        "macOS": run("sw_vers", "-productVersion"),
        "macOSBuild": run("sw_vers", "-buildVersion"),
        "xcode": optional_run("xcodebuild", "-version"),
        "hardware": run("sysctl", "-n", "hw.model"),
    }
    if artifact:
        metadata["artifact"] = str(artifact.resolve())
        metadata["artifactSHA256"] = hashlib.sha256(artifact.read_bytes()).hexdigest()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
