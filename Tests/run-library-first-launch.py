#!/usr/bin/env python3
"""First launch fills ~/Library/TeXShop from the copy inside TeXShop.

The production mirrorPath:toPath: of TSAppDelegate and HelpDocuments run verbatim, on folders in a temporary
directory:
- a home without a Library folder gets ~/Library/TeXShop with its parents;
- a folder that cannot be created gives one alert that names it and the cause, without an exception.
Replaced here: NSRunAlertPanel (records its arguments and formats the message as AppKit does, raising for a nil
format as AppKit does). Removing each rule must fail."""
from pathlib import Path
import plistlib, subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
delegate = source_file(root, 'TSAppDelegate.m').read_text(encoding='utf-8', errors='surrogateescape')
help_docs = source_file(root, 'HelpDocuments.m').read_text(encoding='utf-8', errors='surrogateescape')
MIRROR = '- (void)mirrorPath:(NSString *)srcPath toPath:(NSString *)dstPath\n{'
fragments = [
    ('TSAppDelegate mirrorPath', delegate, method(delegate, MIRROR)),
    ('HelpDocuments mirrorPath', help_docs, method(help_docs, MIRROR)),
]

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <sys/stat.h>
static NSMutableArray<NSString *> *alerts;
// AppKit raises for a nil message format and formats the rest of the arguments into the message.
static NSInteger RecordAlert(NSString *title, NSString *format, NSString *b1, NSString *b2, NSString *b3, ...) {
    if (format == nil) [NSException raise:NSInvalidArgumentException format:@"NSRunAlertPanel: nil message"];
    va_list args; va_start(args, b3);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args]; va_end(args);
    [alerts addObject:[NSString stringWithFormat:@"%@|%@", title, message]];
    return 1;
}
#define NSRunAlertPanel RecordAlert
static NSString *Resources;
static NSString *TestResourcePath(id self, SEL _cmd) { return Resources; }
static void check(BOOL ok, NSString *what) { if (!ok) { fprintf(stderr, "FAIL: %s\n", what.UTF8String); exit(1); } }

@interface Mirror : NSObject @end
@implementation Mirror
__DELEGATE_MIRROR__
@end
@interface HelpMirror : NSObject @end
@implementation HelpMirror
__HELP_MIRROR__
@end
static void Write(NSDictionary *d, NSString *path) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL] writeToFile:path atomically:YES];
}
int main(int argc, char **argv) { @autoreleasepool {
    alerts = [NSMutableArray array];
    NSString *base = @(argv[1]);
    NSFileManager *fm = NSFileManager.defaultManager;
    method_setImplementation(class_getInstanceMethod(NSBundle.class, @selector(resourcePath)), (IMP)TestResourcePath);
    Resources = [base stringByAppendingPathComponent:@"Resources"];
    NSString *bundled = [Resources stringByAppendingPathComponent:@"TeXShop"];
    Write(@{@"content": @[]}, [bundled stringByAppendingPathComponent:@"Macros/Macros_Latex.plist"]);
    [@"x" writeToFile:[bundled stringByAppendingPathComponent:@"Templates/a.tex"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [fm createDirectoryAtPath:[bundled stringByAppendingPathComponent:@"Templates"] withIntermediateDirectories:YES attributes:nil error:NULL];
    [@"x" writeToFile:[bundled stringByAppendingPathComponent:@"Templates/a.tex"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    // A home without a Library folder, as a new account or an empty test home.
    for (Class mirrorClass in @[Mirror.class, HelpMirror.class]) {
        NSString *home = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"home-%@", NSStringFromClass(mirrorClass)]];
        [fm createDirectoryAtPath:home withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *library = [home stringByAppendingPathComponent:@"Library/TeXShop"];
        [alerts removeAllObjects];
        @try { [[mirrorClass new] mirrorPath:bundled toPath:library]; }
        @catch (NSException *e) { check(NO, [NSString stringWithFormat:@"%@ mirror threw %@", mirrorClass, e.reason]); }
        check(alerts.count == 0 && [fm fileExistsAtPath:[library stringByAppendingPathComponent:@"Macros/Macros_Latex.plist"]] &&
              [fm fileExistsAtPath:[library stringByAppendingPathComponent:@"Templates/a.tex"]],
              [NSString stringWithFormat:@"%@: a home without Library gets ~/Library/TeXShop with its parents", mirrorClass]);
        // A folder that cannot be created: one alert naming it, and no exception.
        NSString *locked = [home stringByAppendingPathComponent:@"Locked"];
        [fm createDirectoryAtPath:locked withIntermediateDirectories:YES attributes:nil error:NULL];
        chmod(locked.fileSystemRepresentation, 0500);
        [alerts removeAllObjects];
        @try { [[mirrorClass new] mirrorPath:bundled toPath:[locked stringByAppendingPathComponent:@"TeXShop"]]; }
        @catch (NSException *e) { chmod(locked.fileSystemRepresentation, 0700); check(NO, [NSString stringWithFormat:@"%@ unwritable folder threw %@", mirrorClass, e.reason]); }
        chmod(locked.fileSystemRepresentation, 0700);
        check(alerts.count == 1 && [alerts[0] containsString:[locked stringByAppendingPathComponent:@"TeXShop"]] && [alerts[0] componentsSeparatedByString:@"\n"].count > 2,
              [NSString stringWithFormat:@"%@: a folder that cannot be created gives one alert with the folder and the cause: %@", mirrorClass, alerts]);
    }

    puts("PASS: first-launch library folders");
} return 0; }
'''


def build_and_run(td, parts, name):
    program = PROGRAM.replace('__DELEGATE_MIRROR__', parts[0]).replace('__HELP_MIRROR__', parts[1])
    src = td / (name + '.m'); exe = td / name
    src.write_text(program, encoding='utf-8', errors='surrogateescape')
    subprocess.run(['clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', str(src), '-o', str(exe)], check=True)
    work = td / ('work-' + name); work.mkdir()
    return subprocess.run([str(exe), str(work)], capture_output=True, text=True, timeout=30), program


MUTATIONS = {
    'no parents': (0, 'withIntermediateDirectories:YES attributes:nil error:&createError', 'withIntermediateDirectories:NO attributes:nil error:&createError'),
    'help no parents': (1, 'withIntermediateDirectories:YES attributes:nil error:&createError', 'withIntermediateDirectories:NO attributes:nil error:&createError'),
    'nil message': (0, 'NSRunAlertPanel(NSLocalizedString(@"Error", @"Error"), @"%@", nil, nil, nil, message);', 'NSRunAlertPanel(NSLocalizedString(@"Error", @"Error"), reason, message, nil, nil);'),
}

with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    parts = [f for _, _, f in fragments]
    result, program = build_and_run(td, parts, 'normal')
    verify_embedded(program, fragments)
    sys.stdout.write(result.stdout); sys.stderr.write(result.stderr)
    assert result.returncode == 0, 'normal harness failed'
    for name, (index, old, new) in MUTATIONS.items():
        assert parts[index].count(old) == 1, name
        mutated = list(parts); mutated[index] = parts[index].replace(old, new)
        r, _ = build_and_run(td, mutated, 'mutation-' + name.replace(' ', '-'))
        assert r.returncode != 0, 'mutation went unnoticed: ' + name
        print('PASS mutation %s: %s' % (name, (r.stderr.strip().splitlines() or ['failed'])[-1]))
