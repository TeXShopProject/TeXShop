#!/usr/bin/env python3
"""Split Window with Link (#31), with the production code in windows that are never shown.

The contextual menu of the preview has the item over an internal link only, not over a URL,
a link to another file or text. Choosing it splits an unsplit window as Split Window does, or
uses the split window as it is; the part with the link stays where it is, and the other part
goes to the target of the link, keeping its display format and magnification, with Back and
Forward, and becomes the active view. A part too small to show anything is first given half
of the window. It also works when the preview is in the single window.

When both parts show a page, PDFKit can ask the part that showed it last for the menu of a
click on it in the other part. The part under the click then makes the menu."""
from pathlib import Path
import argparse
import subprocess
import sys
import tempfile
from source_tree import include_args
from production_fragments import closing_brace, verify_embedded

MUTATIONS = {
    'no-item': ('view', '            [theMenu insertItem: linkItem atIndex: 2];\n', ''),
    'any-link': ('view', '    if (destination.page == nil || destination.page.document != self.document)\n        return nil;\n',
                 '    if (destination == nil)\n        return (PDFDestination *)[NSNull null];\n'),
    'stale-target': ('window', '    if (destination.page == nil || destination.page.document == nil || destination.page.document != view.document)\n        return;\n', ''),
    'no-split': ('window', '        [self splitPdfKitWindow: nil];\n', ''),
    'clicked-part-moves': ('window', '    [otherView goToDestination: destination];\n', '    [linkView goToDestination: destination];\n'),
    'always-second-view': ('window', '    MyPDFKitView *otherView = (MyPDFKitView *)(view == self.myPDFKitView ? self.myPDFKitView2 : self.myPDFKitView);\n',
                           '    MyPDFKitView *otherView = (MyPDFKitView *)self.myPDFKitView2;\n'),
    'small-part-stays': ('window', '    if (otherExtent < whole / 10) {\n', '    if (NO) {\n'),
    'not-active': ('window', '        [otherView becomeActiveView];\n', '        ;\n'),
    'focus-stays': ('window', "! [window makeFirstResponder: otherView]", 'YES'),
    'menu-of-asked-part': ('view', '    if (part != self)\n        return [part menuForEvent: theEvent];\n', ''),
    # The part that goes to the target closes its pinned popup, and the part with the link keeps its own (#35).
    'moving-part-keeps-pin': ('window', '    [otherView closePinnedLinkPreview];\n', ''),
    'link-part-closes-pin': ('window', '    [otherView closePinnedLinkPreview];\n', '    [otherView closePinnedLinkPreview];\n    [linkView closePinnedLinkPreview];\n'),
    'menu-of-first-part': ('view', '    NSView *hit = [window.contentView.superview hitTest: point];\n',
                           '    NSView *hit = self.myPDFWindow.myPDFKitView;\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
window_source = (root / 'Sources/Windows/TSPreviewWindow.m').read_text(encoding='latin1')
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
divider = root / 'Sources/Preview/TSPreviewSplitDivider.m'

def last_method(source, signature):
    # TSPreviewWindow.m keeps an older copy of mainSplitPdfKitWindow in a comment.
    start = source.rindex(signature)
    return source[start:closing_brace(source, source.index('{', start))]

window_methods = [last_method(window_source, s) for s in (
    '- (void) mainSplitPdfKitWindow', '- (void) splitPdfKitWindow:', '- (void)showLinkDestination: (PDFDestination *)destination')]
view_methods = [last_method(view_source, s) for s in (
    # The contextual menu and its new item (#31).
    '- (MyPDFKitView *)previewPartForMenuEvent:', '- (NSMenu *)menuForEvent:(NSEvent *)theEvent',
    '- (PDFDestination *)internalLinkDestinationAtPoint:',
    '- (void)splitWindowWithLink: (id)sender',
    # Splitting (#23) and the active view (#25, #14), as in run-preview-switch-views.py.
    '- (void)saveLocation\n', '- (void)restoreLocation\n', '- (NSInteger)index\n', '- (void)moveSplitToCorrectSpot:',
    '- (BOOL)hasPinnedLinkPreview\n', '- (TSLinkPreviewView *)detachPinnedLinkPreviewWithWindowFrame:',
    '- (void)attachPinnedLinkPreview:', '- (void)keepPinnedLinkPreviewInView\n', '- (void)closePinnedLinkPreview\n',
    '- (void)setMagnification: (double)magnification', '- (void) scaleChanged: (NSNotification *) notification',
    '- (void)fixMagnificationControls\n', '- (void)fixStuff\n', '- (void)resetSearchDelegate\n',
    '- (BOOL)becomeFirstResponder\n', '- (void)becomeActiveView\n',
    '- (void)awakeFromNib\n', '- (void) showForSecond;', '- (void) displayPageChange:', '- (void) goToKitPageNumber:',
    '- (NSInteger) getModifiedValue:', '- (void) goToKitPage: (id)sender',
    '- (void) notificationSetup;', '- (void) pageChanged:', '- (void) makePageChanges:', '- (void) showPageInOutline:')]
fragments = [('complete method: ' + text.split('\n')[0], source, text)
             for source, texts in ((window_source, window_methods), (view_source, view_methods)) for text in texts]
window_text = '\n'.join(window_methods)
view_text = '\n'.join(view_methods)
if args.mutation:
    which, old, new = MUTATIONS[args.mutation]
    if which == 'window':
        assert window_text.count(old) == 1, args.mutation
        window_text = window_text.replace(old, new)
    else:
        assert view_text.count(old) == 1, args.mutation
        view_text = view_text.replace(old, new)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewPanePlace.h"
#import "TSPreviewSplitDivider.h"
// Values from globals.h.
enum { PDF_SINGLE_PAGE_STYLE = 1, PDF_TWO_PAGE_STYLE = 2, PDF_MULTI_PAGE_STYLE = 3, PDF_DOUBLE_MULTI_PAGE_STYLE = 4 };
enum { NEW_PDF_ACTUAL_SIZE = 1, NEW_PDF_FIT_TO_NONE = 2, NEW_PDF_FIT_TO_WINDOW = 3, NEW_PDF_FIT_TO_WIDTH = 4 };
enum { NEW_MOUSE_MODE_SCROLL = 1, NEW_MOUSE_MODE_SELECT_TEXT = 2 };
enum { MOUSE_MODE_MAG_GLASS = 2 };
// The settings are in memory only (TestAppKitIsolation.h).
#define SUD NSUserDefaults.standardUserDefaults
#define PdfMouseModeKey @"PdfMouseMode"
#define PdfKitMouseModeKey @"PdfKitMouseMode"
static NSString *MagnificationChangedNotification = @"TestMagnificationChanged";
static NSString *PreviewColorChangedNotification = @"TestPreviewColorChanged";
#define PDF_MAX_SCALE 2000
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSEventModifierFlags flags;
static NSEventModifierFlags currentFlags(id s, SEL c) { return flags; }
@interface TSLinkPreviewView : NSView
@property (nonatomic) BOOL pinned;
@property (copy) BOOL (^usesHandTool)(void);
- (void)keepInView;
@end
@implementation TSLinkPreviewView
- (void)keepInView {}
@end
@interface TestWindow : NSWindow
@property BOOL firstTime, windowIsSplit, horizontal;
@property PDFView *activeView, *myPDFKitView, *myPDFKitView2;
@property NSSplitView *pdfKitSplitView;
@property (strong) TSPreviewSplitDivider *previewSplitDivider;
- (void)mainSplitPdfKitWindow;
- (void)splitPdfKitWindow:(id)sender;
- (void)showLinkDestination:(PDFDestination *)destination besideView:(PDFView *)view;
@end
#define TSPreviewWindow TestWindow
@interface TestDocument : NSObject
@property (weak) TestWindow *window;
@property NSInteger numberingCorrection;
@property NSMenu *annotationMenu;
- (id)myPDFKitView;
- (NSWindow *)pagenumberPanel;
@end
@implementation TestDocument
- (id)topView { return self.window.myPDFKitView; }
- (id)myPDFKitView { return self.window.myPDFKitView; }
- (NSWindow *)pagenumberPanel { return nil; }
- (void)updatePreviewLayoutControls {}
- (NSMenu *)getContextMenu { return self.annotationMenu; }
@end
@interface MyPDFKitView : PDFView {
    TSPreviewPanePlace splitPlace;
    NSInteger pageStyle, firstPageStyle, resizeOption, mouseMode, scaleMag;
    TSLinkPreviewView *linkPreview;
    TSLinkPreviewView *pinnedLinkPreview;
    NSTextField *myScale, *smyScale, *myScale1;
    NSStepper *myStepper, *smyStepper, *myStepper1;
    NSTableView *_searchTable;
    NSTextField *currentPage0, *scurrentPage, *currentPage1;
    NSInteger totalPages, currentMouseMode;
    NSMatrix *mouseModeMatrix;
    NSMenu *mouseModeMenu;
    NSOutlineView *_outlineView;
    NSPoint menuPoint;
}
@property NSArray *sourceFiles;
@property PDFOutline *outline;
@property (weak) TestWindow *myPDFWindow;
@property (weak) TestDocument *myDocument;
@property BOOL locationSaved, verticalSplitSaved, horizontalSplitSaved;
@property double horizontalHeight1, horizontalHeight2, verticalWidth1, verticalWidth2;
@property NSInteger handlingLink;
@property BOOL globalLongTerm;
@property BOOL oldUsed, doScroll; @property NSRect oldVisibleRect; @property NSInteger oldIndex;
@property NSInteger marqueeCleanups;
- (void)moveSplitToCorrectSpot:(NSInteger)index;
- (void)saveLocation;
- (void)restoreLocation;
- (void)becomeActiveView;
@end
@implementation MyPDFKitView
- (NSInteger)pageStyle { return pageStyle; }
- (NSInteger)firstPageStyle { return firstPageStyle; }
- (NSInteger)resizeOption { return resizeOption; }
- (void)setPageStyle:(NSInteger)s { pageStyle = s; }
- (void)setFirstPageStyle:(NSInteger)s { firstPageStyle = s; }
- (void)setResizeOption:(NSInteger)s { resizeOption = s; }
- (double)magnification { return self.scaleFactor; }
- (void)useScaleField:(NSTextField *)field stepper:(NSStepper *)stepper searchTable:(NSTableView *)table {
    myScale = field; myStepper = stepper; _searchTable = table;
}
- (void)usePageField:(NSTextField *)field singleWindowField:(NSTextField *)single {
    currentPage0 = field; scurrentPage = single;
}
- (NSString *)romanStringValue:(NSInteger)n { return @"i"; }
- (void)previewZoomBoundsChanged:(NSNotification *)notification {}
- (void)previewLiveMagnify:(NSNotification *)notification {}
- (void)changeMagnification:(NSNotification *)notification {}
- (void)previewBackgroundChange:(NSNotification *)notification {}
- (void)initializeDisplay {}
- (void)cleanupMarquee:(BOOL)terminate { [self doKillPopup]; }
- (void)setupPageStyle {
    PDFDisplayMode modes[] = {kPDFDisplaySinglePageContinuous, kPDFDisplaySinglePage, kPDFDisplayTwoUp,
                              kPDFDisplaySinglePageContinuous, kPDFDisplayTwoUpContinuous};
    [self setDisplayMode:modes[pageStyle >= 1 && pageStyle <= 4 ? pageStyle : 0]];
    [self setDisplaysPageBreaks:pageStyle != PDF_SINGLE_PAGE_STYLE];
}
- (void)setupMagnificationStyle { if (resizeOption == NEW_PDF_FIT_TO_NONE) [self setScaleFactor:1]; else [self setAutoScales:YES]; }
// As a click on a link does in its own view, the part that follows the link loses its marquee.
- (void)cleanupMarqueeKeepingPinnedLinkPreview { self.marqueeCleanups++; }
- (void)observeLinkPreviewEvents {}
- (void)killTransientLinkPreview { [linkPreview removeFromSuperview]; linkPreview = nil; self.handlingLink = 0; }
- (void)doKillPopup { [pinnedLinkPreview removeFromSuperview]; pinnedLinkPreview = nil; [self killTransientLinkPreview]; }
- (BOOL)acceptsFirstResponder { return YES; }
VIEWMETHODS
@end
@implementation TestWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (void)keepPinnedLinkPreviewsInView {
    [(MyPDFKitView *)self.myPDFKitView keepPinnedLinkPreviewInView];
    [(MyPDFKitView *)self.myPDFKitView2 keepPinnedLinkPreviewInView];
}
WINDOWMETHODS
@end

static void settle(NSWindow *w) {
    for (int i = 0; i < 4; i++) {
        [w layoutIfNeeded];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}
// How far below the top edge of a part a point of a page is shown, in points on the screen.
static CGFloat belowTop(PDFView *v, NSUInteger pageIndex, NSPoint pagePoint) {
    NSScrollView *scroll = v.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    PDFPage *page = [v.document pageAtIndex:pageIndex];
    if (v.displayMode == kPDFDisplaySinglePage && v.currentPage != page) return 1e9;
    NSPoint point = [clip convertPoint:[v convertPoint:pagePoint fromPage:page] fromView:v];
    NSRect b = clip.bounds;
    CGFloat d = clip.isFlipped ? point.y - NSMinY(b) : NSMaxY(b) - point.y;
    return d * scroll.magnification;
}
static CGFloat distanceFromTop(PDFView *v, TSPreviewPanePlace place) { return belowTop(v, place.pageIndex, place.pagePoint); }
static void scrollTo(PDFView *v, NSUInteger pageIndex, CGFloat y) {
    [v goToRect:NSMakeRect(100, y, 1, 1) onPage:[v.document pageAtIndex:pageIndex]];
}
static BOOL near(CGFloat d) { return fabs(d) < 0.01; }
static NSString *describe(NSString *name, NSString *what) { return [NSString stringWithFormat:@"%@: %@", name, what]; }
static NSInteger pageOf(PDFView *v) { return (NSInteger)[v.document indexForPage:v.currentPage]; }
static CGFloat extentOf(NSSplitView *sv, NSView *v) { return sv.isVertical ? NSWidth(v.frame) : NSHeight(v.frame); }

typedef struct {
    TestWindow *window; MyPDFKitView *upper, *lower;
    TestDocument *document; NSTextField *scaleField; NSTableView *searchTable; NSSearchField *searchField;
    NSTextField *pageField;
} Preview;
// An unsplit Preview window. In the single window the split view is moved into another window,
// as TSDocument does, while the views keep the Preview window as theirs.
static Preview makePreview(PDFDocument *doc, NSWindow *singleWindow) {
    TestWindow *w = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 900)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    NSWindow *host = singleWindow ?: w;
    NSSplitView *sv = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 900, 900)];
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [host.contentView addSubview:sv];
    MyPDFKitView *a = [[MyPDFKitView alloc] initWithFrame:sv.bounds], *b = [[MyPDFKitView alloc] initWithFrame:sv.bounds];
    for (MyPDFKitView *v in @[a, b]) {
        v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        v.autoresizesSubviews = NO; v.wantsLayer = YES;
        [v setPageStyle:PDF_MULTI_PAGE_STYLE];
        [v setResizeOption:NEW_PDF_FIT_TO_NONE];
    }
    [sv addSubview:a];
    w.pdfKitSplitView = sv; w.myPDFKitView = a; w.myPDFKitView2 = b; w.activeView = a;
    w.firstTime = YES;
    TestDocument *document = [TestDocument new]; document.window = w;
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)];
    NSStepper *stepper = [NSStepper new]; stepper.maxValue = 1000;
    NSTableView *table = [NSTableView new];
    NSSearchField *search = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
    [host.contentView addSubview:search];
    NSTextField *pageField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)];
    [host.contentView addSubview:pageField];
    for (MyPDFKitView *v in @[a, b]) {
        v.myPDFWindow = w; v.myDocument = document;
        [v useScaleField:field stepper:stepper searchTable:table];
        [v usePageField:pageField singleWindowField:nil];
        [NSNotificationCenter.defaultCenter addObserver:v selector:@selector(scaleChanged:) name:PDFViewScaleChangedNotification object:v];
    }
    [a awakeFromNib]; [b awakeFromNib];
    a.document = doc; [a setupPageStyle]; [a setupMagnificationStyle];
    [b showForSecond];
    settle(host);
    return (Preview){w, a, b, document, field, table, search, pageField};
}
static void split(Preview p, BOOL sideBySide) {
    flags = sideBySide ? NSEventModifierFlagOption : 0; [p.window splitPdfKitWindow:nil]; flags = 0;
    settle(p.upper.window);
}

