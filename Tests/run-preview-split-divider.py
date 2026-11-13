#!/usr/bin/env python3
"""Dragging the divider of a Preview window split into a top and a bottom part,
and changing the height of such a window.

Each part keeps the text at its top edge: when the divider is dragged, the top part
shows more or less below it and the text of the bottom part moves with the divider;
when the window gets taller or shorter, both parts keep their tops. Moves of the
divider by the program, an unsplit window and a window split side by side are left
alone.

During a drag, PDFKit must not scroll the parts away at any step only for them to be
put back, and a part pushed to no height must come back with its text. How far the
text moves is measured at every step of the drag.

The production TSPreviewSplitDivider runs unchanged with two real PDFViews, set up as
in TSDocument.nib, in an NSSplitView in a window that is never ordered on screen. The
divider is dragged through NSSplitView's own tracking: a mouse-down on the divider,
with the drags and the mouse-up queued as events for the window.
"""
import argparse, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file

MUTATIONS = {
    'no-scroll': ('TSPreviewSplitDivider.m', '            [clip scrollToPoint:target];\n', ''),
    'mouse-overrides-program': ('TSPreviewSplitDivider.m',
        '    if (byUser != nil)\n        return byUser.boolValue;\n', '    if (byUser.boolValue)\n        return YES;\n'),
    'every-resize': ('TSPreviewSplitDivider.m',
        '+ (BOOL)isDividerDrag:(NSNotification *)notification\n{\n', '+ (BOOL)isDividerDrag:(NSNotification *)notification\n{\n    return YES;\n'),
    'not-installed': ('TSPreviewWindow.m',
        '        self.previewSplitDivider = [[TSPreviewSplitDivider alloc] initWithSplitView:self.pdfKitSplitView];\n', ''),
    # PDFKit is told about every step of a drag, and scrolls the parts away each time.
    'pdfkit-every-step': ('TSPreviewSplitDivider.m',
        '            view.postsFrameChangedNotifications = NO;\n            anchor.quiet = YES;\n', ''),
    # A part pushed to no height loses its place.
    'empty-part-forgotten': ('TSPreviewSplitDivider.m',
        '        (empty || TSPartStillAt(clip, anchor.origin)))', '        !empty && TSPartStillAt(clip, anchor.origin))'),
    # PDFKit is never told about the size after a drag.
    'never-finished': ('TSPreviewSplitDivider.m',
        '        view.postsFrameChangedNotifications = YES;\n        if (view.superview', '        if (view.superview'),
    # The top edge counts the content insets, which change for a moment during a window resize.
    'inset-edge': ('TSPreviewSplitDivider.m',
        '    return clip.isFlipped ? NSMinY(clip.bounds) : NSMaxY(clip.bounds);\n',
        '    NSEdgeInsets insets = ((NSScrollView *)clip.superview).contentInsets;\n'
        '    return clip.isFlipped ? NSMinY(clip.bounds) + insets.top : NSMaxY(clip.bounds) - insets.top;\n'),
    # Any move of the scroll position, also an alignment to the pixels, reads the text at the top again.
    'exact-origin': ('TSPreviewSplitDivider.m', '        (empty || TSPartStillAt(clip, anchor.origin)))', '        (empty || NSEqualPoints(clip.bounds.origin, anchor.origin)))'),
    # Window resizes are not seen.
    'no-window-resize': ('TSPreviewSplitDivider.m',
        '        if (splitView.delegate == nil)\n            splitView.delegate = self;\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--binary', type=Path, help='write the test program, built for macOS 14 and later, here instead of running it')
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
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewSplitDivider.h"
static int failures;
static void Check(BOOL ok, NSString *name) { if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }

static PDFDocument *MakeDocument(void) {
    PDFDocument *document = [PDFDocument new];
    for (int i = 0; i < 8; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600, 800)];
        [image lockFocus]; [NSColor.whiteColor set]; NSRectFill(NSMakeRect(0, 0, 600, 800)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return document;
}
static NSEvent *MouseEvent(NSWindow *window, NSEventType type, NSPoint point) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}
// The event loop back in the default mode, as after a drag or a live resize.
static void RunLoop(void) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; }

