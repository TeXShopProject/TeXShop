#!/usr/bin/env python3
"""Fullwidth letters, digits and symbols are colored only by themes that define
EditorHighlightZenkakuSymbol(Background); older and user themes look unchanged."""
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from source_tree import source_file

root = Path(__file__).resolve().parents[1]
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
color = source_file(root, 'TSDocument-Color.m').read_text(encoding='latin-1')
syntax = source_file(root, 'TSDocument-Syntax.m').read_text(encoding='latin-1')
support = source_file(root, 'TSColorSupport.m').read_text(encoding='latin-1')
preferences = source_file(root, 'TSPreferences-Color.m').read_text(encoding='latin-1')
wells = preferences[preferences.index('- (NSColor *)fullwidthHighlightColorForKey:'):]
wells = wells[:wells.index('\n}\n') + 3]

# The document takes the fullwidth colors of TSSyntaxColorScheme, and none when it has none.
scheme_source = source_file(root, 'TSSyntaxColorScheme.m').read_text(encoding='utf-8')
scheme = scheme_source[scheme_source.index('// Where a role finds its color'):]
block = color[color.index('    TSSyntaxColorScheme *scheme = [[TSSyntaxColorScheme alloc] initWithTheme:'):]
block = block[:block.index('\n') + 1]
rule = color[color.index('    NSDictionary *fullwidthAttributes = [scheme attributesForRole:TSSyntaxRoleFullwidthSymbol];'):]
rule = rule[:rule.index('self.fullwidthSymbolColorAttribute = ')]
assert 'self.fullwidthSymbolColorAttribute = fullwidthAttributes.count ? fullwidthAttributes : nil;' in color
block += rule + 'result = fullwidthAttributes.count ? fullwidthAttributes : nil;\n'
# The scanner finds the characters; the document asks for them when its scheme has fullwidth colors.
scanner_header = source_file(root, 'TSSyntaxTeXScanner.h').read_text(encoding='utf-8')
scanner = source_file(root, 'TSSyntaxTeXScanner.m').read_text(encoding='utf-8')
membership = scanner_header[scanner_header.index('static inline BOOL TSIsHighlightedFullwidthCharacter'):]
membership = membership[:membership.index('\n}\n') + 3]
readers = ''.join(support[support.index(sig):support.index('\n}\n', support.index(sig)) + 3] for sig in
                  ['- (NSArray *) colorArrayFromDictionary:', '- (NSColor *) colorFromDictionary:', '- (NSColor *) colorAndAlphaFromDictionary:',
                   '- (NSColor *)liteColorWithKey:', '- (NSColor *)darkColorWithKey:', '- (NSColor *)liteColorAndAlphaWithKey:',
                   '- (NSColor *)darkColorAndAlphaWithKey:'])
branch = scanner[scanner.index('else if (fullwidth && TSIsHighlightedFullwidthCharacter((unichar)c))'):]
branch = branch[:branch.index('else if ((c == \'&\')')]
assert 'TSToken(&scan, location, 1, TSSyntaxRoleFullwidthSymbol);' in branch
assert 'const BOOL fullwidth = options.marksFullwidthSymbols;' in scanner
assert 'options.marksFullwidthSymbols = [self.syntaxColorScheme attributesForRole:TSSyntaxRoleFullwidthSymbol].count > 0;' in syntax
if mutation == 'fallback-color':
    old = 'if (color)\n        attributes[NSForegroundColorAttributeName] = color;'
    assert scheme.count(old) == 1
    scheme = scheme.replace(old, 'attributes[NSForegroundColorAttributeName] = color ?: NSColor.redColor;')
elif mutation == 'clear-background':
    assert scheme.count('color && color.alphaComponent > 0') == 1
    scheme = scheme.replace('color && color.alphaComponent > 0', 'color')
elif mutation == 'empty-attributes':
    block = block.replace('result = fullwidthAttributes.count ? fullwidthAttributes : nil;', 'result = fullwidthAttributes;')
elif mutation == 'comma':
    membership = membership.replace('c >= 0xFF01 && c <= 0xFF0B', 'c >= 0xFF01 && c <= 0xFF0C')
elif mutation == 'well-fallback':
    wells = wells.replace('@"EditorBackground" : @"EditorText"', '@"EditorText" : @"EditorBackground"')
elif mutation:
    sys.exit('unknown mutation')

