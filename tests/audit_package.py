"""Probe the real packager in a disposable copy; never add junk to real src/."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        shutil.copytree(ROOT / 'src', root / 'src')
        (root / 'tools').mkdir()
        shutil.copy(ROOT / 'tools/package.py', root / 'tools/package.py')
        shutil.copy(ROOT / 'tools/package_manifest.json', root / 'tools/package_manifest.json')
        shutil.copy(ROOT / 'LICENSE', root / 'LICENSE')
        (root / 'src/lsc_super_combine/.DS_Store').write_bytes(b'audit-only-placeholder')
        run = subprocess.run([sys.executable, str(root / 'tools/package.py')],
                             capture_output=True, text=True, timeout=30)
        if run.returncode:
            raise RuntimeError(run.stderr)
        with zipfile.ZipFile(next((root / 'dist').glob('*.rbz'))) as archive:
            names = archive.namelist()
        unexpected = [name for name in names if name.endswith('/.DS_Store')]
        report = {'scope': 'Local packager in a disposable copy',
                  'expected': 'Exclude non-runtime Finder metadata',
                  'actual_packaged_extra_files': unexpected, 'pass': not unexpected}
    output = ROOT / 'test-results/audit-package.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report, indent=2))
    return 0 if report['pass'] else 1


if __name__ == '__main__':
    sys.exit(main())
