#!/usr/bin/env python3
"""A horizontal scroller that comes or goes in a Preview view only covers or uncovers
a strip at the bottom: the text stays where it is.

With scroll bars that are always shown, the scroller takes its height from the visible
area. That happens when a view gets narrower or wider than the pages (dragging the
divider of a window split side by side, changing the width of the window) and when the
magnification changes.

- Up to macOS 26 the document view of a PDFView is not flipped, so the scroll view keeps
  the bottom of the visible area, and the text jumped by the height of the scroller.
  This was measured in a macOS 26.6.2 virtual machine: -17pt for every scroller that
  appears, and the bottom kept when the height changes. The test makes the document view
  answer NO to isFlipped to get the same behaviour on later systems ("unflipped" model).
- When the magnification changes, PDFKit keeps the text at the centre of the visible
  area, which moves by half the height of the scroller, on every system.

Plain PDFViews run with the production TSPreviewScrollerKeeper and TSPreviewSplitDivider
in windows that are never ordered on screen. -[NSWindow isVisible] answers YES, so that
PDFKit takes the path it takes on screen.

The controls without the fix only show that the test sees the jumps on this system. A
later PDFKit that no longer jumps makes them a note, not a failure. --binary writes the
test program, built for macOS 14 and later, to run it on other systems.
"""
import argparse, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file

MUTATIONS = {
    # The text is not put back after the scroller came or went.
    'no-restore': ('TSPreviewScrollerKeeper.m',
        '    TSMoveTextUp(scroll, TSTextBelowTop(view, scroll, (TSPreviewText){YES, page, self.point}));\n', ''),
    # The text at the top is not noted before the scroller comes or goes.
    'no-prior': ('TSPreviewScrollerKeeper.m',
        'forKeyPath:@"hasHorizontalScroller" options:NSKeyValueObservingOptionPrior', 'forKeyPath:@"hasHorizontalScroller" options:0'),
    # The magnification is changed as PDFKit does it.
    'no-scale-fix': ('TSPreviewScrollerKeeper.m',
        '    TSMoveTextUp(scroll, TSTextBelowTop(view, scroll, text) - below);\n', ''),
    # The text is put back after every change of the magnification, also without a scroller change.
    'scale-fix-always': ('TSPreviewScrollerKeeper.m',
        '        fabs(TSVisibleHeight(scroll) - height) < 0.5)', '        NO)'),
    # Views with content insets are kept too.
    'insets-kept': ('TSPreviewScrollerKeeper.m', '    return insets.top != 0 || insets.bottom != 0;\n', '    return NO;\n'),
    # The Preview views do not use the keeper.
    'not-installed': ('MyPDFKitView.m', '    [super setDocument:document];\n    [TSPreviewScrollerKeeper installInView:self];\n',
        '    [super setDocument:document];\n'),
    'scale-not-kept': ('MyPDFKitView.m', '    TSPreviewChangeScale(self, ^{ [super setScaleFactor: scale]; });\n',
        '    [super setScaleFactor: scale];\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--binary', type=Path, help='write the test program here instead of running it')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
names = ('TSPreviewScrollerKeeper.m', 'TSPreviewSplitDivider.m', 'MyPDFKitView.m')
text = {name: source_file(root, name).read_text(encoding='utf-8', errors='surrogateescape') for name in names}
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert text[name].count(old) == 1, args.mutation
    text[name] = text[name].replace(old, new)

# The Preview views install the keeper and change the magnification through it.
view = text['MyPDFKitView.m']
def method(signature):
    start = view.index(signature)
    return view[start:view.index('\n}\n', start)]
installed = ('#import "TSPreviewScrollerKeeper.h"' in view and
             '[TSPreviewScrollerKeeper installInView:self];' in method('- (void)setDocument:(PDFDocument *)document') and
             '[TSPreviewScrollerKeeper installInView:self];' in method('- (void)viewDidMoveToWindow'))
scales = 'TSPreviewChangeScale(self, ^{ [super setScaleFactor: scale]; });' in method('- (void)setScaleFactor:(CGFloat)scale')

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewScrollerKeeper.h"
#import "TSPreviewSplitDivider.h"
static int failures; static const char *model;
static void Check(BOOL ok, NSString *name) { if (!ok) { printf("FAIL (%s): %s\n", model, name.UTF8String); failures++; } }
// A control that only shows the test sees the problem on this system.
static void Control(BOOL ok, NSString *name) { if (!ok) printf("NOTE (%s): not seen on this system: %s\n", model, name.UTF8String); }
static NSScrollerStyle Legacy(id s, SEL c) { return NSScrollerStyleLegacy; }
static NSScrollerStyle Overlay(id s, SEL c) { return NSScrollerStyleOverlay; }
static BOOL Yes(id s, SEL c) { return YES; }
static BOOL No(id s, SEL c) { return NO; }

static PDFDocument *MakeDocument(void) {
    PDFDocument *document = [PDFDocument new];
    for (int i = 0; i < 8; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600, 800)];
        [image lockFocus]; [NSColor.whiteColor set]; NSRectFill(NSMakeRect(0, 0, 600, 800)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return document;
}
static void RunLoop(void) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
static NSEvent *MouseEvent(NSWindow *window, NSEventType type, NSPoint point) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime
                          windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}
