#!/usr/bin/env python3
"""Check that Show Full Path keeps the full path in the source window's title.

AppKit names a document window again after saves, autosaves and renames. The window controller
gives the full path at that time, so the title does not fall back to the file name. The test builds
the real TSWindowController with a small TSDocument stand-in, keeps its window off screen, and
saves, autosaves and renames the document in a private folder. The single window of source and
preview, which has a controller of the same class, keeps AppKit's name."""
from pathlib import Path
import argparse
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
CONTROLLER = 'Sources/Windows/TSWindowController.m'
WINDOW = 'Sources/Windows/TSTextEditorWindow.m'
DOCUMENT = 'Sources/Document/TSDocument.m'

MUTATIONS = {
    # The controller gives AppKit's name: saves bring the file name back.
    'controller-gives-file-name': (CONTROLLER, 'if ([document isKindOfClass:[TSDocument class]]', 'if (NO && [document isKindOfClass:[TSDocument class]]'),
    # The single window of source and preview also shows the full path (first audit).
    'single-window-full-path': (CONTROLLER, '((TSDocument *)document).standardController == self\n        && ', ''),
    # The switch is turned without naming the window again.
    'switch-without-renaming': (DOCUMENT, '\t[self.standardController synchronizeWindowTitleWithDocumentName];\n', ''),
    # The window sets its own title again, which the next save overwrites.
    'window-sets-own-title': (WINDOW, '\t[[self windowController] synchronizeWindowTitleWithDocumentName];\n',
                              '\tif([self.myDocument fileURL] != nil) [self setTitle:[self.myDocument fileTitleName]];\n'),
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

sources = {name: (root / name).read_text() for name in (CONTROLLER, WINDOW, DOCUMENT)}
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert sources[name].count(old) == 1, args.mutation
    sources[name] = sources[name].replace(old, new)

checks = 0
def check(ok, message):
    global checks
    checks += 1
    if not ok:
        print('FAIL:', message, file=sys.stderr)
        sys.exit(1)

# Source checks: the window and the switch leave the naming to the window controller.
window = sources[WINDOW]
start = window.index('- (void)refreshTitle')
body = window[start:window.index('}', start)]
check('synchronizeWindowTitleWithDocumentName' in body and 'setTitle' not in body,
      'the source window asks its controller for the title')
document = sources[DOCUMENT]
start = document.index('- (void) changeShowFullPath: sender')
body = document[start:document.index('\n}', start)]
check('[self.standardController synchronizeWindowTitleWithDocumentName]' in body,
      'turning the switch names the source window again')
check('performSelector:@selector(refreshTitle)' not in document
      and 'performSelector:@selector(refreshTitle)' not in (root / 'Sources/Typesetting/TSDocument-Jobs.m').read_text(),
      'no delayed renaming after saves is needed')

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TSWindowController.h"
#import "TSDocument.h"
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
@implementation TSDocument
+ (BOOL)autosavesInPlace { return YES; }
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error { return [@"\\relax\n" dataUsingEncoding:NSUTF8StringEncoding]; }
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)error { return YES; }
- (NSString *)fileType { return @"public.plain-text"; }
@end
static void waitFor(BOOL *done) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!*done && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    check(*done, @"the save finished");
    // AppKit may name the window a little after the save.
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
}
int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *folder = [NSString stringWithUTF8String:argv[1]];
        NSURL *first = [NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"a folder/sample.tex"]];
        NSURL *second = [NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"a folder/renamed.tex"]];
        [[NSFileManager defaultManager] createDirectoryAtURL:first.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"\\relax\n" writeToURL:first atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        TSDocument *document = [[TSDocument alloc] init];
        document.fileURL = first;
        document.fileModificationDate = [[NSFileManager defaultManager] attributesOfItemAtPath:first.path error:NULL][NSFileModificationDate];
        // Never ordered front: the window stays off screen.
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
        TSWindowController *controller = [[TSWindowController alloc] initWithWindow:window];
        document.standardController = controller;
        [document addWindowController:controller];
        // The single window of source and preview: a second controller of the same class (doMove:).
        NSWindow *single = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
        TSWindowController *singleController = [[TSWindowController alloc] initWithWindow:single];
        [document addWindowController:singleController];

        document.showsFullPath = NO;
        [controller synchronizeWindowTitleWithDocumentName];
        check([window.title isEqualToString:document.displayName], @"switch off: AppKit's name");

        document.showsFullPath = YES;
        [controller synchronizeWindowTitleWithDocumentName];
        check([window.title isEqualToString:first.path], @"switch on: the full path");
        [singleController synchronizeWindowTitleWithDocumentName];
        check([single.title isEqualToString:document.displayName], @"switch on: the single window keeps AppKit's name");

        [document updateChangeCount:NSChangeDone];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        check([window.title isEqualToString:first.path], @"edited: still the full path");

        __block BOOL done = NO;
        [document autosaveWithImplicitCancellability:NO completionHandler:^(NSError *error) {
            check(error == nil, @"the autosave succeeded");
            done = YES;
        }];
        waitFor(&done);
        check([window.title isEqualToString:first.path], @"after an autosave: still the full path");

        [document updateChangeCount:NSChangeDone];
        done = NO;
        [document saveToURL:first ofType:document.fileType forSaveOperation:NSSaveOperation completionHandler:^(NSError *error) {
            check(error == nil, @"the save succeeded");
            done = YES;
        }];
        waitFor(&done);
        check([window.title isEqualToString:first.path], @"after a save: still the full path");
        check([single.title isEqualToString:document.displayName], @"the single window keeps AppKit's name");

        // A rename (Move To, Rename in the title bar) gives the new full path without any call of ours.
        document.fileURL = second;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        check([window.title isEqualToString:second.path], @"after a rename: the new full path");
        check([single.title isEqualToString:document.displayName], @"after a rename: the single window keeps AppKit's name");

        document.showsFullPath = NO;
        [controller synchronizeWindowTitleWithDocumentName];
        check([window.title isEqualToString:document.displayName], @"switch off again: AppKit's name");

        document.fileURL = nil;
        document.showsFullPath = YES;
        [controller synchronizeWindowTitleWithDocumentName];
        check([window.title isEqualToString:document.displayName], @"untitled: AppKit's name");
        printf("%lu\n", (unsigned long)checks);
    }
    return 0;
}
'''

STUB_DOCUMENT = r'''
#import <Cocoa/Cocoa.h>
@class TSWindowController;
@interface TSDocument : NSDocument
@property BOOL showsFullPath;
@property (retain) TSWindowController *standardController;
@end
'''

with tempfile.TemporaryDirectory() as work:
    work = Path(work)
    (work / 'TSDocument.h').write_text(STUB_DOCUMENT)
    (work / 'globals.h').write_text('')
    (work / 'TSWindowController.h').write_text((root / 'Sources/Windows/TSWindowController.h').read_text())
    (work / 'TSWindowController.m').write_text(sources[CONTROLLER])
    (work / 'main.m').write_text(PROGRAM)
    binary = work / 'test'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-framework', 'Cocoa', '-I', str(work),
                    str(work / 'TSWindowController.m'), str(work / 'main.m'), '-o', str(binary)], check=True)
    folder = work / 'documents'
    folder.mkdir()
    env = dict(os.environ, TMPDIR=str(work) + '/')
    result = subprocess.run([str(binary), str(folder)], capture_output=True, text=True, env=env)
    if result.returncode != 0:
        print(result.stderr, end='', file=sys.stderr)
        sys.exit(1)
    checks += int(result.stdout.strip())

print(f'OK: {checks} checks')
