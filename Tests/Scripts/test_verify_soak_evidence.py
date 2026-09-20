import csv
import runpy
import tempfile
import unittest
from pathlib import Path


VERIFY = runpy.run_path(
    str(Path(__file__).resolve().parents[2] / "scripts/verify-soak-evidence.py")
)["verify"]


class SoakEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "samples.csv"
        self.samples = [
            {
                "epoch": str(index * 60),
                "pid": "123",
                "cpu": "0.4",
                "rss_kb": "40000",
                "identity": "1",
                "db_open": "1",
                "responsive": "1",
            }
            for index in range(481)
        ]

    def verify_samples(self):
        with self.path.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=self.samples[0].keys())
            writer.writeheader()
            writer.writerows(self.samples)
        return VERIFY(self.path)

    def test_complete_eight_hour_evidence_passes(self):
        self.assertEqual(self.verify_samples()["duration_seconds"], 28800)

    def test_wrong_database_or_unresponsive_process_fails(self):
        for field in ("db_open", "responsive", "identity"):
            with self.subTest(field=field):
                self.samples[200][field] = "0"
                with self.assertRaisesRegex(ValueError, "database ownership|responsiveness"):
                    self.verify_samples()
                self.samples[200][field] = "1"

    def test_cpu_and_rss_limits_fail(self):
        for field, value in (("cpu", "1.0"), ("rss_kb", "76800")):
            with self.subTest(field=field):
                for sample in self.samples:
                    sample[field] = value
                with self.assertRaisesRegex(ValueError, "budget exceeded"):
                    self.verify_samples()
                for sample in self.samples:
                    sample[field] = "0.4" if field == "cpu" else "40000"

    def test_growth_at_ten_percent_fails(self):
        for sample in self.samples[-11:]:
            sample["rss_kb"] = "44000"
        with self.assertRaisesRegex(ValueError, "budget exceeded"):
            self.verify_samples()

    def test_missing_sample_fails(self):
        del self.samples[200]
        with self.assertRaisesRegex(ValueError, "missing or out of order"):
            self.verify_samples()


if __name__ == "__main__":
    unittest.main()
