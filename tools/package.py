from pathlib import Path
import hashlib,zipfile
root=Path(__file__).resolve().parents[1]
src=root/'src'; dist=root/'dist';dist.mkdir(exist_ok=True)
# Compare original path parts explicitly: Windows Path ordering case-folds names.
files=sorted((p for p in src.rglob('*') if p.is_file()), key=lambda p: p.relative_to(src).parts)
required=['lsc_super_combine.rb','lsc_super_combine/main.rb','lsc_super_combine/engine.rb','lsc_super_combine/bsp.rb','lsc_super_combine/icons/combine.png','lsc_super_combine/THIRD_PARTY_NOTICES.txt']
assert all((src/f).is_file() for f in required)
path=dist/'super-combine-1.0.0.rbz'
with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in files:
        info=zipfile.ZipInfo(p.relative_to(src).as_posix(),date_time=(2026,10,13,0,0,0))
        info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16
        z.writestr(info,p.read_bytes())
with zipfile.ZipFile(path) as z: assert z.testzip() is None
sha=hashlib.sha256(path.read_bytes()).hexdigest()
(dist/'SHA256SUMS.txt').write_text(f'{sha}  {path.name}\n')
print(f'{path}: {len(files)} files, {path.stat().st_size} bytes, SHA256 {sha}')
