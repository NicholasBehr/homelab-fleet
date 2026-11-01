"""Failure injection against the production hook scripts with isolated paths/tools."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class BackupHooks(unittest.TestCase):
    def exercise(self, failure):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            for directory in ['persist/redis', 'persist/immich', 'data/immich', 'etc', 'bin', 'run']:
                (base/directory).mkdir(parents=True, exist_ok=True)
            (base/'etc/homelab-versions.json').write_text('{}')
            wrapper = '''#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s %s\\n' "$name" "$*" >> "$EVENTS"
if test "$name" = rsync; then
 count=$(grep -c '^rsync' "$EVENTS")
 test "${FAILURE:-}" != "rsync-$count" || exit 17
fi
if test "$name" = systemctl && test "${FAILURE:-}" = stop && test "$1" = stop; then exit 17; fi
if test "$name" = runuser; then
 test "${FAILURE:-}" != dump || exit 17
 printf 'database dump'
fi
'''
            for command in ['rsync', 'systemctl', 'runuser']:
                p = base/'bin'/command
                p.write_text(wrapper)
                p.chmod(0o755)
            env = dict(os.environ, PATH=str(base/'bin')+':'+os.environ['PATH'], EVENTS=str(base/'events'), FAILURE=failure)
            def run(name):
                content = (ROOT/'scripts'/name).read_text()
                for path in ['/persist', '/data', '/run/homelab-backup', '/etc/homelab-versions.json']:
                    content = content.replace(path, str(base)+path)
                p = base/name
                p.write_text(content)
                return subprocess.run(['bash', str(p)], env=env, capture_output=True)
            result = run('backup-prepare')
            self.assertEqual(result.returncode == 0, failure == '', result.stderr.decode())
            cleanup = run('backup-cleanup')
            self.assertEqual(cleanup.returncode, 0, cleanup.stderr)
            events = (base/'events').read_text()
            if failure not in ('rsync-1', 'rsync-2'):
                self.assertIn('systemctl start redis-immich.service', events)
                self.assertIn('immich-server.service', events.split('systemctl start')[-1])
            self.assertFalse((base/'run/homelab-backup/restart').exists())
    def test_success(self): self.exercise('')
    def test_initial_sync_failure(self): self.exercise('rsync-1')
    def test_final_sync_failure(self): self.exercise('rsync-3')
    def test_hot_initial_sync_failure(self): self.exercise('rsync-2')
    def test_hot_final_sync_failure(self): self.exercise('rsync-4')
    def test_partial_stop_failure(self): self.exercise('stop')
    def test_dump_failure(self): self.exercise('dump')

if __name__ == '__main__': unittest.main()
