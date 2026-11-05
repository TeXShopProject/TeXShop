#!/usr/bin/env python3
"""Compare identical 300 MB PDFs in separate processes, without TeXShop settings."""
import subprocess,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-pdf-memory-') as td:
    t=Path(td);exe=t/'probe';pdf=t/'large.pdf'
    subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',
        '-I'+str(root/'Sources'),str(root/'Tests/PDFSnapshot.m'),str(root/'Sources/TSExternalPDFSnapshot.m'),'-o',str(exe)],check=True)
    subprocess.run([str(exe),str(pdf),'generate'],check=True)
    print(f'PDF bytes: {pdf.stat().st_size}',flush=True)
    for mode in ['url','data','snapshot']: subprocess.run([str(exe),str(pdf),mode],check=True)
