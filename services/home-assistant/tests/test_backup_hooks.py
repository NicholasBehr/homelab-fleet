"""Failure injection against Home Assistant's quiesce/restart hooks."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BackupHooks(unittest.TestCase):
    def exercise(self, active_after_stop="", restart_failure=""):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "bin"
            binary.mkdir()
            wrapper = binary / "systemctl"
            wrapper.write_text(
                r'''#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$EVENTS"
if test "$1" = is-active && test "$3" = "$ACTIVE_AFTER_STOP.service"; then exit 0; fi
if test "$1" = is-active; then exit 3; fi
if test "$1" = start && test "$2" = "$RESTART_FAILURE.service"; then exit 18; fi
'''
            )
            wrapper.chmod(0o755)
            events = root / "events"
            env = dict(
                os.environ,
                PATH=str(binary) + ":" + os.environ["PATH"],
                EVENTS=str(events),
                ACTIVE_AFTER_STOP=active_after_stop,
                RESTART_FAILURE=restart_failure,
            )

            prepared = subprocess.run(
                ["bash", str(ROOT / "backup-prepare")], env=env, capture_output=True
            )
            self.assertEqual(prepared.returncode == 0, active_after_stop == "")
            before_cleanup = events.read_text()
            self.assertNotIn("start ", before_cleanup)

            cleaned = subprocess.run(
                ["bash", str(ROOT / "backup-cleanup")], env=env, capture_output=True
            )
            self.assertEqual(cleaned.returncode == 0, restart_failure == "")
            all_events = events.read_text()
            self.assertIn("start tailscaled.service", all_events)
            self.assertIn("start home-assistant.service", all_events)

    def test_success(self):
        self.exercise()

    def test_home_assistant_refuses_to_stop(self):
        self.exercise(active_after_stop="home-assistant")

    def test_tailscale_refuses_to_stop(self):
        self.exercise(active_after_stop="tailscaled")

    def test_restart_attempts_every_service(self):
        self.exercise(restart_failure="tailscaled")


if __name__ == "__main__":
    unittest.main()
