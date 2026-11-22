"""Exercise a Jellyfin-state-only Borg archive and SQLite restoration."""
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which("borg"), "Borg is provided by the repository dev shell")
class JellyfinRestoreTests(unittest.TestCase):
    def run_borg(self, *arguments, cwd):
        return subprocess.run(
            ["borg", *arguments],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=True,
        )

    def test_restores_application_state_without_media(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repository = root / "repository"
            work = root / "work"
            restore = root / "restore"
            database = work / "persist/jellyfin/data/library.db"
            database.parent.mkdir(parents=True)
            restore.mkdir()

            with sqlite3.connect(database) as connection:
                connection.execute("CREATE TABLE library (title TEXT NOT NULL)")
                connection.execute("INSERT INTO library VALUES (?)", ("synthetic title",))

            config = work / "persist/jellyfin/config/network.xml"
            config.parent.mkdir(parents=True)
            config.write_text("<NetworkConfiguration />\n")
            media = work / "data/media/movies/synthetic.mkv"
            media.parent.mkdir(parents=True)
            media.write_bytes(b"synthetic regenerable media")

            self.run_borg("init", "--encryption=none", str(repository), cwd=root)
            self.run_borg("create", f"{repository}::jellyfin-state", "persist", cwd=work)

            listing = self.run_borg("list", f"{repository}::jellyfin-state", cwd=root)
            self.assertIn("persist/jellyfin/data/library.db", listing.stdout)
            self.assertNotIn("data/media", listing.stdout)

            self.run_borg("extract", f"{repository}::jellyfin-state", cwd=restore)
            restored_db = restore / "persist/jellyfin/data/library.db"
            with sqlite3.connect(restored_db) as connection:
                self.assertEqual(
                    connection.execute("SELECT title FROM library").fetchone()[0],
                    "synthetic title",
                )
            self.assertEqual(
                (restore / "persist/jellyfin/config/network.xml").read_text(),
                "<NetworkConfiguration />\n",
            )
            self.assertFalse((restore / "data/media").exists())


if __name__ == "__main__":
    unittest.main()
