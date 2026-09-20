import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "write-evidence-metadata.py"
SPEC = importlib.util.spec_from_file_location("evidence_metadata", SCRIPT)
metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metadata)


class EvidenceMetadataTests(unittest.TestCase):
    def test_dirty_content_changes_digest_without_path_change(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Feature.swift"
            source.write_text("first revision")
            with patch.object(metadata.subprocess, "check_output", return_value=b"Feature.swift\0"):
                before = metadata.source_hashes(root)
                source.write_text("second revision")
                after = metadata.source_hashes(root)
            self.assertEqual(before.keys(), after.keys())
            self.assertNotEqual(before["Feature.swift"], after["Feature.swift"])

    def test_deleted_files_and_symlinks_do_not_read_external_content(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "link").symlink_to("missing-destination")
            with patch.object(
                metadata.subprocess, "check_output", return_value=b"deleted.swift\0link\0link\0"
            ):
                snapshot = metadata.source_hashes(root)
            self.assertEqual(len(snapshot), 2)
            self.assertIsNone(snapshot["deleted.swift"])
            self.assertEqual(len(snapshot["link"]), 64)


if __name__ == "__main__":
    unittest.main()
