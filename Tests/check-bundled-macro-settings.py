#!/usr/bin/env python3
"""Check that bundled macros only write settings that TeXShop still reads.

A macro that runs `defaults write TeXShop KEY …` must name a key defined in Sources/App/globals.m
or in the factory defaults. Colored source and Default Colored source wrote the color settings used
before themes, which TeXShop no longer has."""
from pathlib import Path
import argparse
import plistlib
import re
import sys

MUTATIONS = {
    # The removed macros come back.
    'colored-source': lambda macros: macros + ['--Applescript direct\ndo shell script "defaults write TeXShop background_R 0.3"'],
    # A macro writes a setting that TeXShop reads (must still pass).
    'live-setting': lambda macros: macros + ['--Applescript direct\ndo shell script "defaults write TeXShop SourceWindowAlpha 0.9"'],
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]

known = set(re.findall(r'NSString \*\w+\s*=\s*@"([^"]+)"', (root / 'Sources/App/globals.m').read_text()))
known |= set(plistlib.loads((root / 'Resources/Defaults/FactoryDefaults.plist').read_bytes()))

def contents(item, found):
    if isinstance(item, dict):
        if isinstance(item.get('content'), str):
            found.append(item['content'])
        for child in item.get('submenu', []):
            contents(child, found)
    return found

macros = []
files = sorted((root / 'Resources/TeXShop/Macros').glob('Macros_*.plist'))
assert files, 'no bundled macros'
for path in files:
    contents(plistlib.loads(path.read_bytes()), macros)
if args.mutation:
    macros = MUTATIONS[args.mutation](macros)
problems = []
for text in macros:
    for key in re.findall(r'defaults write (?:TeXShop|TeXShop\.app|[\w.]+\.TeXShop) (\w+)', text):
        if key not in known:
            problems.append(key)
if problems:
    print('FAIL: bundled macros write settings TeXShop does not read: ' + ', '.join(sorted(set(problems))))
    sys.exit(1)
print(f'PASS: {len(macros)} bundled macros in {len(files)} files write only settings TeXShop reads')
