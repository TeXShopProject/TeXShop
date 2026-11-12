#!/usr/bin/env python3
"""Every bundled theme defines the seven expl3 colors, readable on its own
background; the Lite and Dark themes match their reserve copies."""
from pathlib import Path
import plistlib, sys
root = Path(__file__).resolve().parents[1]
KEYS = ['explFunction', 'explIntenseFunction', 'explVariable', 'explIntenseVariable', 'explmykey', 'explmykeyArgument', 'explmsg']
mutation = sys.argv[1] if len(sys.argv) > 1 else ''

def luminance(color):
    channel = lambda x: x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
    return 0.2126 * channel(color[0]) + 0.7152 * channel(color[1]) + 0.0722 * channel(color[2])

def contrast(a, b):
    high, low = sorted([luminance(a), luminance(b)], reverse=True)
    return (high + 0.05) / (low + 0.05)

bundled = sorted((root / 'Resources/TeXShop/Themes').glob('*.plist'))
reserve = sorted((root / 'Resources/Themes').glob('*.plist'))
assert len(bundled) == 9 and len(reserve) == 2, (bundled, reserve)
themes = {path: plistlib.loads(path.read_bytes()) for path in bundled + reserve}
if mutation == 'missing-key':
    del themes[bundled[0]]['explmsg']
elif mutation == 'background-color':
    themes[bundled[2]]['explVariable'] = list(themes[bundled[2]]['EditorBackground'][:3]) + [1]
elif mutation == 'reserve-differs':
    themes[bundled[4]]['explFunction'] = [0.5, 0.5, 0.5, 1]
elif mutation:
    raise SystemExit('unknown mutation ' + mutation)
for path, theme in themes.items():
    colors = [theme.get(key) for key in KEYS]
    assert all(isinstance(c, list) and len(c) == 4 and all(0 <= x <= 1 for x in c) and c[3] == 1 for c in colors), ('expl3 colors present and opaque', path.name)
    assert len({tuple(c) for c in colors}) == 7, ('seven distinct expl3 colors', path.name)
    background = theme['EditorBackground']
    if background[3] < 0.5:  # A transparent source background shows the window behind it.
        background = [0.12, 0.12, 0.12] if luminance(theme['EditorText']) > 0.5 else [1, 1, 1]
    for key, color in zip(KEYS, colors):
        assert contrast(color, background) >= 2.3, ('expl3 color readable on the theme background', path.name, key, round(contrast(color, background), 2))
for path in reserve:
    copy = root / 'Resources/TeXShop/Themes' / path.name
    assert all(themes[path][key] == themes[copy][key] for key in KEYS), ('bundled copy matches the reserve theme', path.name)
print(f'PASS: seven readable expl3 colors in {len(themes)} bundled themes; Lite and Dark match their reserve copies')
