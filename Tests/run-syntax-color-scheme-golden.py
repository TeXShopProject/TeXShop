#!/usr/bin/env python3
"""The colors that a theme gives syntax coloring stay exactly the same.

-[TSDocument changeColorsUsingDictionary:] turns a theme into the attribute
dictionaries of syntax coloring: commands, comments, the marker and the three
kinds of brackets, index, footnote, the seven expl3 colors, the five XML colors,
the fullwidth highlight, the active line, and the brace and content highlights.
Every bundled theme, the reserve copies of Lite and Dark, and two made-up themes
that lack the newer keys are applied in a light and a dark window. The color
space, components and alpha of every color are compared with
Tests/Fixtures/SyntaxColorSchemeGolden.txt.

The production method and the color look-ups of TSColorSupport are compiled
unchanged onto a small TSDocument stand-in. No window is created.

  --update         rewrite the golden file from the current sources
  --mutation NAME  check that a change of the colors is detected
"""
from pathlib import Path
import argparse, plistlib, re, subprocess, sys, tempfile
from source_tree import include_args
from production_fragments import method

ROOT = Path(__file__).resolve().parents[1]
COLOR = 'Sources/Editor/TSDocument-Color.m'
SUPPORT = 'Sources/Editor/TSColorSupport.m'
GOLDEN = ROOT / 'Tests/Fixtures/SyntaxColorSchemeGolden.txt'

MUTATIONS = {
    # Footnotes fall back to the comment color instead of the command color.
    'footnote-fallback': (COLOR, 'mySyntaxColor = [[TSColorSupport sharedInstance] colorFromDictionary:colorDictionary andKey: @"SyntaxCommand"];\n    /*',
                          'mySyntaxColor = [[TSColorSupport sharedInstance] colorFromDictionary:colorDictionary andKey: @"SyntaxComment"];\n    /*'),
    # The built-in defaults of a dark window are not used.
    'no-dark-defaults': (COLOR, 'withDarkColors = YES;', 'withDarkColors = NO;'),
    # A transparent fullwidth background is added after all.
    'transparent-fullwidth-background': (COLOR, 'if (myColor && myColor.alphaComponent > 0)', 'if (myColor)'),
}
parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
group = parser.add_mutually_exclusive_group()
group.add_argument('--update', action='store_true')
group.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

text = {path: (ROOT / path).read_text(encoding='latin1') for path in (COLOR, SUPPORT)}
if args.mutation:
    path, old, new = MUTATIONS[args.mutation]
    assert text[path].count(old) == 1, args.mutation
    text[path] = text[path].replace(old, new)

change_colors = method(text[COLOR], '- (void) changeColorsUsingDictionary: (NSDictionary *)colorDictionary')
support = '\n'.join(method(text[SUPPORT], s) for s in [
    '- (NSArray *) colorArrayFromDictionary:', '- (NSColor *) colorFromDictionary:', '- (NSColor *) colorAndAlphaFromDictionary:',
    '- (NSColor *)liteColorWithKey:', '- (NSColor *)darkColorWithKey:',
    '- (NSColor *)liteColorAndAlphaWithKey:', '- (NSColor *)darkColorAndAlphaWithKey:'])

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TSThemeAlpha.h"
#define MOJAVEORHIGHER
BOOL atLeastMojave = YES;
NSDictionary *liteColors, *darkColors, *highlightBracesColorDict, *highlightContentColorDict;
NSColor *PreviewBackgroundColor, *ReverseSyncColor, *InvisibleColor, *ImageForegroundColor, *ImageBackgroundColor, *PreviewDirectSyncColor;

@interface TSColorSupport : NSObject
@end
@implementation TSColorSupport
+ (id)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
@@SUPPORT@@
@end

// The source window: only its appearance is read.
@interface FakeAppearance : NSObject
@property (copy) NSAppearanceName name;
@end
@implementation FakeAppearance
@end
@interface FakeWindow : NSObject
@property (strong) FakeAppearance *effectiveAppearance;
@property CGFloat alphaValue;
- (void)display;
@end
@implementation FakeWindow
- (void)display {}
@end

