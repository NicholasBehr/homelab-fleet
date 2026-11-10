"""A single active unit must not conceal another failed required unit."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import json

class HealthCheck(unittest.TestCase):
    def test_expected_http_status(self):
        for expected, actual, reached_tailnet in [(401, 401, True), (401, 200, False), (200, 200, True), (200, 500, False)]:
            with self.subTest(expected=expected, actual=actual), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                (root/'storage.json').write_text('[]')
                (root/'health.json').write_text(json.dumps({'units': [], 'url': 'http://unused', 'httpStatus': expected}))
                for name, body in {'curl': f'printf {actual}', 'tailscale': 'touch "$EVENTS"; exit 1'}.items():
                    target = root/name
                    target.write_text('#!/bin/sh\n'+body+'\n')
                    target.chmod(0o755)
                script = (Path(__file__).resolve().parents[1]/'scripts/health-check').read_text()
                script = script.replace('/etc/homelab-storage.json', str(root/'storage.json')).replace('/etc/homelab-health.json', str(root/'health.json'))
                env = dict(os.environ, PATH=tmp+':'+os.environ['PATH'], EVENTS=str(root/'events'))
                subprocess.run(['bash', '-c', script], env=env, capture_output=True)
                self.assertEqual((root/'events').exists(), reached_tailnet)

    def test_checks_every_required_unit(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'storage.json').write_text('[]')
            (root/'health.json').write_text('{"units":["healthy","broken"],"url":"http://unused"}')
            (root/'systemctl').write_text('#!/bin/sh\nprintf "%s\n" "$*" >> "$EVENTS"\ntest "$3" != broken\n')
            (root/'systemctl').chmod(0o755)
            script = (Path(__file__).resolve().parents[1]/'scripts/health-check').read_text()
            script = script.replace('/etc/homelab-storage.json', str(root/'storage.json')).replace('/etc/homelab-health.json', str(root/'health.json'))
            env = dict(os.environ, PATH=tmp+':'+os.environ['PATH'], EVENTS=str(root/'events'))
            result = subprocess.run(['bash','-c',script], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((root/'events').read_text().splitlines(), ['is-active --quiet healthy','is-active --quiet broken'])

if __name__ == '__main__': unittest.main()
