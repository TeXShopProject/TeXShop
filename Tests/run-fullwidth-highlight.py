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

block = color[color.index('    // A theme without these keys'):]
block = block[:block.index('self.fullwidthSymbolColorAttribute = ') ]
block += 'result = fullwidthAttributes.count ? fullwidthAttributes : nil;\n'
membership = syntax[syntax.index('static inline BOOL TSIsHighlightedFullwidthCharacter'):]
membership = membership[:membership.index('\n}\n') + 3]
readers = ''.join(support[support.index(sig):support.index('\n}\n', support.index(sig)) + 3] for sig in
                  ['- (NSArray *) colorArrayFromDictionary:', '- (NSColor *) colorFromDictionary:', '- (NSColor *) colorAndAlphaFromDictionary:'])
branch = syntax[syntax.index('else if (self.fullwidthSymbolColorAttribute && TSIsHighlightedFullwidthCharacter(theChar))'):]
branch = branch[:branch.index('else if ((theChar == \'&\')')]
assert 'addTemporaryAttributes:self.fullwidthSymbolColorAttribute' in branch
if mutation == 'fallback-color':
    block = block.replace('if (myColor)\n        fullwidthAttributes[NSForegroundColorAttributeName] = myColor;',
                          'fullwidthAttributes[NSForegroundColorAttributeName] = myColor ?: NSColor.redColor;')
elif mutation == 'clear-background':
    block = block.replace('myColor && myColor.alphaComponent > 0', 'myColor')
elif mutation == 'comma':
    membership = membership.replace('c >= 0xFF01 && c <= 0xFF0B', 'c >= 0xFF01 && c <= 0xFF0C')
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
MEMBERSHIP
static NSDictionary *Attributes(NSDictionary *colorDictionary)
{
    NSColor *myColor; NSDictionary *result;
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
    NSString *on = @"！＃＋－／０９：＠ＡＺ［｝ａｚ−", *off = @"，．～、。あ漢!0A-　";
    for (NSUInteger i = 0; i < on.length; i++) Require("highlighted character", TSIsHighlightedFullwidthCharacter([on characterAtIndex:i]));
    for (NSUInteger i = 0; i < off.length; i++) Require("ordinary character", !TSIsHighlightedFullwidthCharacter([off characterAtIndex:i]));
    for (int i = 1; i < argc; i++) {
        NSDictionary *theme = [NSDictionary dictionaryWithContentsOfFile:@(argv[i])];
        NSDictionary *a = Attributes(theme);
        BOOL dark = Same(a[NSForegroundColorAttributeName], 0.308, 0.899, 1) && Same(a[NSBackgroundColorAttributeName], 0.1, 0, 0);
        BOOL light = Same(a[NSForegroundColorAttributeName], 0.692, 0.101, 0) && Same(a[NSBackgroundColorAttributeName], 0.9, 1, 1);
        BOOL expectDark = [@[@"DarkTheme", @"DarkTheme 2", @"Dracula", @"PreTeXt-Dark", @"SolarizedDark"] containsObject:@(argv[i]).lastPathComponent.stringByDeletingPathExtension];
        Require(argv[i], expectDark ? dark : light);
    }
    if (failures) return 1;
    printf("PASS: fullwidth highlight from theme keys only, %d bundled themes\n", argc - 1);
} return 0; }
'''.replace('READERS', readers).replace('MEMBERSHIP', membership).replace('BLOCK', block)
themes = sorted((root / 'Resources/TeXShop/Themes').glob('*.plist')) + sorted((root / 'Resources/Themes').glob('*.plist'))
assert len(themes) == 12
with tempfile.TemporaryDirectory(prefix='texshop-fullwidth-') as tmp:
    (Path(tmp) / 'test.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', str(Path(tmp) / 'test.m'), '-o', str(Path(tmp) / 'test')], check=True)
    result = subprocess.run([str(Path(tmp) / 'test'), *map(str, themes)], capture_output=True, text=True)
    print(result.stdout, end='')
    if result.returncode:
        sys.exit(f'FAIL ({mutation or "production"})')
# The rest of every bundled theme is unchanged by the two new keys.
for theme in themes:
    text = theme.read_text()
    assert len(re.findall(r'<key>EditorHighlightZenkakuSymbol(?:Background)?</key>', text)) == 2, theme