program = r'''
#import <Cocoa/Cocoa.h>
@interface TSColorSupport : NSObject
+ (instancetype)sharedInstance;
@end
@implementation TSColorSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
READERS
@end
#import "TSSyntaxColorScheme.h"
SCHEME
MEMBERSHIP
@interface Wells : NSObject { @public NSMutableDictionary *EditingColors; }
@end
@implementation Wells
WELLS
@end
static NSDictionary *Attributes(NSDictionary *colorDictionary)
{
    BOOL withDarkColors = NO; NSDictionary *result;
BLOCK
    return result;
}
static int failures;
static void Require(const char *name, BOOL ok) { if (!ok) { printf("FAIL %s\n", name); failures++; } }
static BOOL Same(NSColor *a, double r, double g, double b) {
    a = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return fabs(a.redComponent - r) < 1e-6 && fabs(a.greenComponent - g) < 1e-6 && fabs(a.blueComponent - b) < 1e-6;
}
int main(int argc, char **argv) { @autoreleasepool {
    Require("theme without keys adds nothing", Attributes(@{@"EditorText": @[@0, @0, @0, @1]}) == nil);
    NSDictionary *both = Attributes(@{@"EditorHighlightZenkakuSymbol": @[@0.692, @0.101, @0, @1], @"EditorHighlightZenkakuSymbolBackground": @[@0.9, @1, @1, @1]});
    Require("foreground", Same(both[NSForegroundColorAttributeName], 0.692, 0.101, 0));
    Require("background", Same(both[NSBackgroundColorAttributeName], 0.9, 1, 1));
    NSDictionary *clear = Attributes(@{@"EditorHighlightZenkakuSymbol": @[@0, @0, @1, @1], @"EditorHighlightZenkakuSymbolBackground": @[@1, @1, @1, @0]});
    Require("transparent background adds no background", clear.count == 1 && clear[NSForegroundColorAttributeName]);
    NSDictionary *onlyBackground = Attributes(@{@"EditorHighlightZenkakuSymbolBackground": @[@0.1, @0, @0]});
    Require("background alone, three components", onlyBackground.count == 1 && Same(onlyBackground[NSBackgroundColorAttributeName], 0.1, 0, 0));
    Wells *w = [Wells new];
    w->EditingColors = [@{@"EditorText": @[@0.1, @0.2, @0.3, @1], @"EditorBackground": @[@0.9, @0.8, @0.7, @1]} mutableCopy];
    Require("well shows the text color without a key", Same([w fullwidthHighlightColorForKey:@"EditorHighlightZenkakuSymbol"], 0.1, 0.2, 0.3));
    Require("well shows the background without a key", Same([w fullwidthHighlightColorForKey:@"EditorHighlightZenkakuSymbolBackground"], 0.9, 0.8, 0.7));
    w->EditingColors[@"EditorHighlightZenkakuSymbol"] = @[@0.5, @0.5, @0];
    Require("well shows a three-component key", Same([w fullwidthHighlightColorForKey:@"EditorHighlightZenkakuSymbol"], 0.5, 0.5, 0));
    NSString *on = @"！＃＋－／０９：＠ＡＺ［｝ａｚ−", *off = @"，．～、。あ漢!0A-　";
    for (NSUInteger i = 0; i < on.length; i++) Require("highlighted character", TSIsHighlightedFullwidthCharacter([on characterAtIndex:i]));
    for (NSUInteger i = 0; i < off.length; i++) Require("ordinary character", !TSIsHighlightedFullwidthCharacter([off characterAtIndex:i]));
    for (int i = 1; i < argc; i++) {
        NSDictionary *theme = [NSDictionary dictionaryWithContentsOfFile:@(argv[i])];
        NSDictionary *a = Attributes(theme);
        BOOL dark = Same(a[NSForegroundColorAttributeName], 0.308, 0.899, 1) && Same(a[NSBackgroundColorAttributeName], 0.1, 0, 0);
        BOOL light = Same(a[NSForegroundColorAttributeName], 0.692, 0.101, 0) && Same(a[NSBackgroundColorAttributeName], 0.9, 1, 1);
        BOOL expectDark = [@[@"DarkTheme", @"Dracula", @"PreTeXt-Dark", @"SolarizedDark"] containsObject:@(argv[i]).lastPathComponent.stringByDeletingPathExtension];
        Require(argv[i], expectDark ? dark : light);
    }
    if (failures) return 1;
    printf("PASS: fullwidth highlight from theme keys only, %d bundled themes\n", argc - 1);
} return 0; }
'''.replace('READERS', readers).replace('SCHEME', scheme).replace('MEMBERSHIP', membership).replace('BLOCK', block).replace('WELLS', wells)
themes = sorted((root / 'Resources/TeXShop/Themes').glob('*.plist')) + sorted((root / 'Resources/Themes').glob('*.plist'))
assert len(themes) >= 11
bundled = [t.read_bytes() for t in sorted((root / 'Resources/TeXShop/Themes').glob('*.plist'))]
assert len(bundled) == len(set(bundled)), 'two bundled themes have the same contents'
with tempfile.TemporaryDirectory(prefix='texshop-fullwidth-') as tmp:
    (Path(tmp) / 'test.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-I', str(root / 'Sources/Syntax'),
                    str(Path(tmp) / 'test.m'), '-o', str(Path(tmp) / 'test')], check=True)
    result = subprocess.run([str(Path(tmp) / 'test'), *map(str, themes)], capture_output=True, text=True)
    print(result.stdout, end='')
    if result.returncode:
        sys.exit(f'FAIL ({mutation or "production"})')
# The rest of every bundled theme is unchanged by the two new keys.
for theme in themes:
    text = theme.read_text()
    assert len(re.findall(r'<key>EditorHighlightZenkakuSymbol(?:Background)?</key>', text)) == 2, theme
