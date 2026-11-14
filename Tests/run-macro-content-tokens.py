#!/usr/bin/env python3
"""The macro editor shows the placeholders of a macro as tokens (Tests/MacroContentTokens.m): which ones, their width
and drawing, typing, the kind of the macro, the insertion point, delete, undo and copy. No window is shown.
--mutations breaks one rule at a time in a copy of the sources and checks that the test notices."""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args, source_file
from macro_editor_sources import PLACEHOLDER_RULES

root = Path(__file__).resolve().parents[1]
NAMES = ['TSMacroContentTokens.m', 'TSPlaceholderToken.m', 'TSMacroContentKind.m', *PLACEHOLDER_RULES,
         'TSAdvancedFindTextView.m', 'TSAdvancedFindHighlights.m', 'globals.m']
MUTATIONS = {
    'every #INS# is a token': ('TSSyntaxMacroContentScanner.m', 'TSSyntaxMacroContentScanner.teXPlaceholders, [NSSet setWithObject:@"#INS#"],\n                                ^(NSRange range',
                               'TSSyntaxMacroContentScanner.teXPlaceholders, [NSSet set],\n                                ^(NSRange range'),
    'the whole note of a mark is a token': ('TSSyntaxMacroContentScanner.m', '[found addObject:[NSValue valueWithRange:NSMakeRange(range.location, 1)]];', '[found addObject:[NSValue valueWithRange:range]];'),
    'the characters after the first take room': ('TSMacroContentTokens.m', ' ? NSGlyphPropertyControlCharacter : NSGlyphPropertyNull;', ' ? NSGlyphPropertyControlCharacter : properties[i];'),
    'tokens on another line are not laid out again': ('TSMacroContentTokens.m', '        invalidatedCharRange = invalidated;\n', ''),
    'the insertion point stops inside a token': ('TSMacroContentTokens.m', '                range.location = range.location < previous ? first.location : NSMaxRange(first);', '                ;'),
    'every selection goes by whole tokens (Find)': ('TSMacroContentTokens.m', '// Only what the user does moves the selection by whole tokens', '''- (void)setSelectedRanges:(NSArray<NSValue *> *)ranges affinity:(NSSelectionAffinity)affinity stillSelecting:(BOOL)still
{
    [super setSelectedRanges:[self rangesSnappedToTokens:ranges previous:self.selectedRange.location] affinity:affinity stillSelecting:still];
}
// Only what the user does moves the selection by whole tokens'''),
    'the mouse stops inside a token': ('TSMacroContentTokens.m', '    return [[self rangesSnappedToTokens:@[[NSValue valueWithRange:range]] previous:0].firstObject rangeValue];', '    return range;'),
    'delete takes one character of a token': ('TSMacroContentTokens.m', '            [self deleteToken:token];\n            return;\n        }\n    }\n    [super deleteBackward:sender];',
                                              '        }\n    }\n    [super deleteBackward:sender];'),
    'no pill is drawn': ('TSMacroContentTokens.m', '        TSDrawPlaceholderToken(title, font, pill);\n', ''),
}

def run(changes=None):
    with tempfile.TemporaryDirectory(prefix='texshop-macro-tokens-') as tmp:
        tmp = Path(tmp)
        sources = []
        for name in NAMES:
            path = source_file(root, name)
            if changes and changes[0] == name:
                text = path.read_text()
                assert text.count(changes[1]) == 1, changes
                path = tmp / name
                path.write_text(text.replace(changes[1], changes[2]))
            sources.append(str(path))
        # The Advanced Find panel's search and replace, which set the selection of the contents.
        sources += [str(path) for path in sorted((root / 'Sources/Find').glob('TSRegex*.m'))]
        binary = tmp / 'test'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-mmacosx-version-min=14.6', '-framework', 'Cocoa', '-I', str(tmp), '-I', str(root / 'Tests'),
                        *include_args(root), str(root / 'Tests/MacroContentTokens.m'), *sources, '-o', str(binary)], check=True)
        return subprocess.run([str(binary), '-AppleLanguages', '(en)'], capture_output=True, text=True, timeout=120)

result = run()
print(result.stdout, end='')
if result.returncode:
    sys.exit('FAIL: macro tokens\n' + result.stderr)
if '--mutations' in sys.argv:
    for name, change in MUTATIONS.items():
        result = run(change)
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {name!r} was not detected')
        print(f'DETECTED: {name}: {result.stderr.strip().splitlines()[-1] if result.stderr.strip() else result.returncode}')
