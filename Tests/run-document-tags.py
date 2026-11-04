#!/usr/bin/env python3
"""Terada: compare every compiled popup with its runtime localization."""
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-tags-') as tmp:
    exe=Path(tmp)/'tags'
    subprocess.run(['xcrun','clang','-w','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',str(root/'Tests/DocumentTagsNib.m'),'-o',str(exe)],check=True)
    menu_exe=Path(tmp)/'menu'
    subprocess.run(['xcrun','clang','-w','-fobjc-arc','-framework','Cocoa',str(root/'Tests/MainMenuTagsNib.m'),'-o',str(menu_exe)],check=True)
    count=0; menu_count=0
    for p in sorted((root/'Resources/Interfaces').glob('*.lproj/TSDocument.nib')):
        strings=p.parent/'Localizable.strings'
        if not strings.exists():strings=root/'Resources/Interfaces/en.lproj/Localizable.strings'
        expected=subprocess.check_output(['plutil','-extract','Tags','raw',str(strings)],text=True).strip()
        nibs=list(p.glob('keyedobjects*.nib'))
        if not nibs: raise SystemExit(f'Missing compiled document nib: {p}')
        for nib in nibs:
            result=subprocess.run([str(exe),str(nib)],env=dict(os.environ,TS_EXPECT_TAGS=expected),capture_output=True,text=True)
            if result.returncode: raise SystemExit((str(nib),expected,result.stdout,result.stderr))
        menus=list((p.parent/'MainMenu.nib').glob('keyedobjects*.nib'))
        if not menus: raise SystemExit(f'Missing compiled menu nib: {p.parent}')
        for nib in menus:
            result=subprocess.run([str(menu_exe),str(nib),expected],capture_output=True,text=True)
            if result.returncode: raise SystemExit((str(nib),expected,result.stdout,result.stderr))
            menu_count+=1
        print('PASS',p.parent.name,expected)
        count+=1
    if count!=12 or menu_count!=36: raise SystemExit(f'Incomplete coverage: {count} locales, {menu_count} menus')
    print('PASS: 12 document locales and 36 compiled MainMenu variants')
