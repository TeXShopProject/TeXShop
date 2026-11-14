#!/usr/bin/env python3
"""Find Next in a long document centres the misspelled word, also after the text
around it is laid out to be drawn (#38). Uses the user manual's source as the long
document, a stand-in spell checker and a window that is never shown.
Use --mutation to check that the test catches the faults it is meant to catch.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
LAYOUT = ('        [lm ensureLayoutForBoundingRect:NSMakeRect(0, NSMidY(r) - viewH / 2, tc.size.width, viewH)\n'
          '                        inTextContainer:tc];\n')
MUTATIONS = {
    # Lay out the range alone, as before the fix.
    'range-only': (LAYOUT, ''),
    # Lay out the visible part once, but keep the place measured before it.
    'one-pass': ('for (NSUInteger pass = 0; pass < 8; pass++)', 'for (NSUInteger pass = 0; pass < 1; pass++)'),
    # Lay out only the half above the range.
    'above-only': (LAYOUT, LAYOUT.replace('tc.size.width, viewH)', 'tc.size.width, viewH / 2)')),
    # Lay out the whole text before the range.
    'full-layout': ('        [lm ensureLayoutForCharacterRange:range];\n        NSRange glyphs',
                    '        [lm ensureLayoutForCharacterRange:NSMakeRange(0, NSMaxRange(range))];\n        NSRange glyphs'),
}
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--mutation', choices=MUTATIONS)
args = p.parse_args()
s = '#import "SessionChecker.h"\n#define NSSpellChecker SessionChecker\n' + (root/'Sources/Editor/TSSpellSupport.m').read_text()
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert s.count(old) == 1, args.mutation
    s = s.replace(old, new)
with tempfile.TemporaryDirectory(prefix='texshop-spell-center-') as td:
    t = Path(td); (t/'support.m').write_text(s)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-DTSSPELL_STANDALONE_TEST', *include_args(root),
        '-I'+str(root/'Tests/SpellCheck'), '-I'+str(root/'Tests'), '-framework', 'Cocoa',
        str(root/'Tests/SpellCheck/center.m'), str(t/'support.m'), str(root/'Sources/Editor/TSSpellExclusions.m'),
        '-o', str(t/'probe')], check=True)
    subprocess.run([str(t/'probe'), str(root/'DocumentSources/Manual Source/Manual.tex')],
        env=dict(os.environ, TSSPELL_RULES=str(root/'Resources/TeXShop/SpellCheck/SpellingExclusions.txt')),
        check=True, timeout=300)
