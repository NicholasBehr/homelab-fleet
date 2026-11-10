"""Metadata regression checks for the runtime credential boundary."""
import importlib.machinery
import importlib.util
import io
import stat
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from pathlib import Path

loader = importlib.machinery.SourceFileLoader('verify_secret', str(Path(__file__).parents[1] / 'scripts/verify-secret'))
spec = importlib.util.spec_from_loader(loader.name, loader)
guard = importlib.util.module_from_spec(spec)
loader.exec_module(guard)


class RuntimeSecrets(unittest.TestCase):
    def exercise(self, mode=0o600, uid=0, gid=0, data=b'fixture', directory=0o700,
                 parent_uid=0, parent_gid=0, kind=stat.S_IFREG, parent_kind=stat.S_IFDIR):
        def metadata(path):
            if str(path) == '/persist/secrets':
                return SimpleNamespace(st_mode=parent_kind | directory, st_uid=parent_uid, st_gid=parent_gid)
            return SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0, st_gid=0)
        info = SimpleNamespace(st_mode=kind | mode, st_uid=uid, st_gid=gid)
        class Stream(io.BytesIO):
            def fileno(self):
                return 99
        with patch.object(Path, 'lstat', metadata), patch.object(guard.os, 'open', return_value=99), \
             patch.object(guard.os, 'fdopen', return_value=Stream(data)), \
             patch.object(guard.os, 'fstat', return_value=info):
            guard.verify('/persist/secrets/fixture')

    def test_private_modes(self):
        for mode in (0o400, 0o600):
            self.exercise(mode=mode)

    def test_unsafe_metadata_and_empty_content(self):
        for arguments in ({'mode': 0o644}, {'uid': 1000}, {'gid': 1000}, {'data': b''},
                          {'directory': 0o755}, {'parent_uid': 1000}, {'parent_gid': 1000},
                          {'kind': stat.S_IFIFO}, {'kind': stat.S_IFLNK},
                          {'parent_kind': stat.S_IFLNK}):
            with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                self.exercise(**arguments)
