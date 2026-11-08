#!/usr/bin/env python3
"""Exercise production shortcut settings with memory defaults and unordered windows."""
from pathlib import Path
from shortcut_sources import production_source
import subprocess,tempfile,json
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-shortcut-pane-') as td:
 p=Path(td)
 (p/'TSKeyboardShortcuts.m').write_text(production_source(r))
 translations={f.parent.name:json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(f)])) for f in (r/'Resources/Interfaces').glob('*.lproj/Localizable.strings')}
 (p/'translations.json').write_text(json.dumps(translations))
 subprocess.run(['xcrun','ibtool','--compile',str(p/'SettingsWindow.nib'),str(r/'Resources/SettingsWindow.xib')],check=True)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wno-deprecated-declarations','-Wno-nullability-completeness','-mmacosx-version-min=14.6','-I',str(p),'-I',str(r/'Tests'),'-I',str(r/'Sources'),'-framework','Cocoa','-framework','Carbon',str(r/'Tests/ShortcutPane.m'),*[str(f) for f in sorted((r/'Sources').glob('TSSettings*.m'))],str(r/'Sources/TSPreferenceProfile.m'),str(r/'Sources/TSMacroTreeNode.m'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test'),str(p/'SettingsWindow.nib'),str(p/'translations.json')],check=True,timeout=60)
