"""Failure injection against actual backup hooks, isolated from the host."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class BackupHooks(unittest.TestCase):
    def exercise(self, failure="", restart_failure=False):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            for directory in ['persist', 'etc', 'bin', 'run']:
                (base/directory).mkdir(parents=True, exist_ok=True)
            (base/'etc/homelab-versions.json').write_text('{}')
            wrapper = r'''#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$EVENTS"
if test "$name" = systemctl && test "$1" = stop; then
 case "$FAILURE" in
  stop-app) test "$2" != immich-server.service || exit 17 ;;
  stop-state) test "$2" != redis-immich.service || exit 17 ;;
 esac
fi
if test "$name" = systemctl && test "$1" = start && test "$2" = tailscaled.service; then
 test "$RESTART_FAILURE" != 1 || exit 18
fi
if test "$name" = runuser; then
 test "$FAILURE" != dump || exit 17
 printf 'database dump'
fi
'''
            for command in ['systemctl', 'runuser']:
                p = base/'bin'/command
                p.write_text(wrapper); p.chmod(0o755)
            env = dict(os.environ, PATH=str(base/'bin')+':'+os.environ['PATH'], EVENTS=str(base/'events'), FAILURE=failure, RESTART_FAILURE=str(int(restart_failure)))
            def run(name):
                content = (ROOT/name).read_text()
                for path in ['/persist', '/run/homelab-backup', '/etc/homelab-versions.json']:
                    content = content.replace(path, str(base)+path)
                p = base/name; p.write_text(content)
                return subprocess.run(['bash', str(p)], env=env, capture_output=True)
            result = run('backup-prepare')
            self.assertEqual(result.returncode == 0, failure == '', result.stderr.decode())
            before = (base/'events').read_text()
            self.assertNotIn('systemctl start', before, 'Services must stay stopped for Borg')
            self.assertTrue((base/'run/homelab-backup/restart').exists())
            if failure == '':
                self.assertEqual((base/'persist/backup/immich.dump').read_text(), 'database dump')
                # Simulate either successful or failed Borg: both require cleanup.
                self.assertLess(before.index('stop immich-server'), before.index('pg_dump'))
            cleanup = run('backup-cleanup')
            self.assertEqual(cleanup.returncode == 0, not restart_failure)
            events = (base/'events').read_text()
            for unit in ['tailscaled', 'redis-immich', 'immich-machine-learning', 'immich-server']:
                self.assertIn('systemctl start '+unit+'.service', events)
            self.assertEqual((base/'run/homelab-backup/restart').exists(), restart_failure)
            if not restart_failure:
                self.assertEqual(run('backup-cleanup').returncode, 0)
                self.assertEqual((base/'events').read_text(), events, 'Cleanup must be idempotent')
    def test_success_and_borg_failure_cleanup(self): self.exercise()
    def test_partial_app_stop_failure(self): self.exercise('stop-app')
    def test_state_stop_failure(self): self.exercise('stop-state')
    def test_dump_failure(self): self.exercise('dump')
    def test_failed_restart_attempts_every_service_and_retains_intent(self): self.exercise(restart_failure=True)

if __name__ == '__main__': unittest.main()
