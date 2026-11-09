#!/usr/bin/env python3
"""Inspect current documentation and reject known obsolete routes, including arrows."""
from pathlib import Path
import runpy
root=Path(__file__).resolve().parents[1]
checks=runpy.run_path(str(root/'Tests/check-settings-guidance.py'))
check=checks['check_obsolete']
for old in ['Settings → Source','Settings > Misc 1','Preferences → Misc 2','Settings > Engine']:
    try:check('The setting is under '+old+'.','en',root/'Resources/Interfaces/en.lproj/TeXShopHelp/pgs/whatisnew.htm')
    except AssertionError:print('DETECTED obsolete route:',old)
    else:raise AssertionError('Obsolete route survived: '+old)
for language,text in [('en','Settings → Editor'),('ja','設定 → エディタ'),('ko','설정 → 도구'),('de','Einstellungen → Editor'),('es','Ajustes → Editor')]:check(text,language,'normal control')
print('NORMAL CONTROL current routes')
