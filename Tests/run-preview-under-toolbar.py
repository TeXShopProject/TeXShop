#!/usr/bin/env python3
"""The part of the Preview under the title bar and the toolbar (macOS 26 and later).

In a document window whose content runs under the toolbar, the Preview reaches the
top of the window. A click or a pointer on the toolbar is then inside the Preview's
bounds, but it belongs to the toolbar. With the production code, in windows that
are never ordered on screen, the test checks:

- the test that sendEvent: of the Preview window and of the combined window uses to
  hand a click to the magnifying glass refuses every point on the title bar and the
  toolbar, takes the same points of the Preview as on earlier systems below them,
  and never takes a point that AppKit's hit test gives to another view;
- mouseMoved: of the Preview shows neither the tool's cursor nor a popup for a link
  while the pointer is on the toolbar, and leaves the cursor of a toolbar control
  alone;
- resetCursorRects gives the tool its cursor only below the toolbar;
- a window whose content does not run under the toolbar behaves as before.

Where content does not run under the toolbar (before macOS 26), only the last
group applies and the others are reported as skipped.
"""
import argparse, os, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file
from production_fragments import method, verify_embedded

MUTATIONS = {
    # The magnifying glass takes clicks anywhere in the Preview's bounds, toolbar included (#44).
    'glass-takes-toolbar-clicks': ('guard', 'NSRect Inside = TSDocumentWindowRectBelowToolbar(aView, aView.bounds);', 'NSRect Inside = aView.bounds;'),
    # The band under the toolbar is never recognized.
    'band-not-recognized': ('glass', '    return NSIntersectionRect(rect, [view convertRect:window.contentLayoutRect fromView:nil]);\n', '    return rect;\n'),
    # A pointer on the toolbar counts as a pointer over the page under it.
    'pointer-on-toolbar-over-page': ('moved', '    if (TSDocumentWindowPointIsUnderToolbar(self.window, theEvent.locationInWindow)) {', '    if (NO) {'),
    # The arrow is set again with every move, over the cursor of a toolbar control.
    'toolbar-cursor-overridden': ('moved', '        if (! pointerIsUnderToolbar) {', '        {'),
    # A popup that a link started stays when the pointer goes up to the toolbar.
    'popup-stays-under-toolbar': ('moved', '        if (self.handlingLink > 0) [self killTransientLinkPreview];\n        if (! pointerIsUnderToolbar) {', '        if (! pointerIsUnderToolbar) {'),
    # The tool has its cursor rectangle over the toolbar too.
    'cursor-rects-under-toolbar': ('rects', '\tNSRect toolRect = TSDocumentWindowRectBelowToolbar(self, [self visibleRect]);', '\tNSRect toolRect = [self visibleRect];'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]

def read(name):
    return source_file(root, name).read_text(encoding='latin1')
view_source = read('MyPDFKitView.m')
glass_source = read('TSDocumentWindowGlass.m')
globals_source = read('globals.h')
for line in ('NEW_MOUSE_MODE_SCROLL = 1,', 'NEW_MOUSE_MODE_SELECT_TEXT = 2,', 'NEW_MOUSE_MODE_MAG_GLASS = 3,',
             'NEW_MOUSE_MODE_MAG_GLASS_L = 4,', 'NEW_MOUSE_MODE_SELECT_PDF = 5'):
    assert line in globals_source, line

fragments = []
# The statements of sendEvent: that decide whether the magnifying glass takes a click.
def guard(name):
    text = read(name)
    send = method(text, '- (void)sendEvent:(NSEvent *)theEvent')
    assert '[[self.myDocument pdfKitView] fancyMouseDown: theEvent];' in send, name
    first, last = 'NSPoint thePoint = [theEvent locationInWindow];', 'BOOL inPDF = [aView mouse: aPoint inRect: Inside];'
    assert send.count(first) == 1 and send.count(last) == 1, name
    span = send[send.index(first):send.index(last) + len(last)]
    fragments.append(('statement span: the magnifying glass takes a click, ' + name, text, span))
    return span
guards = {'PREVIEWGUARD': guard('TSPreviewWindow.m'), 'COMBINEDGUARD': guard('TSFullSplitWindow.m')}
moved = method(view_source, '- (void) mouseMoved: (NSEvent *) theEvent')
rects = method(view_source, '- (void)resetCursorRects')
fragments.append(('complete method: mouseMoved:', view_source, moved))
fragments.append(('complete method: resetCursorRects', view_source, rects))

if args.mutation:
    where, old, new = MUTATIONS[args.mutation]
    if where == 'guard':
        for key in guards:
            assert guards[key].count(old) == 1, args.mutation
            guards[key] = guards[key].replace(old, new)
    elif where == 'glass':
        assert glass_source.count(old) == 1, args.mutation
        glass_source = glass_source.replace(old, new)
    elif where == 'moved':
        assert moved.count(old) == 1, args.mutation
        moved = moved.replace(old, new)
    else:
        assert rects.count(old) == 1, args.mutation
        rects = rects.replace(old, new)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSDocumentWindowGlass.h"
// The values of Sources/App/globals.h (checked by the script).
#define NEW_MOUSE_MODE_SCROLL 1
#define NEW_MOUSE_MODE_SELECT_TEXT 2
#define NEW_MOUSE_MODE_MAG_GLASS 3
#define NEW_MOUSE_MODE_MAG_GLASS_L 4
#define NEW_MOUSE_MODE_SELECT_PDF 5
static int failures, checks, skipped;
static void Check(BOOL ok, NSString *name) { checks++; if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }

// The pinned popup: there is none in this test.
@interface PopupStandIn : NSObject
- (NSCursor *)cursorAtPoint:(NSPoint)point;
@end
@implementation PopupStandIn
- (NSCursor *)cursorAtPoint:(NSPoint)point { return nil; }
@end

@interface MyPDFKitView : PDFView
{
@public
    NSInteger mouseMode, currentMouseMode;
    PopupStandIn *pinnedLinkPreview;
    BOOL showsLinkPreviewCursor;
    BOOL pointerIsUnderToolbar;
    NSRect selectedRect;
}
@property NSInteger handlingLink, timerNumber;
@property BOOL overLink, linkPopups, recordsCursorRects;
@property NSUInteger kills;
@property (strong) NSTimer *selRectTimer;
@property (strong) NSMutableArray *toolCursorRects;
@end
@implementation MyPDFKitView
- (void)killTransientLinkPreview { self.kills++; self.handlingLink = 0; }
- (void)showToolCursorOutsideLinkPreviewWithEvent:(NSEvent *)event { showsLinkPreviewCursor = NO; }
- (BOOL)showsLinkPopupsWithModifierFlags:(NSEventModifierFlags)flags { return self.linkPopups; }
- (void)increaseTimerNumber { self.timerNumber++; }
- (void)handleLink:(NSTimer *)timer {}
// PDFKit's own answer for the point, with a link there when the test says so.
- (PDFAreaOfInterest)areaOfInterestForMouse:(NSEvent *)event {
    PDFAreaOfInterest area = [self areaOfInterestForPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    return (area & kPDFPageArea) && self.overLink ? area | kPDFLinkArea : area;
}
// The rectangles the production resetCursorRects adds, in the window's coordinates.
- (void)addCursorRect:(NSRect)rect cursor:(NSCursor *)cursor {
    if (self.recordsCursorRects) [self.toolCursorRects addObject:[NSValue valueWithRect:[self convertRect:rect toView:nil]]];
}
MOVED
RECTS
@end

@interface GuardDocument : NSObject
@property (weak) MyPDFKitView *pdfKitView;
@end
@implementation GuardDocument
@end
@interface GuardWindow : NSWindow
@property (strong) GuardDocument *myDocument;
- (BOOL)glassTakes:(NSEvent *)theEvent;
@end
@implementation GuardWindow
- (BOOL)glassTakes:(NSEvent *)theEvent { return NO; }
@end
// The Preview window.
@interface PreviewGuardWindow : GuardWindow
@end
@implementation PreviewGuardWindow
- (BOOL)glassTakes:(NSEvent *)theEvent {
    PREVIEWGUARD
    return inPDF;
}
@end
// The window with the source and the Preview.
@interface CombinedGuardWindow : GuardWindow
@end
@implementation CombinedGuardWindow
- (BOOL)glassTakes:(NSEvent *)theEvent {
    COMBINEDGUARD
    return inPDF;
}
@end

// An Expanded toolbar with a few items, as the document windows have.
@interface BandToolbar : NSObject <NSToolbarDelegate>
@end
@implementation BandToolbar
- (NSArray *)items { return @[@"a", @"b", @"c", NSToolbarFlexibleSpaceItemIdentifier, @"d", @"e"]; }
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return self.items; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return self.items; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = identifier; item.image = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:nil];
    return item;
}
@end
static BandToolbar *toolbarDelegate;

