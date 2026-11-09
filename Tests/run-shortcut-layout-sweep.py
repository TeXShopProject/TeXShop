#!/usr/bin/env python3
"""Compare event recording with the previous implementation across installed layouts.
No active input source changes; no windows, app bundle or persistent preferences.
"""
from pathlib import Path
from shortcut_sources import production_source, companion_sources
import subprocess, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-layout-sweep-') as td:
    binary = Path(td) / 'sweep'
    (Path(td)/'TSKeyboardShortcuts.m').write_text(production_source(root))
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-O2', '-Wno-deprecated-declarations', '-I',td,*include_args(root),'-framework', 'Cocoa', '-framework', 'Carbon', str(root/'Tests/ShortcutLayoutSweep.m'), *companion_sources(root), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
