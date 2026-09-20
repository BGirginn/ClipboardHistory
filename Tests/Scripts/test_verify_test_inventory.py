import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "verify-test-inventory.py"
SPEC = importlib.util.spec_from_file_location("verify_test_inventory", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class TestInventoryTests(unittest.TestCase):
    def test_all_declared_tests_must_pass_exactly_once(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "Fixture.swift").write_text("func testFirst() {}\nfunc testSecond() {}\n")
            first = {"nodeType": "Test Case", "name": "testFirst()", "result": "Passed"}
            second = {"nodeType": "Test Case", "name": "testSecond()", "result": "Passed"}
            self.assertEqual(MODULE.verify(source, {"testNodes": [first, second]}), 2)
            with self.assertRaisesRegex(ValueError, "missing=.*testSecond"):
                MODULE.verify(source, {"testNodes": [first]})
            with self.assertRaisesRegex(ValueError, "did not pass"):
                MODULE.verify(source, {"testNodes": [first, second | {"result": "Failed"}]})
            with self.assertRaisesRegex(ValueError, "duplicate executed"):
                MODULE.verify(source, {"testNodes": [first, first, second]})


if __name__ == "__main__":
    unittest.main()
