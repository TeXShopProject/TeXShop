#!/usr/bin/env python3
# Terada: Update XML and compiled nibs together, removing obsolete OS-specific variants.
from pathlib import Path
import sys, tempfile, subprocess, shutil
if '--check-settings' in sys.argv[1:]:
    with tempfile.TemporaryDirectory(prefix='texshop-compile-settings-') as td:
        for xib in sorted(Path('Resources/Interfaces/Base.lproj').glob('Settings*.xib')):
            subprocess.run(['xcrun','ibtool','--compile',str(Path(td)/(xib.stem+'.nib')),str(xib)],check=True)
            print(xib.name, 'compiled in temporary directory')
    if '--app' in sys.argv:
        app=Path(sys.argv[sys.argv.index('--app')+1]).resolve()
        assert (app/'Contents/Resources/SettingsWindow.nib').exists(), app
        subprocess.run([sys.executable,str(Path(__file__).with_name('run-settings-panes.py')),'--app',str(app)],check=True)
    raise SystemExit(0)
if 'Preferences' in sys.argv[1:]:
    raise SystemExit('Preferences.nib is historical. Use --check-settings for shared XIBs; Xcode builds product nibs.')
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
