#!/usr/bin/env python3
"""Dragging the divider of a Preview window split into a top and a bottom part.

Each part keeps the text at its top edge: the top part shows more or less below
it, and the text of the bottom part moves with the divider. Other resizes are
left alone.

The production TSPreviewSplitDivider runs unchanged with two real PDFViews in an
NSSplitView, in a window that is never ordered on screen. A divider drag is
replayed as NSSplitView does it: the will-resize notification marked as a resize
by the user, the new frames of the parts, then the did-resize notification.
"""
import argparse, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file

MUTATIONS = {
    'no-scroll': ('TSPreviewSplitDivider.m',
        '        [clipView scrollToPoint:[clipView constrainBoundsRect:bounds].origin];\n', ''),
    'every-resize': ('TSPreviewSplitDivider.m',
        '+ (BOOL)isDividerDrag:(NSNotification *)notification\n{\n', '+ (BOOL)isDividerDrag:(NSNotification *)notification\n{\n    return YES;\n'),
    'not-installed': ('TSPreviewWindow.m',
        '        self.previewSplitDivider = [[TSPreviewSplitDivider alloc] initWithSplitView:self.pdfKitSplitView];\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
text = {name: source_file(root, name).read_text(encoding='latin1') for name in ('TSPreviewSplitDivider.m', 'TSPreviewWindow.m')}
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert text[name].count(old) == 1, args.mutation
    text[name] = text[name].replace(old, new)

# The Preview window installs the divider keeper whenever it splits or unsplits.
window = text['TSPreviewWindow.m']
start = window.rindex('- (void) mainSplitPdfKitWindow\n{\n    NSSize')  # the earlier one is commented out
body = window[start:window.index('\n}\n', start)]
installed = ('self.previewSplitDivider = [[TSPreviewSplitDivider alloc] initWithSplitView:self.pdfKitSplitView];' in body
             and '#import "TSPreviewSplitDivider.h"' in window)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewSplitDivider.h"
static int failures;
static void Check(BOOL ok, const char *name) { if (!ok) { printf("FAIL: %s\n", name); failures++; } }

// The page and the height on it at the top or bottom edge of a part.
static NSString *Edge(PDFView *view, BOOL top) {
    NSRect b = view.bounds;
    NSPoint p = NSMakePoint(NSMidX(b), top ? NSMaxY(b) - 0.5 : NSMinY(b) + 0.5);
    PDFPage *page = [view pageForPoint:p nearest:YES];
    return [NSString stringWithFormat:@"%lu:%.0f", [view.document indexForPage:page], [view convertPoint:p toPage:page].y];
}
static PDFDocument *MakeDocument(void) {
    PDFDocument *document = [PDFDocument new];
    for (int i = 0; i < 6; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600, 800)];
        [image lockFocus]; [NSColor.whiteColor set]; NSRectFill(NSMakeRect(0, 0, 600, 800)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return document;
}
// A divider drag as NSSplitView performs it.
static void DragDivider(NSSplitView *split, CGFloat position, NSDictionary *info) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center postNotificationName:NSSplitViewWillResizeSubviewsNotification object:split userInfo:info];
    NSView *top = split.subviews[0], *bottom = split.subviews[1];
    CGFloat width = NSWidth(split.bounds), height = NSHeight(split.bounds), thickness = split.dividerThickness;
    top.frame = NSMakeRect(0, 0, width, position);
    bottom.frame = NSMakeRect(0, position + thickness, width, height - position - thickness);
    [split.window layoutIfNeeded];
    [center postNotificationName:NSSplitViewDidResizeSubviewsNotification object:split userInfo:info];
}

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    Check(INSTALLED, "the Preview window installs the divider keeper when it splits");

    PDFDocument *document = MakeDocument();
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 800)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 600, 800)];
    split.vertical = NO;
    window.contentView = split;
    PDFView *upper = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    PDFView *lower = [[PDFView alloc] initWithFrame:NSMakeRect(0, 400, 600, 400)];
    for (PDFView *view in @[upper, lower]) {
        view.document = document; view.displayMode = kPDFDisplaySinglePageContinuous;
        view.autoScales = NO; view.scaleFactor = 1.0;
        [split addSubview:view];
    }
    [split adjustSubviews];
    [window layoutIfNeeded];
    TSPreviewSplitDivider *keeper = [[TSPreviewSplitDivider alloc] initWithSplitView:split];
    NSDictionary *user = @{@"NSSplitViewUserResizeKey": @YES, @"NSSplitViewDividerIndex": @0};

    // Which resizes count as divider drags.
    NSNotification *(^note)(NSDictionary *) = ^(NSDictionary *info) {
        return [NSNotification notificationWithName:NSSplitViewWillResizeSubviewsNotification object:split userInfo:info]; };
    Check([TSPreviewSplitDivider isDividerDrag:note(user)], "a resize by the user is a divider drag");
    Check(![TSPreviewSplitDivider isDividerDrag:note(@{@"NSSplitViewUserResizeKey": @NO, @"NSSplitViewDividerIndex": @0})],
          "a resize by the program is not a divider drag");
    Check(![TSPreviewSplitDivider isDividerDrag:note(@{@"NSSplitViewDividerIndex": @0})],
          "a resize of the window, without a mouse drag, is not a divider drag");

    // Both parts are scrolled into the middle of a page.
    [upper goToRect:NSMakeRect(0, 420, 10, 10) onPage:[document pageAtIndex:1]];
    [lower goToRect:NSMakeRect(0, 300, 10, 10) onPage:[document pageAtIndex:3]];
    [window layoutIfNeeded];
    NSString *upperTop = Edge(upper, YES), *lowerTop = Edge(lower, YES), *upperBottom = Edge(upper, NO);
    CGFloat lowerTopInWindow = NSMaxY([lower convertRect:lower.bounds toView:nil]);

    // Dragging the divider down, in steps.
    for (CGFloat position = 420; position <= 560; position += 20)
        DragDivider(split, position, user);
    Check([Edge(upper, YES) isEqual:upperTop], "dragging the divider down keeps the text at the top of the upper part");
    Check(![Edge(upper, NO) isEqual:upperBottom], "the upper part shows more below");
    Check([Edge(lower, YES) isEqual:lowerTop], "the text of the lower part moves down with the divider");
    Check(NSMaxY([lower convertRect:lower.bounds toView:nil]) < lowerTopInWindow, "the top edge of the lower part moved down");

    // And up again, past where it started.
    for (CGFloat position = 540; position >= 300; position -= 30)
        DragDivider(split, position, user);
    Check([Edge(upper, YES) isEqual:upperTop] && [Edge(lower, YES) isEqual:lowerTop],
          "dragging the divider up keeps the text at the top of both parts");

    // The last page cannot scroll past its end: the lower part shows its bottom.
    [lower goToPage:[document pageAtIndex:5]];
    [lower scrollPageDown:nil]; [lower scrollPageDown:nil]; [lower scrollPageDown:nil];
    [window layoutIfNeeded];
    DragDivider(split, 500, user);
    Check(lower.documentView.enclosingScrollView != nil && [Edge(lower, NO) hasPrefix:@"5:"],
          "at the end of the document the lower part still shows the last page");

    // An unsplit window has one part, which is left as it is.
    [lower removeFromSuperview];
    [split adjustSubviews];
    [upper goToRect:NSMakeRect(0, 420, 10, 10) onPage:[document pageAtIndex:2]];
    [window layoutIfNeeded];
    [NSNotificationCenter.defaultCenter postNotificationName:NSSplitViewWillResizeSubviewsNotification object:split userInfo:user];
    [NSNotificationCenter.defaultCenter postNotificationName:NSSplitViewDidResizeSubviewsNotification object:split userInfo:user];
    Check([Edge(upper, YES) hasPrefix:@"2:"], "an unsplit window is unchanged");
    (void)keeper;

    if (failures) return 1;
    printf("PASS: dragging the divider keeps the top of both Preview parts; other resizes are left alone\n");
} return 0; }
'''.replace('INSTALLED', 'YES' if installed else 'NO')

with tempfile.TemporaryDirectory(prefix='texshop-preview-split-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='latin1')
    (tmp / 'TSPreviewSplitDivider.m').write_text(text['TSPreviewSplitDivider.m'], encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz', *include_args(root),
                    '-I', str(root / 'Tests'), str(tmp / 'probe.m'), str(tmp / 'TSPreviewSplitDivider.m'),
                    '-o', str(tmp / 'probe')], check=True)
    result = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True, timeout=120)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr)
        sys.exit('FAIL')
