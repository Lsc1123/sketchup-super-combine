"""Build a reproducible RBZ from the explicit runtime manifest."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def version(root=ROOT):
    source = (root / 'src/lsc_super_combine/version.rb').read_text(encoding='utf-8')
    match = re.search(r"VERSION\s*=\s*'([0-9]+\.[0-9]+\.[0-9]+)'", source)
    if not match:
        raise ValueError('Missing semantic version in version.rb')
    return match.group(1)


def archive_files(root=ROOT):
    manifest = json.loads((root / 'tools/package_manifest.json').read_text(encoding='utf-8'))
    entries = [(name, root / 'src' / name) for name in manifest['runtime_files']]
    entries.append((manifest['project_license_in_archive'], root / 'LICENSE'))
    seen = set()
    for name, path in entries:
        parts = PurePosixPath(name).parts
        if not parts or name.startswith('/') or '..' in parts or '\\' in name or name in seen:
            raise ValueError(f'Invalid or duplicate archive path: {name}')
        if not path.is_file():
            raise FileNotFoundError(f'Missing required package file: {path.relative_to(root)}')
        seen.add(name)
    return sorted(entries, key=lambda item: PurePosixPath(item[0]).parts)


def build(root=ROOT):
    files = archive_files(root)
    release_version = version(root)
    dist = root / 'dist'
    dist.mkdir(exist_ok=True)
    path = dist / f'super-combine-{release_version}.rbz'
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, source in files:
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 13, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, source.read_bytes())
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('Corrupt RBZ archive')
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    (dist / 'SHA256SUMS.txt').write_text(f'{sha}  {path.name}\n', encoding='utf-8')
    print(f'{path}: {len(files)} files, {path.stat().st_size} bytes, SHA256 {sha}')
    return path


if __name__ == '__main__':
    build()
