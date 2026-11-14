#!/usr/bin/env python3
"""Show Spelling and Grammar with TeX-aware checking opens the panel without the
system's own search and keeps the TeX-aware finding; a shown panel is hidden with
no search (#38). Stand-in spell checker and panel; nothing is ordered on screen.
Use --mutation to check that the test catches the faults it is meant to catch.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
MUTATIONS = {
    # Search also when the command hides the panel.
    'search-when-shown': ('        hidePanel();\n        return;\n', '        hidePanel();\n'),
    # Do not show the panel.
    'no-show': ('    [panel orderFront:nil];\n', ''),
    # Open the panel with the system's showGuessPanel:, as before.
    'system-open': ('    [panel orderFront:nil];\n', '    hidePanel();\n    [panel orderFront:nil];\n'),
}
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--mutation', choices=MUTATIONS)
args = p.parse_args()
s = '#import "SessionChecker.h"\n#define NSSpellChecker SessionChecker\n' + (root/'Sources/Editor/TSSpellSupport.m').read_text()
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert s.count(old) == 1, args.mutation
    s = s.replace(old, new)
with tempfile.TemporaryDirectory(prefix='texshop-spell-open-panel-') as td:
    t = Path(td); (t/'support.m').write_text(s)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-DTSSPELL_STANDALONE_TEST', *include_args(root),
        '-I'+str(root/'Tests/SpellCheck'), '-I'+str(root/'Tests'), '-framework', 'Cocoa',
        str(root/'Tests/SpellCheck/open-panel.m'), str(t/'support.m'), str(root/'Sources/Editor/TSSpellExclusions.m'),
        '-o', str(t/'probe')], check=True)
    subprocess.run([str(t/'probe')],
        env=dict(os.environ, TSSPELL_RULES=str(root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt')),
        check=True, timeout=60)
