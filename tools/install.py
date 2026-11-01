"""Install the built, verified RBZ into SketchUp 2026 for the current Mac user."""
from pathlib import Path
from package import version
import zipfile
root=Path(__file__).resolve().parents[1]
dest=Path.home()/'Library/Application Support/SketchUp 2026/SketchUp/Plugins'
archive=root/'dist'/f'super-combine-{version(root)}.rbz'
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name in z.namelist():
        assert '..' not in Path(name).parts and Path(name).parts[0] in ('lsc_super_combine.rb','lsc_super_combine')
    z.extractall(dest)
    assert all((dest/name).read_bytes()==z.read(name) for name in z.namelist())
print('Installed and verified:', dest/'lsc_super_combine.rb')
