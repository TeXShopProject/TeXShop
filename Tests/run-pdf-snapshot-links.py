#!/usr/bin/env python3
"""Check relative/absolute links and normal-exit cleanup without app preferences."""
from pathlib import Path
import subprocess,tempfile
from source_tree import include_args
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-pdf-links-') as td:
    t=Path(td)
    subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',*include_args(root),str(root/'Tests/PDFSnapshotLinks.m'),str(root/'Sources/Preview/TSExternalPDFSnapshot.m'),'-o',str(t/'probe')],check=True)
    subprocess.run([str(t/'probe'),str(t)],check=True)
    if Path((t/'exit-path').read_text()).exists(): raise SystemExit('FAIL: retained document snapshot left behind at normal exit')
    print('PASS: normal-exit cleanup')
