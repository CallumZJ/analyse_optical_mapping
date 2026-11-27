"""Adversarial archive-safety tests for the .mlapp surgery helper."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path


HELPER = Path(__file__).parent / "helpers" / "mlapp_surgery.py"
SPEC = importlib.util.spec_from_file_location("mlapp_surgery", HELPER)
assert SPEC is not None and SPEC.loader is not None
SURGERY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SURGERY)


class MlappSurgeryTests(unittest.TestCase):
    def test_nonzero_zip_flags_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as raw_root:
            root = Path(raw_root)
            archive = root / "flagged.mlapp"
            with zipfile.ZipFile(archive, "w") as zf:
                # Non-ASCII filename forces the UTF-8 general-purpose flag.
                zf.writestr("é.xml", b"<x/>")
                zf.writestr("matlab/document.xml", b"<document/>")
            report, _ = SURGERY.inspect_archive(archive)
            self.assertTrue(any(m["flag_bits"] for m in report["members"]))
            errors = SURGERY.validate_source(report)
            self.assertTrue(
                any("unsupported non-zero ZIP flag_bits" in error for error in errors),
                errors,
            )


if __name__ == "__main__":
    unittest.main()