static NSScrollView *Scroll(PDFView *view) { return view.documentView.enclosingScrollView; }
static NSClipView *Clip(PDFView *view) { return Scroll(view).contentView; }
static BOOL HasScroller(PDFView *view) { return Scroll(view).hasHorizontalScroller && !Scroll(view).horizontalScroller.isHidden; }

// The text a distance below the top edge of the visible area, as a point on a page.
typedef struct { PDFPage *page; NSPoint point; } Mark;
static CGFloat TopInWindow(PDFView *view) {
    NSClipView *clip = Clip(view); NSRect b = clip.bounds;
    return [clip convertPoint:NSMakePoint(NSMidX(b), clip.isFlipped ? NSMinY(b) : NSMaxY(b)) toView:nil].y;
}
static Mark MarkAt(PDFView *view, CGFloat below) {
    NSPoint p = [view convertPoint:NSMakePoint(NSMidX(Clip(view).frame), TopInWindow(view) - below) fromView:nil];
    PDFPage *page = [view pageForPoint:p nearest:YES];
    return (Mark){page, [view convertPoint:p toPage:page]};
}
// How far the marked text is below the top edge of the visible area.
static CGFloat Below(PDFView *view, Mark mark) {
    return TopInWindow(view) - [view convertPoint:[view convertPoint:mark.point fromPage:mark.page] toView:nil].y;
}

static PDFView *MakeView(NSRect frame, PDFDocument *document, BOOL single, BOOL keeper) {
    PDFView *view = [[PDFView alloc] initWithFrame:frame];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.autoresizesSubviews = NO; view.wantsLayer = YES;
    view.document = document;
    if (keeper) [TSPreviewScrollerKeeper installInView:view];
    view.displayMode = single ? kPDFDisplaySinglePage : kPDFDisplaySinglePageContinuous;
    view.autoScales = NO; view.scaleFactor = 1.0;
    return view;
}
// Into the middle of a page, away from the ends of the document.
static void ScrollIntoPage(PDFView *view, NSUInteger index, CGFloat into) {
    NSClipView *clip = Clip(view); PDFPage *page = [view.document pageAtIndex:index];
    NSRect r = [view.documentView convertRect:[view convertRect:[page boundsForBox:kPDFDisplayBoxCropBox] fromPage:page] fromView:view];
    CGFloat y = clip.isFlipped ? NSMinY(r) + into : NSMaxY(r) - into - NSHeight(clip.bounds);
    [clip scrollToPoint:[clip constrainBoundsRect:NSMakeRect(NSMinX(clip.bounds), y, NSWidth(clip.bounds), NSHeight(clip.bounds))].origin];
    [Scroll(view) reflectScrolledClipView:clip];
    [view.window layoutIfNeeded]; RunLoop();
}
static NSWindow *MakeWindow(CGFloat width, CGFloat height) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    return window;
}
static void SetWidth(NSWindow *window, CGFloat width) {
    NSRect frame = window.frame; frame.size.width = width;
    [window setFrame:frame display:NO]; [window layoutIfNeeded]; RunLoop();
}

// An unsplit view: the width of the window crosses the width of the page.
// Returns the largest movement of the text at the top, and whether the scroller came and went.
static CGFloat WidthChanges(PDFDocument *document, BOOL single, BOOL keeper, BOOL *toggled) {
    NSWindow *window = MakeWindow(900, 700);
    PDFView *view = MakeView(window.contentView.bounds, document, single, keeper);
    [window.contentView addSubview:view]; [window layoutIfNeeded]; RunLoop();
    ScrollIntoPage(view, single ? 0 : 2, 60);
    Mark mark = MarkAt(view, 0); CGFloat worst = 0; BOOL appeared = NO, gone = NO;
    for (NSNumber *width in @[@500, @900, @450, @760, @430, @900]) {
        SetWidth(window, width.doubleValue);
        if (HasScroller(view)) appeared = YES; else gone = YES;
        worst = fmax(worst, fabs(Below(view, mark)));
    }
    *toggled = appeared && gone;
    return worst;
}

