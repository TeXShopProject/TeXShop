#!/usr/bin/env python3
"""Edit › Copy with Style: the four commands put RTF, HTML and text on a pasteboard.

TSStyledCopy.m, the TeX scanner, TSSyntaxColorScheme.m and the document's method
-copyStyledSelectionOfTextView:darkTheme:withBackground: (verbatim, on a stand-in
document whose general pasteboard is a private one) are compiled with the bundled
Lite and Dark themes. The RTF is read back: the text, the theme's text color, the
colors of a command (selected from its middle), a comment and a brace, the theme's
background only with the commands that ask for it, the font, several ranges, coloring
turned off, and fullwidth letters with a translucent background blended onto the
paper. Every compiled MainMenu has the submenu right after Copy, with the four actions,
their shortcut identifiers and no key equivalents. No window is shown and the general
pasteboard is never touched.

  --mutation NAME  check that a broken copy is detected
"""
from pathlib import Path
import argparse, os, subprocess, sys, tempfile
from source_tree import include_args, source_file
from production_fragments import method, verify_embedded

ROOT = Path(__file__).resolve().parents[1]
STYLED = 'Sources/Editor/TSStyledCopy.m'
HEADER = 'Sources/Editor/TSStyledCopy.h'
SYNTAX = 'Sources/Editor/TSDocument-StyledCopy.m'
MUTATIONS = {
    # Only the lines of the selection are scanned: the middle line of a footnote loses its color.
    'selected-lines-scanned': (STYLED, '[scanner lineAlignedRangeForEditedRange:NSMakeRange(0, length) inString:string]',
                               '[scanner lineAlignedRangeForEditedRange:selected.firstObject.rangeValue inString:string]'),
    # AppKit writes the HTML: sizes in CSS pixels, other colors, a background over the paragraph.
    'appkit-html': (STYLED, '[TSStyledCopyHTML(styled) dataUsingEncoding:NSUTF8StringEncoding]',
                    '[styled dataFromRange:whole documentAttributes:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType} error:NULL]'),
    # The paragraphs lose the indents and the line spacing of the source.
    'no-paragraph-layout': (STYLED, '    if (style.headIndent != 0)\n', '    if (NO)\n'),
    # The line break that ends the selection is left out of the HTML.
    'final-break-dropped': (STYLED, '        if (NSMaxRange(enclosing) == string.length && enclosing.length > paragraph.length)\n', '        if (NO)\n'),
    # A CRLF is written as two line feeds.
    'crlf-two-breaks': (STYLED, '    NSAttributedString *styled = TSStyledCopyWithLineFeeds(original);', '    NSAttributedString *styled = original;'),
    # A light face is written as regular.
    'regular-weight': (STYLED, '    return (nearest + 1) * 100;', '    return 400;'),
    # A source behind a find field (or in a window that is not key) is copied from.
    'any-responder': (HEADER, '    if (!window.isKeyWindow || window.firstResponder != view)\n        return NO;\n', ''),
    # The commands of Light Mode take the theme of Dark Mode.
    'themes-swapped': (SYNTAX, '(dark ? darkColors : liteColors)', '(dark ? liteColors : darkColors)'),
    # A translucent color is written as it is.
    'translucent-kept': (STYLED, '    if (alpha >= 1)\n        return srgb;', '    return srgb;'),
    # The font of the source is not copied.
    'no-font': (STYLED, 'return @[NSFontAttributeName, NSParagraphStyleAttributeName];', 'return @[NSParagraphStyleAttributeName];'),
    # The background is added whether or not it was asked for.
    'background-always': (SYNTAX, 'withBackground ? [support opaqueColorForKey:@"EditorBackground"', 'YES ? [support opaqueColorForKey:@"EditorBackground"'),
}
STUB_HEADER = '''#import <AppKit/AppKit.h>
@interface TSColorSupport : NSObject
+ (instancetype)sharedInstance;
- (NSColor *)colorFromDictionary:(NSDictionary *)theme andKey:(NSString *)key;
- (NSColor *)colorAndAlphaFromDictionary:(NSDictionary *)theme andKey:(NSString *)key;
- (NSColor *)liteColorAndAlphaWithKey:(NSString *)key;
- (NSColor *)darkColorAndAlphaWithKey:(NSString *)key;
- (NSColor *)opaqueColorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark;
@end
'''
SIGNATURE = '- (BOOL)copyStyledSelectionOfTextView:(NSTextView *)sourceView darkTheme:(BOOL)dark withBackground:(BOOL)withBackground'

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

text = {path: (ROOT / path).read_text(encoding='utf-8') for path in (STYLED, SYNTAX, HEADER)}
document_method = method(text[SYNTAX], SIGNATURE)
if args.mutation:
    path, old, new = MUTATIONS[args.mutation]
    assert text[path].count(old) == 1, args.mutation
    text[path] = text[path].replace(old, new)
    if path == SYNTAX:
        document_method = method(text[SYNTAX], SIGNATURE)
else:
    verify_embedded(document_method, [('document method', text[SYNTAX], document_method)])

# The source and Copy with Style ask the same method for the options of the scanner, spelling settings included
# (they change how a bracket is split): colorizeText: sets none of its own.
syntax_source = (ROOT / 'Sources/Editor/TSDocument-Syntax.m').read_text(encoding='utf-8')
colorize = method(syntax_source, '- (void)colorizeText:(NSTextView *)aTextView range:(NSRange)range')
assert '[self sourceScannerOptionsWithScheme:self.syntaxColorScheme]' in colorize and 'options.' not in colorize, 'colorizeText: sets scanner options of its own'
assert 'options.excludesParametersFromSpelling' in method(syntax_source, '- (TSMutableSyntaxTeXOptions *)sourceScannerOptionsWithScheme:(TSSyntaxColorScheme *)scheme')
assert '[self sourceScannerOptionsWithScheme:scheme]' in text[SYNTAX]

menus = sorted((ROOT / 'Resources/Interfaces').glob('*.lproj/MainMenu.nib/keyedobjects*.nib'))
if len(menus) != 36:
    raise SystemExit('Expected 36 compiled menu variants')
syntax = ROOT / 'Sources/Syntax'
with tempfile.TemporaryDirectory(prefix='texshop-styled-copy-') as tmp:
    tmp = Path(tmp)
    (tmp / 'TSColorSupport.h').write_text(STUB_HEADER, encoding='utf-8')
    (tmp / 'StyledCopyDocumentMethod.inc').write_text(document_method + '\n', encoding='utf-8')
    (tmp / 'TSStyledCopy.m').write_text(text[STYLED], encoding='utf-8')
    (tmp / 'TSStyledCopy.h').write_text(text[HEADER], encoding='utf-8')
    exe = tmp / 'styled-copy'
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'WebKit', '-I', str(tmp), *include_args(ROOT),
                    str(ROOT / 'Tests/StyledCopy.m'), str(tmp / 'TSStyledCopy.m'),
                    *(str(syntax / name) for name in ['TSSyntaxScanner.m', 'TSSyntaxTeXOptions.m', 'TSSyntaxTeXScanner.m',
                                                      'TSSyntaxXMLScanning.m', 'TSSyntaxColorScheme.m']),
                    '-o', str(exe)], check=True)
    env = dict(os.environ, TMPDIR=str(tmp))
    result = subprocess.run([str(exe), str(ROOT / 'Resources/Themes'), *map(str, menus)], capture_output=True, text=True,
                            timeout=300, env=env)
    print(result.stdout, end='')
    if result.returncode:
        print(result.stderr, end='')
        raise SystemExit(f'FAIL ({args.mutation or "production"})')
