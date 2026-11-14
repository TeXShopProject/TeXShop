#!/usr/bin/env python3
"""The titles written in the Settings XIBs equal their Base .strings entries.

At run time the Base .strings table replaces the XIB titles, so a stale title in a XIB
is never seen and no interface test notices it. It still misleads whoever opens the
XIB in Interface Builder or translates from it, as the former pTeX and otf names did.
"""
from pathlib import Path
import html
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'Resources/Interfaces/Base.lproj'
MUTATIONS = {
    # The otf group box keeps its former name in the XIB only.
    'stale-box': ('SettingsMiscTwo.xib', 'title="Japanese pLaTeX"', 'title="pTeX support (for Japan)"'),
    # The otf switch keeps its former name in the XIB only.
    'stale-switch': ('SettingsMiscTwo.xib', 'title="Convert to otf Package \\UTF / \\CID"', 'title="utf export"'),
}
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation and mutation not in MUTATIONS:
    sys.exit(f'unknown mutation {mutation}; choose from {", ".join(sorted(MUTATIONS))}')

failures, checked, files = [], 0, 0
for xib in sorted(BASE.glob('Settings*.xib')):
    table = BASE / (xib.stem + '.strings')
    if not table.exists():
        continue
    files += 1
    strings = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(table)]))
    text = xib.read_text(encoding='utf-8')
    if mutation and MUTATIONS[mutation][0] == xib.name:
        old, new = MUTATIONS[mutation][1:]
        assert text.count(old) == 1, (mutation, old)
        text = text.replace(old, new)
    for element in re.finditer(r'<\w+\b([^>]*)>', text):
        attributes = element.group(1)
        identifier = re.search(r'\bid="([^"]+)"', attributes)
        title = re.search(r'\btitle="([^"]*)"', attributes)
        if not identifier or not title:
            continue
        key = identifier.group(1) + '.title'
        if key not in strings:
            continue
        checked += 1
        if html.unescape(title.group(1)) != strings[key]:
            failures.append(f'{xib.name}: {key} is "{html.unescape(title.group(1))}" in the XIB but "{strings[key]}" in {table.name}')

if failures:
    print('FAIL: XIB titles differ from the Base strings', *failures, sep='\n', file=sys.stderr)
    sys.exit(1)
print(f'PASS: {checked} titles in {files} Settings XIBs equal their Base strings')
