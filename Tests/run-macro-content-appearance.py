#!/usr/bin/env python3
"""The macro editor's contents use the source font and the theme colors."""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Macros/TSMacroEditor.m').read_text()
body = source[source.index('// BEGIN content appearance'):source.index('// END content appearance')]
mutations = {
    'always-light': ('NSDictionary *theme = dark ? darkColors : liteColors;', 'NSDictionary *theme = liteColors; dark = NO;'),
    'no-background': ('contentTextView.backgroundColor = ', '(void)'),
    'ignore-console-font': ('if ([SUD boolForKey:SameFontForMacroKey])', 'if (NO)'),
}
def run(text):
    with tempfile.TemporaryDirectory(prefix='texshop-macro-contents-') as tmp:
        tmp = Path(tmp)
        (tmp / 'MacroContentAppearance.inc').write_text(text)
        binary = tmp / 'test'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(tmp), '-I', str(root / 'Tests'), *include_args(root),
                        str(root / 'Tests/MacroContentAppearance.m'), str(root / 'Sources/Editor/TSColorSupport.m'), str(root / 'Sources/App/globals.m'), '-o', str(binary)], check=True)
        themes = root / 'Resources/TeXShop/Themes'
        return subprocess.run([str(binary), str(themes / 'SolarizedLite.plist'), str(themes / 'Dracula.plist')], capture_output=True, text=True, timeout=60)
result = run(body); print(result.stdout, end=''); assert result.returncode == 0, result.stderr
if '--mutations' in sys.argv:
    for name, (before, after) in mutations.items():
        assert body.count(before) == 1, name
        result = run(body.replace(before, after))
        assert result.returncode and 'FAIL' in result.stderr, (name, result.stderr)
        print('DETECTED', name, result.stderr.strip().splitlines()[-1])
