#!/usr/bin/env python3
"""Where TeX is set against LaTeX, the interface says "plain TeX" in every language.

The spelling is fixed: lowercase p, one space, TeX. Compounds such as plain-TeX-Programm,
"Plain TeX" and a translated plain are refused. Every interface table, XIB and XML nib is
read, and the items that name plain TeX against LaTeX must say it.
"""
from pathlib import Path
import json, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[1]
INTERFACES = ROOT / 'Resources/Interfaces'
LANGUAGES = ['Base', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt', 'pt-PT', 'ro', 'zh_CN']
# "plain" next to TeX in any spelling, but not "plain text".
ANY = re.compile(r'plain[\s\- ‐‑]*tex(?!t)', re.I)
EXACT = 'plain TeX'


def table(lang, name):
    path = INTERFACES / f'{lang}.lproj/{name}.strings'
    if lang == 'Base' and not path.exists():
        path = INTERFACES / f'en.lproj/{name}.strings'
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))


def main():
    assert [m.group(0) for m in ANY.finditer('Plain TeX, plain-TeX-Programm, plain TeX, plain text, plain TeX')] == \
        ['Plain TeX', 'plain-TeX', 'plain TeX', 'plain TeX'], 'the pattern finds every spelling'
    problems = []
    files = sorted(INTERFACES.glob('*.lproj/*.strings')) + sorted(INTERFACES.glob('*.lproj/*.xib')) + \
        sorted(INTERFACES.glob('*.lproj/*.nib/designable.nib'))
    for path in files:
        text = path.read_bytes()
        text = text.decode('utf-16') if text[:2] in (b'\xff\xfe', b'\xfe\xff') else text.decode('utf-8', 'replace')
        for match in ANY.finditer(text):
            if match.group(0) != EXACT:
                problems.append(f'{path.relative_to(ROOT)}: {match.group(0)!r}')
    required = {
        'SettingsCategories': ['catalog.typesetting.4.0.title', 'catalog.typesetting.5.0.title',
                               'catalog.typesetting.6.0.title', 'catalog.typesetting.4.2.note', 'catalog.typesetting.5.2.note'],
        'SettingsTypesetting': ['588.title'],
        'ToolbarItems': ['tiLabelTeX', 'tiPaletteLabelTeX', 'tiToolTipTeX'],
    }
    for lang in LANGUAGES:
        for name, keys in required.items():
            values = table('en' if name == 'ToolbarItems' and lang == 'Base' else lang, name)
            for key in keys:
                if EXACT not in values.get(key, ''):
                    problems.append(f'{lang} {name} {key}: {values.get(key)!r}')
        for nib in ('MainMenu', 'TSDocument'):
            path = INTERFACES / f'{lang}.lproj/{nib}.nib/designable.nib'
            if f'title="{EXACT}"' not in path.read_text():
                problems.append(f'{path.relative_to(ROOT)}: no item titled {EXACT}')
    for source in ('Sources/Document/TSDocument.m', 'Sources/Typesetting/TSDocument-Jobs.m'):
        if f'selectItemWithTitle: @"{EXACT}"' not in (ROOT / source).read_text():
            problems.append(f'{source}: the program menu is not selected by {EXACT}')
    if problems:
        print('\n'.join(problems))
        print(f'FAIL: {len(problems)} places do not say {EXACT}')
        sys.exit(1)
    print(f'PASS: {len(files)} interface files say {EXACT} wherever plain TeX is named, and the items set against LaTeX say it in {len(LANGUAGES)} languages')


if __name__ == '__main__':
    main()
