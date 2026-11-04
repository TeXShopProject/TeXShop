#!/usr/bin/env python3
"""Terada: verify all compiled menu variants using the responder chain."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-console-') as tmp:
    exe=Path(tmp)/'console'
    subprocess.run(['xcrun','clang','-w','-fobjc-arc','-framework','Cocoa',str(root/'Tests/ConsoleMenuNib.m'),'-o',str(exe)],check=True)
    paths=sorted((root/'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
    assert len(paths)>=12
    for path in paths:
        r=subprocess.run([str(exe),str(path)],capture_output=True,text=True)
        assert r.returncode==0,(str(path),r.returncode,r.stdout,r.stderr)
    print('PASS:',len(paths),'compiled menu variants, nil target / application responder chain')
