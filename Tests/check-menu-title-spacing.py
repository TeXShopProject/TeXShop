#!/usr/bin/env python3
"""Menu titles have no space at the start or end and no doubled space inside.

Checked are the menus and menu items of the interface files in the product (nib
wrappers, XIBs and the .strings files that translate the XIBs), their compiled nibs,
and the translations of the titles that the code gives to the menu items it makes.
The historical Preferences.nib is not in the product and is not checked.

Pass a mutation name to check that the test notices a stray space it introduces.
"""
from pathlib import Path
import json, plistlib, re, struct, subprocess, sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'
SPACE = ' \t\u00a0\u3000'
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
MUTATIONS = ('designable', 'xib', 'xib-strings', 'code-strings', 'compiled')
assert mutation in ('',) + MUTATIONS, f'unknown mutation {mutation}; use one of {MUTATIONS}'
failures = []

def stray(title):
    return title != title.strip(SPACE) or re.search(f'[{SPACE}]{{2,}}', title) is not None

def normal(title):
    return re.sub(f'[{SPACE}]+', ' ', title).strip()

def strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))

def menu_elements(tree):
    return [e for e in tree.iter() if e.tag in ('menu', 'menuItem') and e.get('title') is not None]

# The historical Preferences.nib must stay out of the product for it to be skipped.
project = (root / 'TeXShop.xcodeproj/project.pbxproj').read_text()
assert 'Preferences.nib in Resources' not in project, 'Preferences.nib is in the product; check it too'

# 1. Menus in the nib wrappers and the XIBs.
wrappers = sorted(p.parent for p in interfaces.glob('*.lproj/*.nib/designable.nib') if p.parent.name != 'Preferences.nib')
xibs = sorted(p for d in ('Resources', 'Sources') for p in (root / d).rglob('*.xib'))
assert len(wrappers) >= 60 and len(xibs) >= 14, (len(wrappers), len(xibs))
titles_checked = 0
for path in [w / 'designable.nib' for w in wrappers] + xibs:
    text = path.read_text(encoding='utf-8')
    if mutation == 'designable' and path.parts[-3:] == ('ja.lproj', 'MainMenu.nib', 'designable.nib'):
        text = text.replace('title="代替エンジンでタイプセット"', 'title=" 代替エンジンでタイプセット"')
    if mutation == 'xib' and path.name == 'SettingsPreview.xib':
        text = text.replace('<menuItem title="Select Text"', '<menuItem title="Select Text "')
    for element in menu_elements(ET.fromstring(text)):
        titles_checked += 1
        if stray(element.get('title')):
            failures.append(f'{path.relative_to(root)}: {element.tag} {element.get("id")}: {element.get("title")!r}')
assert titles_checked > 4000, titles_checked

# 2. Translations of the XIB menus in the .strings file named after each XIB.
translated = 0
for xib in sorted(interfaces.glob('Base.lproj/*.xib')):
    ids = {e.get('id') for e in menu_elements(ET.parse(xib).getroot())}
    for table in sorted(interfaces.glob(f'*.lproj/{xib.stem}.strings')):
        values = strings(table)
        if mutation == 'xib-strings' and table.parts[-2:] == ('fr.lproj', 'SettingsPreview.strings'):
            values['636.title'] = 'Sélectionner le  texte'
        for key, value in values.items():
            if key.endswith('.title') and key[:-len('.title')] in ids:
                translated += 1
                if stray(value):
                    failures.append(f'{table.relative_to(root)}: {key} = {value!r}')
assert translated > 300, translated

# 3. Titles the code gives to the menu items it makes, in every language: titles passed
# where a menu item is made or retitled, the Advanced Find menu commands, the toolbar
# labels (the titles of the toolbar's menu when it shows text only) and the encodings.
made = re.compile(r'(?:(?:initWithTitle|addItemWithTitle|insertItemWithTitle)\s*:'
                  r'|\b\w*(?:[Ii]tem|[Mm]enu)\w*\s*\.\s*title\s*='
                  r'|\[\s*\w*(?:[Ii]tem|[Mm]enu)\w*\s+setTitle\s*:)(?P<rest>[^;]*);', re.S)