// The text at the top edge of a part, kept as a point on a page.
typedef struct { PDFPage *page; NSPoint point; } Mark;
static NSClipView *Clip(PDFView *view) { return view.documentView.enclosingScrollView.contentView; }
static Mark TopMark(PDFView *view) {
    NSClipView *clip = Clip(view); NSRect b = clip.bounds;
    NSPoint top = [view convertPoint:NSMakePoint(NSMidX(b), clip.isFlipped ? NSMinY(b) : NSMaxY(b)) fromView:clip];
    PDFPage *page = [view pageForPoint:top nearest:YES];
    return (Mark){page, [view convertPoint:top toPage:page]};
}
// How far the marked text is from the top edge of the part, in points in the window.
static CGFloat Off(PDFView *view, Mark mark) {
    NSClipView *clip = Clip(view); NSRect b = clip.bounds;
    if (NSIsEmptyRect(b)) return 0;
    NSPoint edge = [clip convertPoint:NSMakePoint(NSMidX(b), clip.isFlipped ? NSMinY(b) : NSMaxY(b)) toView:nil];
    return [view convertPoint:[view convertPoint:mark.point fromPage:mark.page] toView:nil].y - edge.y;
}

// Both parts are scrolled into the middle of a page, away from where they are.
static void ScrollParts(PDFView *upper, PDFView *lower) {
    for (PDFView *view in @[upper, lower]) {
        NSClipView *clip = Clip(view);
        NSRect page = [view.documentView convertRect:[view convertRect:[[view.document pageAtIndex:view == upper ? 1 : 4]
            boundsForBox:kPDFDisplayBoxCropBox] fromPage:[view.document pageAtIndex:view == upper ? 1 : 4]] fromView:view];
        // A point a little more than half way down the page.
        CGFloat y = clip.isFlipped ? NSMinY(page) + NSHeight(page) * 0.55 : NSMaxY(page) - NSHeight(page) * 0.55 - NSHeight(clip.bounds);
        [clip scrollToPoint:[clip constrainBoundsRect:NSMakeRect(NSMinX(clip.bounds), y, NSWidth(clip.bounds), NSHeight(clip.bounds))].origin];
        [view.documentView.enclosingScrollView reflectScrolledClipView:clip];
    }
    [upper.window layoutIfNeeded];
    // PDFKit takes the scrolled pages as its current pages.
    RunLoop();
}

// A Preview window split in two, set up as in TSDocument.nib and mainSplitPdfKitWindow.
typedef struct { NSWindow *window; NSSplitView *split; PDFView *upper, *lower; TSPreviewSplitDivider *keeper; } Preview;
static Preview MakePreview(PDFDocument *document, BOOL vertical, BOOL keeper, BOOL autoScales) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 786, 984)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:window.contentView.bounds];
    split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    split.vertical = vertical;
    [window.contentView addSubview:split];
    PDFView *upper = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 786, 487)];
    PDFView *lower = [[PDFView alloc] initWithFrame:NSMakeRect(0, 496, 786, 488)];
    for (PDFView *view in @[upper, lower]) {
        view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        view.autoresizesSubviews = NO; view.wantsLayer = YES;
        view.document = document; view.displayMode = kPDFDisplaySinglePageContinuous;
        if (autoScales) view.autoScales = YES; else { view.autoScales = NO; view.scaleFactor = 1.0; }
        [split addSubview:view];
    }
    [split adjustSubviews];
    [window layoutIfNeeded];
    Preview p = {window, split, upper, lower, keeper ? [[TSPreviewSplitDivider alloc] initWithSplitView:split] : nil};
    ScrollParts(p.upper, p.lower);
    return p;
}
// One drag of the divider through the positions, in a single mouse-down.
static void Drag(NSSplitView *split, NSArray<NSNumber *> *positions) {
    NSWindow *window = split.window;
    CGFloat half = split.dividerThickness / 2;
    NSPoint from = [split convertPoint:NSMakePoint(300, NSMaxY(split.subviews[0].frame) + half) toView:nil];
    for (NSNumber *position in positions)
        [NSApp postEvent:MouseEvent(window, NSEventTypeLeftMouseDragged,
                                    [split convertPoint:NSMakePoint(300, position.doubleValue + half) toView:nil]) atStart:NO];
    [NSApp postEvent:MouseEvent(window, NSEventTypeLeftMouseUp,
                                [split convertPoint:NSMakePoint(300, positions.lastObject.doubleValue + half) toView:nil]) atStart:NO];
    [split mouseDown:MouseEvent(window, NSEventTypeLeftMouseDown, from)];
    [window layoutIfNeeded];
}
// The window keeps its top edge, as when its bottom edge is dragged.
static void SetWindowSize(NSWindow *window, CGFloat width, CGFloat height) {
    NSRect frame = window.frame; CGFloat top = NSMaxY(frame);
    frame.size = NSMakeSize(width, height); frame.origin.y = top - height;
    [window setFrame:frame display:NO];
    [window layoutIfNeeded];
}

