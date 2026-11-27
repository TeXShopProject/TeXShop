#!/usr/bin/env python3
"""The title of the window that shows the source and the Preview (#77).

Command-click on the file name in the title opens the path menu, as in the
source window: the single window sends the click to its document icon before
anything else handles it (the same routing as the Preview window, #73).

AppKit puts the document's title menu (the arrow next to the name) on the
window that the document returns from windowForSheet. While the single window
is in use, that is the single window; before and after, it is the source window.
The production windowForSheet runs unchanged in a stand-in NSDocument with real
AppKit window controllers, kept off screen.
"""
import argparse, re, subprocess, sys, tempfile
from pathlib import Path
from source_tree import source_file

MUTATIONS = {
    'title-click-not-forwarded': ('TSFullSplitWindow.m',
        '    NSEvent *titleEvent = TSPreviewTitlePathMenuEvent(self, theEvent);\n', '    NSEvent *titleEvent = nil;\n'),
    'title-click-after-keys': ('TSFullSplitWindow.m',
        '    // Command-click on the title opens the path menu, as it does in the source window.\n'
        '    NSEvent *titleEvent = TSPreviewTitlePathMenuEvent(self, theEvent);\n'
        '    if (titleEvent) {\n        [super sendEvent:titleEvent];\n        return;\n    }\n\n',
        ''),
    'sheet-window-unchanged': ('TSDocument.m',
        '    if (self.splitController != nil && [self.windowControllers containsObject: self.splitController])\n'
        '        return fullSplitWindow;\n', ''),
    'sheet-window-always-single': ('TSDocument.m',
        '    if (self.splitController != nil && [self.windowControllers containsObject: self.splitController])\n',
        '    if (self.splitController != nil)\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
text = {name: source_file(root, name).read_text(encoding='latin1') for name in ('TSFullSplitWindow.m', 'TSDocument.m')}
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert text[name].count(old) == 1, args.mutation
    text[name] = text[name].replace(old, new)

def fail(message):
    print('FAIL:', message, file=sys.stderr)
    sys.exit(1)

def method(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n}\n', start) + 3]

def code(source):
    source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    return '\n'.join(line for line in source.splitlines() if not line.strip().startswith('//'))

# The single window routes a Command-click on its title first, before its own key and magnifier handling.
send = code(method(text['TSFullSplitWindow.m'], '- (void)sendEvent:(NSEvent *)theEvent'))
route = send.find('TSPreviewTitlePathMenuEvent(self, theEvent)')
if route < 0 or '#import "TSPreviewTitlePathMenu.h"' not in text['TSFullSplitWindow.m']:
    fail('the single window sends a Command-click on its title to the document icon')
if not (route < send.index('NSEventTypeKeyDown') and route < send.index('[super sendEvent: theEvent]')
        and re.search(r'if \(titleEvent\) \{\s*\[super sendEvent:titleEvent\];\s*return;\s*\}', send)):
    fail('the title click is routed before anything else handles the event')

sheet = method(text['TSDocument.m'], '- (NSWindow *)windowForSheet')
program = r'''
#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "TestAppKitIsolation.h"
@interface TestDocument : NSDocument { @public NSWindow *fullSplitWindow; }
@property (retain) NSWindowController *splitController;
@end
@implementation TestDocument
+ (BOOL)autosavesInPlace { return YES; }
''' + sheet + r'''
@end
static int checks;
static void check(BOOL ok, const char *message) { checks++; if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); } }
static NSWindow *window(void) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    return w;
}
// AppKit's own decision for the title menu, where this macOS has it.
static int titleMenu(NSDocument *d, NSWindow *w) {
    SEL s = NSSelectorFromString(@"_shouldShowAutosaveButtonForWindow:");
    if (![d respondsToSelector:s]) return -1;
    return ((BOOL(*)(id, SEL, id))objc_msgSend)(d, s, w) ? 1 : 0;
}
int main(void) {
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        TestDocument *d = [TestDocument new];
        d.fileURL = [NSURL fileURLWithPath:@"/tmp/日本語 空白/sample.tex"];
        NSWindow *source = window(), *single = window();
        d->fullSplitWindow = single;
        NSWindowController *standard = [[NSWindowController alloc] initWithWindow:source];
        [d addWindowController:standard];
        d.splitController = [[NSWindowController alloc] initWithWindow:single];
        check(d.windowForSheet == source, "separate windows: the source window carries the title menu and sheets");
        int m = titleMenu(d, source);
        check(m != 0, "AppKit shows the title menu on the source window");
        check(titleMenu(d, single) != 1, "the hidden single window has no title menu");
        [d addWindowController:d.splitController];
        check(d.windowForSheet == single, "single window: the title menu and sheets are on the single window");
        check(titleMenu(d, single) != 0, "AppKit shows the title menu on the single window");
        check(titleMenu(d, source) != 1, "the hidden source window has no title menu");
        [d removeWindowController:d.splitController];
        check(d.windowForSheet == source, "back to separate windows: the source window again");
        check(titleMenu(d, source) != 0, "AppKit shows the title menu on the source window again");
        printf("%d checks%s\n", checks, m < 0 ? " (AppKit decision not available on this macOS)" : "");
    }
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='texshop-single-title-') as directory:
    source = Path(directory) / 'test.m'
    source.write_text(program)
    binary = Path(directory) / 'test'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-objc-property-no-attribute',
                    '-framework', 'Cocoa', '-I', str(root / 'Tests'), str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=60)
print('PASS run-single-window-title')
