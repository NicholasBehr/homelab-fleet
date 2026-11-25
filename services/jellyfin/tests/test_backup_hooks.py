"""Failure injection for Jellyfin's backup quiesce and restart hooks."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE_UNITS = ["caddy", "jellyfin", "tailscale-policy", "tailscaled"]


class BackupHooks(unittest.TestCase):
    def exercise(
        self, initially_active="", active_after_stop="", restart_failure=""
    ):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "bin"
            binary.mkdir()
            wrapper = binary / "systemctl"
            wrapper.write_text(
                r"""#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$EVENTS"
unit=${3:-${2:-}}
base=${unit%.service}
base=${base%.timer}
if test "$1" = stop; then touch "$STATE/$base-stopped"; exit 0; fi
if test "$1" = is-active && test -e "$STATE/$base-stopped" && { test "$unit" = "$ACTIVE_AFTER_STOP" || test "$base" = "$ACTIVE_AFTER_STOP"; }; then exit 0; fi
if test "$1" = is-active && test ! -e "$STATE/$base-stopped"; then
  case " $INITIALLY_ACTIVE " in *" $unit "*) exit 0;; esac
fi
if test "$1" = is-active; then exit 3; fi
if test "$1" = start && { test "$2" = "$RESTART_FAILURE" || test "$2" = "$RESTART_FAILURE.service"; }; then exit 18; fi
"""
            )
            wrapper.chmod(0o755)
            events = root / "events"
            runtime_directory = root / "run"
            env = dict(
                os.environ,
                PATH=str(binary) + ":" + os.environ["PATH"],
                EVENTS=str(events),
                STATE=str(root),
                INITIALLY_ACTIVE=initially_active,
                ACTIVE_AFTER_STOP=active_after_stop,
                RESTART_FAILURE=restart_failure,
            )

            prepared = subprocess.run(
                ["bash", str(ROOT / "backup-prepare"), str(runtime_directory)],
                env=env,
                capture_output=True,
            )
            self.assertEqual(prepared.returncode == 0, active_after_stop == "")
            before_cleanup = events.read_text()
            self.assertTrue((runtime_directory / "restart").exists())
            self.assertEqual(
                (runtime_directory / "restart-rclone-timer").exists(),
                "rclone-import.timer" in initially_active.split(),
            )
            self.assertEqual(
                (runtime_directory / "restart-rclone-service").exists(),
                "rclone-import.service" in initially_active.split(),
            )
            self.assertIn("stop rclone-import.timer", before_cleanup)
            self.assertIn("stop caddy.service", before_cleanup)
            self.assertIn("stop jellyfin.service", before_cleanup)
            self.assertNotIn("start ", before_cleanup)

            cleaned = subprocess.run(
                ["bash", str(ROOT / "backup-cleanup"), str(runtime_directory)],
                env=env,
                capture_output=True,
            )
            self.assertEqual(cleaned.returncode == 0, restart_failure == "")
            self.assertEqual(
                (runtime_directory / "restart").exists(), restart_failure != ""
            )
            all_events = events.read_text()
            for unit in CORE_UNITS:
                self.assertIn(f"start {unit}", all_events)
            self.assertEqual(
                "start rclone-import.timer" in all_events,
                "rclone-import.timer" in initially_active.split(),
            )
            self.assertEqual(
                "start rclone-import\n" in all_events,
                "rclone-import.service" in initially_active.split(),
            )

    def test_success(self):
        self.exercise()

    def test_restarts_previously_active_rclone_units(self):
        self.exercise(initially_active="rclone-import.timer rclone-import.service")

    def test_jellyfin_refuses_to_stop(self):
        self.exercise(active_after_stop="jellyfin")

    def test_importer_refuses_to_stop(self):
        self.exercise(active_after_stop="rclone-import")

    def test_restart_attempts_every_service(self):
        self.exercise(restart_failure="tailscaled")


if __name__ == "__main__":
    unittest.main()
