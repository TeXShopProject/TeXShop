#!/usr/bin/env python3
"""Compare event recording with the previous implementation across installed layouts.
No active input source changes; no windows, app bundle or persistent preferences.
"""
from pathlib import Path
from shortcut_sources import production_source
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-layout-sweep-') as td:
    binary = Path(td) / 'sweep'
    (Path(td)/'TSKeyboardShortcuts.m').write_text(production_source(root))
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-O2', '-Wno-deprecated-declarations', '-I',td,'-I',str(root/'Sources'),'-framework', 'Cocoa', '-framework', 'Carbon', str(root/'Tests/ShortcutLayoutSweep.m'), str(root/'Sources/TSPrefPaneLayout.m'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
