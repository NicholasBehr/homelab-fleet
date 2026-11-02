"""Run the actual NixOS Borg job/cleanup scripts with isolated state and fake I/O.

Only process control, dump and remote Borg are mocked. Real flock protects the
operation. This supplements real encrypted Borg/PostgreSQL archive tests.
"""
import fcntl
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

launcher, cleanup, prepare, app_cleanup = map(Path, sys.argv[1:])
native = Path(shlex.split(launcher.read_text())[-1])

for scenario in ['success', 'borg-failure', 'dump-failure', 'lock-held', 'stale-owner', 'restart-failure']:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        for directory in ['persist/backup', 'run/homelab-backup', 'etc', 'bin']:
            (root/directory).mkdir(parents=True, exist_ok=True)
        (root/'etc/homelab-versions.json').write_text('{}')
        copies = {p: root/p.name for p in [native, cleanup, prepare, app_cleanup]}
        for original, target in copies.items():
            content = original.read_text()
            for old, new in copies.items():
                content = content.replace(str(old), str(new))
            for path in ['/persist', '/run/homelab-backup', '/etc/homelab-versions.json']:
                content = content.replace(path, str(root)+path)
            target.write_text(content)
            target.chmod(0o755)
        wrapper = r'''#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$EVENTS"
if test "$name" = runuser; then
 test "$SCENARIO" != dump-failure || exit 17
 printf 'consistent logical dump'
fi
if test "$name" = borg && test "$1" = create; then
 test -f "$FIXTURE/run/homelab-backup/restart"
 if grep -q '^systemctl start' "$EVENTS"; then exit 99; fi
 test "$SCENARIO" != borg-failure || exit 18
fi
if test "$name" = systemctl && test "$1" = start && test "$2" = tailscaled.service; then
 test "$SCENARIO" != restart-failure || exit 19
fi
'''
        for command in ['borg', 'systemctl', 'runuser']:
            target = root/'bin'/command
            target.write_text(wrapper); target.chmod(0o755)
        env = dict(os.environ, PATH=str(root/'bin')+':'+os.environ['PATH'],
                   SCENARIO=scenario, EVENTS=str(root/'events'), FIXTURE=str(root),
                   INVOCATION_ID='this-invocation')
        owner = root/'run/homelab-backup/owner'
        marker = root/'run/homelab-backup/restart'
        if scenario == 'stale-owner':
            owner.write_text('previous-invocation'); marker.touch()
        with open(root/'persist/operation.lock', 'w') as lock:
            if scenario == 'lock-held':
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                owner.write_text('other-operation'); marker.touch()
            result = subprocess.run(['bash', str(copies[native])], env=env, capture_output=True)
            assert (result.returncode == 0) == (scenario == 'success'), (scenario, result.stderr)
            events = (root/'events').read_text() if (root/'events').exists() else ''
            if scenario in ['lock-held', 'stale-owner']:
                assert not events, (scenario, events)
                assert marker.exists()
            else:
                for unit in ['tailscaled', 'redis-immich', 'immich-machine-learning', 'immich-server']:
                    assert 'systemctl start '+unit+'.service' in events, (scenario, events)
                assert marker.exists() == (scenario == 'restart-failure')
                assert owner.exists() == (scenario == 'restart-failure')
            # ExecStopPost is a separate process, same invocation; it must also be safe.
            env['SCENARIO'] = 'success'
            recovered = subprocess.run(['bash', str(copies[cleanup])], env=env, capture_output=True)
            assert recovered.returncode == 0, (scenario, recovered.stderr)
            if scenario not in ['lock-held', 'stale-owner']:
                assert not marker.exists() and not owner.exists()
        print('Borg job lifecycle:', scenario, 'passed')
