#!/usr/bin/env python3
# Terada: XMLとコンパイル済みnibを同時に更新し、古いOS別の派生物を残さない。
from pathlib import Path
import sys, tempfile, subprocess, shutil
with tempfile.TemporaryDirectory() as td:
    for name in sys.argv[1:]:
        for path in sorted(Path('Resources/Interfaces').glob(f'*/{name}.nib/designable.nib')):
            xib=Path(td)/'input.xib'; out=Path(td)/'output.nib'
            shutil.copy2(path,xib)
            subprocess.run(['xcrun','ibtool','--compile',str(out),str(xib)],check=True,stdout=subprocess.DEVNULL)
            for old in path.parent.glob('keyedobjects*.nib'): old.unlink()
            if out.is_dir():
                for f in out.glob('keyedobjects*.nib'): shutil.copy2(f,path.parent/f.name)
                shutil.rmtree(out)
            else:
                shutil.copy2(out,path.parent/'keyedobjects.nib');out.unlink()
            print(path.parent.parent.name,name,flush=True)
