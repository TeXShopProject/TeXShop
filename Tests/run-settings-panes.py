#!/usr/bin/env python3
"""Load shared nibs and all localized strings with memory-only defaults; never order windows."""
from pathlib import Path
import json, plistlib, shutil, subprocess, tempfile, os
import xml.etree.ElementTree as ET
from pane_fixtures import bundles, sources
import argparse
parser=argparse.ArgumentParser();parser.add_argument("--app",type=Path);args=parser.parse_args()
r = Path(__file__).resolve().parents[1]
base = r / 'Resources/Interfaces/Base.lproj'

def expectations(xib, strings):
    root = ET.parse(xib).getroot()
    parents = {c: e for e in root.iter() for c in e}
    ids = {e.get('id'): e for e in root.iter() if e.get('id')}
    result = []
    for key, value in strings.items():
        identifier, prop = key.split('.', 1)
        e = ids[identifier]
        prop = 'toolTip' if prop == 'ibShadowedToolTip' else prop
        kind, view = 'view', e
        details = {}
        if e.tag == 'tabViewItem':
            # The color subtab labels become headings in the common stack.
            continue
        if e.tag == 'window': kind = 'window'
        elif e.tag == 'menuItem':
            kind = 'menuItem'; details['index'] = list(parents[e]).index(e)
            while view.tag != 'popUpButton': view = parents[view]
        elif e.tag == 'menu':
            kind = 'menu'
            while view.tag != 'popUpButton': view = parents[view]
        elif e.tag.endswith('Cell'):
            if e.get('key') == 'prototype': kind, view = 'prototype', parents[e]
            elif parents[e].tag == 'column':
                kind = 'matrix'; column = parents[e]; cells = parents[column]
                details = {'row': list(column).index(e), 'column': list(cells).index(column)}
                view = parents[cells]
            else: kind, view = 'cell', parents[e]
        result.append({'key': key, 'view': 'settings.' + view.get('id'), 'kind': kind, 'property': prop, 'value': value, **details})
    return result

with tempfile.TemporaryDirectory(prefix='texshop-settings-panes-') as temp:
    p = Path(temp); compiled = p / 'Base.lproj'; compiled.mkdir()
    xibs = sorted(base.glob('Settings*.xib'))
    sources = sorted((r/'Sources').glob('TSPref*Controller.m')) + [r/'Sources/TSPrefPaneLayout.m',r/'Sources/TSDockIconController.m',r/'Sources/TSPreferences+Panes.m',r/'Sources/TSSettingsCategory.m']
    subprocess.run(['xcrun','clang','-fobjc-arc','-Werror','-Wno-deprecated-declarations','-Wno-nullability-completeness','-mmacosx-version-min=14.6','-I',str(r/'Sources'),'-I',str(r/'Tests'),'-framework','Cocoa',str(r/'Tests/SettingsPanes.m'),*map(str,sources),'-o',str(p/'probe')],check=True)
    (p/'fixtures').mkdir()
    for bundle in bundles(r,p/'fixtures',product=args.app,dock=True):
        language=bundle.stem;localization=r/'Resources/Interfaces'/(language+'.lproj')
        resources=bundle/'Contents/Resources'
        expected={"Bridge":[]}
        original=ET.parse(base/'Preferences.nib/designable.nib').getroot()
        oldOutlets={e.get('destination'):e.get('property') for e in original.find('./objects/customObject').findall('./connections/outlet')}

        for xib in xibs:
            strings_file=localization/(xib.stem+'.strings')
            strings=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(strings_file)]))
            name=xib.stem.removeprefix('Settings')
            expected[name]=expectations(xib,strings)
            document=ET.parse(xib).getroot();parents={c:e for e in document.iter() for c in e}
            for outlet in document.find('./objects/customObject').findall('./connections/outlet'):
                if outlet.get('property')=='view':continue
                expected['Bridge'].append({'ivar':oldOutlets[outlet.get('destination')],'property':outlet.get('property'),'class':'TSPref'+name+'Controller'})

            actions=[];tags=[]
            for connection in document.iter('action'):
                if connection.get('target')!='-2':continue
                control=parents[parents[connection]]
                entries=expectations(xib,{control.get('id')+'.action':connection.get('selector')})
                actions.extend(entries)
            for cell in document.iter('buttonCell'):
                if parents[cell].tag!='column':continue
                entries=expectations(xib,{cell.get('id')+'.tag':int(cell.get('tag','0'))});tags.extend(entries)
            for control in document.iter():
                if control.tag not in ['button','popUpButton','textField','colorWell','menuItem']:continue
                if control.get('tag') is not None:tags.extend(expectations(xib,{control.get('id')+'.tag':int(control.get('tag'))}))
            expected[name+'Actions']=actions;expected[name+'Tags']=tags
        (resources/'expected.json').write_text(json.dumps(expected))
        print('CHECK',language,flush=True)
        args=[str(p/'probe'),str(bundle)]
        if os.environ.get('PANE_DRAWINGS'):
            drawings=Path(os.environ['PANE_DRAWINGS'])/language;drawings.mkdir(parents=True,exist_ok=True);args.append(str(drawings))
        subprocess.run(args,check=True,timeout=90)
