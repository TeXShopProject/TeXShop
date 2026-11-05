#!/usr/bin/env python3
"""Themes without per-bracket colors color brackets with the marker color."""
from pathlib import Path
import plistlib, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/TSColorSupport.m').read_text(encoding='latin-1')
start = source.index('- (NSColor *) colorFromDictionary:(NSDictionary *)theDictionary andKey:')
method = source[start:source.index('\n}\n', start) + 3]
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation == 'no-fallback':
    method = method.replace('theColorArray = [theDictionary objectForKey: @"SyntaxMarker"];', ';')
program = r'''
#import <Cocoa/Cocoa.h>
@interface Colors : NSObject @end
@implementation Colors
METHOD
@end
static BOOL Same(NSColor *c, NSArray *a) {
    return c && fabs(c.redComponent - [a[0] doubleValue]) < 1e-6 && fabs(c.greenComponent - [a[1] doubleValue]) < 1e-6 && fabs(c.blueComponent - [a[2] doubleValue]) < 1e-6;
}
int main(int argc, char **argv) { @autoreleasepool {
    Colors *colors = [Colors new]; int failures = 0;
    NSArray *marker = @[@0.1, @0.6, @0.5, @1], *curly = @[@0.9, @0.2, @0.3, @1];
    NSDictionary *legacy = @{@"SyntaxMarker": marker}, *current = @{@"SyntaxMarker": marker, @"SyntaxMarkerCurly": curly};
    for (NSString *key in @[@"SyntaxMarkerParen", @"SyntaxMarkerCurly", @"SyntaxMarkerSquare"])
        if (!Same([colors colorFromDictionary:legacy andKey:key], marker)) { printf("FAIL: %s does not fall back to SyntaxMarker\n", key.UTF8String); failures++; }
    if (!Same([colors colorFromDictionary:current andKey:@"SyntaxMarkerCurly"], curly)) { printf("FAIL: theme bracket color ignored\n"); failures++; }
    if ([colors colorFromDictionary:@{} andKey:@"SyntaxMarkerCurly"] != nil) { printf("FAIL: empty theme should give nil\n"); failures++; }
    if ([colors colorFromDictionary:legacy andKey:@"EditorFlash"] != nil) { printf("FAIL: other missing keys must stay nil\n"); failures++; }
    for (int i = 1; i < argc; i++) {
        NSDictionary *theme = [NSDictionary dictionaryWithContentsOfFile:@(argv[i])];
        if (theme[@"SyntaxMarker"] && !theme[@"SyntaxMarkerCurly"] && !Same([colors colorFromDictionary:theme andKey:@"SyntaxMarkerCurly"], theme[@"SyntaxMarker"])) {
            printf("FAIL: legacy theme %s\n", argv[i]); failures++;
        }
    }
    return failures ? 1 : 0;
} }
'''.replace('METHOD', method)
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
    else: print('PASS: bracket colors fall back to the marker color; other missing keys stay nil')
