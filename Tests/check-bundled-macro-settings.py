#!/usr/bin/env python3
"""Check that bundled macros only write settings that TeXShop still reads.

A macro that runs `defaults write TeXShop KEY …` must name a setting that TeXShop reads: a key that
the code outside comments passes to a defaults accessor (`…forKey:` / `…ForKey:`), either as a
string literal or as a string defined in Sources/App/globals.m outside comments. Commented-out
definitions and notification names do not count. Colored source and Default Colored source wrote the
color settings used before themes, which TeXShop no longer has."""
from pathlib import Path
import argparse
import plistlib
import re
import sys

MUTATIONS = {
    # The removed macros come back.
    'colored-source': lambda macros: macros + ['--Applescript direct\ndo shell script "defaults write TeXShop background_R 0.3"'],
    # A setting whose definition is only in a comment of globals.m.
    'commented-key': lambda macros: macros + ['--Applescript direct\ndo shell script "defaults write TeXShop DarkModeInvertPreview YES"'],
    # A notification name, which is no setting.
    'notification-name': lambda macros: macros + ['--Applescript direct\ndo shell script "defaults write TeXShop SyntaxColoringChangedNotification 1"'],
    # A setting whose name has no Key suffix in globals.m (must still pass).
    'live-path-setting': lambda macros: macros + ['--Applescript direct\ndo shell script "defaults write TeXShop TetexBinPath /Library/TeX/texbin"'],
    # A macro writes a setting that TeXShop reads (must still pass).
    'live-setting': lambda macros: macros + ['--Applescript direct\ndo shell script "defaults write TeXShop SourceWindowAlpha 0.9"'],
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--mutations', action='store_true', help='check that every mutation is caught, and that the control passes')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]

def code(text):
    """The text without comments; string literals are kept."""
    return re.sub(r'"(?:\\.|[^"\\\n])*"|/\*.*?\*/|//[^\n]*',
                  lambda m: m.group(0) if m.group(0).startswith('"') else '\n' * m.group(0).count('\n') or ' ', text, flags=re.S)

definitions = dict(re.findall(r'NSString \*(\w+)\s*=\s*@"([^"]+)"', code((root / 'Sources/App/globals.m').read_text())))
names, literals = set(), set()
for path in (root / 'Sources').rglob('*'):
    if path.suffix in ('.m', '.h', '.mm', '.inc', '.swift') and path.name not in ('globals.m', 'globals.h'):
        text = code(path.read_text(errors='replace'))
        names |= set(re.findall(r'[fF]orKey:\s*(\w+)', text))
        literals |= set(re.findall(r'[fF]orKey:\s*@"([^"]+)"', text))
known = {value for name, value in definitions.items() if name in names} | literals

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


def unread(texts):
    return sorted({key for text in texts
                   for key in re.findall(r'defaults write (?:TeXShop|TeXShop\.app|[\w.]+\.TeXShop) (\w+)', text)
                   if key not in known})


if args.mutations:
    for name, mutate in sorted(MUTATIONS.items()):
        caught = bool(unread(mutate(macros)))
        assert caught == (name not in ('live-setting', 'live-path-setting')), f'mutation {name}: caught={caught}'
        print(f'{"DETECTED" if caught else "ACCEPTED"} {name}')
if args.mutation:
    macros = MUTATIONS[args.mutation](macros)
problems = unread(macros)
if problems:
    print('FAIL: bundled macros write settings TeXShop does not read: ' + ', '.join(problems))
    sys.exit(1)
print(f'PASS: {len(macros)} bundled macros in {len(files)} files write only settings TeXShop reads')