// Measures the marked texts at each step of a resize: before the keeper (what PDFKit
// did) and after it (what is shown).
static PDFView *watchedUpper, *watchedLower; static Mark upperMark, lowerMark;
static CGFloat worstBefore, worstAfter; static int steps;
@interface Watcher : NSObject @end
@implementation Watcher
- (void)before:(NSNotification *)n {
    worstBefore = fmax(worstBefore, fmax(fabs(Off(watchedUpper, upperMark)), fabs(Off(watchedLower, lowerMark))));
}
- (void)after:(NSNotification *)n {
    steps++;
    worstAfter = fmax(worstAfter, fmax(fabs(Off(watchedUpper, upperMark)), fabs(Off(watchedLower, lowerMark))));
}
@end
static void Watch(Preview p) {
    watchedUpper = p.upper; watchedLower = p.lower;
    upperMark = TopMark(p.upper); lowerMark = TopMark(p.lower);
    worstBefore = worstAfter = 0; steps = 0;
}
static BOOL Kept(Preview p) { return fabs(Off(p.upper, upperMark)) <= 0.5 && fabs(Off(p.lower, lowerMark)) <= 0.5; }

// Up to macOS 15, AppKit gives the top part a content inset as large as the change of the
// window's height while the window is resized, and takes it away afterwards.
static NSEdgeInsets (*nativeInsets)(id, SEL);
static __weak NSScrollView *transientScroll; static CGFloat transientInset;
static NSEdgeInsets TransientInsets(NSScrollView *self, SEL _cmd) {
    NSEdgeInsets insets = nativeInsets(self, _cmd);
    if (self == transientScroll) insets.top += transientInset;
    return insets;
}

