"""Exercise Paperless backup hooks with disposable fake commands."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BackupHooks(unittest.TestCase):
    def exercise(self, failure="", cleanup_failure=""):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "bin").mkdir()
            (root / "etc").mkdir()
            (root / "etc/homelab-versions.json").write_text('{"paperless-ngx":"fixture"}')
            events = root / "events"
            events.touch()
            wrappers = {
                "systemctl": '''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$EVENTS"
if test "$1" = is-active; then test "$2" = --quiet && test "$3" = "$FAILURE.service"; exit; fi
if test "$1" = stop && test "$FAILURE" = stop; then exit 1; fi
if test "$1" = start && test "$2" = "$CLEANUP_FAILURE"; then exit 1; fi
exit 0
''',
                "runuser": '''#!/usr/bin/env bash
printf 'dump\n' >> "$EVENTS"
printf 'synthetic database dump'
test "$FAILURE" != dump
''',
            }
            for name, content in wrappers.items():
                path = root / "bin" / name
                path.write_text(content)
                path.chmod(0o755)
            for name in ("backup-prepare", "backup-cleanup"):
                source = (ROOT / name).read_text()
                for prefix in ("/persist", "/run/homelab-backup", "/etc/homelab-versions.json"):
                    source = source.replace(prefix, str(root) + prefix)
                (root / name).write_text(source)
            env = dict(
                os.environ,
                PATH=str(root / "bin") + ":" + os.environ["PATH"],
                EVENTS=str(events),
                FAILURE=failure,
                CLEANUP_FAILURE=cleanup_failure,
            )
            prepared = subprocess.run(["bash", str(root / "backup-prepare")], env=env, capture_output=True)
            self.assertEqual(prepared.returncode == 0, not failure, prepared.stderr.decode())
            self.assertNotIn("start ", events.read_text())
            if failure in ("stop", "paperless-consumer", "paperless-task-queue", "paperless-web", "paperless-scheduler"):
                self.assertNotIn("dump\n", events.read_text())
            self.assertEqual((root / "persist/backup/paperless.dump").exists(), not failure)
            cleaned = subprocess.run(["bash", str(root / "backup-cleanup")], env=env, capture_output=True)
            self.assertEqual(cleaned.returncode == 0, not cleanup_failure, cleaned.stderr.decode())
            for unit in (
                "postgresql.service",
                "redis-paperless.service",
                "tailscaled.service",
                "paperless-secret-key.service",
                "paperless-scheduler.service",
                "paperless-task-queue.service",
                "paperless-consumer.service",
                "paperless-web.service",
            ):
                self.assertIn("start " + unit, events.read_text())
            intent = root / "run/homelab-backup/restart"
            self.assertEqual(intent.exists(), bool(cleanup_failure))
            if not cleanup_failure:
                prior = events.read_text()
                subprocess.run(["bash", str(root / "backup-cleanup")], env=env, check=True)
                self.assertEqual(events.read_text(), prior)

    def test_success_and_borg_failure_cleanup(self):
        self.exercise()

    def test_prepare_failures(self):
        for failure in ("stop", "dump", "paperless-consumer", "paperless-task-queue", "paperless-web", "paperless-scheduler"):
            with self.subTest(failure=failure):
                self.exercise(failure=failure)

    def test_every_restart_attempted_on_failure(self):
        units = (
            "postgresql.service",
            "redis-paperless.service",
            "tailscaled.service",
            "paperless-secret-key.service",
            "paperless-scheduler.service",
            "paperless-task-queue.service",
            "paperless-consumer.service",
            "paperless-web.service",
        )
        for failure in units:
            with self.subTest(failure=failure):
                self.exercise(cleanup_failure=failure)


if __name__ == "__main__":
    unittest.main()
