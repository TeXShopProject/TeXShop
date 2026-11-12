#!/usr/bin/env python3
"""Classify macro contents as TeX, AppleScript or direct AppleScript without opening anything."""
from pathlib import Path
import re, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Macros/TSMacroContentKind.m').read_text()
menu = (root / 'Sources/Macros/TSMacroMenuController.m').read_text()
# doMacro: and validateMenuItem: decide through the shared function only.
assert not re.search(r'(?i)"--? ?applescript', menu), 'TSMacroMenuController.m still has its own AppleScript test'
assert menu.count('TSMacroContentKindForString(') == 2, 'expected one call in doMacro: and one in validateMenuItem:'
assert 'contentKind == TSMacroContentKindAppleScriptDirect' in menu
mutations = {
    'old-21-guard': ('|| TSMacroContentHasPrefix(string, @"-- applescript direct")',
                     '|| [[[string substringToIndex: 21] lowercaseString] isEqualToString: @"-- applescript direct"]'),
    'no-length-14': ('if ([string length] < 14 ||', 'if ('),
    'case-sensitive': ('[[[string substringToIndex: length] lowercaseString] isEqualToString: prefix]',
                       '[[string substringToIndex: length] isEqualToString: prefix]'),
}
def run(text):
    with tempfile.TemporaryDirectory(prefix='texshop-macro-kind-') as tmp:
        tmp = Path(tmp)
        (tmp / 'TSMacroContentKind.m').write_text(text)
        binary = tmp / 'test'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-framework', 'Foundation', '-I', str(root / 'Sources/Macros'),
                        str(root / 'Tests/MacroContentKind.m'), str(tmp / 'TSMacroContentKind.m'), '-o', str(binary)], check=True)
        macros = root / 'Resources/TeXShop/Macros'
        return subprocess.run([str(binary), *map(str, sorted(macros.glob('Macros_*.plist')))], capture_output=True, text=True, timeout=60)
result = run(source); print(result.stdout, end=''); assert result.returncode == 0, result.stderr
if '--mutations' in sys.argv:
    for name, (before, after) in mutations.items():
        assert source.count(before) == 1, name
        result = run(source.replace(before, after))
        assert result.returncode and 'FAIL' in result.stderr, (name, result.stderr)
        print('DETECTED', name, result.stderr.strip().splitlines()[-1])
