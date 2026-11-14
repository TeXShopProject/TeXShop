#!/usr/bin/env python3
"""Verify immediate actions in shared panes and, optionally, the built product."""
from pathlib import Path
import subprocess, sys, xml.etree.ElementTree as ET
r=Path(__file__).resolve().parents[1]
xibs=sorted([x for x in (r/'Resources/Interfaces/Base.lproj').glob('Settings*.xib') if x.name != 'SettingsWindow.xib'])
assert len(xibs)==10
all_actions={a.get('selector') for p in xibs for a in ET.parse(p).iter('action')}
assert not all_actions.intersection({'okButtonPressed:','cancelButtonPressed:','SaveEditedStyle:'})
assert 'themeSelectionChanged:' in all_actions
shell=ET.parse(r/'Resources/Interfaces/Base.lproj/SettingsWindow.xib')
mask=next(shell.iter('windowStyleMask'))
assert mask.get('closable')=='YES' and mask.get('resizable')=='YES'
args=[sys.executable,str(r/'Tests/run-settings-panes.py')]
if len(sys.argv)>1:
 product=Path(sys.argv[1]);assert not list((product/'Contents/Resources').glob('*.lproj/Preferences.nib'))
 args += ['--app',str(product)]
subprocess.run(args,check=True)
print('PASS: shared panes, immediate theme actions, no global OK/Cancel, resizable shell')
