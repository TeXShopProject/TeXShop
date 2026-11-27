#!/usr/bin/env python3
"""The two sides of the window that shows the source and the Preview start below the toolbar (#74).

On macOS 26 and later the content of a document window runs under the title bar and
the toolbar. In the single window the source's text and background ran up into the
band of the toolbar. The split view that holds the two sides is placed below the band,
as the source window and the Preview window are, at the sides and the bottom as before.

The production placeFullSplitBelowToolbar runs unchanged in a stand-in document with a
real window that has a toolbar and a full-size content view, kept off screen.
"""
import argparse, re, subprocess, sys, tempfile
from pathlib import Path
from source_tree import source_file

MUTATIONS = {
    'not-placed': ('            [self placeFullSplitBelowToolbar];\n', ''),
    'placed-after-shown': ('            [self placeFullSplitBelowToolbar];\n            NSString *splitPosition',
                           '            NSString *splitPosition'),
    'top-of-content': ('content.safeAreaLayoutGuide.topAnchor', 'content.topAnchor'),
    'sides-not-kept': ('constant: left]', 'constant: 0]'),
    'placed-twice': ('    if (! TSDocumentWindowsUseFullSizeContent() || self.fullSplitPlacement != nil)\n',
                     '    if (! TSDocumentWindowsUseFullSizeContent())\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
document = source_file(root, 'TSDocument.m').read_text(encoding='latin1')
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    if args.mutation == 'placed-after-shown':
        old = '            [self placeFullSplitBelowToolbar];\n'
        new = ''
        assert document.count(old) == 1
        document = document.replace(old, new)
        old = '            [self.splitController showWindow: nil];\n'
        new = old + '            [self placeFullSplitBelowToolbar];\n'
    assert document.count(old) == 1, args.mutation
    document = document.replace(old, new)

def fail(message):
    print('FAIL:', message, file=sys.stderr)
    sys.exit(1)

def method(signature):
    start = document.index(signature)
    return document[start:document.index('\n}\n', start) + 3]

# The sides are placed when the single window is put together, before it is shown.
move = method('- (void) doMove: (id)sender;')
place = move.find('[self placeFullSplitBelowToolbar];')
if place < 0 or not place < move.index('[self.splitController showWindow: nil];'):
    fail('the single window places its sides below the toolbar before it is shown')
if 'useSourceBorders' in document:
    fail('the border of the source is no longer changed for the single window')

body = method('- (void) placeFullSplitBelowToolbar')
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
static BOOL fullSize = YES;
static BOOL TSDocumentWindowsUseFullSizeContent(void) { return fullSize; }
@interface TestDocument : NSObject { @public NSWindow *fullSplitWindow; NSView *leftView; }
@property (strong) NSArray<NSLayoutConstraint *> *fullSplitPlacement;
@end
@implementation TestDocument
''' + body + r'''
@end
static int checks;
static void check(BOOL ok, const char *message) { checks++; if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); } }
int main(void) {
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 600)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
            backing:NSBackingStoreBuffered defer:NO];
        w.toolbar = [[NSToolbar alloc] initWithIdentifier:@"test"];
        w.toolbarStyle = NSWindowToolbarStyleUnified;
        NSView *content = w.contentView;
        // As in the nib: the split view of the two sides fills the content view, a little inset at the sides.
        NSSplitView *sides = [[NSSplitView alloc] initWithFrame:NSInsetRect(content.bounds, 2, 0)];
        sides.vertical = YES;
        sides.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 600)];
        NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(401, 0, 495, 600)];
        [sides addSubview:left]; [sides addSubview:right];
        [content addSubview:sides];
        [w layoutIfNeeded];
        CGFloat band = NSHeight(content.bounds) - NSMaxY(content.safeAreaRect);
        check(band > 20, "the window has a band under its title bar and toolbar");
        TestDocument *d = [TestDocument new];
        d->fullSplitWindow = w; d->leftView = left;

        fullSize = NO;
        [d placeFullSplitBelowToolbar];
        check(d.fullSplitPlacement == nil && NSMaxY(sides.frame) == NSHeight(content.bounds),
              "before macOS 26 the sides stay as in the nib");
        fullSize = YES;
        [d placeFullSplitBelowToolbar];
        [w layoutIfNeeded];
        check(fabs(NSMaxY(sides.frame) - NSMaxY(content.safeAreaRect)) < 0.5, "the sides start below the band of the toolbar");
        check(NSMinX(sides.frame) == 2 && NSMaxX(sides.frame) == NSWidth(content.bounds) - 2 && NSMinY(sides.frame) == 0,
              "at the sides and the bottom the sides are where they were");
        NSArray *placement = d.fullSplitPlacement;
        [d placeFullSplitBelowToolbar];
        check(d.fullSplitPlacement == placement, "placing again keeps the same constraints");
        [w setContentSize:NSMakeSize(700, 450)];
        [w layoutIfNeeded];
        check(fabs(NSMaxY(sides.frame) - NSMaxY(content.safeAreaRect)) < 0.5 && NSMaxX(sides.frame) == NSWidth(content.bounds) - 2
              && NSMinY(sides.frame) == 0, "the sides follow the window when it is resized");
        w.toolbar.visible = NO;
        [w layoutIfNeeded];
        check(fabs(NSMaxY(sides.frame) - NSMaxY(content.safeAreaRect)) < 0.5, "the sides follow the band when the toolbar is hidden");
        printf("%d checks\n", checks);
    }
    return 0;
}
'''
with tempfile.TemporaryDirectory(prefix='texshop-single-below-') as directory:
    source = Path(directory) / 'test.m'
    source.write_text(program)
    binary = Path(directory) / 'test'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-unused-function',
                    '-framework', 'Cocoa', '-I', str(root / 'Tests'), str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=60)
print('PASS run-single-window-below-toolbar')