localized = re.compile(r'NSLocalizedString(?:FromTable)?\s*\(\s*@"((?:\\.|[^"\\])*)"(?:\s*,\s*@"((?:\\.|[^"\\])*)")?')
keys = set()
for source in sorted((root / 'Sources').rglob('*.m')):
    code = source.read_text(encoding='utf-8', errors='replace')
    for statement in made.finditer(code):
        for match in localized.finditer(statement.group('rest')):
            table = match.group(2) if 'FromTable' in match.group(0) else 'Localizable'
            keys.add((table, match.group(1)))
assert ('Localizable', 'Link Popups') in keys and len(keys) >= 30, len(keys)
english = interfaces / 'en.lproj'
keys |= {('AdvancedFind', k) for k in strings(english / 'AdvancedFind.strings') if k.startswith('AdvancedFind.Menu.') or k == 'MultipleReplace.EditMenu'}
keys |= {('ToolbarItems', k) for k in strings(english / 'ToolbarItems.strings') if k.startswith('tiLabel')}
keys |= {('Encodings', k) for k in strings(english / 'Encodings.strings')}
assert len(keys) > 120, len(keys)
code_titles = 0
for language in sorted(interfaces.glob('*.lproj')):
    for table in sorted({t for t, _ in keys}):
        path = language / f'{table}.strings'
        if not path.exists():
            continue
        values = strings(path)
        if mutation == 'code-strings' and language.name == 'ko.lproj' and table == 'Localizable':
            values['Link Popups'] = ' 링크 팝업'
        for t, key in sorted(keys):
            if t == table and key in values:
                code_titles += 1
                if stray(values[key]):
                    failures.append(f'{path.relative_to(root)}: {key!r} = {values[key]!r}')
assert code_titles > 1000, code_titles

# 4. Compiled nibs carry the titles of their designable.nib, without the stray spaces.
def nib_archive_strings(data):
    """The data values of a NIBArchive that read as UTF-8 text; NSString keeps its text there."""
    assert data.startswith(b'NIBArchive')
    # After the name and two version numbers: counts and offsets of objects, keys, values, class names.
    value_count, value_offset = struct.unpack_from('<2I', data, 34)
    def varint(pos):
        result = shift = 0
        while True:
            byte = data[pos]; pos += 1
            result |= (byte & 0x7f) << shift; shift += 7
            if byte & 0x80:
                return result, pos
    sizes = {0: 1, 1: 2, 2: 4, 3: 8, 4: 0, 5: 0, 6: 4, 7: 8, 9: 0, 10: 4}
    texts, pos = [], value_offset
    for _ in range(value_count):
        _, pos = varint(pos)
        kind = data[pos]; pos += 1
        if kind == 8:
            length, pos = varint(pos)
            try:
                texts.append(data[pos:pos + length].decode('utf-8'))
            except UnicodeDecodeError:
                pass
            pos += length
        else:
            pos += sizes[kind]
    return texts

compiled = 0
for wrapper in wrappers:
    tree = ET.parse(wrapper / 'designable.nib').getroot()
    menu_titles = {normal(e.get('title')) for e in menu_elements(tree)}
    written = {v for e in tree.iter() for v in list(e.attrib.values()) + [e.text or '']}
    for nib in sorted(wrapper.glob('keyedobjects*.nib')):
        data = nib.read_bytes()
        if data.startswith(b'bplist'):
            texts = [o for o in plistlib.loads(data)['$objects'] if isinstance(o, str)]
        else:
            texts = nib_archive_strings(data)
        assert texts, nib
        if mutation == 'compiled' and wrapper.parts[-2:] == ('nl.lproj', 'MainMenu.nib'):
            texts.append(' Wis Aux-bestanden & Zet')
        compiled += 1
        for text in texts:
            if stray(text) and normal(text) in menu_titles and text not in written:
                failures.append(f'{nib.relative_to(root)}: {text!r}')
assert compiled > 100, compiled

if mutation:
    if not failures:
        raise SystemExit(f'FAIL: mutation {mutation} was not detected')
    print('detected mutation', mutation, '-', failures[0])
elif failures:
    raise SystemExit('Menu title with a stray space:\n' + '\n'.join(failures))
else:
    print(f'PASS: {titles_checked} menu titles in {len(wrappers)} nibs and {len(xibs)} XIBs, {translated} XIB menu translations, '
          f'{code_titles} translations of {len(keys)} titles the code gives to menu items, and {compiled} compiled nibs have no stray space')
