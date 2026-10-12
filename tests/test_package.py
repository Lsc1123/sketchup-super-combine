"""Exercise the real packager in an isolated source copy on both runner platforms."""
import hashlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / 'src', self.root / 'src')
        (self.root / 'tools').mkdir()
        shutil.copy(ROOT / 'tools/package.py', self.root / 'tools/package.py')

    def build(self):
        return subprocess.run([sys.executable, str(self.root / 'tools/package.py')],
                              capture_output=True, text=True, encoding='utf-8')

    def test_archive_layout_integrity_and_checksum(self):
        result = self.build()
        self.assertEqual(0, result.returncode, result.stderr)
        archive = self.root / 'dist/super-combine-1.0.0.rbz'
        with zipfile.ZipFile(archive) as z:
            self.assertIsNone(z.testzip())
            expected = sorted(p.relative_to(self.root / 'src').as_posix()
                              for p in (self.root / 'src').rglob('*') if p.is_file())
            self.assertEqual(expected, sorted(z.namelist()))
            self.assertEqual(6, len(expected))
            for name in z.namelist():
                self.assertEqual(3, z.getinfo(name).create_system)
                self.assertFalse(name.startswith('/'))
                self.assertNotIn('..', name.split('/'))
                self.assertNotIn('\\', name)
                self.assertEqual((self.root / 'src' / name).read_bytes(), z.read(name))
            self.assertIn(b'Permission is hereby granted', z.read('lsc_super_combine/THIRD_PARTY_NOTICES.txt'))
            self.assertTrue(z.read('lsc_super_combine/icons/combine.png').startswith(b'\x89PNG\r\n\x1a\n'))
        expected_checksum = f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}'
        self.assertEqual(expected_checksum, (self.root / 'dist/SHA256SUMS.txt').read_text().strip())

    def test_package_is_reproducible(self):
        self.assertEqual(0, self.build().returncode)
        archive = self.root / 'dist/super-combine-1.0.0.rbz'
        first = archive.read_bytes()
        self.assertEqual(0, self.build().returncode)
        self.assertEqual(first, archive.read_bytes())

    def test_missing_runtime_file_is_rejected(self):
        (self.root / 'src/lsc_super_combine/bsp.rb').unlink()
        self.assertNotEqual(0, self.build().returncode)
        self.assertFalse((self.root / 'dist/super-combine-1.0.0.rbz').exists())

if __name__ == '__main__':
    unittest.main()
