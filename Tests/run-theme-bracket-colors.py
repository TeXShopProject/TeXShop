#!/usr/bin/env python3
"""Bracket colors fall back to the marker color, then to the built-in default,
in both the document and the Preferences color wells, which show the theme
being edited rather than the applied one."""
from pathlib import Path
import plistlib, re, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]

from production_fragments import method, verify_embedded

support = (root / 'Sources/Editor/TSColorSupport.m').read_text(encoding='latin-1')
signatures = ['- (NSArray *) colorArrayFromDictionary:', '- (NSColor *) colorFromDictionary:',
              '- (NSColor *)liteColorWithKey:', '- (NSColor *)darkColorWithKey:',
              '- (NSColor *)liteColorAndAlphaWithKey:', '- (NSColor *)darkColorAndAlphaWithKey:',
              '- (NSColor *)colorForKey: (NSString *)theKey fromDictionary:',
              '- (NSColor *)colorForKey: (NSString *)theKey isWindowDark:']
methods = [method(support, s) for s in signatures if s in support]
document_source = (root / 'Sources/Editor/TSDocument-Color.m').read_text(encoding='latin-1')
document=document_source
start = document.index('mySyntaxColor = [[TSColorSupport sharedInstance] colorFromDictionary:colorDictionary andKey: @"SyntaxMarkerParen"];')
end = document.index('\n', document.index('self.markerColorSquareAttribute =', start)) + 1
document = document[start:end]
prefs = (root / 'Sources/Settings/TSPreferences-Color.m').read_text(encoding='latin-1')
helper = method(prefs, '- (NSColor *)editingColorForKey:') if '- (NSColor *)editingColorForKey:' in prefs else ''
wells = re.search(r'^[ \t]*markerParenColorWell\.color = .*?^[ \t]*markerSquareColorWell\.color = [^\n]*\n', method(prefs, '- (void)FillInColorWells'), re.M | re.S).group(0)

fragments=[('complete method:'+m.split('{')[0],support,m) for m in methods]+[('document bracket assignments',document_source,document),('editing helper',prefs,helper),('editing wells',prefs,wells)]
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation == 'no-fallback':
    methods = [m.replace('theColorArray = [theDictionary objectForKey: @"SyntaxMarker"];', ';') for m in methods]
elif mutation == 'no-well-fallback':
    methods = [m.replace('[self colorArrayFromDictionary: theDictionary andKey: theKey]', '[theDictionary objectForKey: theKey]')
               if m.startswith('- (NSColor *)colorForKey:') else m for m in methods]
elif mutation == 'wells-read-applied-theme':
    assert 'fromDictionary: EditingColors' in helper
    helper = helper.replace('fromDictionary: EditingColors', 'fromDictionary: (withDarkColors ? darkColors : liteColors)')
elif mutation == 'no-default':
    document = document.replace('if (mySyntaxColor == nil)', 'if (0)')
elif mutation:
    raise SystemExit('unknown mutation ' + mutation)

