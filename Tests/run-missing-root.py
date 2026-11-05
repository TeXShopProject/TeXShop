#!/usr/bin/env python3
"""A missing "% !TEX root" file is reported on the document window."""
from pathlib import Path
import re, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/TSDocument-RootFile.m').read_text(encoding='latin-1')
start = source.index('- (void)reportMissingRootFile:')
method = source[start:source.index('\n}\n', start) + 3]
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation == 'notification':
    method = method.replace('[alert beginSheetModalForWindow: window completionHandler: nil];', ';')
failures = []
# The missing-file branch must call the reporter, and nothing may rely on NSUserNotification.
active = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
if '[self reportMissingRootFile: nameString forTask: task];' not in active:
    failures.append('missing root branch does not report the file')
if 'NSUserNotificationCenter' in active:
    failures.append('NSUserNotification is still used')
program = r'''
#import <Cocoa/Cocoa.h>
enum { RootForOpening = 1, RootForTexing = 2, RootForPrinting = 3 };
@interface Doc : NSObject
@property (strong) NSWindow *window;
- (NSWindow *)windowForSheet;
@end
@implementation Doc
- (NSWindow *)windowForSheet { return self.window; }
METHOD
@end
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    int failures = 0;
    for (NSNumber *task in @[@(RootForTexing), @(RootForPrinting), @(RootForOpening)]) {
        Doc *doc = [Doc new];
        doc.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [doc.window orderFront:nil];
        [doc reportMissingRootFile:@"/tmp/no-such-root.tex" forTask:task.integerValue];
        NSWindow *sheet = doc.window.attachedSheet;
        BOOL expectSheet = task.integerValue != RootForOpening;
        if ((sheet != nil) != expectSheet) { printf("FAIL: task %ld sheet=%d\n", (long)task.integerValue, sheet != nil); failures++; }
        if (sheet) {
            BOOL named = NO;
            for (NSView *v in sheet.contentView.subviews) if ([v isKindOfClass:NSTextField.class] && [[(NSTextField *)v stringValue] containsString:@"no-such-root.tex"]) named = YES;
            if (!named) { printf("FAIL: sheet does not show the path\n"); failures++; }
            [doc.window endSheet:sheet];
        }
    }
    return failures ? 1 : 0;
} }
'''.replace('METHOD', method)
with tempfile.TemporaryDirectory(prefix='texshop-root-') as tmp:
    src, exe = Path(tmp) / 'test.m', Path(tmp) / 'test'
    src.write_text(program)
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', str(src), '-o', str(exe)], check=True)
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    out = r.stdout.strip()
    if out: print(out)
    if r.returncode: failures.append('runtime checks failed')
for f in failures: print('FAIL:', f)
if mutation:
    if not failures: raise SystemExit('FAIL: mutation %s was not detected' % mutation)
    print('detected mutation', mutation)
elif failures: raise SystemExit(1)
else: print('PASS: missing root file shown in a sheet with its path for typesetting and printing; opening stays quiet')
