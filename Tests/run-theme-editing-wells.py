#!/usr/bin/env python3
"""The bracket and expl3 color wells in the Themes tab show the theme being
edited rather than the applied one."""
from pathlib import Path
import re, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]

def method(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n}\n', start) + 3]

support = (root / 'Sources/TSColorSupport.m').read_text(encoding='latin-1')
signatures = ['- (NSArray *) colorArrayFromDictionary:', '- (NSColor *) colorFromDictionary:',
              '- (NSColor *) colorAndAlphaFromDictionary:',
              '- (NSColor *)liteColorWithKey:', '- (NSColor *)darkColorWithKey:',
              '- (NSColor *)liteColorAndAlphaWithKey:', '- (NSColor *)darkColorAndAlphaWithKey:',
              '- (NSColor *)colorForKey: (NSString *)theKey fromDictionary:',
              '- (NSColor *)colorForKey: (NSString *)theKey isWindowDark:',
              '- (void)changeColorValueInDictionary:']
methods = [method(support, s) for s in signatures if s in support]

prefs = (root / 'Sources/TSPreferences-Color.m').read_text(encoding='latin-1')
helpers = [method(prefs, s) for s in ['- (NSColor *)editingColorForKey:', '- (void)refreshInheritedBracketColorWells']
           if s in prefs]
wells = re.search(r'^[ \t]*markerParenColorWell\.color = .*?^[ \t]*explmsgColorWell\.color = [^\n]*\n',
                  method(prefs, '- (void)FillInColorWells'), re.M | re.S).group(0)
actionNames = ['SyntaxMarkerColorChanged', 'markerParenColorChanged', 'markerCurlyColorChanged', 'markerSquareColorChanged',
               'explFunctionColorChanged', 'explVariableColorChanged', 'explIntenseFunctionColorChanged',
               'explIntenseVariableColorChanged', 'explmykeyColorChanged', 'explmykeyArgumentColorChanged', 'explmsgColorChanged']
actions = [method(prefs, '- (IBAction)%s:sender' % name) for name in actionNames]

mutation = sys.argv[1] if len(sys.argv) > 1 else ''
def mutate(parts, old, new):
    if not any(old in p for p in parts): raise SystemExit('mutation %s does not apply to these sources' % mutation)
    return [p.replace(old, new) for p in parts]
if mutation == 'wells-read-applied-theme':
    helpers = mutate(helpers, 'fromDictionary: EditingColors', 'fromDictionary: (withDarkColors ? darkColors : liteColors)')
elif mutation == 'default-ignores-appearance':
    helpers = mutate(helpers, 'isWindowDark: withDarkColors]', 'isWindowDark: NO]')
elif mutation:
    raise SystemExit('unknown mutation ' + mutation)

# The color panel is replaced by a stub so the probe never opens a real panel.
actions = [a.replace('[NSColorPanel sharedColorPanel]', 'colorPanel') for a in actions]