@interface TSDocument : NSObject {
    @public
    NSTextView *textView1, *textView2, *outputText;
    FakeWindow *textWindow, *fullSplitWindow, *outputWindow;
}
@property (strong) NSDictionary *EntryColorAttribute, *commandColorAttribute, *commentColorAttribute,
    *explColorAttribute1, *explColorAttribute2, *explColorAttribute3, *explColorAttribute4, *explColorAttribute5,
    *explColorAttribute6, *explColorAttribute7, *footnoteColorAttribute, *fullwidthSymbolColorAttribute,
    *indexColorAttribute, *markerColorAttribute, *markerColorCurlyAttribute, *markerColorParenAttribute,
    *markerColorSquareAttribute, *commentXMLColorAttribute, *tagXMLColorAttribute,
    *specialXMLColorAttribute, *parameterXMLColorAttribute, *valueXMLColorAttribute;
@property (strong) NSTextView *logTextView;
@property (strong) FakeWindow *logWindow, *pdfKitWindow;
@property (strong) NSView *myPDFKitView, *myPDFKitView2;
@end
@implementation TSDocument
- (void)colorizeVisibleAreaInTextView:(NSTextView *)view {}
- (void)colorizeExperimentSource {}
@@CHANGE_COLORS@@
@end

static NSString *Describe(NSColor *color)
{
    if (!color) return @"none";
    CGColorRef cg = color.CGColor;
    CFStringRef space = CGColorSpaceCopyName(CGColorGetColorSpace(cg));
    NSMutableString *out = [NSMutableString stringWithFormat:@"%@", space ? (__bridge NSString *)space : @"unnamed"];
    if (space) CFRelease(space);
    const CGFloat *components = CGColorGetComponents(cg);
    for (size_t i = 0; i < CGColorGetNumberOfComponents(cg); i++)
        [out appendFormat:@" %.4f", components[i]];
    return out;
}

static void Print(NSString *label, NSDictionary *attributes)
{
    if (!attributes) { printf("  %s nil\n", label.UTF8String); return; }
    for (NSString *key in [attributes.allKeys sortedArrayUsingSelector:@selector(compare:)])
        printf("  %s %s %s\n", label.UTF8String, key.UTF8String, Describe(attributes[key]).UTF8String);
}