// Magnification steps across the scale where the scroller appears. Returns the largest
// movement, in one step, of the text at the centre of the visible area.
static CGFloat ScaleSteps(PDFDocument *document, BOOL single, BOOL keep, BOOL *toggled) {
    NSWindow *window = MakeWindow(900, 700);
    PDFView *view = MakeView(window.contentView.bounds, document, single, YES);
    [window.contentView addSubview:view]; [window layoutIfNeeded]; RunLoop();
    ScrollIntoPage(view, single ? 0 : 2, 60);
    CGFloat worst = 0; BOOL appeared = NO, gone = NO;
    for (NSNumber *scale in @[@1.2, @1.3, @1.4, @1.5, @1.6, @1.5, @1.4, @1.3, @1.2, @1.0]) {
        CGFloat half = NSHeight(Clip(view).frame) / 2;
        Mark mark = MarkAt(view, half);
        if (keep) TSPreviewChangeScale(view, ^{ view.scaleFactor = scale.doubleValue; });
        else view.scaleFactor = scale.doubleValue;
        [window layoutIfNeeded]; RunLoop();
        if (HasScroller(view)) appeared = YES; else gone = YES;
        worst = fmax(worst, fabs(Below(view, mark) - half));
    }
    *toggled = appeared && gone;
    return worst;
}

