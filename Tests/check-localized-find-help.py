#!/usr/bin/env python3
"""The Japanese, German, Spanish and Korean help describe the Advanced Find panel.

Their Editing Tricks page names the panel, the Settings row that chooses it and its
commands with the words of the interface in that language, and no longer presents the
OgreKit Find Panel as the new panel that needs Panther. The TeX Command Line Settings
page no longer introduces the find panel of TeXShop 1.35.
"""
from pathlib import Path
import html
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
INTERFACES = ROOT / 'Resources/Interfaces'
LANGUAGES = ('ja', 'de', 'es', 'ko')

# Each entry is a strings table and a key whose value the page must contain.
TERMS = (
    ('SettingsSource', 'adv-Fd-Pnl.title'),          # Advanced Find Panel
    ('SettingsCategories', 'editor'),                 # Editor
    ('SettingsCategories', 'catalog.editor.7.0.title'),  # the row that chooses the find method
    ('AdvancedFind', 'AdvancedFind.FindAll'),
    ('AdvancedFind', 'AdvancedFind.HighlightAll'),
    ('AdvancedFind', 'AdvancedFind.SelectAll'),
    ('AdvancedFind', 'AdvancedFind.Unhighlight'),
    ('AdvancedFind', 'AdvancedFind.ReplaceAll'),
    ('AdvancedFind', 'AdvancedFind.RegularExpression'),
    ('AdvancedFind', 'AdvancedFind.Cancel'),
    ('AdvancedFind', 'MultipleReplace.EditMenu'),
    ('AdvancedFind', 'MultipleReplace.Title'),
)
# Words of the old pages: OgreKit as the new panel for Panther, and its web site.
OLD_EDITING = re.compile(r'Panther|10\.3|sonobe/OgreKit|園部さんのOgreKit|新しい検索パネル|neuen Suchdialog|nuevo panel de B|new Find panel')
OLD_DEFAULTS = re.compile(r'1\.35.{0,40}?(?:検索パネル|Suchdialog|panel de B|Find panel)', re.I)


def strings(language, table):
    path = INTERFACES / f'{language}.lproj/{table}.strings'
    if not path.exists():
        path = INTERFACES / f'Base.lproj/{table}.strings'
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


def page(language, name):
    raw = (INTERFACES / f'{language}.lproj/TeXShopHelp/pgs/{name}').read_bytes()
    match = re.search(br'charset=([^"\s>]+)', raw, re.I)
    encoding = match[1].decode().lower() if match else 'latin-1'
    encoding = {'shift_jis': 'cp932', 'x-sjis': 'cp932', 'iso-8859-1': 'latin-1'}.get(encoding, encoding)
    text = raw.decode(encoding)
    assert text.encode(encoding) == raw, name
    text = html.unescape(re.sub(r'<!--.*?-->', ' ', text, flags=re.S))
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', text))


failures = []
for language in LANGUAGES:
    tricks = page(language, 'basic_edittricks.htm')
    folded = tricks.casefold()
    for table, key in TERMS:
        value = strings(language, table)[key]
        if value.casefold() not in folded:
            failures.append(f'{language} basic_edittricks.htm lacks {table} {key} “{value}”')
    old = OLD_EDITING.search(tricks)
    if old:
        failures.append(f'{language} basic_edittricks.htm still has “{old[0]}”')
    if (INTERFACES / f'{language}.lproj/TeXShopHelp/pgs/configure_defaults.htm').exists():
        defaults = page(language, 'configure_defaults.htm')
        if OLD_DEFAULTS.search(defaults):
            failures.append(f'{language} configure_defaults.htm still introduces the find panel of TeXShop 1.35')

if failures:
    print('\n'.join(f'FAIL: {f}' for f in failures))
    sys.exit(1)
print(f'PASS: the Editing Tricks help in {len(LANGUAGES)} languages describes the Advanced Find panel '
      f'with the {len(TERMS)} interface terms of each language, and no page presents OgreKit as the new panel')
