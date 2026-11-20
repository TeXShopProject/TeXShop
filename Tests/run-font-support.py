#!/usr/bin/env python3
"""Fonts read from the settings never come back nil or raise (Sources/Utilities/TSFontSupport.h).

A font that is not installed, a size of 0, NaN or infinity, and settings data that is damaged, of another class or
not data at all give the fallback, or nil where the caller has its own; text views and the Font panel raise when given
nil. --mutations checks that the guards are needed."""
from pathlib import Path
import subprocess, sys, tempfile
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
header = (root / 'Sources/Utilities/TSFontSupport.h').read_text()
MUTATIONS = {
    'not-installed': ('return [NSFont fontWithName:(NSString *)name size:size] ?: fallback;', 'return [NSFont fontWithName:(NSString *)name size:size];'),
    'size': ("[(NSString *)name length] == 0 || !(size > 0) || !isfinite(size))", "[(NSString *)name length] == 0)"),
    'damaged-data': ('    } @catch (NSException *exception) {\n        object = nil;\n    }', '    } @finally {\n    }'),
    'class': ('return [object isKindOfClass:expected] ? object : nil;', 'return object;'),
}
PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TSFontSupport.h"
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { failures++; printf("FAIL: %s\n", what.UTF8String); } }
int main(void) { @autoreleasepool {
    NSFont *fallback = [NSFont userFixedPitchFontOfSize:11];
    Check(TSFontNamed(@"No Such Font 93762", 12, fallback) == fallback, @"a font that is not installed gives the fallback");
    Check(TSFontNamed(nil, 12, fallback) == fallback && TSFontNamed(@"", 12, fallback) == fallback && TSFontNamed(@42, 12, fallback) == fallback, @"no name, an empty name or a name that is not text gives the fallback");
    for (NSNumber *size in @[@0, @(-3), @(NAN), @(INFINITY)])
        Check(TSFontNamed(@"Menlo", size.doubleValue, fallback) == fallback, [NSString stringWithFormat:@"a size of %@ gives the fallback", size]);
    NSFont *menlo = TSFontNamed(@"Menlo-Regular", 13, fallback);
    Check([menlo.fontName isEqualToString:@"Menlo-Regular"] && menlo.pointSize == 13, @"an installed font is used");
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"TSFontSupportTest-93762"];
    [defaults removePersistentDomainForName:@"TSFontSupportTest-93762"];
    [defaults setObject:@"No Such Font 93762" forKey:@"Name"]; [defaults setFloat:0 forKey:@"Size"];
    NSFont *console = TSConsoleFontFromDefaults(defaults, @"Name", @"Size");
    Check(console != nil && console.pointSize == 12, @"a console font that is not installed, of size 0, gives a fixed-pitch font of 12 points");
    [defaults removePersistentDomainForName:@"TSFontSupportTest-93762"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData *archived = [NSArchiver archivedDataWithRootObject:[NSFont userFontOfSize:14]];
    NSData *notFont = [NSArchiver archivedDataWithRootObject:@"text"];
#pragma clang diagnostic pop
    Check([TSArchivedFont(archived) pointSize] == 14, @"an archived font is read");
    Check(TSArchivedFont([@"damaged 93762" dataUsingEncoding:NSUTF8StringEncoding]) == nil, @"damaged data gives nil");
    // An archive cut short (a damaged settings file): NSUnarchiver raises.
    Check(TSArchivedFont([archived subdataWithRange:NSMakeRange(0, archived.length / 2)]) == nil, @"an archive cut short gives nil");
    Check(TSArchivedFont(notFont) == nil, @"an archive of another class gives nil");
    Check(TSArchivedFont(@"text") == nil && TSArchivedFont(nil) == nil && TSArchivedFont(@[]) == nil, @"a value that is not data gives nil");
    Check(TSUnarchivedObject(archived, NSDictionary.class) == nil, @"a font is not taken for attributes");
    if (!failures) puts("PASS: fonts read from the settings fall back instead of being nil or raising");
    return failures ? 1 : 0;
} }
'''

def run(text):
    with tempfile.TemporaryDirectory(prefix='texshop-font-support-') as temp:
        t = Path(temp)
        (t / 'TSFontSupport.h').write_text(text)
        (t / 'probe.m').write_text(PROGRAM)
        build = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-unused-function', '-mmacosx-version-min=14.6',
                                '-I', str(t), *include_args(root), '-framework', 'Cocoa', str(t / 'probe.m'), '-o', str(t / 'probe')],
                               capture_output=True, text=True)
        if build.returncode:
            return 2, build.stderr
        result = subprocess.run([str(t / 'probe')], capture_output=True, text=True, timeout=60)
        return result.returncode, result.stdout + result.stderr

if '--mutations' in sys.argv:
    for name, (old, new) in MUTATIONS.items():
        if old not in header:
            raise SystemExit(f'FAIL: mutation {name} does not apply')
        code, output = run(header.replace(old, new, 1))
        if code == 0:
            raise SystemExit(f'FAIL: mutation {name} was not detected')
        print('detected mutation', name)
code, output = run(header)
print(output.strip())
raise SystemExit(code)
