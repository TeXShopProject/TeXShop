#!/usr/bin/env python3
"""Switch the parts of a split preview with the production code in a window that is never
shown (#25): the parts change places with their size, place, display format, magnification,
selection, pinned link popup and focus, and switching again gives back the first arrangement.
The toolbar's page number field shows the page of the active part and moves it (#14)."""
from pathlib import Path
import argparse
import subprocess
import sys
import tempfile
from source_tree import include_args
from production_fragments import closing_brace, verify_embedded

MUTATIONS = {
    # window code
    'divider-stays': ('window', '    [splitView setPosition:start + lowerExtent ofDividerAtIndex:0];\n', ''),
    'magnification-stays': ('window', '            [view setMagnification:scales[i]];\n', '            ;\n'),
    'format-stays': ('window', '        if (view.pageStyle != styles[i]) {', '        if (NO) {'),
    'fit-lost': ('window', '        if (autoScales[i])\n', '        if (NO)\n'),
    'selection-stays': ('window', '    [upperView setCurrentSelection:lowerSelection];\n    [lowerView setCurrentSelection:upperSelection];\n', ''),
    'popup-stays-on-screen': ('window', 'NSMinX(newUpperFrame) - NSMinX(lowerFrame), NSMaxY(newUpperFrame) - NSMaxY(lowerFrame)', '0, 0'),
    'popup-dropped': ('window', '    if (upperPopup)\n        [lowerView attachPinnedLinkPreview:', '    if (NO)\n        [lowerView attachPinnedLinkPreview:'),
    'focus-stays': ('window', '![window makeFirstResponder:active]', 'YES'),
    'active-view-only': ('window', '        [active becomeActiveView];\n', '        self.activeView = active;\n'),
    # view code
    'search-not-followed': ('view', '\t[self resetSearchDelegate];\n    [self.myDocument', '    [self.myDocument'),
    'places-not-swapped': ('window', '    TSPreviewPaneRestore(upperView, lower);\n    TSPreviewPaneRestore(lowerView, upper);\n', ''),
    # The page number field (#14).
    'page-count-cached': ('view', '\tNSInteger pageCount = (NSInteger)[[self document] pageCount];\n', '\tNSInteger pageCount = totalPages;\n'),
    'page-field-not-followed': ('view', '\tif (activePage)\n\t\t[self displayPageChange:', '\tif (NO)\n\t\t[self displayPageChange:'),
    'single-field-not-shared': ('view', '        scurrentPage = first->scurrentPage;\n', '        ;\n'),
    'second-not-observed': ('window', '        [(MyPDFKitView *)self.myPDFKitView2 notificationSetup];\n', ''),
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
    '- (void) mainSplitPdfKitWindow', '- (void)switchViews;', '- (void)switchSplitParts\n', '- (void) splitPdfKitWindow:',
    '- (void) goToKitPage: sender')]