// A Preview window split in two, as in mainSplitPdfKitWindow, with the divider keeper.
typedef struct { NSWindow *window; NSSplitView *split; PDFView *a, *b; TSPreviewSplitDivider *divider; } Split;
static Split MakeSplit(PDFDocument *document, BOOL vertical, CGFloat width) {
    NSWindow *window = MakeWindow(width, 984);
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:window.contentView.bounds];
    split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; split.vertical = vertical;
    [window.contentView addSubview:split];
    PDFView *a = MakeView(NSMakeRect(0, 0, width / 2, 487), document, NO, YES);
    PDFView *b = MakeView(NSMakeRect(0, 0, width / 2, 487), document, NO, YES);
    [split addSubview:a]; [split addSubview:b]; [split adjustSubviews];
    [window layoutIfNeeded]; RunLoop();
    ScrollIntoPage(a, 1, 300); ScrollIntoPage(b, 4, 450);
    return (Split){window, split, a, b, [[TSPreviewSplitDivider alloc] initWithSplitView:split]};
}
static Mark watchMarkA, watchMarkB; static Split watched; static CGFloat watchWorst; static BOOL watchA, watchB;
@interface Watcher : NSObject @end
@implementation Watcher
- (void)did:(NSNotification *)n {
    watchWorst = fmax(watchWorst, fmax(fabs(Below(watched.a, watchMarkA)), fabs(Below(watched.b, watchMarkB))));
    if (HasScroller(watched.a)) watchA = YES;
    if (HasScroller(watched.b)) watchB = YES;
}
@end

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    model = argv[1];
    BOOL overlay = !strcmp(model, "overlay");
    method_setImplementation(class_getClassMethod(NSScroller.class, @selector(preferredScrollerStyle)), overlay ? (IMP)Overlay : (IMP)Legacy);
    method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(isVisible)), (IMP)Yes);
    [NSApplication sharedApplication];
    if (!strcmp(model, "unflipped"))
        method_setImplementation(class_getInstanceMethod(NSClassFromString(@"PDFDocumentView"), @selector(isFlipped)), (IMP)No);
    if (!strcmp(model, "sources")) {
        Check(INSTALLED, @"the Preview views keep their text when the scroller comes or goes");
        Check(SCALES, @"the Preview views change the magnification through TSPreviewChangeScale");
        return failures ? 1 : 0;
    }
    PDFDocument *document = MakeDocument();
    BOOL flipped;
    { PDFView *probe = MakeView(NSMakeRect(0, 0, 100, 100), document, NO, NO); flipped = probe.documentView.isFlipped; }
    printf("%s: document view flipped %d, scroller %s\n", model, flipped, overlay ? "overlay" : "legacy");

    // (a)/(b) without a split: the width of the window crosses the width of the page.
    for (int single = 0; single < 2; single++) {
        BOOL toggled = NO;
        CGFloat kept = WidthChanges(document, single, YES, &toggled);
        Check(overlay || toggled, @"the horizontal scroller comes and goes with the width");
        Check(kept <= 0.5, [NSString stringWithFormat:@"%s: the text at the top stays when the scroller comes or goes (%.2fpt)",
                            single ? "single page" : "continuous", kept]);
        CGFloat bare = WidthChanges(document, single, NO, &toggled);
        if (!flipped && !overlay)
            Control(bare >= 10, [NSString stringWithFormat:@"without the keeper the text jumps by the scroller (%.2fpt)", bare]);
        if (overlay)
            Check(bare <= 0.5, @"overlay scrollers never moved the text");
    }

    // (a) A window split side by side: the divider is dragged so that each part gets
    // narrower than the page and wider again, through NSSplitView's own tracking.
    {
        Split s = MakeSplit(document, YES, 1400);
        watched = s; watchMarkA = MarkAt(s.a, 0); watchMarkB = MarkAt(s.b, 0); watchWorst = 0; watchA = watchB = NO;
        Watcher *watcher = [Watcher new];
        [NSNotificationCenter.defaultCenter addObserver:watcher selector:@selector(did:) name:NSSplitViewDidResizeSubviewsNotification object:s.split];
        CGFloat half = s.split.dividerThickness / 2;
        NSPoint from = [s.split convertPoint:NSMakePoint(NSMaxX(s.split.subviews[0].frame) + half, 300) toView:nil];
        for (int x = 690; x >= 350; x -= 20)
            [NSApp postEvent:MouseEvent(s.window, NSEventTypeLeftMouseDragged, [s.split convertPoint:NSMakePoint(x, 300) toView:nil]) atStart:NO];
        for (int x = 370; x <= 1050; x += 20)
            [NSApp postEvent:MouseEvent(s.window, NSEventTypeLeftMouseDragged, [s.split convertPoint:NSMakePoint(x, 300) toView:nil]) atStart:NO];
        [NSApp postEvent:MouseEvent(s.window, NSEventTypeLeftMouseUp, [s.split convertPoint:NSMakePoint(1050, 300) toView:nil]) atStart:NO];
        [s.split mouseDown:MouseEvent(s.window, NSEventTypeLeftMouseDown, from)];
        [s.window layoutIfNeeded]; RunLoop(); [watcher did:nil];
        [NSNotificationCenter.defaultCenter removeObserver:watcher];
        Check(overlay || (watchA && watchB), @"both parts got a horizontal scroller during the drag");
        Check(watchWorst <= 0.5, [NSString stringWithFormat:@"split side by side: both parts keep their tops during the drag (%.2fpt)", watchWorst]);
    }

    // (b) A window split into a top and a bottom part: its width crosses the width of the page.
    {
        Split s = MakeSplit(document, NO, 1000);
        Mark a = MarkAt(s.a, 0), b = MarkAt(s.b, 0); CGFloat worst = 0; BOOL appeared = NO, gone = NO;
        for (NSNumber *width in @[@560, @1000, @450, @800, @500, @1000]) {
            SetWidth(s.window, width.doubleValue);
            if (HasScroller(s.a) && HasScroller(s.b)) appeared = YES;
            if (!HasScroller(s.a) && !HasScroller(s.b)) gone = YES;
            worst = fmax(worst, fmax(fabs(Below(s.a, a)), fabs(Below(s.b, b))));
        }
        Check(overlay || (appeared && gone), @"the scrollers of both parts come and go with the width");
        Check(worst <= 0.5, [NSString stringWithFormat:@"split top and bottom: both parts keep their tops when the width changes (%.2fpt)", worst]);
        // The height of such a window still keeps the tops (#24, beta-9).
        NSRect frame = s.window.frame; CGFloat top = NSMaxY(frame);
        frame.size.height = 700; frame.origin.y = top - 700;
        [s.window setFrame:frame display:NO]; [s.window layoutIfNeeded]; RunLoop();
        Check(fabs(Below(s.a, a)) <= 0.5 && fabs(Below(s.b, b)) <= 0.5,
              [NSString stringWithFormat:@"split top and bottom: the tops are kept when the height changes (%.2f, %.2fpt)", Below(s.a, a), Below(s.b, b)]);
    }

    // (c) The magnification crosses the scale where the scroller appears.
    for (int single = 0; single < 2; single++) {
        BOOL toggled = NO;
        CGFloat kept = ScaleSteps(document, single, YES, &toggled);
        Check(overlay || toggled, @"the horizontal scroller comes and goes with the magnification");
        Check(kept <= 1.0, [NSString stringWithFormat:@"%s: the text at the centre stays when the magnification changes (%.2fpt)",
                            single ? "single page" : "continuous", kept]);
        CGFloat bare = ScaleSteps(document, single, NO, &toggled);
        if (!overlay)
            Control(bare >= 5, [NSString stringWithFormat:@"without the fix the text jumps by half the scroller (%.2fpt)", bare]);
        else
            Check(fabs(bare - kept) <= 0.01, @"overlay scrollers: the magnification is left to PDFKit");
    }

    // A view with content insets is left to PDFKit: the text noted while the scroller comes or
    // goes is not always the text at the top then (Codex's case in the first audit).
    {
        CGFloat moved[2];
        for (int keep = 0; keep < 2; keep++) {
            NSWindow *window = MakeWindow(900, 500);
            PDFView *view = MakeView(window.contentView.bounds, document, NO, keep);
            [window.contentView addSubview:view]; [window layoutIfNeeded]; RunLoop();
            Scroll(view).automaticallyAdjustsContentInsets = NO;
            Scroll(view).contentInsets = NSEdgeInsetsMake(23, 7, 11, 13);
            RunLoop();
            ScrollIntoPage(view, 3, 150);
            Mark mark = MarkAt(view, 90); CGFloat before = Below(view, mark); moved[keep] = 0;
            for (NSNumber *width in @[@450, @900, @500, @1000]) {
                SetWidth(window, width.doubleValue);
                moved[keep] = fmax(moved[keep], fabs(Below(view, mark) - before));
            }
        }
        Check(fabs(moved[1] - moved[0]) <= 0.5, [NSString stringWithFormat:
              @"with content insets the text moves as it does without the keeper (%.2f and %.2fpt)", moved[1], moved[0]]);
    }

    // A view that gets another document, and a view that goes away with its keeper.
    {
        NSWindow *window = MakeWindow(900, 700);
        PDFView *view = MakeView(window.contentView.bounds, document, NO, YES);
        [window.contentView addSubview:view]; [window layoutIfNeeded]; RunLoop();
        view.document = MakeDocument(); [TSPreviewScrollerKeeper installInView:view]; [TSPreviewScrollerKeeper installInView:view];
        [window layoutIfNeeded]; RunLoop();
        ScrollIntoPage(view, 3, 200);
        Mark mark = MarkAt(view, 0);
        SetWidth(window, 450);
        Check(HasScroller(view) || overlay, @"the scroller appears for the new document");
        Check(fabs(Below(view, mark)) <= 0.5, @"the text stays for the new document, with the keeper installed again");
        @autoreleasepool { [view removeFromSuperview]; view = nil; }
        RunLoop();
    }

    if (failures) return 1;
    printf("PASS (%s): the text stays when a horizontal scroller comes or goes\n", model);
} return 0; }
'''.replace('INSTALLED', 'YES' if installed else 'NO').replace('SCALES', 'YES' if scales else 'NO')

with tempfile.TemporaryDirectory(prefix='texshop-preview-scroller-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='utf-8')
    for name in ('TSPreviewScrollerKeeper.m', 'TSPreviewSplitDivider.m'):
        (tmp / name).write_text(text[name], encoding='utf-8', errors='surrogateescape')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-mmacosx-version-min=14.0', '-framework', 'Cocoa', '-framework', 'Quartz', *include_args(root),
                    '-I', str(root / 'Tests'), str(tmp / 'probe.m'), str(tmp / 'TSPreviewScrollerKeeper.m'),
                    str(tmp / 'TSPreviewSplitDivider.m'), '-o', str(tmp / 'probe')], check=True)
    if args.binary:
        import shutil
        shutil.copy2(tmp / 'probe', args.binary)
        print(f'wrote {args.binary}; run it with the models sources, unflipped, system and overlay')
        sys.exit(0)
    failed = False
    for model in ('sources', 'unflipped', 'system', 'overlay'):
        result = subprocess.run([str(tmp / 'probe'), model], capture_output=True, text=True, timeout=300)
        print(result.stdout, end='')
        if result.returncode:
            if not args.mutation:
                print(result.stderr)
            failed = True
    if args.mutation:
        if not failed:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif failed:
        sys.exit('FAIL')