static void Settle(NSWindow *window) {
    for (int i = 0; i < 4; i++) {
        [window layoutIfNeeded];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}
static PDFDocument *Document(void) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 595, 842);
    CGContextRef c = CGPDFContextCreate(consumer, &box, NULL);
    for (int n = 0; n < 4; n++) {
        CGPDFContextBeginPage(c, NULL);
        CGContextSetRGBFillColor(c, 0, 0, 0, 1);
        CGContextFillRect(c, CGRectMake(100, 100 + 150 * n, 200, 40));
        CGPDFContextEndPage(c);
    }
    CGPDFContextClose(c); CGContextRelease(c); CGDataConsumerRelease(consumer);
    return [[PDFDocument alloc] initWithData:data];
}
// A document window with a toolbar. In the combined window the Preview has the right half.
static GuardWindow *Open(Class class, BOOL combined, BOOL prepare) {
    GuardWindow *window = [[class alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.toolbarStyle = NSWindowToolbarStyleExpanded;
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:[NSString stringWithFormat:@"band-%@-%d", NSStringFromClass(class), prepare]];
    toolbar.delegate = toolbarDelegate; window.toolbar = toolbar;
    NSView *content = window.contentView;
    NSRect frame = content.bounds;
    if (combined) { frame.origin.x = floor(NSWidth(frame) / 2); frame.size.width -= frame.origin.x; }
    MyPDFKitView *view = [[MyPDFKitView alloc] initWithFrame:frame];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable | (combined ? NSViewMinXMargin : 0);
    view.toolCursorRects = [NSMutableArray array];
    [content addSubview:view];
    view.document = Document(); view.autoScales = NO; view.scaleFactor = 1;
    window.myDocument = [GuardDocument new]; window.myDocument.pdfKitView = view;
    [window setFrame:NSMakeRect(60, 60, 900, 760) display:NO];
    if (prepare) TSDocumentWindowPrepare(window);
    Settle(window);
    return window;
}
static NSEvent *Mouse(NSWindow *window, NSEventType type, NSPoint point) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0 windowNumber:window.windowNumber
        context:nil eventNumber:0 clickCount:type == NSEventTypeMouseMoved ? 0 : 1 pressure:type == NSEventTypeMouseMoved ? 0 : 1];
}
static CGFloat Band(NSWindow *window) { return NSHeight(window.contentView.frame) - NSMaxY(window.contentLayoutRect); }

