#!/usr/bin/env python3
"""Fail closed unless physical, usability, performance, and soak evidence is complete."""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

SUPPORTED_OS = {"14.2", "15", "26"}
DRAWER_ITEMS = {"wifi", "bluetooth", "battery", "sound", "focus"}
DRAWER_CHECKS = {
    "stableIdentity", "reclaimsSpace", "nativeActivation", "modifierForwarding",
    "temporaryPresentation", "rehides", "manualRestore", "crashRestore",
}
SCENARIOS = {
    "accessibilityGrant", "accessibilityDeny", "accessibilityRevoke",
    "menuBarAgentRestart", "sleepWake", "midOperationCrash", "displayChange",
    "autoHide", "managerConflict", "duplicateApplicationItems", "pasteTargetChange",
    "eventTapLoss", "coreAudioDeviceChange", "chromiumReconnect", "safariReconnect",
    "keychainLockedUnlocked", "voiceOverKeyboard", "turkishIME", "appearanceModes",
    "reduceMotionTransparency", "twoHundredPercentScale", "notchMultiDisplaySpaces",
}
TASKS = {
    "firstClipboardUse", "search", "plainTextPaste", "pin", "quickNoteSave",
    "returnToDraft", "keyboardCleaning", "readSystemStatus", "changeApplicationAudio",
    "drawerMoveRestore",
}


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _current_source(root: Path) -> tuple[str, dict]:
    metadata_path = root / "scripts/write-evidence-metadata.py"
    spec = importlib.util.spec_from_file_location("evidence_metadata", metadata_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    commit = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    return commit, module.source_hashes(root)


def validate(document: dict, commit: str, source_hashes: dict) -> None:
    _require(document.get("sourceCommit") == commit, "acceptance source commit differs")
    _require(document.get("sourceFileSHA256") == source_hashes, "acceptance source content differs")

    cells = document.get("physicalCells")
    _require(isinstance(cells, list), "physicalCells is required")
    by_os = {str(cell.get("os")): cell for cell in cells if isinstance(cell, dict)}
    _require(SUPPORTED_OS <= set(by_os), "macOS 14.2, 15, and 26 cells are required")
    for os_version in SUPPORTED_OS:
        cell = by_os[os_version]
        _require(cell.get("status") == "passed", f"macOS {os_version} did not pass")
        _require(bool(cell.get("hardware")), f"macOS {os_version} hardware is missing")
        _require(bool(cell.get("build")), f"macOS {os_version} build is missing")
        items = cell.get("drawerItems", {})
        _require(DRAWER_ITEMS <= set(items), f"macOS {os_version} drawer items are incomplete")
        for item in DRAWER_ITEMS:
            checks = items[item]
            _require(
                isinstance(checks, dict) and all(checks.get(name) is True for name in DRAWER_CHECKS),
                f"macOS {os_version} {item} drawer acceptance is incomplete",
            )
        scenarios = cell.get("scenarios", {})
        _require(
            isinstance(scenarios, dict) and all(scenarios.get(name) is True for name in SCENARIOS),
            f"macOS {os_version} physical scenarios are incomplete",
        )
    _require(document.get("betaSafeIncompatibility") is True, "developer beta safety is unverified")

    performance = document.get("performance", {})
    maximums = {
        "write5000P95Ms": 100, "read5000P95Ms": 50, "modelLoadP95Ms": 100,
        "filterP95Ms": 50, "layoutP95Ms": 50, "quickCenterFirstFrameP95Ms": 120,
        "drawerFirstFrameP95Ms": 120, "activationStartP95Ms": 50,
        "idleMedianCPUPercent": 1, "stableRSSMiB": 75,
        "externalManagementCPUPointIncrease": 0.2, "iconCount": 64,
        "iconCacheMiB": 8, "cycleResourceDelta": 0, "soakRSSGrowthPercent": 10,
        "missedFramePercent": 1,
    }
    for name, maximum in maximums.items():
        value = performance.get(name)
        _require(isinstance(value, (int, float)), f"performance metric {name} is missing")
        _require(value < maximum if name in {"idleMedianCPUPercent", "soakRSSGrowthPercent", "missedFramePercent"}
                 else value <= maximum, f"performance metric {name} exceeded its budget")
    _require(performance.get("openCloseCycles") == 100, "100 open/close cycles are required")
    _require(performance.get("soakHours", 0) >= 8, "eight-hour soak is required")
    _require(performance.get("soakCrashHangCount") == 0, "soak crash or hang detected")
    _require(performance.get("sqliteIntegrity") == "ok", "SQLite integrity did not pass")

    users = document.get("userAcceptance")
    _require(isinstance(users, list) and len(users) >= 5, "five user sessions are required")
    successes = {task: 0 for task in TASKS}
    total = 0
    for session in users[:5]:
        _require(session.get("criticalEvents") == 0, "critical user-acceptance event detected")
        results = session.get("tasks", {})
        _require(TASKS <= set(results), "a user session is missing required tasks")
        for task in TASKS:
            if results[task] is True:
                successes[task] += 1
                total += 1
    _require(total >= 45, "user acceptance is below 45/50")
    _require(all(count >= 4 for count in successes.values()), "a task is below 4/5 success")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify-integrated-acceptance.py evidence.json", file=sys.stderr)
        return 64
    root = Path(__file__).resolve().parent.parent
    try:
        document = json.loads(Path(sys.argv[1]).read_text())
        commit, hashes = _current_source(root)
        validate(document, commit, hashes)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"integrated acceptance gate: {error}", file=sys.stderr)
        return 1
    print("integrated acceptance gate: physical, usability, performance, and soak evidence passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
