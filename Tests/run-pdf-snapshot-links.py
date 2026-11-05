#!/usr/bin/env python3
"""Check relative/absolute links and normal-exit cleanup without app preferences."""
from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-pdf-links-') as td:
    t=Path(td)
    subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-framework','PDFKit','-I'+str(root/'Sources'),str(root/'Tests/PDFSnapshotLinks.m'),str(root/'Sources/TSExternalPDFSnapshot.m'),'-o',str(t/'probe')],check=True)
    subprocess.run([str(t/'probe'),str(t)],check=True)
    if Path((t/'exit-path').read_text()).exists(): raise SystemExit('FAIL: retained document snapshot left behind at normal exit')
    print('PASS: normal-exit cleanup')
