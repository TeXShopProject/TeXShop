#!/usr/bin/env python3
"""Every help book (en, ja, de, es, ko, fr, it, nl, pt, pt-PT, ro, zh_CN) describes the Advanced Find panel.

Their Find and Replace page (basic_find.htm) names the panel, the Settings row that
chooses it and its commands with the words of the interface in that language, and has
the anchor of Multiple Replace. Neither that page nor the Editing Tricks page presents
the OgreKit Find Panel as the new panel that needs Panther. The TeX Command Line Settings
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
LANGUAGES = ('en', 'ja', 'de', 'es', 'ko', 'fr', 'it', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN')
FIND_PAGE = 'basic_find.htm'

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
# The mark that the settings put after the name of the panel: (recommended), （推奨）, (recommandée), （推荐）, …
RECOMMENDED = re.compile(r'\s*[(（][^()（）]+[)）]$')
OLD_DEFAULTS = re.compile(r'1\.35.{0,40}?(?:検索パネル|Suchdialog|panel de B|Find panel)', re.I)


def strings(language, table):
    path = INTERFACES / f'{language}.lproj/{table}.strings'
    if not path.exists():
        path = INTERFACES / f'Base.lproj/{table}.strings'
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


def raw_page(language, name):
    raw = (INTERFACES / f'{language}.lproj/TeXShopHelp/pgs/{name}').read_bytes()
    match = re.search(br'charset=["\x27]?([^"\x27\s>]+)', raw, re.I)
    encoding = match[1].decode().lower() if match else 'latin-1'
    encoding = {'shift_jis': 'cp932', 'x-sjis': 'cp932', 'iso-8859-1': 'latin-1'}.get(encoding, encoding)
    text = raw.decode(encoding)
    assert text.encode(encoding) == raw, name
    return re.sub(r'<!--.*?-->', ' ', text, flags=re.S)


def page(language, name):
    text = html.unescape(raw_page(language, name))
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', text))


failures = []
for language in LANGUAGES:
    for name in ('basic_edittricks.htm', FIND_PAGE):
        if (INTERFACES / f'{language}.lproj/TeXShopHelp/pgs/{name}').exists():
            old = OLD_EDITING.search(page(language, name))
            if old:
                failures.append(f'{language} {name} still has “{old[0]}”')
    if (INTERFACES / f'{language}.lproj/TeXShopHelp/pgs/configure_defaults.htm').exists():
        defaults = page(language, 'configure_defaults.htm')
        if OLD_DEFAULTS.search(defaults):
            failures.append(f'{language} configure_defaults.htm still introduces the find panel of TeXShop 1.35')
    if not (INTERFACES / f'{language}.lproj/TeXShopHelp/pgs/{FIND_PAGE}').exists():
        failures.append(f'{language} has no {FIND_PAGE}')
        continue
    folded = page(language, FIND_PAGE).casefold()
    for table, key in TERMS:
        value = strings(language, table)[key]
        # The settings mark the Advanced Find panel as recommended; the help names the panel without that mark.
        value = RECOMMENDED.sub('', value)
        # German writes a no-break space before the ellipsis in the application; the page may break the line there.
        value = re.sub(r'\s+', ' ', value)
        if value.casefold() not in folded:
            failures.append(f'{language} {FIND_PAGE} lacks {table} {key} “{value}”')
    # The ? button of the Multiple Replace window opens the help at this anchor.
    anchored = re.search(r'<a name="multiplereplace"></a>\s*(.{0,80})',
                         html.unescape(raw_page(language, FIND_PAGE)), re.S)
    edit_menu = re.sub(r'\s+', ' ', strings(language, 'AdvancedFind')['MultipleReplace.EditMenu'])
    if not anchored or edit_menu not in re.sub(r'\s+', ' ', anchored[1]):
        failures.append(f'{language} {FIND_PAGE} lacks the anchor multiplereplace before “{edit_menu}”')

if failures:
    print('\n'.join(f'FAIL: {f}' for f in failures))
    sys.exit(1)
print(f'PASS: the Find and Replace help in {len(LANGUAGES)} languages describes the Advanced Find panel '
      f'with the {len(TERMS)} interface terms of each language and the anchor of Multiple Replace, and no page presents OgreKit as the new panel')