view_methods = [last_method(view_source, s) for s in (
    '- (void)saveLocation\n', '- (void)restoreLocation\n', '- (NSInteger)index\n', '- (void)moveSplitToCorrectSpot:',
    '- (BOOL)hasPinnedLinkPreview\n', '- (TSLinkPreviewView *)detachPinnedLinkPreviewWithWindowFrame:',
    '- (void)attachPinnedLinkPreview:', '- (void)keepPinnedLinkPreviewInView\n',
    # What the toolbar, the menus and the search results follow (#25 audit).
    '- (void)setMagnification: (double)magnification', '- (void) scaleChanged: (NSNotification *) notification',
    '- (void)fixMagnificationControls\n', '- (void)fixStuff\n', '- (void)resetSearchDelegate\n',
    '- (BOOL)becomeFirstResponder\n', '- (void)becomeActiveView\n',
    # The toolbar's page number field and the views' setup when the nib is loaded and the PDF is opened (#14).
    '- (void)awakeFromNib\n', '- (void) showForSecond;', '- (void) displayPageChange:', '- (void) goToKitPageNumber:',
    '- (NSInteger) getModifiedValue:', '- (void) goToKitPage: (id)sender',
    # The page number field follows the page of the active part through these notifications.
    '- (void) notificationSetup;', '- (void) pageChanged:', '- (void) makePageChanges:')]
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
// Whether the document was opened with its PDF: only then the second view runs showForSecond.
static BOOL openedWithPDF = YES;
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
- (void)switchViews;
- (void)goToKitPage:(id)sender;
@end
#define TSPreviewWindow TestWindow
@interface TestDocument : NSObject
@property (weak) TestWindow *window;
@property NSInteger numberingCorrection;
- (id)myPDFKitView;
- (NSWindow *)pagenumberPanel;
@end
@implementation TestDocument
- (id)topView { return self.window.myPDFKitView; }
- (id)myPDFKitView { return self.window.myPDFKitView; }
- (NSWindow *)pagenumberPanel { return nil; }
- (void)updatePreviewLayoutControls {}
@end
@interface MyPDFKitView : PDFView {
    TSPreviewPanePlace splitPlace;
    NSInteger pageStyle, firstPageStyle, resizeOption, mouseMode, scaleMag;
    TSLinkPreviewView *linkPreview;
    // The toolbar's magnification field and stepper and the search results, shared by both parts.
    NSTextField *myScale, *smyScale, *myScale1;
    NSStepper *myStepper, *smyStepper, *myStepper1;
    NSTableView *_searchTable;
    // The toolbar's page number fields: the Preview window's and the single window's.
    NSTextField *currentPage0, *scurrentPage, *currentPage1;
    NSInteger totalPages, currentMouseMode;
    NSMatrix *mouseModeMatrix;
    NSMenu *mouseModeMenu;
    NSOutlineView *_outlineView;
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
@property (readonly) TSLinkPreviewView *preview;
- (void)moveSplitToCorrectSpot:(NSInteger)index;
- (void)saveLocation;
- (void)restoreLocation;
@end
@implementation MyPDFKitView
- (TSLinkPreviewView *)preview { return linkPreview; }
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
// As the nib connects them: the single window's page field only to the first view.
- (void)usePageField:(NSTextField *)field singleWindowField:(NSTextField *)single {
    currentPage0 = field; scurrentPage = single;
}
- (NSString *)romanStringValue:(NSInteger)n { return @"i"; }
- (void)previewZoomBoundsChanged:(NSNotification *)notification {}
- (void)previewLiveMagnify:(NSNotification *)notification {}
- (void)changeMagnification:(NSNotification *)notification {}
- (void)previewBackgroundChange:(NSNotification *)notification {}
- (void)initializeDisplay {}
// As in MyPDFKitView, cleaning up the marquee closes a popup that is not kept.
- (void)cleanupMarquee:(BOOL)terminate { [self doKillPopup]; }
- (void)setupPageStyle {
    PDFDisplayMode modes[] = {kPDFDisplaySinglePageContinuous, kPDFDisplaySinglePage, kPDFDisplayTwoUp,
                              kPDFDisplaySinglePageContinuous, kPDFDisplayTwoUpContinuous};
    [self setDisplayMode:modes[pageStyle >= 1 && pageStyle <= 4 ? pageStyle : 0]];
    [self setDisplaysPageBreaks:pageStyle != PDF_SINGLE_PAGE_STYLE];
}
- (void)setupMagnificationStyle { if (resizeOption == NEW_PDF_FIT_TO_NONE) [self setScaleFactor:1]; else [self setAutoScales:YES]; }
- (void)cleanupMarqueeKeepingPinnedLinkPreview {}
- (void)observeLinkPreviewEvents {}
- (void)doKillPopup { [linkPreview removeFromSuperview]; linkPreview = nil; self.globalLongTerm = NO; self.handlingLink = 0; }
- (void)pin:(NSRect)windowFrame {
    TSLinkPreviewView *p = [[TSLinkPreviewView alloc] initWithFrame:NSZeroRect];
    [self attachPinnedLinkPreview:p windowFrame:windowFrame];
}
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
static CGFloat distanceFromTop(PDFView *v, TSPreviewPanePlace place) {
    NSScrollView *scroll = v.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    PDFPage *page = [v.document pageAtIndex:place.pageIndex];
    if (v.displayMode == kPDFDisplaySinglePage && v.currentPage != page) return 1e9;
    NSPoint point = [clip convertPoint:[v convertPoint:place.pagePoint fromPage:page] fromView:v];
    NSRect b = clip.bounds;
    CGFloat d = clip.isFlipped ? point.y - NSMinY(b) : NSMaxY(b) - point.y;
    return d * scroll.magnification;
}
static TSPreviewPanePlace topOf(PDFView *v) { return TSPreviewPaneCapture(v); }
static void scrollTo(PDFView *v, NSUInteger pageIndex, CGFloat y) {
    [v goToRect:NSMakeRect(100, y, 1, 1) onPage:[v.document pageAtIndex:pageIndex]];
}
static BOOL near(CGFloat d) { return fabs(d) < 0.01; }
static BOOL sameRect(NSRect a, NSRect b) {
    return near(NSMinX(a) - NSMinX(b)) && near(NSMinY(a) - NSMinY(b)) && near(NSWidth(a) - NSWidth(b)) && near(NSHeight(a) - NSHeight(b));
}
static NSRect inWindow(NSView *v) { return [v convertRect:v.bounds toView:nil]; }
static NSRect popupInWindow(MyPDFKitView *v) { return v.preview ? [v.preview.superview convertRect:v.preview.frame toView:nil] : NSZeroRect; }
// The popup's place relative to the top left corner of its part.
static NSPoint popupOffset(MyPDFKitView *v) {
    NSRect p = popupInWindow(v), f = inWindow(v);
    return NSMakePoint(NSMinX(p) - NSMinX(f), NSMaxY(f) - NSMaxY(p));
}
static NSString *selectionText(PDFView *v) { return v.currentSelection.string ?: @""; }

typedef struct {
    TestWindow *window; MyPDFKitView *upper, *lower;
    TestDocument *document; NSTextField *scaleField; NSTableView *searchTable; NSSearchField *searchField;
    NSTextField *pageField, *singlePageField;
} Preview;
static Preview makePreview(PDFDocument *doc, BOOL sideBySide) {
    TestWindow *w = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 900)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    NSSplitView *sv = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [w.contentView addSubview:sv];
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
    // The search field of the drawer, which can have the focus instead of either part.
    NSSearchField *search = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
    [w.contentView addSubview:search];
    // The page number fields of the Preview window's and of the single window's toolbar.
    NSTextField *pageField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)];
    NSTextField *singlePageField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)];
    [w.contentView addSubview:pageField];
    for (MyPDFKitView *v in @[a, b]) {
        v.myPDFWindow = w; v.myDocument = document;
        [v useScaleField:field stepper:stepper searchTable:table];
        [v usePageField:pageField singleWindowField:v == a ? singlePageField : nil];
        [NSNotificationCenter.defaultCenter addObserver:v selector:@selector(scaleChanged:) name:PDFViewScaleChangedNotification object:v];
    }
    [a awakeFromNib]; [b awakeFromNib];
    // Opening the PDF: the second view counts the pages before it has the PDF.
    a.document = doc; [a setupPageStyle]; [a setupMagnificationStyle];
    if (openedWithPDF) [b showForSecond];
    settle(w);
    flags = sideBySide ? NSEventModifierFlagOption : 0; [w splitPdfKitWindow:nil]; flags = 0;
    settle(w);
    return (Preview){w, a, b, document, field, table, search, pageField, singlePageField};
}

