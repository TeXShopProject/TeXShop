#!/usr/bin/env python3
"""Load shared nibs and all localized strings with memory-only defaults; never order windows."""
from pathlib import Path
import json, subprocess, tempfile, os
from pane_fixtures import bundles
import argparse
parser=argparse.ArgumentParser();parser.add_argument("--app",type=Path);args=parser.parse_args()
r = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-settings-panes-') as temp:
    p = Path(temp)
    sources = sorted((r/'Sources').glob('TSPref*Controller.m')) + [r/'Sources/TSPrefPaneLayout.m',r/'Sources/TSDockIconController.m',r/'Sources/TSPreferences+Panes.m',r/'Sources/TSSettingsCategory.m']
    subprocess.run(['xcrun','clang','-fobjc-arc','-Werror','-Wno-deprecated-declarations','-Wno-nullability-completeness','-mmacosx-version-min=14.6','-I',str(r/'Sources'),'-I',str(r/'Tests'),'-framework','Cocoa',str(r/'Tests/SettingsPanes.m'),*map(str,sources),'-o',str(p/'probe')],check=True)
    (p/'fixtures').mkdir()
    for bundle in bundles(r,p/'fixtures',product=args.app,dock=True):
        language=bundle.stem;localization=r/'Resources/Interfaces'/(language+'.lproj')
        resources=bundle/'Contents/Resources'
        # Frozen migration contract; never derive expected actions, tags or translations from the inputs under test.
        expected=json.loads((r/'Tests/Fixtures/SettingsPaneContract.json').read_text())[language]
        for table, values in expected['Tables'].items():
            actual=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(localization/(table+'.strings'))]))
            assert actual == values, f'{language}/{table}: localized contract changed'
        (resources/'expected.json').write_text(json.dumps(expected))
        print('CHECK',language,flush=True)
        command=[str(p/'probe'),str(bundle)]
        if os.environ.get('PANE_DRAWINGS'):
            drawings=Path(os.environ['PANE_DRAWINGS'])/language;drawings.mkdir(parents=True,exist_ok=True);command.append(str(drawings))
        subprocess.run(command,check=True,timeout=90)
