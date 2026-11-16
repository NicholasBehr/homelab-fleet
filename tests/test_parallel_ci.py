"""Fail-closed matrix aggregation and exact-release artifact handoff."""
import hashlib
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load_source(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


gate = load_source('ci_result', ROOT / 'scripts/ci-result')
release = load_source('assemble_release', ROOT / 'scripts/assemble-release')

class RequiredCheck(unittest.TestCase):
    def test_selected_images_require_success(self):
        gate.require_success('success', 'success', ['immich'])
        for result in ['failure', 'cancelled', 'skipped', '']:
            with self.subTest(result=result), self.assertRaises(ValueError):
                gate.require_success('success', result, ['immich'])
    def test_empty_selection_requires_skipped_matrix(self):
        gate.require_success('success', 'skipped', [])
        for result in ['failure', 'cancelled', 'success', '']:
            with self.subTest(result=result), self.assertRaises(ValueError):
                gate.require_success('success', result, [])
    def test_validation_failure_never_passes(self):
        for result in ['failure', 'cancelled', 'skipped', '']:
            with self.subTest(result=result), self.assertRaises(ValueError):
                gate.require_success(result, 'skipped', [])
    def test_invalid_selection_never_passes(self):
        for selected in [None, {}, [''], [None]]:
            with self.subTest(selected=selected), self.assertRaises(ValueError):
                gate.require_success('success', 'skipped', selected)

class ReleaseAssembly(unittest.TestCase):
    def fixture(self, root):
        catalog = {name: {'service':name,'variant':'operational'} for name in ['first','second']}
        for name, entry in catalog.items():
            archive = name+'-v0.1.0-x86_64-linux.tar.xz'
            manifest = name+'-manifest.json'
            (root/archive).write_bytes(b'fixture archive bytes')
            (root/manifest).write_text(json.dumps(dict(outputName=name, **entry, commit='reviewed',
                repositoryVersion='0.1.0', architecture='x86_64-linux',archive=archive)))
            (root/(name+'-SHA256SUMS')).write_text(''.join(
                hashlib.sha256((root/file).read_bytes()).hexdigest()+'  '+file+'\n'
                for file in [archive,manifest]))
        return catalog
    def test_complete_release_assembles(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); catalog=self.fixture(root)
            release.assemble(root,catalog,'reviewed','0.1.0')
            self.assertEqual(len((root/'SHA256SUMS').read_text().splitlines()),4)
            self.assertFalse(list(root.glob('*-SHA256SUMS')))
    def test_checksum_output_is_canonical_without_source_newline(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); catalog=self.fixture(root)
            path=root/'first-SHA256SUMS'; path.write_text(path.read_text().rstrip('\n'))
            release.assemble(root,catalog,'reviewed','0.1.0')
            self.assertEqual(len((root/'SHA256SUMS').read_text().splitlines()),4)
    def test_partial_release_refused_without_mutation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); catalog=self.fixture(root)
            (root/'second-manifest.json').unlink()
            with self.assertRaises(ValueError): release.assemble(root,catalog,'reviewed','0.1.0')
            self.assertTrue((root/'first-SHA256SUMS').exists())
            self.assertFalse((root/'SHA256SUMS').exists())
    def test_changed_bytes_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); catalog=self.fixture(root)
            (root/'first-v0.1.0-x86_64-linux.tar.xz').write_bytes(b'tampered')
            with self.assertRaises(ValueError): release.assemble(root,catalog,'reviewed','0.1.0')
    def test_wrong_commit_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); catalog=self.fixture(root)
            with self.assertRaises(ValueError): release.assemble(root,catalog,'different','0.1.0')
    def test_extra_artifact_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); catalog=self.fixture(root); (root/'unexpected').touch()
            with self.assertRaises(ValueError): release.assemble(root,catalog,'reviewed','0.1.0')
    def test_checksum_paths_cannot_escape(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); catalog=self.fixture(root)
            (root/'first-SHA256SUMS').write_text('0'*64+'  ../elsewhere\n')
            with self.assertRaises(ValueError): release.assemble(root,catalog,'reviewed','0.1.0')
    def test_symlink_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); catalog=self.fixture(root)
            archive=root/'first-v0.1.0-x86_64-linux.tar.xz'
            archive.unlink(); archive.symlink_to('second-v0.1.0-x86_64-linux.tar.xz')
            with self.assertRaises(ValueError): release.assemble(root,catalog,'reviewed','0.1.0')

if __name__ == '__main__': unittest.main()