program = r'''
#import <Cocoa/Cocoa.h>
#define MOJAVEORHIGHER
NSDictionary *liteColors, *darkColors;
BOOL atLeastMojave = YES;
@interface FakeAppearance : NSObject @property NSAppearanceName name; @end
@implementation FakeAppearance @end
@interface FakeWindow : NSObject @property BOOL keyWindow; @property FakeAppearance *effectiveAppearance; @end
@implementation FakeWindow @end
@interface TSColorSupport : NSObject @end
@implementation TSColorSupport
+ (id)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
METHODS
@end
@interface Well : NSObject @property NSColor *color; @end
@implementation Well @end
@interface Document : NSObject
@property NSDictionary *markerColorParenAttribute, *markerColorCurlyAttribute, *markerColorSquareAttribute;
@end
@implementation Document
- (void)applyDictionary:(NSDictionary *)colorDictionary dark:(BOOL)withDarkColors
{
    NSColor *mySyntaxColor;
DOCUMENT
}
@end
@interface Prefs : NSObject { @public Well *markerParenColorWell, *markerCurlyColorWell, *markerSquareColorWell; NSMutableDictionary *EditingColors; FakeWindow *_prefsWindow; }
@end
@implementation Prefs
HELPER
- (void)fillDark:(BOOL)withDarkColors
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
WELLS
}
@end
static BOOL Same(NSColor *c, NSArray *a) {
    return c && fabs(c.redComponent - [a[0] doubleValue]) < 1e-3 && fabs(c.greenComponent - [a[1] doubleValue]) < 1e-3 && fabs(c.blueComponent - [a[2] doubleValue]) < 1e-3;
}
static NSString *Describe(NSColor *c) {
    return c ? [NSString stringWithFormat:@"(%.3f %.3f %.3f)", c.redComponent, c.greenComponent, c.blueComponent] : @"nil";
}
int main(int argc, char **argv) { @autoreleasepool {
    TSColorSupport *colors = [TSColorSupport sharedInstance]; int failures = 0;
    NSArray *marker = @[@0.1, @0.6, @0.5, @1], *explicitColor = @[@0.9, @0.2, @0.3, @1], *decoy = @[@0.4, @0.4, @0.9, @1];
    NSArray *builtIn[2] = { @[@0.02, @0.51, @0.13], @[@0.968, @0.578, @0.911] };
    NSArray *keys = @[@"SyntaxMarkerParen", @"SyntaxMarkerCurly", @"SyntaxMarkerSquare"];
    NSDictionary *decoyTheme = @{@"SyntaxMarker": decoy, @"SyntaxMarkerParen": decoy, @"SyntaxMarkerCurly": decoy, @"SyntaxMarkerSquare": decoy};
    for (int dark = 0; dark < 2; dark++) {
        const char *mode = dark ? "dark" : "light";
        for (NSString *key in keys) {
            NSArray *cases = @[
                @[@"explicit bracket key", @{@"SyntaxMarker": marker, key: explicitColor}, explicitColor],
                @[@"marker only", @{@"SyntaxMarker": marker, @"SyntaxCommand": decoy}, marker],
                @[@"no marker colors", @{@"SyntaxCommand": decoy}, builtIn[dark]]];
            for (NSArray *c in cases) {
                NSDictionary *theme = c[1]; NSArray *expected = c[2];
                Document *doc = [Document new];
                [doc applyDictionary:theme dark:dark];
                NSDictionary *attrs = @{@"SyntaxMarkerParen": doc.markerColorParenAttribute ?: @{}, @"SyntaxMarkerCurly": doc.markerColorCurlyAttribute ?: @{}, @"SyntaxMarkerSquare": doc.markerColorSquareAttribute ?: @{}};
                NSColor *docColor = attrs[key][NSForegroundColorAttributeName];
                // The bracket wells show the theme being edited, not the applied ones.
                liteColors = darkColors = decoyTheme;
                Prefs *prefs = [Prefs new];
                prefs->_prefsWindow = [FakeWindow new]; prefs->_prefsWindow.effectiveAppearance = [FakeAppearance new];
                prefs->_prefsWindow.effectiveAppearance.name = dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua;
                prefs->EditingColors = [theme mutableCopy];
                prefs->markerParenColorWell = [Well new]; prefs->markerCurlyColorWell = [Well new]; prefs->markerSquareColorWell = [Well new];
                [prefs fillDark:dark];
                NSDictionary *wellsByKey = @{@"SyntaxMarkerParen": prefs->markerParenColorWell, @"SyntaxMarkerCurly": prefs->markerCurlyColorWell, @"SyntaxMarkerSquare": prefs->markerSquareColorWell};
                NSColor *wellColor = [wellsByKey[key] color];
                if (!Same(docColor, expected)) { printf("FAIL: document %s %s %s: %s\n", mode, key.UTF8String, [c[0] UTF8String], Describe(docColor).UTF8String); failures++; }
                if (!Same(wellColor, expected)) { printf("FAIL: color well %s %s %s: %s\n", mode, key.UTF8String, [c[0] UTF8String], Describe(wellColor).UTF8String); failures++; }
                if (![prefs->EditingColors isEqual:theme]) { printf("FAIL: filling the wells changed the edited theme (%s %s %s)\n", mode, key.UTF8String, [c[0] UTF8String]); failures++; }
            }
        }
        liteColors = darkColors = @{@"SyntaxMarker": marker};
        if (!Same([colors colorForKey:@"explFunction" isWindowDark:dark], dark ? @[@0.57, @0.57, @0] : @[@0, @0.1, @0.57])) { printf("FAIL: %s non-bracket well uses the marker color\n", mode); failures++; }
    }
    if ([colors colorFromDictionary:@{} andKey:@"SyntaxMarkerCurly"] != nil) { printf("FAIL: empty theme should give nil\n"); failures++; }
    if ([colors colorFromDictionary:@{@"SyntaxMarker": marker} andKey:@"EditorFlash"] != nil) { printf("FAIL: other missing keys must stay nil\n"); failures++; }
    for (int i = 1; i < argc; i++) {
        NSDictionary *theme = [NSDictionary dictionaryWithContentsOfFile:@(argv[i])];
        if (theme[@"SyntaxMarker"] && !theme[@"SyntaxMarkerCurly"] && !Same([colors colorFromDictionary:theme andKey:@"SyntaxMarkerCurly"], theme[@"SyntaxMarker"])) {
            printf("FAIL: legacy theme %s\n", argv[i]); failures++;
        }
    }
    return failures ? 1 : 0;
} }
'''.replace('METHODS', '\n'.join(methods)).replace('DOCUMENT', document).replace('HELPER', helper).replace('WELLS', wells)
if not mutation:verify_embedded(program,fragments)
else:
    for label,source,fragment in fragments:assert source.count(fragment)==1,(label,'mutation baseline')
with tempfile.TemporaryDirectory(prefix='texshop-theme-') as tmp:
    tmp = Path(tmp)
    legacy = tmp / 'Legacy.plist'
    plistlib.dump({'SyntaxMarker': [0.165, 0.63, 0.596, 1.0], 'SyntaxCommand': [0.8, 0.2, 0.2, 1.0]}, legacy.open('wb'))
    themes = [str(legacy)] + [str(p) for p in sorted((root / 'Resources/TeXShop/Themes').glob('*.plist'))]
    (tmp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', str(tmp / 'test.m'), '-o', str(tmp / 'test')], check=True)
    r = subprocess.run([str(tmp / 'test')] + themes, capture_output=True, text=True)
    print(r.stdout.strip())
    if mutation:
        if r.returncode == 0: raise SystemExit('FAIL: mutation %s was not detected' % mutation)
        print('detected mutation', mutation)
    elif r.returncode: raise SystemExit(r.stderr or 'FAIL')
    else: print('PASS: document and color wells use the edited bracket key, then SyntaxMarker, then the built-in default')
