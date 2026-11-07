#!/usr/bin/env python3
"""Compare event recording with the previous implementation across installed layouts.
No active input source changes; no windows, app bundle or persistent preferences.
"""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-layout-sweep-') as td:
    binary = Path(td) / 'sweep'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-O2', '-Wno-deprecated-declarations', '-framework', 'Cocoa', '-framework', 'Carbon', str(root/'Tests/ShortcutLayoutSweep.m'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
