#!/usr/bin/env python3
"""Every localized Preferences window is connected like the English one.

For each outlet of File's Owner in Base.lproj that refers to a control, every
localization must have the outlet too, pointing at a control of the same kind in
a window of the nib (not a detached view) that sends the same actions. Every
action sent to File's Owner must be a TSPreferences method, and labels send none."""
from pathlib import Path
import re, sys, xml.etree.ElementTree as ET
root = Path(__file__).resolve().parents[1]
CONTROLS = {'button', 'popUpButton', 'textField', 'colorWell', 'matrix', 'buttonCell', 'slider', 'stepper',
            'segmentedControl', 'comboBox'}

def declared_methods():
    names = {"closeSamplePanel:"}  # Unused historical panel; absent from product panes.
    # The settings profile menu of the earlier window. The product builds no Preferences.nib
    # (run-live-settings-nibs.py); engine profiles are applied in Settings > Typesetting.
    names.add("setDefaults:")
    # The engine field of the earlier window. Settings chooses the engine file from a menu.
    names.add("setEngine:")
    for path in [root / 'Sources/Settings/TSPreferences.h', *sorted(root.glob('Sources/TSPreferences*.m'))]:
        text = re.sub(r'/\*.*?\*/', '', path.read_text(errors='replace'), flags=re.S)
        text = re.sub(r'//.*', '', text)
        names |= {m + ':' for m in re.findall(r'^\s*-\s*\([^)]*\)\s*(\w+)\s*:', text, re.M)}
    return names

def wiring(path):
    r = ET.parse(path).getroot()
    parent = {c: p for p in r.iter() for c in p}
    byid = {e.get('id'): e for e in r.iter() if e.get('id')}
    inside = {id(e) for o in r.find('objects') if o.tag == 'window' for e in o.iter()}
    owner = next(e for e in r.iter('customObject') if e.get('id') == '-2')
    outlets = {}
    for o in owner.find('connections'):
        if o.tag != 'outlet':
            continue
        d = byid.get(o.get('destination'))
        if d is None or d.tag not in CONTROLS:
            continue
        acts = {a.get('selector') for a in d.iter('action') if a.get('target') == '-2'}
        if not acts and d.tag == 'buttonCell':        # a cell may use its matrix's action
            m = d
            while m is not None and m.tag != 'matrix':
                m = parent.get(m)
            if m is not None and m.find('connections') is not None:
                acts = {a.get('selector') for a in m.find('connections') if a.tag == 'action' and a.get('target') == '-2'}
        outlets[o.get('property')] = (d.tag, tuple(sorted(acts)), id(d) in inside)
    actions = {a.get('selector') for a in r.iter('action') if a.get('target') == '-2'}
    labels = []
    for a in r.iter('action'):
        e = parent[parent[a]]
        field = e if e.tag == 'textField' else parent.get(e) if e.tag == 'textFieldCell' else None
        if field is not None and field.tag == 'textField':
            cell = field.find('textFieldCell')
            if cell is not None and cell.get('editable') != 'YES':
                labels.append(f"{a.get('selector')} on label {field.get('id')}")
    return outlets, actions, labels

nibs = sorted((root / 'Resources/Interfaces').glob('*.lproj/Preferences.nib/designable.nib'))
base_path = root / 'Resources/Interfaces/Base.lproj/Preferences.nib/designable.nib'
base, _, _ = wiring(base_path)
declared = declared_methods()
problems = []
for path in nibs:
    lang = path.parent.parent.name
    outlets, actions, labels = wiring(path)
    problems += [f'{lang}: {x}' for x in labels]
    # Removed because they had no effect: scrollPressed: ("Do not scroll" with page buttons, since PDFKit),
    # distillerChanged: (Apple Distiller, whose pstopdf macOS 14 removed) and antialiasChanged: (always on).
    problems += [f'{lang}: action {s} is not a TSPreferences method' for s in sorted(actions - declared - {'scrollPressed:', 'distillerChanged:', 'antialiasChanged:'})]
    for prop, want in sorted(base.items()):
        have = outlets.get(prop)
        if have is None:
            problems.append(f'{lang}: no outlet {prop}')
        elif not have[2]:
            problems.append(f'{lang}: outlet {prop} is outside the windows')
        elif have[:2] != want[:2]:
            problems.append(f'{lang}: {prop} is {have[0]} sending {list(have[1])}, Base {want[0]} sending {list(want[1])}')
for p in problems:
    print(p)
if problems:
    raise SystemExit(f'FAIL: {len(problems)} wiring problems')
print(f'PASS: {len(nibs)} localized Preferences windows connect {len(base)} outlets as Base does')

# Shared panes retain every used Base outlet, action and tag. The runtime probe
# also verifies the typed objects and forwarding through each pane controller.
base=ET.parse(root/'Resources/Interfaces/Base.lproj/Preferences.nib/designable.nib')
old={o.get('property'):o.get('destination') for o in base.findall(".//customObject[@id='-2']/connections/outlet")}
# Outlets added after the migration have no legacy counterpart.
added={'EditorHighlightZenkakuSymbolColorWell','EditorHighlightZenkakuSymbolBackgroundColorWell','linkPopupsButton','scrollPageTurnButton'}
new={}
for p in [x for x in (root/'Resources/Interfaces/Base.lproj').glob('Settings*.xib') if x.name != 'SettingsWindow.xib']:
 tree=ET.parse(p)
 for outlet in tree.findall(".//customObject[@id='-2']/connections/outlet"):
  name=outlet.get('property')
  if name=='view' or name in added:continue
  original=name if name in old else '_'+name
  assert original in old and old[original]==outlet.get('destination'),(p,name)
  assert original not in new,(p,name)
  new[original]=p.name
missing=set(old)-set(new)
# _scrollButton ("Do not scroll" with page buttons), _distillerMatrix and _antialiasButton were removed.
# _engineTextField gave way to the Engine File menu built in code.
assert missing <= {'_prefsWindow','_tabView','_samplePanel','_fontTextView','_scrollButton','_distillerMatrix','_antialiasButton','_engineTextField'},missing
assert len(new)==169
print('PASS: 170 used outlets each migrate exactly once into shared panes')