program = r'''
#import <Cocoa/Cocoa.h>
#define MOJAVEORHIGHER
NSDictionary *liteColors, *darkColors;
BOOL atLeastMojave = YES;
NSString *SourceColorChangedNotification = @"ProbeSourceColorChangedNotification";
@interface FakeAppearance : NSObject @property NSAppearanceName name; @end
@implementation FakeAppearance @end
@interface FakeWindow : NSObject @property BOOL keyWindow; @property FakeAppearance *effectiveAppearance; @property int closed; - (void)close; @end
@implementation FakeWindow - (void)close { self.closed++; } @end
FakeWindow *colorPanel;
@interface TSColorSupport : NSObject @end
@implementation TSColorSupport
+ (id)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
METHODS
@end
@interface Well : NSObject @property NSColor *color; @end
@implementation Well @end
@interface Prefs : NSObject { @public
    Well *SyntaxMarkerColorWell, *markerParenColorWell, *markerCurlyColorWell, *markerSquareColorWell;
    Well *explFunctionColorWell, *explVariableColorWell, *explIntenseFunctionColorWell, *explIntenseVariableColorWell;
    Well *explmykeyColorWell, *explmykeyArgumentColorWell, *explmsgColorWell;
    NSMutableDictionary *EditingColors; FakeWindow *_prefsWindow; }
@end
@implementation Prefs
HELPERS
- (void)fillDark:(BOOL)withDarkColors
{
    TSColorSupport *colorSupport = [TSColorSupport sharedInstance];
WELLS
}
ACTIONS
@end
static BOOL Same(NSColor *c, NSArray *a) {
    return c && fabs(c.redComponent - [a[0] doubleValue]) < 1e-3 && fabs(c.greenComponent - [a[1] doubleValue]) < 1e-3 && fabs(c.blueComponent - [a[2] doubleValue]) < 1e-3;
}
static NSArray *Components(NSColor *c) { return @[@(c.redComponent), @(c.greenComponent), @(c.blueComponent), @1]; }
static NSString *Describe(NSColor *c) {
    return c ? [NSString stringWithFormat:@"(%.3f %.3f %.3f)", c.redComponent, c.greenComponent, c.blueComponent] : @"nil";
}
static NSColor *Color(NSArray *a) { return [NSColor colorWithRed:[a[0] doubleValue] green:[a[1] doubleValue] blue:[a[2] doubleValue] alpha:1]; }
static NSArray *bracketKeys, *explKeys;
static Prefs *MakePrefs(NSDictionary *theme, BOOL dark) {
    Prefs *p = [Prefs new];
    p->_prefsWindow = [FakeWindow new]; p->_prefsWindow.effectiveAppearance = [FakeAppearance new];
    p->_prefsWindow.effectiveAppearance.name = dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua;
    p->_prefsWindow.keyWindow = YES;
    p->EditingColors = [theme mutableCopy];
    p->SyntaxMarkerColorWell = [Well new];
    p->markerParenColorWell = [Well new]; p->markerCurlyColorWell = [Well new]; p->markerSquareColorWell = [Well new];
    p->explFunctionColorWell = [Well new]; p->explVariableColorWell = [Well new]; p->explIntenseFunctionColorWell = [Well new];
    p->explIntenseVariableColorWell = [Well new]; p->explmykeyColorWell = [Well new]; p->explmykeyArgumentColorWell = [Well new];
    p->explmsgColorWell = [Well new];
    return p;
}
static NSDictionary *WellsByKey(Prefs *p) {
    return @{@"SyntaxMarkerParen": p->markerParenColorWell, @"SyntaxMarkerCurly": p->markerCurlyColorWell, @"SyntaxMarkerSquare": p->markerSquareColorWell,
             @"explFunction": p->explFunctionColorWell, @"explVariable": p->explVariableColorWell, @"explIntenseFunction": p->explIntenseFunctionColorWell,
             @"explIntenseVariable": p->explIntenseVariableColorWell, @"explmykey": p->explmykeyColorWell,
             @"explmykeyArgument": p->explmykeyArgumentColorWell, @"explmsg": p->explmsgColorWell};
}
static NSDictionary *ActionsByKey(void) {
    return @{@"SyntaxMarkerParen": @"markerParenColorChanged:", @"SyntaxMarkerCurly": @"markerCurlyColorChanged:", @"SyntaxMarkerSquare": @"markerSquareColorChanged:",
             @"explFunction": @"explFunctionColorChanged:", @"explVariable": @"explVariableColorChanged:", @"explIntenseFunction": @"explIntenseFunctionColorChanged:",
             @"explIntenseVariable": @"explIntenseVariableColorChanged:", @"explmykey": @"explmykeyColorChanged:",
             @"explmykeyArgument": @"explmykeyArgumentColorChanged:", @"explmsg": @"explmsgColorChanged:"};
}
int main(int argc, char **argv) { @autoreleasepool {
    TSColorSupport *colors = [TSColorSupport sharedInstance]; int failures = 0;
    bracketKeys = @[@"SyntaxMarkerParen", @"SyntaxMarkerCurly", @"SyntaxMarkerSquare"];
    explKeys = @[@"explFunction", @"explVariable", @"explIntenseFunction", @"explIntenseVariable", @"explmykey", @"explmykeyArgument", @"explmsg"];
    NSArray *allKeys = [bracketKeys arrayByAddingObjectsFromArray:explKeys];
    NSArray *marker = @[@0.1, @0.6, @0.5, @1], *newMarker = @[@0.7, @0.15, @0.05, @1], *decoy = @[@0.4, @0.4, @0.9, @1];
    NSArray *userPick = @[@0.33, @0.77, @0.11, @1];
    NSMutableDictionary *decoyTheme = [NSMutableDictionary dictionaryWithObject:decoy forKey:@"SyntaxMarker"];
    for (NSString *key in allKeys) decoyTheme[key] = decoy;
    NSMutableDictionary *explicitTheme = [NSMutableDictionary dictionaryWithObject:marker forKey:@"SyntaxMarker"];
    for (NSUInteger i = 0; i < allKeys.count; i++) explicitTheme[allKeys[i]] = @[@(0.05 + 0.08 * i), @(0.9 - 0.07 * i), @(0.3 + 0.05 * i), @1];
    NSArray *themes = @[@[@"explicit keys", explicitTheme], @[@"marker only", @{@"SyntaxMarker": marker, @"SyntaxCommand": decoy}],
                        @[@"no marker or expl3 colors", @{@"SyntaxCommand": decoy}]];
    // The applied themes differ from the one being edited.
    liteColors = darkColors = decoyTheme;
    colorPanel = [FakeWindow new];

    for (int dark = 0; dark < 2; dark++) {
        const char *mode = dark ? "dark" : "light";
        for (NSArray *t in themes) {
            NSDictionary *theme = t[1];
            NSDictionary *(^expectedFor)(void) = ^{
                NSMutableDictionary *e = [NSMutableDictionary dictionary];
                for (NSString *key in allKeys) {
                    NSArray *a = theme[key];
                    if (!a && [bracketKeys containsObject:key]) a = theme[@"SyntaxMarker"];
                    e[key] = a ?: Components(dark ? [colors darkColorWithKey:key] : [colors liteColorWithKey:key]);
                }
                return e;
            };
            NSDictionary *expected = expectedFor();

            // Wells show the edited theme.
            Prefs *p = MakePrefs(theme, dark);
            [p fillDark:dark];
            for (NSString *key in allKeys) {
                NSColor *c = [WellsByKey(p)[key] color];
                if (!Same(c, expected[key])) { printf("FAIL: %s %s well %s: %s\n", mode, [t[0] UTF8String], key.UTF8String, Describe(c).UTF8String); failures++; }
            }
            if (![p->EditingColors isEqual:theme]) { printf("FAIL: %s %s filling the wells changed the edited theme\n", mode, [t[0] UTF8String]); failures++; }

        }

    }
    return failures ? 1 : 0;
} }
'''.replace('METHODS', '\n'.join(methods)).replace('HELPERS', '\n'.join(helpers)).replace('WELLS', wells).replace('ACTIONS', '\n'.join(actions))
with tempfile.TemporaryDirectory(prefix='texshop-theme-') as tmp:
    tmp = Path(tmp)
    (tmp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', str(tmp / 'test.m'), '-o', str(tmp / 'test')], check=True)
    r = subprocess.run([str(tmp / 'test')], capture_output=True, text=True)
    print(r.stdout.strip())
    if mutation:
        if r.returncode == 0: raise SystemExit('FAIL: mutation %s was not detected' % mutation)
        print('detected mutation', mutation)
    elif r.returncode: raise SystemExit(r.stderr or 'FAIL')
    else: print('PASS: theme color wells follow the edited theme')