// The contextual menu opened at a point of a page of a part.
static NSMenu *menuAt(MyPDFKitView *v, NSUInteger pageIndex, NSPoint pagePoint) {
    NSPoint inView = [v convertPoint:pagePoint fromPage:[v.document pageAtIndex:pageIndex]];
    NSPoint inWindow = [v convertPoint:inView toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:inWindow modifierFlags:0 timestamp:0
                                    windowNumber:v.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    return [v menuForEvent:event];
}
// The menu of a click at a point of a page of a part, asked of another view, as PDFKit can do.
static NSMenu *menuAskedOf(MyPDFKitView *asked, MyPDFKitView *v, NSUInteger pageIndex, NSPoint pagePoint) {
    NSPoint inWindow = [v convertPoint:[v convertPoint:pagePoint fromPage:[v.document pageAtIndex:pageIndex]] toView:nil];
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:inWindow modifierFlags:0 timestamp:0
                                    windowNumber:v.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    return [asked menuForEvent:event];
}
static NSMenuItem *linkItem(NSMenu *menu) {
    for (NSMenuItem *item in menu.itemArray)
        if ([item.title isEqualToString:@"Split Window with Link"]) return item;
    return nil;
}
static PDFAnnotation *linkOn(PDFDocument *doc, NSUInteger pageIndex, BOOL (^which)(PDFAnnotation *)) {
    for (PDFAnnotation *a in [doc pageAtIndex:pageIndex].annotations)
        if ([a.type isEqualToString:@"Link"] && which(a)) return a;
    return nil;
}
static NSPoint middle(PDFAnnotation *a) { return NSMakePoint(NSMidX(a.bounds), NSMidY(a.bounds)); }
// Chooses the item, as the menu does.
static void choose(MyPDFKitView *v, NSUInteger pageIndex, PDFAnnotation *link, NSString *name) {
    NSMenu *menu = menuAt(v, pageIndex, middle(link));
    NSMenuItem *item = linkItem(menu);
    check(item != nil, describe(name, @"the menu over the link has the item"));
    check([NSApp sendAction:item.action to:item.target from:item], describe(name, @"the item sends its action"));
    settle(v.window);
}
// The part that follows the link shows its target, as PDFKit's goToDestination does: at its top
// edge, unless the whole page fits in the part, as in Single Page display.
static void checkAtTarget(PDFView *v, PDFDestination *d, NSString *name) {
    NSUInteger index = [d.page.document indexForPage:d.page];
    CGFloat y = belowTop(v, index, NSMakePoint(d.point.x < 0 ? 100 : d.point.x, d.point.y));
    NSScrollView *scroll = v.documentView.enclosingScrollView;
    CGFloat visible = NSHeight(scroll.contentView.bounds) * scroll.magnification;
    CGFloat page = NSHeight([d.page boundsForBox:v.displayBox]) * v.scaleFactor;
    check(pageOf(v) == (NSInteger)index && y > -1 && (page > visible ? y < 40 : y < visible),
          describe(name, [NSString stringWithFormat:@"the other part shows the target (page %ld for %lu, %.1f below the top of %.1f)",
                          (long)pageOf(v), (unsigned long)index, y, visible]));
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    method_setImplementation(class_getClassMethod(NSEvent.class, @selector(modifierFlags)), (IMP)currentFlags);
    PDFDocument *doc = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];
    check(doc.pageCount >= 10, @"test document has pages");
    // Page 2 links to the section on page 8, and page 8 to the section on page 3.
    PDFAnnotation *forward = linkOn(doc, 1, ^BOOL(PDFAnnotation *a) { return a.destination != nil; });
    PDFAnnotation *backward = linkOn(doc, 7, ^BOOL(PDFAnnotation *a) { return a.destination != nil; });
    PDFAnnotation *url = linkOn(doc, 1, ^BOOL(PDFAnnotation *a) { return [a.action isKindOfClass:PDFActionURL.class] && !a.URL.isFileURL; });
    PDFAnnotation *file = linkOn(doc, 1, ^BOOL(PDFAnnotation *a) { return [a.action isKindOfClass:PDFActionRemoteGoTo.class]; });
    PDFAnnotation *run = linkOn(doc, 1, ^BOOL(PDFAnnotation *a) { return a.URL.isFileURL; });
    check(forward && backward && url && file && run, @"test document has the links");
    check([doc indexForPage:forward.destination.page] == 7 && [doc indexForPage:backward.destination.page] == 2,
          @"the internal links go to pages 8 and 3");

    {   // The menu.
        Preview p = makePreview(doc, nil);
        scrollTo(p.upper, 1, 750); settle(p.window);
        NSMenu *menu = menuAt(p.upper, 1, middle(forward));
        NSMenuItem *item = linkItem(menu);
        check(item && [menu indexOfItem:item] == 2 && item.target == p.upper && item.action == @selector(splitWindowWithLink:) &&
              item.representedObject == forward.destination,
              @"menu: over an internal link the item follows Split Window and holds the target");
        check([[menu itemAtIndex:0].title isEqualToString:@"Sync"] && [[menu itemAtIndex:1].title isEqualToString:@"Split Window"] &&
              [[menu itemAtIndex:3].title isEqualToString:@"Link Popups"] && [menu itemAtIndex:4].isSeparatorItem,
              @"menu: the other items stay in their order");
        check(item.enabled && [p.upper validateMenuItem:item], @"menu: the item can be chosen");
        for (NSArray *other in @[@[@"a URL", url], @[@"a link to another file", file], @[@"a link that runs a file", run]]) {
            NSMenu *m = menuAt(p.upper, 1, middle(other[1]));
            check(m && !linkItem(m) && [[m itemAtIndex:2].title isEqualToString:@"Link Popups"],
                  describe(@"menu", [@"no item over " stringByAppendingString:other[0]]));
        }
        NSRect text = forward.bounds;
        NSMenu *m = menuAt(p.upper, 1, NSMakePoint(NSMinX(text) - 30, NSMidY(text)));
        check(m && !linkItem(m), @"menu: no item next to the link");
        p.document.annotationMenu = [[NSMenu alloc] initWithTitle:@"Annotations"];
        check(menuAt(p.upper, 1, middle(forward)) == p.document.annotationMenu, @"menu: the annotation menu replaces the menu as before");
        [p.window close];
    }

    for (NSNumber *sideBySide in @[@NO, @YES]) {
        // An unsplit window is split as by Split Window, and the second part shows the target.
        NSString *name = sideBySide.boolValue ? @"unsplit, side by side" : @"unsplit, top and bottom";
        Preview p = makePreview(doc, nil);
        [p.upper setMagnification:1.3];
        scrollTo(p.upper, 1, 750); settle(p.window);
        TSPreviewPanePlace top = TSPreviewPaneCapture(p.upper);
        [p.window makeFirstResponder:p.upper];
        flags = sideBySide.boolValue ? NSEventModifierFlagOption : 0;
        NSMenu *menu = menuAt(p.upper, 1, middle(forward));
        [NSApp sendAction:linkItem(menu).action to:linkItem(menu).target from:linkItem(menu)];
        flags = 0; settle(p.window);
        NSSplitView *sv = p.window.pdfKitSplitView;
        check(p.window.windowIsSplit && p.lower.superview == sv && sv.isVertical == sideBySide.boolValue,
              describe(name, @"the window is split, side by side with Option as by Split Window"));
        check(near(distanceFromTop(p.upper, top)), describe(name, [NSString stringWithFormat:@"the part with the link stays (%.2f)", distanceFromTop(p.upper, top)]));
        checkAtTarget(p.lower, forward.destination, name);
        check(near(extentOf(sv, p.upper) - extentOf(sv, p.lower)), describe(name, @"the first split gives each part half the window"));
        check(near(p.lower.scaleFactor - 1.3) && p.lower.pageStyle == p.upper.pageStyle,
              describe(name, @"the second part takes the display format and magnification of the first, as by Split Window"));
        check(p.window.activeView == p.lower && p.window.firstResponder == p.lower && p.searchTable.delegate == (id)p.lower &&
              p.pageField.integerValue == 8, describe(name, @"the second part becomes active"));
        // Splitting cleans up both parts; following the link cleans up the second part once more.
        check(p.lower.marqueeCleanups == p.upper.marqueeCleanups + 1, describe(name, @"the part that follows the link loses its marquee"));
        // Back and Forward, as after clicking the link there.
        check(p.lower.canGoBack, describe(name, @"Back can take the second part back"));
        [p.lower goBack:nil]; settle(p.window);
        check(pageOf(p.lower) == 1 && p.lower.canGoForward, describe(name, [NSString stringWithFormat:@"Back shows where the second part was (page %ld)", (long)pageOf(p.lower) + 1]));
        [p.lower goForward:nil]; settle(p.window);
        checkAtTarget(p.lower, forward.destination, [name stringByAppendingString:@", Forward"]);
        check(near(distanceFromTop(p.upper, top)), describe(name, @"Back and Forward leave the first part"));
        [p.window close];
    }

    for (NSNumber *sideBySide in @[@NO, @YES]) {
        // In a split window the other part follows the link, from either part, and keeps its
        // own display format and magnification.
        NSString *name = sideBySide.boolValue ? @"split, side by side" : @"split, top and bottom";
        Preview p = makePreview(doc, nil);
        split(p, sideBySide.boolValue);
        NSSplitView *sv = p.window.pdfKitSplitView;
        CGFloat whole = sideBySide.boolValue ? NSWidth(sv.bounds) : NSHeight(sv.bounds);
        [sv setPosition:round(whole * 0.6) ofDividerAtIndex:0]; settle(p.window);
        [p.upper setMagnification:1.2];
        [p.lower setPageStyle:PDF_SINGLE_PAGE_STYLE]; [p.lower setupPageStyle]; [p.lower setMagnification:0.9];
        scrollTo(p.upper, 1, 750); scrollTo(p.lower, 5, 500); settle(p.window);
        CGFloat upperExtent = extentOf(sv, p.upper), lowerExtent = extentOf(sv, p.lower);

        NSString *first = [name stringByAppendingString:@", link in the first part"];
        TSPreviewPanePlace upperTop = TSPreviewPaneCapture(p.upper);
        [p.window makeFirstResponder:p.upper]; settle(p.window);
        // Each part has a pinned popup.
        TSLinkPreviewView *upperPin = [[TSLinkPreviewView alloc] initWithFrame:NSMakeRect(0, 0, 60, 40)];
        TSLinkPreviewView *lowerPin = [[TSLinkPreviewView alloc] initWithFrame:NSMakeRect(0, 0, 60, 40)];
        NSRect upperPlace = [p.upper convertRect:NSMakeRect(NSMidX(p.upper.bounds), NSMidY(p.upper.bounds), 60, 40) toView:nil];
        NSRect lowerPlace = [p.lower convertRect:NSMakeRect(NSMidX(p.lower.bounds), NSMidY(p.lower.bounds), 60, 40) toView:nil];
        [p.upper attachPinnedLinkPreview:upperPin windowFrame:upperPlace];
        [p.lower attachPinnedLinkPreview:lowerPin windowFrame:lowerPlace];
        check(p.upper.hasPinnedLinkPreview && p.lower.hasPinnedLinkPreview, describe(first, @"both parts have a pinned popup"));
        choose(p.upper, 1, forward, first);
        check(!p.lower.hasPinnedLinkPreview && !lowerPin.superview,
              describe(first, @"the part that goes to the target closes its pinned popup"));
        check(p.upper.hasPinnedLinkPreview && upperPin.superview == p.upper.documentView,
              describe(first, @"the part with the link keeps its pinned popup"));
        [p.upper doKillPopup];
        check(near(distanceFromTop(p.upper, upperTop)) && near(p.upper.scaleFactor - 1.2),
              describe(first, @"the part with the link stays"));
        checkAtTarget(p.lower, forward.destination, first);
        check(p.lower.pageStyle == PDF_SINGLE_PAGE_STYLE && p.lower.displayMode == kPDFDisplaySinglePage && near(p.lower.scaleFactor - 0.9),
              describe(first, @"the other part keeps its display format and magnification"));
        check(near(extentOf(sv, p.upper) - upperExtent) && near(extentOf(sv, p.lower) - lowerExtent), describe(first, @"the divider stays"));
        check(p.window.activeView == p.lower && p.window.firstResponder == p.lower, describe(first, @"the other part becomes active"));
        check(p.lower.canGoBack, describe(first, @"Back can take the other part back"));
        [p.lower goBack:nil]; settle(p.window);
        check(pageOf(p.lower) == 5, describe(first, @"Back shows where the other part was"));
        [p.lower goForward:nil]; settle(p.window);

        // From the second part: the first part follows the link, and the second part stays.
        NSString *second = [name stringByAppendingString:@", link in the second part"];
        scrollTo(p.lower, 7, 750); settle(p.window);
        TSPreviewPanePlace lowerTop = TSPreviewPaneCapture(p.lower);
        choose(p.lower, 7, backward, second);
        check(near(distanceFromTop(p.lower, lowerTop)) && near(p.lower.scaleFactor - 0.9), describe(second, @"the part with the link stays"));
        checkAtTarget(p.upper, backward.destination, second);
        check(p.upper.pageStyle == PDF_MULTI_PAGE_STYLE && near(p.upper.scaleFactor - 1.2),
              describe(second, @"the first part keeps its display format and magnification"));
        check(p.window.activeView == p.upper && p.window.firstResponder == p.upper, describe(second, @"the first part becomes active"));
        check(p.upper.canGoBack, describe(second, @"Back can take the first part back"));
        [p.upper goBack:nil]; settle(p.window);
        check(pageOf(p.upper) == 1, describe(second, [NSString stringWithFormat:@"Back shows where the first part was (page %ld)", (long)pageOf(p.upper) + 1]));

        // With the focus elsewhere, as in the search field, the focus stays there.
        NSString *focus = [name stringByAppendingString:@", focus in the search field"];
        [p.window makeFirstResponder:p.searchField];
        NSResponder *responder = p.window.firstResponder;
        scrollTo(p.upper, 1, 750); settle(p.window);
        choose(p.upper, 1, forward, focus);
        checkAtTarget(p.lower, forward.destination, focus);
        check(p.window.firstResponder == responder && p.window.activeView == p.lower && p.searchTable.delegate == (id)p.lower,
              describe(focus, @"the focus stays, and the other part becomes the active view"));
        [p.window close];
    }

    for (NSNumber *sideBySide in @[@NO, @YES]) {
        // When both parts show a page, PDFKit can ask the part that showed it last for the menu
        // of a click on it in the other part. The part under the click makes the menu.
        NSString *name = sideBySide.boolValue ? @"menu asked of the other part, side by side" : @"menu asked of the other part, top and bottom";
        Preview p = makePreview(doc, nil);
        split(p, sideBySide.boolValue);
        PDFPage *linkPage = [doc pageAtIndex:1];
        void (^showLink)(MyPDFKitView *) = ^(MyPDFKitView *v) {
            [v goToRect:NSInsetRect(forward.bounds, -20, -20) onPage:linkPage]; settle(p.window);
            check(NSPointInRect([v convertPoint:middle(forward) fromPage:linkPage], v.bounds), describe(name, @"the part shows the link"));
        };
        showLink(p.upper); showLink(p.lower);
        NSMenu *menu = menuAskedOf(p.lower, p.upper, 1, middle(forward));
        NSMenuItem *item = linkItem(menu);
        check(item && item.target == p.upper && item.representedObject == forward.destination && [menu indexOfItem:item] == 2 &&
              [[menu itemAtIndex:0].title isEqualToString:@"Sync"],
              describe(name, @"a click on the link in the first part has the menu of the first part"));
        menu = menuAskedOf(p.upper, p.lower, 1, middle(forward));
        item = linkItem(menu);
        check(item && item.target == p.lower && item.representedObject == forward.destination,
              describe(name, @"a click on the link in the second part has the menu of the second part"));
        // Choosing the item there moves the first part, and the second part stays.
        TSPreviewPanePlace lowerTop = TSPreviewPaneCapture(p.lower);
        [NSApp sendAction:item.action to:item.target from:item]; settle(p.window);
        checkAtTarget(p.upper, forward.destination, name);
        check(near(distanceFromTop(p.lower, lowerTop)) && p.window.activeView == p.upper,
              describe(name, @"the part with the link stays, and the first part becomes active"));
        // Uwe Schmock's steps: the second part shows the page again and follows the link there.
        showLink(p.upper); showLink(p.lower);
        [p.lower goToDestination:forward.destination]; settle(p.window);
        menu = menuAskedOf(p.lower, p.upper, 1, middle(forward));
        item = linkItem(menu);
        check(item && item.target == p.upper, describe(name, @"after the second part followed the link, the first part still has the item"));
        TSPreviewPanePlace upperTop = TSPreviewPaneCapture(p.upper);
        scrollTo(p.lower, 5, 500); settle(p.window);
        [NSApp sendAction:item.action to:item.target from:item]; settle(p.window);
        checkAtTarget(p.lower, forward.destination, [name stringByAppendingString:@", again"]);
        check(near(distanceFromTop(p.upper, upperTop)), describe(name, @"the first part stays again"));
        // Over the divider, which is in neither part, the menu is made as before.
        NSSplitView *sv = p.window.pdfKitSplitView;
        NSRect upperFrame = p.upper.frame;
        NSPoint dividerPoint = sideBySide.boolValue ? NSMakePoint(NSMaxX(upperFrame) + sv.dividerThickness / 2, NSMidY(upperFrame))
                                                    : NSMakePoint(NSMidX(upperFrame), NSMaxY(upperFrame) + sv.dividerThickness / 2);
        NSPoint inWindow = [sv convertPoint:dividerPoint toView:nil];
        NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:inWindow modifierFlags:0 timestamp:0
                                        windowNumber:p.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
        menu = [p.lower menuForEvent:event];
        check(menu && !linkItem(menu) && [[menu itemAtIndex:0].title isEqualToString:@"Sync"], describe(name, @"over the divider the menu is made as before"));
        [p.window close];
    }
    for (NSNumber *upperHidden in @[@NO, @YES]) {
        // A part dragged out of sight first gets half of the window; the part with the link stays.
        NSString *name = upperHidden.boolValue ? @"first part out of sight" : @"second part out of sight";
        Preview p = makePreview(doc, nil);
        split(p, NO);
        NSSplitView *sv = p.window.pdfKitSplitView;
        [sv setPosition:upperHidden.boolValue ? 0 : NSHeight(sv.bounds) ofDividerAtIndex:0]; settle(p.window);
        MyPDFKitView *linkView = upperHidden.boolValue ? p.lower : p.upper, *other = upperHidden.boolValue ? p.upper : p.lower;
        check(extentOf(sv, other) < 1, describe(name, @"the part is out of sight"));
        scrollTo(linkView, 1, 750); settle(p.window);
        TSPreviewPanePlace top = TSPreviewPaneCapture(linkView);
        choose(linkView, 1, forward, name);
        CGFloat half = (NSHeight(sv.bounds) - sv.dividerThickness) / 2;
        check(fabs(extentOf(sv, other) - half) < 1 && fabs(extentOf(sv, linkView) - half) < 1,
              describe(name, [NSString stringWithFormat:@"the divider moves to the middle (%.1f, %.1f)", extentOf(sv, p.upper), extentOf(sv, p.lower)]));
        check(near(distanceFromTop(linkView, top)), describe(name, [NSString stringWithFormat:@"the part with the link stays (%.2f)", distanceFromTop(linkView, top)]));
        checkAtTarget(other, forward.destination, name);
        [p.window close];
    }
    {   // A small part that still shows something keeps its size.
        Preview p = makePreview(doc, nil);
        split(p, NO);
        NSSplitView *sv = p.window.pdfKitSplitView;
        [sv setPosition:round(NSHeight(sv.bounds) * 0.8) ofDividerAtIndex:0]; settle(p.window);
        CGFloat lowerExtent = extentOf(sv, p.lower);
        scrollTo(p.upper, 1, 750); settle(p.window);
        choose(p.upper, 1, forward, @"small second part");
        check(near(extentOf(sv, p.lower) - lowerExtent), @"small second part: the divider stays");
        [p.window close];
    }
    {   // A window unsplit while the second part was out of sight splits with half the window.
        Preview p = makePreview(doc, nil);
        split(p, NO);
        NSSplitView *sv = p.window.pdfKitSplitView;
        [sv setPosition:NSHeight(sv.bounds) ofDividerAtIndex:0]; settle(p.window);
        split(p, NO);
        check(!p.window.windowIsSplit, @"hidden, unsplit: the window is unsplit");
        scrollTo(p.upper, 1, 750); settle(p.window);
        TSPreviewPanePlace top = TSPreviewPaneCapture(p.upper);
        choose(p.upper, 1, forward, @"hidden, unsplit");
        check(p.window.windowIsSplit && fabs(extentOf(sv, p.lower) - (NSHeight(sv.bounds) - sv.dividerThickness) / 2) < 1,
              @"hidden, unsplit: the second part gets half the window");
        check(near(distanceFromTop(p.upper, top)), @"hidden, unsplit: the part with the link stays");
        checkAtTarget(p.lower, forward.destination, @"hidden, unsplit");
        [p.window close];
    }
    for (NSNumber *wasSplit in @[@NO, @YES]) {
        // The PDF is reloaded while the menu is open: the item then does nothing, since its
        // target belongs to the old PDF.
        NSString *name = wasSplit.boolValue ? @"reloaded, split" : @"reloaded, unsplit";
        Preview p = makePreview(doc, nil);
        if (wasSplit.boolValue) split(p, NO);
        scrollTo(p.upper, 1, 750); scrollTo(p.lower, 5, 500); settle(p.window);
        NSMenu *menu = menuAt(p.upper, 1, middle(forward));
        NSMenuItem *item = linkItem(menu);
        check(item != nil, describe(name, @"the menu has the item"));
        PDFDocument *reloaded = [[PDFDocument alloc] initWithURL:doc.documentURL];
        p.upper.document = reloaded;
        if (wasSplit.boolValue) p.lower.document = reloaded;
        settle(p.window);
        NSInteger lowerPage = wasSplit.boolValue ? pageOf(p.lower) : -1;
        [NSApp sendAction:item.action to:item.target from:item];
        for (int i = 0; i < 5; i++) settle(p.window);
        check(p.window.windowIsSplit == wasSplit.boolValue, describe(name, @"the window stays as it was"));
        check(p.upper.document == reloaded && pageOf(p.upper) >= 0 && pageOf(p.upper) < (NSInteger)reloaded.pageCount,
              describe(name, @"the first part shows the reloaded PDF"));
        if (wasSplit.boolValue)
            check(pageOf(p.lower) == lowerPage, describe(name, @"the second part stays where it was"));
        [p.window close];
    }
    for (NSNumber *wasSplit in @[@NO, @YES]) {
        // In the single window the preview's split view is in that window.
        NSString *name = wasSplit.boolValue ? @"single window, split" : @"single window, unsplit";
        NSWindow *single = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 900)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        single.releasedWhenClosed = NO;
        Preview p = makePreview(doc, single);
        if (wasSplit.boolValue) {
            split(p, NO);
            for (MyPDFKitView *v in @[p.upper, p.lower]) [v goToRect:NSInsetRect(forward.bounds, -20, -20) onPage:[doc pageAtIndex:1]];
            settle(single);
            NSMenuItem *asked = linkItem(menuAskedOf(p.lower, p.upper, 1, middle(forward)));
            check(asked && asked.target == p.upper, describe(name, @"a click in the first part has the menu of the first part"));
        }
        scrollTo(p.upper, 1, 750); settle(single);
        TSPreviewPanePlace top = TSPreviewPaneCapture(p.upper);
        [single makeFirstResponder:p.upper];
        choose(p.upper, 1, forward, name);
        check(p.window.windowIsSplit && p.lower.window == single, describe(name, @"the preview in the single window is split"));
        check(near(distanceFromTop(p.upper, top)), describe(name, @"the part with the link stays"));
        checkAtTarget(p.lower, forward.destination, name);
        check(p.window.activeView == p.lower && single.firstResponder == p.lower, describe(name, @"the other part becomes active"));
        [single close]; [p.window close];
    }
    printf("PASS: %lu checks\n", (unsigned long)checks);
    return 0;
}}
'''
program = program.replace('VIEWMETHODS', view_text).replace('WINDOWMETHODS', window_text)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    tex = temp / 'doc.tex'
    filler = ' '.join(['Text of the test document.'] * 30)
    pages = ['Page %d. %s' % (i + 1, filler) for i in range(12)]
    pages[1] = ('Page 2. ' + filler + '\n\nSee Section~\\ref{far}, \\url{https://example.com}, '
                '\\href{other.pdf}{another file} and \\href{run:other.pdf}{a file to run}.\n\n' + filler)
    pages[2] = '\\section{Near}\\label{near}\n' + pages[2]
    pages[7] = '\\section{Far}\\label{far}\n' + pages[7] + '\n\nBack to Section~\\ref{near}.'
    tex.write_text('\\documentclass{article}\\usepackage{hyperref}\\begin{document}\n' +
                   '\n\\newpage\n'.join(pages) + '\n\\end{document}\n')
    pdflatex = next((p for p in ('/Applications/TeXLive/2026/bin/universal-darwin/pdflatex', '/Library/TeX/texbin/pdflatex')
                     if Path(p).exists()), 'pdflatex')
    for _ in range(2):
        subprocess.run([pdflatex, '-interaction=batchmode', '-output-directory', str(temp), str(tex)],
                       check=True, stdout=subprocess.DEVNULL, cwd=temp)
    (temp / 'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    '-I', str(root / 'Tests'), *include_args(root),
                    str(temp / 'test.m'), str(divider), '-o', str(temp / 'test')], check=True)
    result = subprocess.run([str(temp / 'test'), str(temp / 'doc.pdf')], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.strip().splitlines()[-1])
    else:
        print(output.strip())
        sys.exit(result.returncode)