typedef struct {
    NSRect upperFrame, lowerFrame, upperPopup, lowerPopup;
    TSPreviewPanePlace upperPlace, lowerPlace;
    NSInteger upperStyle, lowerStyle, upperResize, lowerResize;
    BOOL upperAuto, lowerAuto;
    CGFloat upperScale, lowerScale;
    __unsafe_unretained NSString *upperSelection, *lowerSelection;
    __unsafe_unretained TSLinkPreviewView *upperPreview, *lowerPreview;
    __unsafe_unretained NSResponder *responder;
    __unsafe_unretained PDFView *active;
} State;
static State stateOf(Preview p) {
    return (State){inWindow(p.upper), inWindow(p.lower), popupInWindow(p.upper), popupInWindow(p.lower),
        topOf(p.upper), topOf(p.lower), p.upper.pageStyle, p.lower.pageStyle, p.upper.resizeOption, p.lower.resizeOption,
        p.upper.autoScales, p.lower.autoScales, p.upper.scaleFactor, p.lower.scaleFactor,
        selectionText(p.upper), selectionText(p.lower), p.upper.preview, p.lower.preview,
        p.window.firstResponder, p.window.activeView};
}
static NSString *describe(NSString *name, NSString *what) { return [NSString stringWithFormat:@"%@: %@", name, what]; }
// The toolbar's magnification and the search results work with the active part.
static void checkControls(Preview p, NSString *name) {
    PDFView *active = p.window.activeView;
    check(p.scaleField.integerValue == lround(active.scaleFactor * 100),
          describe(name, [NSString stringWithFormat:@"the magnification field shows the active part (%ld for %.0f)",
                          (long)p.scaleField.integerValue, active.scaleFactor * 100]));
    check(p.searchTable.delegate == (id)active, describe(name, @"the search results work with the active part"));
    NSInteger page = (NSInteger)[active.document indexForPage:active.currentPage] + 1;
    check(p.pageField.integerValue == page && p.singlePageField.integerValue == page,
          describe(name, [NSString stringWithFormat:@"the page number fields show the active part (%ld, %ld for %ld)",
                          (long)p.pageField.integerValue, (long)p.singlePageField.integerValue, (long)page]));
}
static NSInteger pageOf(PDFView *v) { return (NSInteger)[v.document indexForPage:v.currentPage] + 1; }
// Typing a page number in the toolbar and pressing Return, after clicking in the field.
static void enterPage(Preview p, NSTextField *field, NSString *text) {
    check([p.window makeFirstResponder:field], @"the page number field takes the focus");
    field.stringValue = text;
    [p.window goToKitPage:field];
    settle(p.window);
}

