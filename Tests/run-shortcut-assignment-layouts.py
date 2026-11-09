#!/usr/bin/env python3
"""Check fixed menu and macro assignments against inverse layout events, never AppKit dispatch."""
from pathlib import Path
import subprocess,tempfile
from shortcut_sources import production_source
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-assignment-layouts-') as folder:
 temp=Path(folder);(temp/'TSKeyboardShortcuts.m').write_text(production_source(root))
 subprocess.run(['xcrun','clang','-fobjc-arc','-O2','-Wno-deprecated-declarations','-I',folder,'-I',str(root/'Sources'),'-framework','Cocoa','-framework','Carbon',str(root/'Tests/ShortcutAssignmentLayouts.m'),str(root/'Sources/TSPrefPaneLayout.m'),'-o',str(temp/'probe')],check=True)
 subprocess.run([str(temp/'probe')],check=True)
