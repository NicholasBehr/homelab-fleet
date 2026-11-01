"""Exercise native layout writes, replacement, and refusal to move existing data."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1]/'scripts/immich-layout'

class ImmichLayout(unittest.TestCase):
    def layout(self, hot, bulk):
        return subprocess.run(['bash', str(SCRIPT), str(hot), str(bulk), str(os.getuid()), str(os.getgid())], capture_output=True)

    def test_writes_and_replacement(self):
        with tempfile.TemporaryDirectory() as tmp:
            hot, bulk = Path(tmp)/'persist/immich', Path(tmp)/'data/immich'
            hot.parent.mkdir(); bulk.parent.mkdir()
            result = self.layout(hot, bulk)
            self.assertEqual(result.returncode, 0, result.stderr)
            for folder in ['thumbs', 'encoded-video', 'profile', 'backups', 'upload', 'library']:
                (hot/folder/'.immich').write_text('integrity marker')
                (hot/folder/'fixture').write_text(folder)
            for folder in ['thumbs', 'encoded-video', 'profile', 'backups']:
                self.assertFalse((hot/folder).is_symlink())
                self.assertFalse((bulk/folder).exists())
            for folder in ['upload', 'library']:
                self.assertEqual((bulk/folder/'fixture').read_text(), folder)
            # Atomic original-file moves remain on the SAME bulk filesystem.
            (hot/'upload/fixture').rename(hot/'library/moved')
            self.assertEqual((bulk/'library/moved').read_text(), 'upload')
            self.assertEqual(self.layout(hot, bulk).returncode, 0)
            self.assertEqual((hot/'thumbs/fixture').read_text(), 'thumbs')
            self.assertEqual((hot/'library/.immich').read_text(), 'integrity marker')

    def test_refuses_existing_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            hot, bulk = Path(tmp)/'persist', Path(tmp)/'data'
            (hot/'upload').mkdir(parents=True)
            (hot/'upload/asset').write_text('preserve')
            self.assertNotEqual(self.layout(hot, bulk).returncode, 0)
            self.assertEqual((hot/'upload/asset').read_text(), 'preserve')
            self.assertFalse(bulk.exists())

    def test_refuses_wrong_link(self):
        with tempfile.TemporaryDirectory() as tmp:
            hot, bulk = Path(tmp)/'persist', Path(tmp)/'data'
            hot.mkdir(); (hot/'library').symlink_to('/wrong-volume/library')
            self.assertNotEqual(self.layout(hot, bulk).returncode, 0)
            self.assertFalse(bulk.exists())

if __name__ == '__main__': unittest.main()