int main(int argc, const char **argv) { @autoreleasepool {
    NSDictionary *themes = [NSDictionary dictionaryWithContentsOfFile:@(argv[1])];
    for (NSString *name in [themes.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        for (NSString *mode in @[@"light", @"dark"]) {
            NSDictionary *theme = themes[name];
            liteColors = theme; darkColors = theme;
            TSDocument *doc = [TSDocument new];
            doc->textView1 = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
            FakeAppearance *appearance = [FakeAppearance new];
            appearance.name = [mode isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua;
            doc->textWindow = [FakeWindow new];
            doc->textWindow.effectiveAppearance = appearance;
            [doc changeColorsUsingDictionary:theme];
            printf("== %s %s\n", name.UTF8String, mode.UTF8String);
            for (NSString *key in @[@"commandColorAttribute", @"commentColorAttribute", @"markerColorAttribute",
                                    @"markerColorParenAttribute", @"markerColorCurlyAttribute", @"markerColorSquareAttribute",
                                    @"indexColorAttribute", @"footnoteColorAttribute", @"fullwidthSymbolColorAttribute",
                                    @"EntryColorAttribute", @"explColorAttribute1", @"explColorAttribute2", @"explColorAttribute3",
                                    @"explColorAttribute4", @"explColorAttribute5", @"explColorAttribute6", @"explColorAttribute7",
                                    @"commentXMLColorAttribute", @"tagXMLColorAttribute", @"specialXMLColorAttribute",
                                    @"parameterXMLColorAttribute", @"valueXMLColorAttribute"])
                Print(key, [doc valueForKey:key]);
            Print(@"highlightBraces", highlightBracesColorDict);
            Print(@"highlightContent", highlightContentColorDict);
            printf("  editorBackground %s\n  editorText %s\n  invisible %s\n", Describe(doc->textView1.backgroundColor).UTF8String,
                   Describe(doc->textView1.textColor).UTF8String, Describe(InvisibleColor).UTF8String);
        }
    }
    return 0;
} }
'''
program = PROGRAM.replace('@@SUPPORT@@', support).replace('@@CHANGE_COLORS@@', change_colors)

themes = {}
for folder, prefix in (('Resources/TeXShop/Themes', ''), ('Resources/Themes', 'reserve-')):
    for path in sorted((ROOT / folder).glob('*.plist')):
        themes[prefix + path.stem] = plistlib.loads(path.read_bytes())
assert len(themes) == 11, sorted(themes)
lite = themes['LiteTheme']
# A theme made before the bracket, expl3, footnote, XML and fullwidth keys existed.
themes['made-up-old'] = {key: lite[key] for key in ('EditorBackground', 'EditorText', 'SyntaxComment', 'SyntaxCommand',
                                                    'SyntaxMarker', 'SyntaxIndex', 'EditorHighlightBraces',
                                                    'EditorHighlightContent', 'EditorInvisibleChar') if key in lite}
# Only the marker color among the brackets, a transparent fullwidth background and an opaque one given with three values.
partial = dict(lite)
for key in ('SyntaxMarkerParen', 'SyntaxMarkerCurly', 'SyntaxMarkerSquare', 'SyntaxIndex', 'FootnoteColor', 'EntryColor', 'XMLTag', 'explmsg'):
    partial.pop(key, None)
partial['EditorHighlightZenkakuSymbolBackground'] = [0.2, 0.4, 0.6, 0]
themes['made-up-partial'] = partial
three = dict(lite)
three['EditorHighlightZenkakuSymbolBackground'] = [0.2, 0.4, 0.6]
three.pop('EditorHighlightZenkakuSymbol', None)
themes['made-up-three-values'] = three

with tempfile.TemporaryDirectory(prefix='texshop-syntax-scheme-golden-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='utf-8')
    (tmp / 'themes.plist').write_bytes(plistlib.dumps(themes))
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', *include_args(ROOT),
                    str(tmp / 'probe.m'), '-o', str(tmp / 'probe')], check=True)
    result = subprocess.run([str(tmp / 'probe'), str(tmp / 'themes.plist')], capture_output=True, text=True, timeout=120)
if result.returncode:
    sys.exit('FAIL: ' + result.stderr)
record = f'# Syntax coloring colors of {len(themes)} themes. Rewrite with run-syntax-color-scheme-golden.py --update.\n' + result.stdout
if args.update:
    GOLDEN.write_text(record, encoding='utf-8')
    print(f'Wrote {GOLDEN.relative_to(ROOT)} ({len(themes)} themes)')
    sys.exit(0)
expected = GOLDEN.read_text(encoding='utf-8')
if record != expected:
    current, theme = {}, None
    differences = []
    old_lines, new_lines = expected.splitlines(), record.splitlines()
    for old, new in zip(old_lines, new_lines):
        if new.startswith('== '):
            theme = new[3:]
        if old != new:
            differences.append(f'{theme}: {old.strip()} -> {new.strip()}')
    if len(old_lines) != len(new_lines):
        differences.append(f'{len(old_lines)} lines -> {len(new_lines)} lines')
    for line in differences[:10]:
        print('FAIL: ' + line)
    if args.mutation:
        print(f'PASS: detected mutation {args.mutation}')
        sys.exit(0)
    sys.exit(f'FAIL: the colors of {len(differences)} entries changed')
if args.mutation:
    sys.exit(f'FAIL: mutation {args.mutation} was not detected')
print(f'PASS: the syntax coloring colors of {len(themes)} themes in light and dark windows are unchanged')
