"""Runtime endpoint parsing must fail closed and never execute file contents."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

LOADER = Path(__file__).resolve().parents[1] / 'modules/borg-repository'


class RepositoryFileTests(unittest.TestCase):
    def run_loader(self, content):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            endpoint = root / 'repository'
            if content is not None:
                endpoint.write_text(content)
            result = subprocess.run(
                ['bash', '-c', 'set -eu; source "$1" "$2"; printf "%s" "$BORG_REPO"',
                 'test', str(LOADER), str(endpoint)],
                cwd=root, env=dict(os.environ, BORG_REPO='ssh://stale@invalid:23/./old'),
                capture_output=True, text=True)
            self.assertFalse((root / 'INJECTED').exists())
            return result

    def test_valid_remote(self):
        value = 'ssh://fixture@example.invalid:23/./archive'
        for content in [value, value + '\n']:
            result = self.run_loader(content)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, value)

    def test_bad_or_missing_fails_without_exposing_content(self):
        for value in [None, '', '\n', '/tmp/local', 'ssh://secret@host:23/./a\n\n',
                      'ssh://secret@host:23/./a\nssh://other@host:23/./b',
                      'ssh://secret@host:23/./a b', 'export BORG_REPO=secret']:
            result = self.run_loader(value)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')
            self.assertNotIn('secret', result.stderr)

    def test_shell_syntax_is_literal_data(self):
        value = 'ssh://fixture@example.invalid:23/./$(touch${IFS}INJECTED)'
        result = self.run_loader(value)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, value)
