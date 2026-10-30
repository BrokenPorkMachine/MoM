"""Portable regression tests for the fail-closed guest qualification gate."""
import importlib.util
import pathlib
import unittest

PATH = pathlib.Path(__file__).resolve().parents[1] / "Scripts" / "qualify-guest.py"
spec = importlib.util.spec_from_file_location("qualification", PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class QualificationTests(unittest.TestCase):
    def valid_record(self):
        data = {name: "value" for name in module.IDENTITY}
        data["artifact_sha256"] = "a" * 64
        data["installer_sha256"] = "b" * 64
        data["schema_version"] = 1
        data["checks"] = {name: {"status": "pass", "evidence": "local-log.txt"}
                          for name in module.CHECKS}
        return data

    def test_complete_record(self):
        self.assertEqual(module.validate(self.valid_record()), [])

    def test_missing_check_fails(self):
        data = self.valid_record()
        del data["checks"]["reboot"]
        self.assertTrue(any("reboot" in x for x in module.validate(data)))

    def test_synthetic_or_unrun_test_fails(self):
        data = self.valid_record()
        data["checks"]["install"]["status"] = "not_run"
        self.assertTrue(module.validate(data))

    def test_missing_evidence_fails(self):
        data = self.valid_record()
        data["checks"]["disk_persistence"]["evidence"] = ""
        self.assertTrue(module.validate(data))

    def test_bad_digest_fails(self):
        data = self.valid_record()
        data["artifact_sha256"] = "short"
        self.assertTrue(module.validate(data))

    def test_bad_structure_fails(self):
        self.assertTrue(module.validate([]))
        self.assertTrue(module.validate({"schema_version": 1}))

if __name__ == "__main__":
    unittest.main()
