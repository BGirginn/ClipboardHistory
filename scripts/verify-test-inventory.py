#!/usr/bin/env python3
"""Require every declared XCTest method to pass in a complete result bundle."""

import json
import re
import subprocess
import sys
from pathlib import Path


def test_names(node: object) -> list[str]:
    if not isinstance(node, dict):
        return []
    names = []
    if node.get("nodeType") == "Test Case":
        if node.get("result") != "Passed":
            raise ValueError(f"test did not pass: {node.get('nodeIdentifier')}")
        name = node.get("name", "")
        if not re.fullmatch(r"test\w+\(\)", name):
            raise ValueError(f"unexpected test identity: {name}")
        names.append(name.removesuffix("()"))
    for child in node.get("children", []):
        names.extend(test_names(child))
    return names


def verify(source_directory: Path, result: dict) -> int:
    declared = []
    for source in sorted(source_directory.glob("*.swift")):
        declared.extend(re.findall(r"\bfunc\s+(test\w+)\s*\(", source.read_text()))
    executed = []
    for node in result.get("testNodes", []):
        executed.extend(test_names(node))
    if len(declared) != len(set(declared)):
        raise ValueError("duplicate declared test names")
    if len(executed) != len(set(executed)):
        raise ValueError("duplicate executed test names")
    missing = sorted(set(declared) - set(executed))
    unexpected = sorted(set(executed) - set(declared))
    if missing or unexpected:
        raise ValueError(f"test inventory mismatch: missing={missing} unexpected={unexpected}")
    if not declared:
        raise ValueError("test source inventory is empty")
    return len(executed)


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ("Unit", "UI"):
        print("usage: verify-test-inventory.py Unit|UI Result.xcresult", file=sys.stderr)
        return 64
    source_directory = Path(__file__).resolve().parent.parent / "Tests" / sys.argv[1]
    output = subprocess.check_output(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", sys.argv[2]],
        text=True,
    )
    try:
        count = verify(source_directory, json.loads(output))
    except ValueError as error:
        print(f"test inventory: {error}", file=sys.stderr)
        return 1
    print(f"test inventory: {sys.argv[1]} {count}/{count} declared tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
