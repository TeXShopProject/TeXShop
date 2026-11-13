#!/usr/bin/env python3
"""The macro editor colors its contents as the source is colored (see
MacroContentHighlighting.m). The production methods between "BEGIN content
appearance" and "END content highlighting" in TSMacroEditor.m are compiled
unchanged into a small TSMacroEditor stand-in, with Sources/Syntax and the
layout manager of the Advanced Find panel. The contents are made by the editor's
own method, as loadUI makes them."""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args

ROOT = Path(__file__).resolve().parents[1]
EDITOR = ROOT / 'Sources/Macros/TSMacroEditor.m'
source = EDITOR.read_text(encoding='utf-8')
body = source[source.index('// BEGIN content appearance'):source.index('// END content highlighting')]
# The editor makes the contents with TextKit 1 and as plain text (loadUI, not compiled here).
for statement in ('contentTextView = [self makeContentTextViewWithSize:contentSize];',
                  'name:DocumentSyntaxColorNotification object:nil];', 'name:TSPreferenceNeedsRecolorNotification object:nil];'):
    assert source.count(statement) == 1, statement
SYNTAX = {p.name: p.read_text(encoding='utf-8') for p in (ROOT / 'Sources/Syntax').glob('*.m')}
MUTATIONS = {
    'no-follow': ('editor', '        [self.contentHighlighter followEdits];\n', ''),
    'ignores-setting': ('editor', 'if (![SUD boolForKey:SyntaxColoringEnabledKey]) {', 'if (NO) {'),
    # The contents get a plain layout manager, which does not draw the Advanced Find highlights.
    'plain-layout-manager': ('editor', 'NSLayoutManager *layout = [[TSAdvancedFindLayoutManager alloc] init];',
                             'NSLayoutManager *layout = [[NSLayoutManager alloc] init];'),
    'theme-not-followed': ('editor', '        self.contentHighlighter.scheme = scheme;\n', ''),
    'colors-composed-text': ('TSSyntaxHighlighter.m', 'if (TSSyntaxStorageHasMarkedText(textView.textStorage)) {', 'if (NO) {'),
    # Ownership by color alone: unmarked text with a color of the scheme is cleared too.
    'owner-by-color': ('TSSyntaxHighlighter.m', '            if (markValue) {',
                       '            if (!markValue) markValue = [layoutManager temporaryAttribute:key atCharacterIndex:i effectiveRange:NULL];\n            if (markValue) {'),
}
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation:
    where, old, new = MUTATIONS[mutation]
    if where == 'editor':
        assert body.count(old) == 1, mutation
        body = body.replace(old, new)
    else:
        assert SYNTAX[where].count(old) == 1, mutation
        SYNTAX[where] = SYNTAX[where].replace(old, new)

with tempfile.TemporaryDirectory(prefix='texshop-macro-highlighting-') as tmp:
    tmp = Path(tmp)
    (tmp / 'MacroContentHighlighting.inc').write_text(body, encoding='utf-8')
    parts = tmp / 'Syntax'
    parts.mkdir()
    for name, text in SYNTAX.items():
        (parts / name).write_text(text, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I', str(tmp), '-I', str(ROOT / 'Tests'), *include_args(ROOT),
                    str(ROOT / 'Tests/MacroContentHighlighting.m'), *map(str, sorted(parts.glob('*.m'))),
                    str(ROOT / 'Sources/Macros/TSMacroContentKind.m'), str(ROOT / 'Sources/Editor/TSColorSupport.m'),
                    str(ROOT / 'Sources/Find/TSAdvancedFindTextView.m'), str(ROOT / 'Sources/Find/TSAdvancedFindHighlights.m'),
                    str(ROOT / 'Sources/App/globals.m'), '-o', str(tmp / 'test')], check=True)
    themes = ROOT / 'Resources/TeXShop/Themes'
    result = subprocess.run([str(tmp / 'test'), str(themes / 'LiteTheme.plist'), str(themes / 'DarkTheme.plist')],
                            capture_output=True, text=True, timeout=60)
print(result.stdout, end='')
if mutation:
    if result.returncode == 0:
        sys.exit(f'FAIL: mutation {mutation} was not detected')
    print(f'PASS: detected mutation {mutation} ({result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "crash"})')
elif result.returncode:
    sys.exit('FAIL: ' + result.stderr)
