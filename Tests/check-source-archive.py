#!/usr/bin/env python3
"""Verify real Git ZIP extraction, including modes and symbolic links."""
from pathlib import Path
import os, subprocess, tempfile
def require(condition, detail):
    if not condition: raise SystemExit('FAIL: '+str(detail))
root=Path(__file__).resolve().parents[1]
entries=subprocess.check_output(['git','ls-tree','-rz','HEAD'],cwd=root).split(b'\0')
with tempfile.TemporaryDirectory(prefix='texshop-zip-check-') as tmp:
    out=Path(tmp);archive=out/'source.zip';tree=out/'tree';tree.mkdir()
    subprocess.run(['git','archive','--format=zip','-o',str(archive),'HEAD'],cwd=root,check=True)
    subprocess.run(['/usr/bin/unzip','-q',str(archive),'-d',str(tree)],check=True,preexec_fn=lambda:os.umask(0o022))
    count=0
    for entry in filter(None,entries):
        metadata,path=entry.split(b'\t',1);mode,kind,blob=metadata.split()
        name=path.decode('ascii');file=tree/name
        expected=subprocess.check_output(['git','cat-file','blob',blob.decode()],cwd=root)
        if mode==b'120000': require(file.is_symlink() and os.fsencode(os.readlink(file))==expected,name)
        else:
            require(file.read_bytes()==expected,name)
            require((file.stat().st_mode & 0o777)==(0o755 if mode==b'100755' else 0o644),name)
        count+=1
    print(f'PASS: {count} Git entries, bytes, modes and symlinks extracted correctly')
