#!/usr/bin/env python3
"""Interface text uses the macOS system font in every language.

Interface Builder sources may not name a font (they use metaFont), and compiled
nibs without a source may not archive a named font for controls. Text views get
their fonts from the user's settings at run time and are not checked here."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[1]
interfaces = root / 'Resources/Interfaces'
problems = []
sources = sorted(interfaces.glob('*.lproj/*.nib/designable.nib')) + sorted(interfaces.glob('*.lproj/*.xib'))
for path in sources:
    if path.parent.name == 'Preferences.nib':
        continue  # historical; not built
    for match in re.finditer(r'<font [^>]*\bname="([^"]+)"', path.read_text(encoding='utf-8')):
        problems.append(f'{path.relative_to(root)}: {match.group(1)}')
compiled = 0
for path in sorted(interfaces.glob('*.lproj/*.nib')) + sorted(interfaces.glob('*.lproj/*.nib/keyedobjects*.nib')):
    if path.is_dir() or 'Preferences.nib' in path.parts:
        continue
    data = path.read_bytes()
    if not data.startswith(b'bplist'):
        continue  # compiled by current Interface Builder from a checked source
    compiled += 1
    objects = plistlib.loads(data)['$objects']
    for item in objects:
        if isinstance(item, dict) and 'NSName' in item and 'NSSize' in item and item.get('NSfFlags') == 16:
            name = objects[item['NSName'].data]
            if not name.startswith('.'):  # .AppleSystemUIFont and older system font names
                problems.append(f'{path.relative_to(root)}: {name} {item["NSSize"]:g}')
assert not problems, 'Named interface fonts:\n' + '\n'.join(problems)
print(f'PASS: {len(sources)} interface sources and {compiled} older compiled nibs use the system font')
