"""Exercise the real packager in an isolated source copy on both runner platforms."""
import hashlib
import json
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
        shutil.copy(ROOT / 'tools/package_manifest.json', self.root / 'tools/package_manifest.json')
        shutil.copy(ROOT / 'LICENSE', self.root / 'LICENSE')

    def archive(self):
        return next((self.root / 'dist').glob('*.rbz'))

    def build(self):
        return subprocess.run([sys.executable, str(self.root / 'tools/package.py')],
                              capture_output=True, text=True, encoding='utf-8')

    def test_archive_layout_integrity_and_checksum(self):
        result = self.build()
        self.assertEqual(0, result.returncode, result.stderr)
        archive = self.archive()
        with zipfile.ZipFile(archive) as z:
            self.assertIsNone(z.testzip())
            manifest = json.loads((self.root / 'tools/package_manifest.json').read_text())
            license_name = manifest['project_license_in_archive']
            expected = sorted(manifest['runtime_files'] + [license_name])
            self.assertEqual(expected, sorted(z.namelist()))
            for name in z.namelist():
                self.assertEqual(3, z.getinfo(name).create_system)
                self.assertFalse(name.startswith('/'))
                self.assertNotIn('..', name.split('/'))
                self.assertNotIn('\\', name)
                source = self.root / 'LICENSE' if name == license_name else self.root / 'src' / name
                self.assertEqual(source.read_bytes(), z.read(name))
            self.assertIn(b'Copyright (c) 2026 LSC', z.read(license_name))
            self.assertIn(b'Permission is hereby granted', z.read('lsc_super_combine/THIRD_PARTY_NOTICES.txt'))
            self.assertTrue(z.read('lsc_super_combine/icons/combine.png').startswith(b'\x89PNG\r\n\x1a\n'))
        expected_checksum = f'{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}'
        self.assertEqual(expected_checksum, (self.root / 'dist/SHA256SUMS.txt').read_text().strip())
        self.assertEqual((expected_checksum+'\n').encode('ascii'),
                         (self.root / 'dist/SHA256SUMS.txt').read_bytes())

    def test_package_is_reproducible(self):
        self.assertEqual(0, self.build().returncode)
        archive = self.archive()
        first = archive.read_bytes()
        self.assertEqual(0, self.build().returncode)
        self.assertEqual(first, archive.read_bytes())

    def test_missing_runtime_file_is_rejected(self):
        (self.root / 'src/lsc_super_combine/bsp.rb').unlink()
        self.assertNotEqual(0, self.build().returncode)
        self.assertFalse(list((self.root / 'dist').glob('*.rbz')))

    def test_extra_metadata_is_excluded(self):
        (self.root / 'src/lsc_super_combine/.DS_Store').write_bytes(b'not-runtime')
        self.assertEqual(0, self.build().returncode)
        with zipfile.ZipFile(self.archive()) as archive:
            self.assertNotIn('lsc_super_combine/.DS_Store', archive.namelist())

    def test_version_controls_archive_name(self):
        source = self.root / 'src/lsc_super_combine/version.rb'
        source.write_text("module LSC; module SuperCombine; VERSION = '9.8.7'; end; end\n")
        self.assertEqual(0, self.build().returncode)
        self.assertEqual('super-combine-9.8.7.rbz', self.archive().name)

    def test_missing_project_license_is_rejected(self):
        (self.root / 'LICENSE').unlink()
        self.assertNotEqual(0, self.build().returncode)

if __name__ == '__main__':
    unittest.main()