// After a switch each view holds what the other part had; `s` is the state before it.
static void checkSwitched(Preview p, State s, NSString *name, BOOL fixedScales) {
    BOOL side = p.window.pdfKitSplitView.isVertical;
    CGFloat (^extent)(NSRect) = ^CGFloat(NSRect r) { return side ? NSWidth(r) : NSHeight(r); };
    NSRect u = inWindow(p.upper), l = inWindow(p.lower);
    check(near(extent(u) - extent(s.lowerFrame)) && near(extent(l) - extent(s.upperFrame)),
          describe(name, [NSString stringWithFormat:@"the parts change sizes (%.1f, %.1f for %.1f, %.1f)", extent(u), extent(l), extent(s.lowerFrame), extent(s.upperFrame)]));
    check(side ? near(NSMinX(u) - NSMinX(s.upperFrame)) && near(NSMaxX(l) - NSMaxX(s.lowerFrame))
               : near(NSMaxY(u) - NSMaxY(s.upperFrame)) && near(NSMinY(l) - NSMinY(s.lowerFrame)),
          describe(name, @"the first view stays at the top (or left) and the divider moves"));
    check(p.upper.pageStyle == s.lowerStyle && p.lower.pageStyle == s.upperStyle, describe(name, @"the display formats change places"));
    check(p.upper.resizeOption == s.lowerResize && p.lower.resizeOption == s.upperResize, describe(name, @"the magnification settings change places"));
    check(p.upper.autoScales == s.lowerAuto && p.lower.autoScales == s.upperAuto, describe(name, @"fitting to the window changes places"));
    if (fixedScales)
        check(near(p.upper.scaleFactor - s.lowerScale) && near(p.lower.scaleFactor - s.upperScale),
              describe(name, [NSString stringWithFormat:@"the magnifications change places (%.3f, %.3f)", p.upper.scaleFactor, p.lower.scaleFactor]));
    else
        check(fabs(p.upper.scaleFactor - s.lowerScale) < 0.005 && fabs(p.lower.scaleFactor - s.upperScale) < 0.005,
              describe(name, [NSString stringWithFormat:@"a magnification that fits the window is the same in the other place (%.4f for %.4f, %.4f for %.4f)",
                              p.upper.scaleFactor, s.lowerScale, p.lower.scaleFactor, s.upperScale]));
    check(near(distanceFromTop(p.upper, s.lowerPlace)) && near(distanceFromTop(p.lower, s.upperPlace)),
          describe(name, [NSString stringWithFormat:@"the places at the top edges change places (%.2f, %.2f)",
                          distanceFromTop(p.upper, s.lowerPlace), distanceFromTop(p.lower, s.upperPlace)]));
    check([selectionText(p.upper) isEqualToString:s.lowerSelection] && [selectionText(p.lower) isEqualToString:s.upperSelection],
          describe(name, @"the selections change places"));
    check(p.upper.preview == s.lowerPreview && p.lower.preview == s.upperPreview, describe(name, @"the pinned popups change places"));
    check((!s.lowerPreview || (p.upper.preview.pinned && p.upper.globalLongTerm && p.upper.handlingLink == 2)) &&
          (!s.upperPreview || (p.lower.preview.pinned && p.lower.globalLongTerm && p.lower.handlingLink == 2)),
          describe(name, @"the moved popups stay pinned"));
    if (s.lowerPreview) {
        NSRect q = popupInWindow(p.upper);
        check(near(NSMinX(q) - NSMinX(s.lowerPopup) - (NSMinX(u) - NSMinX(s.lowerFrame))) &&
              near(NSMaxY(q) - NSMaxY(s.lowerPopup) - (NSMaxY(u) - NSMaxY(s.lowerFrame))) &&
              near(NSWidth(q) - NSWidth(s.lowerPopup)) && near(NSHeight(q) - NSHeight(s.lowerPopup)),
              describe(name, @"the popup of the second part keeps its place in that part"));
    }
    if (s.upperPreview) {
        NSRect q = popupInWindow(p.lower);
        check(near(NSMinX(q) - NSMinX(s.upperPopup) - (NSMinX(l) - NSMinX(s.upperFrame))) &&
              near(NSMaxY(q) - NSMaxY(s.upperPopup) - (NSMaxY(l) - NSMaxY(s.upperFrame))),
              describe(name, @"the popup of the first part keeps its place in that part"));
    }
}
// After switching twice everything is as before.
static void checkSame(Preview p, State s, NSString *name) {
    State t = stateOf(p);
    check(sameRect(t.upperFrame, s.upperFrame) && sameRect(t.lowerFrame, s.lowerFrame), describe(name, @"the divider is back"));
    check(t.upperStyle == s.upperStyle && t.lowerStyle == s.lowerStyle && t.upperResize == s.upperResize && t.lowerResize == s.lowerResize &&
          t.upperAuto == s.upperAuto && t.lowerAuto == s.lowerAuto, describe(name, @"the display formats and magnifications are back"));
    check(fabs(t.upperScale - s.upperScale) < 0.005 && fabs(t.lowerScale - s.lowerScale) < 0.005, describe(name, @"the magnifications are back"));
    check(near(distanceFromTop(p.upper, s.upperPlace)) && near(distanceFromTop(p.lower, s.lowerPlace)), describe(name, @"the places are back"));
    check([t.upperSelection isEqualToString:s.upperSelection] && [t.lowerSelection isEqualToString:s.lowerSelection], describe(name, @"the selections are back"));
    check(t.upperPreview == s.upperPreview && t.lowerPreview == s.lowerPreview &&
          (!s.upperPreview || sameRect(t.upperPopup, s.upperPopup)) && (!s.lowerPreview || sameRect(t.lowerPopup, s.lowerPopup)),
          describe(name, @"the popups are back in their places"));
    check(t.responder == s.responder && t.active == s.active, describe(name, @"the focus is back"));
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    method_setImplementation(class_getClassMethod(NSEvent.class, @selector(modifierFlags)), (IMP)currentFlags);
    PDFDocument *doc = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];
    check(doc.pageCount >= 6, @"test document has pages");
    for (NSNumber *sideBySide in @[@NO, @YES]) {
        NSString *name = sideBySide.boolValue ? @"side by side" : @"top and bottom";
        Preview p = makePreview(doc, sideBySide.boolValue);
        NSSplitView *sv = p.window.pdfKitSplitView;
        check(p.window.windowIsSplit && sv.isVertical == sideBySide.boolValue, describe(name, @"the window is split"));
        // The user moves the divider and sets up the second part differently.
        CGFloat whole = sideBySide.boolValue ? NSWidth(sv.bounds) : NSHeight(sv.bounds);
        [sv setPosition:round(whole * 0.62) ofDividerAtIndex:0]; settle(p.window);
        [p.lower setPageStyle:PDF_SINGLE_PAGE_STYLE]; [p.lower setupPageStyle];
        [p.lower setMagnification:1.5];
        [p.upper setMagnification:0.8];
        scrollTo(p.upper, 1, 500); scrollTo(p.lower, 4, 600); settle(p.window);
        p.upper.currentSelection = [[doc pageAtIndex:1] selectionForRange:NSMakeRange(0, 30)];
        p.lower.currentSelection = [[doc pageAtIndex:4] selectionForRange:NSMakeRange(40, 25)];
        NSRect u = inWindow(p.upper), l = inWindow(p.lower);
        [p.upper pin:NSMakeRect(NSMinX(u) + 30, NSMaxY(u) - 170, 180, 120)];
        [p.lower pin:NSMakeRect(NSMinX(l) + 60, NSMaxY(l) - 140, 150, 100)];
        [p.window makeFirstResponder:p.lower]; settle(p.window);
        check(p.window.activeView == p.lower, describe(name, @"the second part is active"));
        State before = stateOf(p);
        check(!near(before.upperScale - before.lowerScale) && before.upperStyle != before.lowerStyle && before.upperPreview && before.lowerPreview &&
              before.upperSelection.length && before.lowerSelection.length && !near(NSHeight(before.upperFrame) - NSHeight(before.lowerFrame)) == !sideBySide.boolValue,
              describe(name, @"the parts differ before switching"));

        [p.window switchViews]; settle(p.window);
        checkSwitched(p, before, [name stringByAppendingString:@", first switch"], YES);
        check(p.window.firstResponder == p.upper && p.window.activeView == p.upper, describe(name, @"the active part stays active at its new place"));
        checkControls(p, [name stringByAppendingString:@", first switch"]);
        [p.window switchViews]; settle(p.window);
        checkSame(p, before, [name stringByAppendingString:@", second switch"]);
        checkControls(p, [name stringByAppendingString:@", second switch"]);
        for (int i = 0; i < 4; i++) { [p.window switchViews]; settle(p.window); }
        checkSame(p, before, [name stringByAppendingString:@", six switches"]);

        // With the focus in the search field, the focus stays there, and the active view, the
        // magnification field and the search results follow the part, whichever part is active.
        for (MyPDFKitView *start in @[p.lower, p.upper]) {
            MyPDFKitView *other = start == p.lower ? p.upper : p.lower;
            NSString *which = [name stringByAppendingString:start == p.lower ? @", second part active" : @", first part active"];
            [start becomeActiveView];
            check([p.window makeFirstResponder:p.searchField], describe(which, @"the search field has the focus"));
            NSResponder *focus = p.window.firstResponder;
            CGFloat startScale = start.scaleFactor;
            [p.window switchViews]; settle(p.window);
            check(p.window.firstResponder == focus && p.window.activeView == other && near(other.scaleFactor - startScale),
                  describe(which, @"the focus stays in the search field and the active view follows its part"));
            checkControls(p, which);
            [p.window switchViews]; settle(p.window);
            check(p.window.firstResponder == focus && p.window.activeView == start, describe(which, @"the active view follows its part back"));
            checkControls(p, [which stringByAppendingString:@", back"]);
        }

        // Unsplitting after a switch keeps the first view, which now shows what the second part showed.
        [p.window makeFirstResponder:p.lower]; settle(p.window);
        State switched = stateOf(p);
        [p.window switchViews]; settle(p.window);
        TSPreviewPanePlace upper = topOf(p.upper), lower = topOf(p.lower);
        [p.window splitPdfKitWindow:nil]; settle(p.window);
        check(!p.window.windowIsSplit && p.lower.superview == nil, describe(name, @"the window is unsplit"));
        check(near(distanceFromTop(p.upper, upper)) && p.upper.pageStyle == switched.lowerStyle && near(p.upper.scaleFactor - switched.lowerScale) &&
              p.upper.preview == switched.lowerPreview, describe(name, @"unsplitting keeps the part shown at the top (or left)"));
        flags = sideBySide.boolValue ? NSEventModifierFlagOption : 0; [p.window splitPdfKitWindow:nil]; flags = 0; settle(p.window);
        // The second view takes the display format of the first again, so its place is only
        // checked by page here (run-preview-split-position.py checks it exactly).
        check(near(distanceFromTop(p.upper, upper)) && [doc indexForPage:p.lower.currentPage] == lower.pageIndex,
              describe(name, @"splitting again keeps the first part and shows the page of the second part"));
        [p.window close];
    }
    {   // A part that fits the page to the window keeps fitting at its new place.
        Preview p = makePreview(doc, YES);
        NSSplitView *sv = p.window.pdfKitSplitView;
        [sv setPosition:round(NSWidth(sv.bounds) * 0.35) ofDividerAtIndex:0]; settle(p.window);
        [p.upper setResizeOption:NEW_PDF_FIT_TO_WIDTH]; [p.upper setAutoScales:YES];
        [p.lower setMagnification:1.25];
        [p.lower setPageStyle:PDF_TWO_PAGE_STYLE]; [p.lower setupPageStyle];
        scrollTo(p.upper, 2, 300); scrollTo(p.lower, 3, 400); settle(p.window);
        State before = stateOf(p);
        check(before.upperAuto && !before.lowerAuto && !near(before.upperScale - 1.25), @"fit: the first part fits its width");
        [p.window switchViews]; settle(p.window);
        checkSwitched(p, before, @"fit, first switch", NO);
        [p.window switchViews]; settle(p.window);
        checkSame(p, before, @"fit, second switch");
        [p.window close];
    }
    for (NSNumber *sideBySide in @[@NO, @YES]) {
        // The page number field moves the active part, also the second one, whose page count
        // was taken before it had the PDF; the other part stays where it is (#14).
        NSString *name = sideBySide.boolValue ? @"page field, side by side" : @"page field, top and bottom";
        Preview p = makePreview(doc, sideBySide.boolValue);
        scrollTo(p.upper, 1, 500); scrollTo(p.lower, 4, 600); settle(p.window);
        [p.window makeFirstResponder:p.lower]; settle(p.window);
        checkControls(p, [name stringByAppendingString:@", second part clicked"]);
        enterPage(p, p.pageField, @"3");
        check(pageOf(p.lower) == 3 && pageOf(p.upper) == 2,
              describe(name, [NSString stringWithFormat:@"the second part goes to the page typed (%ld, first part %ld)", (long)pageOf(p.lower), (long)pageOf(p.upper)]));
        check(p.window.activeView == p.lower && p.pageField.integerValue == 3 && p.singlePageField.integerValue == 3,
              describe(name, @"the second part stays active and the fields show its page"));
        enterPage(p, p.singlePageField, [NSString stringWithFormat:@"%lu", (unsigned long)doc.pageCount + 5]);
        check(pageOf(p.lower) == (NSInteger)doc.pageCount && pageOf(p.upper) == 2,
              describe(name, @"a number past the end goes to the last page of the second part"));
        [p.window makeFirstResponder:p.upper]; settle(p.window);
        checkControls(p, [name stringByAppendingString:@", first part clicked"]);
        enterPage(p, p.pageField, @"6");
        check(pageOf(p.upper) == 6 && pageOf(p.lower) == (NSInteger)doc.pageCount,
              describe(name, @"the first part goes to the page typed and the second part stays"));
        [p.window splitPdfKitWindow:nil]; settle(p.window);
        enterPage(p, p.pageField, @"2");
        check(!p.window.windowIsSplit && pageOf(p.upper) == 2, describe(name, @"the unsplit window goes to the page typed"));
        [p.window close];
    }
    for (NSNumber *withPDF in @[@YES, @NO]) {
        // The page number field follows the active second part when it scrolls, also when the
        // document was opened without a PDF and typeset before the window was split, and with
        // page numbers corrected for front matter (#14).
        NSString *name = withPDF.boolValue ? @"follow, opened with the PDF" : @"follow, typeset after opening";
        openedWithPDF = withPDF.boolValue;
        Preview p = makePreview(doc, NO);
        openedWithPDF = YES;
        p.document.numberingCorrection = 2;
        scrollTo(p.lower, 4, 600); settle(p.window);
        [p.window makeFirstResponder:p.lower]; settle(p.window);
        check(p.pageField.integerValue == 3 && p.singlePageField.integerValue == 3,
              describe(name, [NSString stringWithFormat:@"the field shows the corrected page of the second part (%ld)", (long)p.pageField.integerValue]));
        scrollTo(p.lower, 6, 600); settle(p.window);
        check(pageOf(p.lower) == 7 && p.pageField.integerValue == 5 && p.singlePageField.integerValue == 5,
              describe(name, [NSString stringWithFormat:@"the field follows the second part as it scrolls (%ld)", (long)p.pageField.integerValue]));
        enterPage(p, p.pageField, @"4");
        check(pageOf(p.lower) == 6 && p.pageField.integerValue == 4,
              describe(name, [NSString stringWithFormat:@"a corrected page number moves the second part (page %ld, field %ld)", (long)pageOf(p.lower), (long)p.pageField.integerValue]));
        scrollTo(p.upper, 2, 600); settle(p.window);
        check(p.pageField.integerValue == 4, describe(name, @"scrolling the inactive first part leaves the field"));
        [p.window close];
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
    tex.write_text('\\documentclass{article}\\begin{document}\n' +
                   '\n\n'.join('Paragraph %d. ' % i + 'Text of the test document. ' * 40 for i in range(120)) +
                   '\n\\end{document}\n')
    pdflatex = next((p for p in ('/Applications/TeXLive/2026/bin/universal-darwin/pdflatex', '/Library/TeX/texbin/pdflatex')
                     if Path(p).exists()), 'pdflatex')
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
