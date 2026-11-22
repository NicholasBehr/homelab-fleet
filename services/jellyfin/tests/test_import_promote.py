"""Tests for safe staging-to-library publication."""
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "promote.py"


class PromoteTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.staging = self.root / "staging"
        self.library = self.root / "library"
        self.staging.mkdir()
        self.library.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def run_promote(self, entries):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(self.staging), str(self.library)],
            input=json.dumps(entries),
            capture_output=True,
            text=True,
        )

    def entry(self, path, source):
        return {
            "Path": path,
            "Size": source.stat().st_size,
            "ModTime": datetime.fromtimestamp(
                source.stat().st_mtime, timezone.utc
            ).isoformat().replace("+00:00", "Z"),
            "IsDir": False,
        }

    def test_publishes_nested_files_from_the_current_remote_listing(self):
        staged = self.staging / "Season 01" / "episode.mkv"
        staged.parent.mkdir()
        staged.write_bytes(b"complete media")

        result = self.run_promote([self.entry("Season 01/episode.mkv", staged)])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.library / "Season 01" / "episode.mkv").read_bytes(),
            b"complete media",
        )
        self.assertFalse(staged.exists())

    def test_collision_preserves_both_existing_and_staged_files(self):
        staged = self.staging / "movie.mkv"
        staged.write_bytes(b"new")
        existing = self.library / "movie.mkv"
        existing.write_bytes(b"existing")

        result = self.run_promote([self.entry("movie.mkv", staged)])

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(staged.read_bytes(), b"new")
        self.assertEqual(existing.read_bytes(), b"existing")

    def test_repeat_listing_keeps_matching_library_file_unchanged(self):
        staged = self.staging / "movie.mkv"
        staged.write_bytes(b"same movie")
        manifest = [self.entry("movie.mkv", staged)]
        first = self.run_promote(manifest)
        published = self.library / "movie.mkv"
        original_mtime = published.stat().st_mtime_ns

        second = self.run_promote(manifest)

        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(published.read_bytes(), b"same movie")
        self.assertEqual(published.stat().st_mtime_ns, original_mtime)

    def test_refuses_staged_symlink(self):
        target = self.root / "outside"
        target.write_bytes(b"outside")
        staged = self.staging / "movie.mkv"
        staged.symlink_to(target)

        result = self.run_promote([self.entry("movie.mkv", target)])

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.library / "movie.mkv").exists())

    def test_refuses_library_symlinked_parent(self):
        target = self.root / "outside"
        target.mkdir()
        (self.library / "Season 01").symlink_to(target, target_is_directory=True)
        staged = self.staging / "Season 01" / "episode.mkv"
        staged.parent.mkdir()
        staged.write_bytes(b"media")

        result = self.run_promote([self.entry("Season 01/episode.mkv", staged)])

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((target / "episode.mkv").exists())
        self.assertTrue(staged.exists())

    def test_does_not_publish_staging_files_missing_from_current_remote_listing(self):
        staged = self.staging / "deleted-remotely.mkv"
        staged.write_bytes(b"old transfer")

        result = self.run_promote([])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(staged.exists())
        self.assertFalse((self.library / staged.name).exists())

    def test_rejects_remote_size_mismatch(self):
        staged = self.staging / "movie.mkv"
        staged.write_bytes(b"partial")
        entry = self.entry("movie.mkv", staged)
        entry["Size"] += 1

        result = self.run_promote([entry])

        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(staged.exists())
        self.assertFalse((self.library / staged.name).exists())

    def test_rejects_path_traversal_in_remote_listing(self):
        staged = self.staging / "movie.mkv"
        staged.write_bytes(b"media")

        result = self.run_promote([self.entry("../outside", staged)])

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "outside").exists())


if __name__ == "__main__":
    unittest.main()