// The clicks the magnifying glass takes, over the whole frame of the window.
static void CheckGuard(Class class, BOOL combined, BOOL prepare) {
    GuardWindow *window = Open(class, combined, prepare);
    MyPDFKitView *view = window.myDocument.pdfKitView;
    NSString *name = [NSString stringWithFormat:@"%@%@", combined ? @"combined window" : @"Preview window",
                      prepare ? @"" : @", content below the toolbar"];
    BOOL under = (window.styleMask & NSWindowStyleMaskFullSizeContentView) != 0;
    NSRect viewInWindow = [view convertRect:view.bounds toView:nil];
    NSRect layout = window.contentLayoutRect;
    if (under) {
        Check(Band(window) > 20, [NSString stringWithFormat:@"%@: the toolbar lies over the content (%.0f)", name, Band(window)]);
        Check(NSMaxY(viewInWindow) > NSMaxY(layout) + 20, [NSString stringWithFormat:@"%@: the Preview reaches under the toolbar", name]);
    } else
        Check(NSMaxY(viewInWindow) <= NSMaxY(layout) + .5, [NSString stringWithFormat:@"%@: the Preview ends at the toolbar", name]);
    // What the glass took before content ran under the toolbar: the Preview less a margin of 15 points.
    NSRect expected = NSInsetRect(NSIntersectionRect(viewInWindow, layout), 15, 15);
    NSView *frameView = window.contentView.superview;
    NSUInteger taken = 0, wrong = 0, notPreview = 0, onBand = 0, othersOnBand = 0;
    NSString *firstWrong = nil, *firstOther = nil;
    for (CGFloat y = 3.5; y < NSHeight(window.frame); y += 5) for (CGFloat x = 3.5; x < NSWidth(window.frame); x += 5) {
        NSPoint point = NSMakePoint(x, y);
        BOOL takes = [window glassTakes:Mouse(window, NSEventTypeLeftMouseDown, point)];
        BOOL should = NSPointInRect(point, expected);
        taken += takes;
        if (takes != should) { wrong++; if (!firstWrong) firstWrong = NSStringFromPoint(point); }
        NSView *hit = [frameView hitTest:point];
        BOOL inPreview = hit && [hit isDescendantOf:view];
        if (takes && !inPreview) { notPreview++; if (!firstOther) firstOther = [NSString stringWithFormat:@"%@ %@", NSStringFromPoint(point), hit.className]; }
        if (y >= NSMaxY(layout)) {
            onBand += takes;
            if (NSPointInRect(point, viewInWindow) && !inPreview) othersOnBand++;
        }
    }
    Check(taken > 1000, [NSString stringWithFormat:@"%@: the glass takes clicks in the Preview (%lu points)", name, (unsigned long)taken]);
    Check(onBand == 0, [NSString stringWithFormat:@"%@: the glass takes no click on the title bar and the toolbar (%lu points)", name, (unsigned long)onBand]);
    Check(wrong == 0, [NSString stringWithFormat:@"%@: the glass takes the Preview below the toolbar less 15 points, as before (%lu points differ, first %@)",
                       name, (unsigned long)wrong, firstWrong]);
    Check(notPreview == 0, [NSString stringWithFormat:@"%@: the glass takes no click that AppKit gives to another view (%lu points, first %@)",
                            name, (unsigned long)notPreview, firstOther]);
    if (under)
        Check(othersOnBand > 100, [NSString stringWithFormat:@"%@: views of the toolbar lie over the Preview (%lu points)", name, (unsigned long)othersOnBand]);
    if (!under) {
        Check(NSEqualRects(TSDocumentWindowRectBelowToolbar(view, view.bounds), view.bounds), [name stringByAppendingString:@": the whole Preview counts"]);
        Check(!TSDocumentWindowPointIsUnderToolbar(window, NSMakePoint(100, NSHeight(window.frame) - 10)), [name stringByAppendingString:@": no band under the toolbar"]);
    }
}

