import copy
import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/verify-integrated-acceptance.py"
SPEC = importlib.util.spec_from_file_location("integrated_acceptance", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def passing_document():
    drawer_checks = {name: True for name in gate.DRAWER_CHECKS}
    cell = {
        "status": "passed", "hardware": "fixture", "build": "fixture",
        "drawerItems": {name: dict(drawer_checks) for name in gate.DRAWER_ITEMS},
        "scenarios": {name: True for name in gate.SCENARIOS},
    }
    tasks = {name: True for name in gate.TASKS}
    return {
        "sourceCommit": "candidate", "sourceFileSHA256": {"Feature.swift": "hash"},
        "physicalCells": [{**copy.deepcopy(cell), "os": version} for version in gate.SUPPORTED_OS],
        "betaSafeIncompatibility": True,
        "performance": {
            "write5000P95Ms": 100, "read5000P95Ms": 50, "modelLoadP95Ms": 100,
            "filterP95Ms": 50, "layoutP95Ms": 50, "quickCenterFirstFrameP95Ms": 120,
            "drawerFirstFrameP95Ms": 120, "activationStartP95Ms": 50,
            "idleMedianCPUPercent": 0.9, "stableRSSMiB": 75,
            "externalManagementCPUPointIncrease": 0.2, "iconCount": 64,
            "iconCacheMiB": 8, "cycleResourceDelta": 0, "openCloseCycles": 100,
            "soakHours": 8, "soakRSSGrowthPercent": 9.9, "soakCrashHangCount": 0,
            "sqliteIntegrity": "ok", "missedFramePercent": 0.9,
        },
        "userAcceptance": [{"criticalEvents": 0, "tasks": dict(tasks)} for _ in range(5)],
    }


class IntegratedAcceptanceTests(unittest.TestCase):
    def test_complete_evidence_passes(self):
        gate.validate(passing_document(), "candidate", {"Feature.swift": "hash"})

    def test_missing_physical_cell_and_stale_source_fail(self):
        document = passing_document()
        document["physicalCells"] = document["physicalCells"][:-1]
        with self.assertRaisesRegex(ValueError, "cells are required"):
            gate.validate(document, "candidate", {"Feature.swift": "hash"})
        document = passing_document()
        with self.assertRaisesRegex(ValueError, "content differs"):
            gate.validate(document, "candidate", {"Feature.swift": "changed"})

    def test_drawer_performance_and_user_thresholds_fail_closed(self):
        document = passing_document()
        document["physicalCells"][0]["drawerItems"]["wifi"]["reclaimsSpace"] = False
        with self.assertRaisesRegex(ValueError, "drawer acceptance"):
            gate.validate(document, "candidate", {"Feature.swift": "hash"})
        document = passing_document()
        document["performance"]["idleMedianCPUPercent"] = 1
        with self.assertRaisesRegex(ValueError, "exceeded"):
            gate.validate(document, "candidate", {"Feature.swift": "hash"})
        document = passing_document()
        for session in document["userAcceptance"][:2]:
            session["tasks"]["search"] = False
        with self.assertRaisesRegex(ValueError, "below 4/5"):
            gate.validate(document, "candidate", {"Feature.swift": "hash"})


if __name__ == "__main__":
    unittest.main()
