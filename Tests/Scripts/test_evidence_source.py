import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/verify-evidence-source.py"
SPEC = importlib.util.spec_from_file_location("evidence_source", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class EvidenceSourceTests(unittest.TestCase):
    def setUp(self):
        self.manifest = {
            "gate": "coverage", "workingTreeClean": True, "sourceCommit": "candidate",
            "sourceFileSHA256": {"Feature.swift": "first"},
        }

    def test_matching_clean_candidate_is_accepted(self):
        gate.validate(self.manifest, "candidate", {"Feature.swift": "first"})

    def test_same_commit_with_different_content_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "content differs"):
            gate.validate(self.manifest, "candidate", {"Feature.swift": "second"})

    def test_old_commit_dirty_run_missing_hashes_and_wrong_gate_are_rejected(self):
        for field, value in (
            ("sourceCommit", "previous"), ("workingTreeClean", False),
            ("sourceFileSHA256", {}), ("gate", "performance"),
        ):
            with self.subTest(field=field), self.assertRaises(ValueError):
                gate.validate({**self.manifest, field: value}, "candidate", {"Feature.swift": "first"})


if __name__ == "__main__":
    unittest.main()
