#!/usr/bin/env python3
"""What the application gives the Advanced Find panel's fields and the rules of Multiple Replace: the theme of a light
or dark window, the source font and the TeX settings, from Sources/App/TSAppDelegate.m ("Advanced Find field style",
compiled unchanged). --mutations checks that a change of it is detected."""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/App/TSAppDelegate.m').read_text()
body = source[source.index('// BEGIN Advanced Find field style'):source.index('// END Advanced Find field style')]
mutations = {
    'always-light': ('return TSAdvancedFindFieldStyleForTheme(dark ? darkColors : liteColors, dark);', 'return TSAdvancedFindFieldStyleForTheme(liteColors, NO);'),
    'coloring-ignored': ('[SUD boolForKey:SyntaxColoringEnabledKey] ?', 'YES ?'),
    'theme-alpha': ('return [colors colorFromDictionary:theme andKey:key] ?:', 'return [colors colorForKey:key fromDictionary:theme isWindowDark:dark] ?:'),
    'no-font-notification': ('TSPreferenceNeedsRecolorNotification,\n                                      DocumentFontChangedNotification]', 'TSPreferenceNeedsRecolorNotification]'),
    'expl3-ignored': ('options.colorsExpl3 = [SUD boolForKey:expl3SyntaxColoringKey];', 'options.colorsExpl3 = NO;'),
}
def run(text):
    with tempfile.TemporaryDirectory(prefix='texshop-advanced-find-field-style-') as tmp:
        tmp = Path(tmp)
        (tmp / 'AdvancedFindFieldStyle.inc').write_text(text)
        binary = tmp / 'test'
        syntax = [root / 'Sources/Syntax' / name for name in ('TSSyntaxColorScheme.m', 'TSSyntaxTeXOptions.m')]
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(tmp), '-I', str(root / 'Tests'), *include_args(root),
                        str(root / 'Tests/AdvancedFindFieldStyle.m'), str(root / 'Sources/Editor/TSColorSupport.m'), str(root / 'Sources/App/globals.m'),
                        *map(str, syntax), str(root / 'Sources/Find/TSAdvancedFindFieldStyle.m'), '-o', str(binary)], check=True)
        themes = root / 'Resources/TeXShop/Themes'
        return subprocess.run([str(binary), str(themes / 'SolarizedLite.plist'), str(themes / 'Dracula.plist')], capture_output=True, text=True, timeout=60)
result = run(body); print(result.stdout, end=''); assert result.returncode == 0, result.stderr
if '--mutations' in sys.argv:
    for name, (before, after) in mutations.items():
        assert body.count(before) == 1, name
        result = run(body.replace(before, after))
        assert result.returncode and 'FAIL' in result.stderr, (name, result.stdout, result.stderr)
        print('DETECTED', name, result.stderr.strip().splitlines()[-1])