static NSEvent *CurrentEvent;
static NSEvent *TestCurrentEvent(id application, SEL selector) { return CurrentEvent; }

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    nativeInsets = (NSEdgeInsets (*)(id, SEL))method_setImplementation(
        class_getInstanceMethod(NSScrollView.class, @selector(contentInsets)), (IMP)TransientInsets);
    Check(INSTALLED, @"the Preview window installs the divider keeper when it splits");
    PDFDocument *document = MakeDocument();

    // Which resizes count as divider drags.
    {
        Preview p = MakePreview(document, NO, YES, NO);
        NSSplitView *split = p.split;
        NSDictionary *user = @{@"NSSplitViewUserResizeKey": @YES, @"NSSplitViewDividerIndex": @0};
        NSDictionary *program = @{@"NSSplitViewUserResizeKey": @NO, @"NSSplitViewDividerIndex": @0};
        NSNotification *(^note)(NSDictionary *) = ^(NSDictionary *info) {
            return [NSNotification notificationWithName:NSSplitViewWillResizeSubviewsNotification object:split userInfo:info]; };
        Check([TSPreviewSplitDivider isDividerDrag:note(user)], @"a resize by the user is a divider drag");
        Check(![TSPreviewSplitDivider isDividerDrag:note(program)], @"a resize by the program is not a divider drag");
        Check(![TSPreviewSplitDivider isDividerDrag:note(@{@"NSSplitViewDividerIndex": @0})],
              @"a resize of the window, without a mouse drag, is not a divider drag");
        Method current = class_getInstanceMethod(NSApplication.class, @selector(currentEvent));
        IMP originalCurrent = method_setImplementation(current, (IMP)TestCurrentEvent);
        CurrentEvent = MouseEvent(p.window, NSEventTypeLeftMouseDragged, NSMakePoint(20, 20));
        Check(![TSPreviewSplitDivider isDividerDrag:note(program)], @"a resize by the program during a mouse drag is not a divider drag");
        Check([TSPreviewSplitDivider isDividerDrag:note(@{@"NSSplitViewDividerIndex": @0})],
              @"without the split view's word, a resize during a mouse drag in the window is a divider drag");
        method_setImplementation(current, originalCurrent);
    }

    Watcher *watcher = [Watcher new];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNumber *autoScales in @[@NO, @YES]) {
        NSString *how = autoScales.boolValue ? @" (fit to width)" : @" (fixed scale)";
        // The watcher sees each step before the keeper, as it is registered first.
        Preview p = MakePreview(document, NO, NO, autoScales.boolValue);
        [center addObserver:watcher selector:@selector(before:) name:NSSplitViewDidResizeSubviewsNotification object:p.split];
        p.keeper = [[TSPreviewSplitDivider alloc] initWithSplitView:p.split];
        [center addObserver:watcher selector:@selector(after:) name:NSSplitViewDidResizeSubviewsNotification object:p.split];
        Watch(p);
        CGFloat lowerTopInWindow = NSMaxY([p.lower convertRect:p.lower.bounds toView:nil]);

        NSMutableArray<NSNumber *> *path = [NSMutableArray array];
        for (CGFloat y = 500; y <= 700; y += 25) [path addObject:@(y)];
        Drag(p.split, path);
        Check(Kept(p) && NSHeight(p.upper.frame) > 650 && NSMaxY([p.lower convertRect:p.lower.bounds toView:nil]) < lowerTopInWindow,
              [@"dragging the divider down keeps the top of the upper part, and the lower part's text moves with the divider" stringByAppendingString:how]);
        // One drag, in steps: down past the bottom of the window, up past its top, and back.
        [path removeAllObjects];
        CGFloat height = NSHeight(p.split.bounds);
        for (CGFloat y = 700; y <= height + 30; y += 13) [path addObject:@(y)];
        for (CGFloat y = height + 30; y >= -30; y -= 13) [path addObject:@(y)];
        for (CGFloat y = -30; y <= 440; y += 13) [path addObject:@(y)];
        Drag(p.split, path);
        printf("drag%s: %d steps; the text at the tops moved %.2f pt before the keeper and %.2f pt as shown\n",
               how.UTF8String, steps, worstBefore, worstAfter);
        Check(steps > 100, [@"the drag went through many steps" stringByAppendingString:how]);
        Check(worstBefore <= 0.5, [@"PDFKit does not scroll the parts away at any step of the drag" stringByAppendingString:how]);
        Check(worstAfter <= 0.5, [@"at every step of the drag, the text at the top of both parts stays where it is" stringByAppendingString:how]);
        Check(Kept(p) && fabs(NSHeight(p.upper.frame) - 440) < 4,
              [@"after pushing each part to no height, both come back with the same text at the top" stringByAppendingString:how]);
        RunLoop();
        Check(p.upper.postsFrameChangedNotifications && p.lower.postsFrameChangedNotifications,
              [@"PDFKit hears about the new sizes once the drag is over" stringByAppendingString:how]);
        Check(Kept(p) && NSEqualSizes(p.upper.documentView.enclosingScrollView.frame.size, p.upper.bounds.size) &&
              NSEqualSizes(p.lower.documentView.enclosingScrollView.frame.size, p.lower.bounds.size),
              [@"after the drag both parts keep their text and their scroll views fill them" stringByAppendingString:how]);

        // Changing the height of the window.
        ScrollParts(p.upper, p.lower);
        Watch(p);
        CGFloat upperHeight = NSHeight(p.upper.frame);
        for (NSNumber *h in @[@900, @760, @1040, @980])
            SetWindowSize(p.window, 786, h.doubleValue);
        printf("window height%s: %d steps; the text at the tops moved %.2f pt\n", how.UTF8String, steps, worstAfter);
        // AppKit aligns the scroll position to half units of the document; with the scale of
        // fitting the width that is up to 0.6pt in the view at a step (macOS 14 and 15). The
        // steps do not add up: the end is checked to 0.5pt, and the passing inset below.
        Check(steps >= 4 && worstAfter <= 0.75 && Kept(p) && NSHeight(p.upper.frame) != upperHeight,
              [@"changing the height of the window keeps the text at the top of both parts" stringByAppendingString:how]);
        RunLoop();
        Check(Kept(p) && p.upper.postsFrameChangedNotifications && p.lower.postsFrameChangedNotifications,
              [@"after the window was resized both parts keep their text, and PDFKit has seen the sizes" stringByAppendingString:how]);
        // And its width with it.
        ScrollParts(p.upper, p.lower);
        Watch(p);
        SetWindowSize(p.window, 700, 880);
        SetWindowSize(p.window, 820, 1000);
        RunLoop();
        Check(Kept(p), [@"changing the width and the height of the window keeps the text at the top of both parts" stringByAppendingString:how]);
        // A content inset the top part has only while the window is resized.
        ScrollParts(p.upper, p.lower);
        Watch(p);
        transientScroll = p.upper.documentView.enclosingScrollView;
        for (NSNumber *h in @[@920, @1080, @960, @1030, @975, @1000]) {
            transientInset = fabs(NSHeight(p.window.frame) - h.doubleValue);
            SetWindowSize(p.window, 820, h.doubleValue);
            transientInset = 0;
            RunLoop();
        }
        transientScroll = nil;
        printf("window height with a passing content inset%s: the text at the tops is %.2f and %.2f pt away\n", how.UTF8String,
               Off(p.upper, upperMark), Off(p.lower, lowerMark));
        Check(Kept(p), [@"a content inset the top part has only during the resize does not move its text" stringByAppendingString:how]);
        [center removeObserver:watcher];
    }

    // An unsplit window, or one split side by side, is resized as before.
    for (NSNumber *vertical in @[@NO, @YES]) {
        Preview with = MakePreview(document, vertical.boolValue, YES, NO), without = MakePreview(document, vertical.boolValue, NO, NO);
        Preview *both[] = {&with, &without};
        if (!vertical.boolValue)
            for (int k = 0; k < 2; k++) { [both[k]->lower removeFromSuperview]; [both[k]->split adjustSubviews]; [both[k]->window layoutIfNeeded]; }
        BOOL same = YES;
        for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(786, 900)], [NSValue valueWithSize:NSMakeSize(700, 760)],
                                [NSValue valueWithSize:NSMakeSize(786, 1040)]]) {
            for (int k = 0; k < 2; k++) SetWindowSize(both[k]->window, size.sizeValue.width, size.sizeValue.height);
            RunLoop();
            for (NSUInteger i = 0; i < with.split.subviews.count; i++) {
                PDFView *a = (PDFView *)with.split.subviews[i], *b = (PDFView *)without.split.subviews[i];
                same = same && NSEqualRects(a.frame, b.frame) && NSEqualPoints(Clip(a).bounds.origin, Clip(b).bounds.origin);
            }
        }
        Check(same, vertical.boolValue ? @"resizing a window split side by side is left as it was"
                                       : @"resizing an unsplit window is left as it was");
    }
    // The parts of a window split into a top and a bottom part get the same sizes as before.
    {
        Preview with = MakePreview(document, NO, YES, NO), without = MakePreview(document, NO, NO, NO);
        Preview *both[] = {&with, &without};
        BOOL same = YES;
        for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(786, 900)], [NSValue valueWithSize:NSMakeSize(700, 640)]]) {
            for (int k = 0; k < 2; k++) SetWindowSize(both[k]->window, size.sizeValue.width, size.sizeValue.height);
            for (NSUInteger i = 0; i < 2; i++)
                same = same && NSEqualRects(with.split.subviews[i].frame, without.split.subviews[i].frame);
        }
        RunLoop();
        Check(same, @"resizing the window gives the parts the same sizes as before");
    }

    // The last page cannot scroll past its end: the lower part shows its bottom.
    {
        Preview p = MakePreview(document, NO, YES, NO);
        // To the end of the document (goToPage: does not move a part offscreen up to macOS 15).
        NSClipView *clip = Clip(p.lower); NSRect end = clip.bounds;
        end.origin.y = clip.isFlipped ? 1e7 : -1e7;
        [clip scrollToPoint:[clip constrainBoundsRect:end].origin];
        [p.lower.documentView.enclosingScrollView reflectScrolledClipView:clip];
        [p.window layoutIfNeeded];
        Check([document indexForPage:[p.lower pageForPoint:NSMakePoint(NSMidX(p.lower.bounds), NSMidY(p.lower.bounds)) nearest:YES]] == 7,
              @"the lower part shows the end of the document before the drag");
        Drag(p.split, @[@450, @400, @500]);
        RunLoop();
        NSRect b = p.lower.bounds;
        Check([document indexForPage:[p.lower pageForPoint:NSMakePoint(NSMidX(b), NSMinY(b) + 0.5) nearest:YES]] == 7,
              @"at the end of the document the lower part still shows the last page");
    }

    // Moving the divider from the program leaves the parts to PDFKit.
    {
        Preview p = MakePreview(document, NO, YES, NO), q = MakePreview(document, NO, NO, NO);
        [p.split setPosition:600 ofDividerAtIndex:0]; [q.split setPosition:600 ofDividerAtIndex:0];
        [p.window layoutIfNeeded]; [q.window layoutIfNeeded];
        RunLoop();
        Check(NSEqualPoints(Clip(p.upper).bounds.origin, Clip(q.upper).bounds.origin) &&
              NSEqualPoints(Clip(p.lower).bounds.origin, Clip(q.lower).bounds.origin),
              @"a move of the divider by the program is left to PDFKit");
    }

    // A drag in a window split side by side is left alone.
    {
        Preview p = MakePreview(document, YES, YES, NO), q = MakePreview(document, YES, NO, NO);
        Preview *both[] = {&p, &q};
        for (int k = 0; k < 2; k++) {
            NSWindow *w = both[k]->window; NSSplitView *s = both[k]->split;
            NSPoint from = [s convertPoint:NSMakePoint(NSMaxX(s.subviews[0].frame) + s.dividerThickness / 2, 300) toView:nil];
            NSPoint to = [s convertPoint:NSMakePoint(250, 300) toView:nil];
            [NSApp postEvent:MouseEvent(w, NSEventTypeLeftMouseDragged, to) atStart:NO];
            [NSApp postEvent:MouseEvent(w, NSEventTypeLeftMouseUp, to) atStart:NO];
            [s mouseDown:MouseEvent(w, NSEventTypeLeftMouseDown, from)];
            [w layoutIfNeeded];
            RunLoop();
        }
        Check(NSEqualRects(p.upper.frame, q.upper.frame) && NSEqualPoints(Clip(p.upper).bounds.origin, Clip(q.upper).bounds.origin) &&
              NSEqualPoints(Clip(p.lower).bounds.origin, Clip(q.lower).bounds.origin),
              @"a drag in a window split side by side is left as it was");
    }

    if (failures) return 1;
    printf("PASS: both Preview parts keep their tops when the divider is dragged or the window height changes; other resizes are left alone\n");
} return 0; }
'''.replace('INSTALLED', 'YES' if installed else 'NO')

with tempfile.TemporaryDirectory(prefix='texshop-preview-split-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='latin1')
    (tmp / 'TSPreviewSplitDivider.m').write_text(text['TSPreviewSplitDivider.m'], encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-mmacosx-version-min=14.0', '-framework', 'Cocoa', '-framework', 'Quartz', *include_args(root),
                    '-I', str(root / 'Tests'), str(tmp / 'probe.m'), str(tmp / 'TSPreviewSplitDivider.m'),
                    '-o', str(tmp / 'probe')], check=True)
    if args.binary:
        import shutil
        shutil.copy2(tmp / 'probe', args.binary)
        sys.exit(0)
    result = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True, timeout=300)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr)
        sys.exit('FAIL')
