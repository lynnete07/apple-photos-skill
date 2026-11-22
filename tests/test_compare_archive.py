import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "apple-photos" / "scripts" / "compare_archive.py"


class CompareArchiveTests(unittest.TestCase):
    def run_compare(self, source: Path, archive: Path, *extra: str):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--source", str(source), "--archive", str(archive), *extra],
            check=False,
            capture_output=True,
            text=True,
        )
        return result, json.loads(result.stdout)

    def test_raw_is_compared_by_default(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            archive = root / "archive"
            source.mkdir()
            archive.mkdir()
            (source / "photo.jpg").write_bytes(b"jpeg")
            (archive / "photo.jpg").write_bytes(b"jpeg")
            (source / "photo.arw").write_bytes(b"raw")

            result, payload = self.run_compare(source, archive)

            self.assertEqual(result.returncode, 2)
            self.assertFalse(payload["complete"])
            self.assertEqual(payload["missing_source_files"], 1)
            self.assertEqual(payload["ignored_suffixes"], [])

    def test_suffix_can_be_explicitly_ignored(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            archive = root / "archive"
            source.mkdir()
            archive.mkdir()
            (source / "photo.jpg").write_bytes(b"jpeg")
            (archive / "photo.jpg").write_bytes(b"jpeg")
            (source / "photo.arw").write_bytes(b"raw")

            result, payload = self.run_compare(source, archive, "--ignore-suffix", "arw")

            self.assertEqual(result.returncode, 0)
            self.assertTrue(payload["complete"])
            self.assertTrue(payload["exact_match"])
            self.assertEqual(payload["ignored_suffixes"], [".arw"])


if __name__ == "__main__":
    unittest.main()
