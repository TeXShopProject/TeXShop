#!/usr/bin/env python3
"""Terada: compare every compiled popup with its runtime localization."""
from pathlib import Path
import os,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-tags-') as tmp:
    exe=Path(tmp)/'tags'
    subprocess.run(['xcrun','clang','-w','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',str(root/'Tests/DocumentTagsNib.m'),'-o',str(exe)],check=True)
    count=0
    for p in sorted((root/'Resources/Interfaces').glob('*.lproj/TSDocument.nib')):
        strings=p.parent/'Localizable.strings'
        if not strings.exists():strings=root/'Resources/Interfaces/en.lproj/Localizable.strings'
        expected=subprocess.check_output(['plutil','-extract','Tags','raw',str(strings)],text=True).strip()
        for nib in p.glob('keyedobjects*.nib'):
            result=subprocess.run([str(exe),str(nib)],env=dict(os.environ,TS_EXPECT_TAGS=expected),capture_output=True,text=True)
            assert result.returncode==0,(str(nib),expected,result.stdout,result.stderr)
        print('PASS',p.parent.name,expected)
        count+=1
    assert count==12,count