// The pointer on the toolbar, over a page that has scrolled under it.
static void CheckPointer(void) {
    GuardWindow *window = Open(PreviewGuardWindow.class, NO, YES);
    MyPDFKitView *view = window.myDocument.pdfKitView;
    NSRect layout = window.contentLayoutRect;
    NSPoint on = NSMakePoint(NSMidX(layout), NSMaxY(layout) + Band(window) / 2), below = NSMakePoint(NSMidX(layout), NSMaxY(layout) - 120);
    // The second page comes to the top of the Preview, so a page lies under the toolbar.
    [view goToPage:[view.document pageAtIndex:1]]; Settle(window);
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    for (int i = 0; i < 6 && !([view areaOfInterestForPoint:[view convertPoint:on fromView:nil]] & kPDFPageArea); i++) {
        NSClipView *clip = scroll.contentView;
        NSRect b = clip.bounds; b.origin.y += (scroll.documentView.isFlipped ? 60 : -60) * (i % 2 ? -(i + 1) : (i + 1));
        [clip scrollToPoint:[clip constrainBoundsRect:b].origin]; [scroll reflectScrolledClipView:clip]; Settle(window);
    }
    Check(([view areaOfInterestForPoint:[view convertPoint:on fromView:nil]] & kPDFPageArea) != 0, @"fixture: a page lies under the toolbar, and PDFKit finds it there");
    Check(([view areaOfInterestForPoint:[view convertPoint:below fromView:nil]] & kPDFPageArea) != 0, @"fixture: a page lies below the toolbar");
    Check(TSDocumentWindowPointIsUnderToolbar(window, on) && !TSDocumentWindowPointIsUnderToolbar(window, below), @"the point on the toolbar is told from the point below it");

    view->mouseMode = view->currentMouseMode = NEW_MOUSE_MODE_SCROLL;
    [NSCursor.IBeamCursor set];
    [view mouseMoved:Mouse(window, NSEventTypeMouseMoved, below)];
    Check(NSCursor.currentCursor == NSCursor.openHandCursor, @"the hand tool shows its cursor over the page below the toolbar");
    [view mouseMoved:Mouse(window, NSEventTypeMouseMoved, on)];
    Check(NSCursor.currentCursor == NSCursor.arrowCursor, @"on the toolbar the arrow comes back, though a page lies under it");
    // A text field of the toolbar sets its own cursor; further moves leave it.
    [NSCursor.IBeamCursor set];
    [view mouseMoved:Mouse(window, NSEventTypeMouseMoved, on)];
    Check(NSCursor.currentCursor == NSCursor.IBeamCursor, @"moving on the toolbar leaves the cursor of a toolbar control alone");
    [view mouseMoved:Mouse(window, NSEventTypeMouseMoved, below)];
    Check(NSCursor.currentCursor == NSCursor.openHandCursor, @"back over the page, the hand tool shows its cursor again");
    [view mouseMoved:Mouse(window, NSEventTypeMouseMoved, on)];
    Check(NSCursor.currentCursor == NSCursor.arrowCursor, @"and the arrow comes back on the toolbar again");

    // A link under the toolbar shows no popup; a popup started below ends on the way up.
    view.linkPopups = YES; view.overLink = YES;
    [view mouseMoved:Mouse(window, NSEventTypeMouseMoved, on)];
    Check(view.handlingLink == 0 && view.timerNumber == 0, @"a link under the toolbar starts no popup");
    [view mouseMoved:Mouse(window, NSEventTypeMouseMoved, below)];
    Check(view.handlingLink == 1, @"fixture: a link below the toolbar starts its popup");
    [view mouseMoved:Mouse(window, NSEventTypeMouseMoved, on)];
    Check(view.handlingLink == 0 && view.kills == 1, @"the popup of a link goes away when the pointer moves up to the toolbar");
    view.linkPopups = NO; view.overLink = NO;

    // Cursor rectangles of every tool end at the toolbar.
    NSInteger modes[] = {NEW_MOUSE_MODE_SCROLL, NEW_MOUSE_MODE_SELECT_PDF, NEW_MOUSE_MODE_MAG_GLASS, NEW_MOUSE_MODE_MAG_GLASS_L, 0};
    NSRect seen = NSIntersectionRect([view convertRect:view.visibleRect toView:nil], layout);
    for (int i = 0; i < 5; i++) {
        view->currentMouseMode = modes[i];
        [view.toolCursorRects removeAllObjects];
        view.recordsCursorRects = YES; [view resetCursorRects]; view.recordsCursorRects = NO;
        BOOL whole = NO, above = NO;
        for (NSValue *value in view.toolCursorRects) {
            NSRect rect = value.rectValue;
            if (NSMaxY(rect) > NSMaxY(layout) + .5) above = YES;
            if (fabs(NSMinX(rect) - NSMinX(seen)) < 1 && fabs(NSMinY(rect) - NSMinY(seen)) < 1 && fabs(NSWidth(rect) - NSWidth(seen)) < 1 && fabs(NSHeight(rect) - NSHeight(seen)) < 1) whole = YES;
        }
        Check(!above, [NSString stringWithFormat:@"tool %ld has no cursor rectangle over the toolbar", (long)modes[i]]);
        Check(whole, [NSString stringWithFormat:@"tool %ld has its cursor over the Preview below the toolbar", (long)modes[i]]);
    }
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    toolbarDelegate = [BandToolbar new];
    BOOL under = TSDocumentWindowsUseFullSizeContent();
    if (under) {
        CheckGuard(PreviewGuardWindow.class, NO, YES);
        CheckGuard(CombinedGuardWindow.class, YES, YES);
        CheckPointer();
    } else {
        skipped = 1;
        printf("SKIPPED: content does not run under the toolbar on this system\n");
    }
    CheckGuard(PreviewGuardWindow.class, NO, NO);
    CheckGuard(CombinedGuardWindow.class, YES, NO);
    if (failures) { printf("%d of %d checks failed\n", failures, checks); return 1; }
    printf("PASS: the title bar and the toolbar keep their clicks and their pointer over the Preview (%d checks%s)\n", checks,
           skipped ? ", windows with content under the toolbar skipped" : "");
    return 0;
}}
'''
for key, text in guards.items():
    program = program.replace(key, text)
program = program.replace('MOVED', moved).replace('RECTS', rects)
if not args.mutation:
    verify_embedded(program, fragments)

with tempfile.TemporaryDirectory(prefix='texshop-preview-under-toolbar-') as directory:
    temp = Path(directory)
    (temp / 'test.m').write_text(program)
    (temp / 'TSDocumentWindowGlass.m').write_text(glass_source, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'PDFKit', *include_args(root), '-I' + str(root / 'Tests'),
                    str(temp / 'test.m'), str(temp / 'TSDocumentWindowGlass.m'), '-o', str(temp / 'test')], check=True)
    home = temp / 'home'; (home / 'Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(temp / 'test')], env=dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home)),
                            capture_output=True, text=True, timeout=120)
    sys.stdout.write(result.stdout); sys.stderr.write(result.stderr)
    if args.mutation:
        if 'SKIPPED:' in result.stdout:
            print('SKIPPED: mutation ' + args.mutation + ' needs content under the toolbar'); sys.exit(0)
        if result.returncode == 0 or 'FAIL:' not in result.stdout:
            print('FAIL: mutation ' + args.mutation + ' was not detected'); sys.exit(1)
        print('PASS: detected mutation ' + args.mutation); sys.exit(0)
    sys.exit(result.returncode)
