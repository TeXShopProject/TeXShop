#!/usr/bin/env python3
"""Check that the Preview comes back as it was on the next launch of TeXShop (#71).

Up to 6.00 RC2, a source restored only the frame and the page of its Preview, and a PDF opened by
itself was not reopened at all. Now the display of the Preview is restored as faithfully as
possible: the display format, magnification (also Actual Size and Fit to Content Width) and the
place at the top edge of each part, its pinned link popup at its place on its page, showing the
same part of its pages, the other view of Switch Views with its own display and popup, whether
the window is split, top and bottom or side by side, where the divider is (also pushed to an end),
which part is in use, the rotation given to the pages and the Two-Page Arrangement chosen. The
Preview window of a PDF opened by itself keeps its file and frame as well.

The production code that encodes and restores this state runs unchanged in stand-in classes: a
window with a real NSSplitView and two real PDFView parts, never shown, the real popup class, and
the product's own setScaleFactor:, setMagnification: and placePinnedLinkPreview:windowFrame:. The
state goes through a keyed archive that requires secure coding, as AppKit's restorable state does.
macOS's own part, which reopens the document and calls these methods on the next launch, was
checked on macOS 26 and 15 with the real application.
--mutation NAME leaves out one part of the restoration (see MUTATIONS); the harness must then fail.
"""
import argparse
import os
import subprocess
import tempfile
from pathlib import Path
from production_fragments import closing_brace, method, verify_embedded
from source_tree import include_args

MUTATIONS = {
    'split-not-restored': ('window', '    if ([coder decodeBoolForKey:@"TSPreviewSplit"] && second) {', '    if (NO) {'),
    'share-ignored': ('window', '            if ([coder containsValueForKey:@"TSPreviewSplitShare"] && share >= 0 && share <= 1) {', '            if (NO) {'),
    # The first audit: a divider pushed to an end came back in the middle.
    'ends-ignored': ('window', '            if ([coder containsValueForKey:@"TSPreviewSplitShare"] && share >= 0 && share <= 1) {', '            if (share > 0 && share < 1) {'),
    'places-not-restored': ('window', '        [one finishRestoringPreview];\n', ''),
    'arrangement-lost': ('window', '    if ([coder containsValueForKey:@"TSPreviewDirection"]) {', '    if (NO) {'),
    'frame-not-restored': ('window', '    if (frame.length)\n', '    if (NO)\n'),
    'old-state-taken': ('window', " || ![coder containsValueForKey:@\"TSPreviewFirstPageStyle\"]) return NO;", ') return NO;'),
    # The first audit: the pages came back unturned.
    'rotation-lost': ('window', '    if ([coder containsValueForKey:@"TSPreviewRotation"])\n', '    if (NO)\n'),
    'page-unbounded': ('view', 'MIN((NSUInteger)index, pageCount - 1)', '(NSUInteger)index'),
    'content-width-not-fitted': ('view', '    if (resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH)\n        [self fitContentWidth];\n', ''),
    # The first audit: the magnification set afterwards made Actual Size and Fit to Content Width fixed.
    'option-before-magnification': ('view',
        '    if (autoScales)\n        [self setAutoScales:YES];\n    else if (scale > 0) {\n        [self setAutoScales:NO];\n        [self setMagnification:scale];\n    }\n'
        '    // After the magnification, which makes it fixed: Actual Size and Fit to Content Width stay\n    // chosen; the latter is fitted again once the window is laid out.\n'
        '    if (resize >= NEW_PDF_ACTUAL_SIZE && resize <= NEW_PDF_FIT_TO_CONTENT_WIDTH)\n        resizeOption = resize;\n',
        '    if (resize >= NEW_PDF_ACTUAL_SIZE && resize <= NEW_PDF_FIT_TO_CONTENT_WIDTH)\n        resizeOption = resize;\n'
        '    if (autoScales)\n        [self setAutoScales:YES];\n    else if (scale > 0) {\n        [self setAutoScales:NO];\n        [self setMagnification:scale];\n    }\n'),
    'popup-lost': ('view', '    if (popup && popupPage.document == [self document]) {', '    if (NO) {'),
    # The second audit: a popup away from its place no longer went back to it.
    'away-place-lost': ('view', '    [coder encodeInteger:(NSInteger)index forKey:TSPreviewStateKey(prefix, @"PopupHomePage")];\n', ''),
    # The third audit: with the page it was brought to gone, an away popup was lost.
    'host-gone-loses-popup': ('view', '        if (current || home) {', '        if (current) {'),
    # The third audit: the other view's popup away from its place forgot it.
    'other-home-lost': ('view', '            [otherViewPinnedLinkPreview setAwayPlaceOnPage:otherHomePage rect:otherHome];', '            ;'),
    # The third audit: a narrower linked page above a wider next one showed the gray margin.
    # The fourth audit: a popup scrolled onto its next page was moved back onto the linked page.
    'linked-page-only': ('popup', '            anchor = i;\n', '            anchor = 0;\n'),
    'same-pages-fitted': ('popup', '    if (same)\n', '    if (NO)\n'),
    # The fifth audit: one page narrower, the whole image as wide as before, went unnoticed.
    'image-size-only': ('popup', '        same = [coder containsValueForKey:key] && NSEqualSizes([coder decodeSizeForKey:key], rects[i].size);', '        same = YES;'),
    # The fifth audit: a part within a lower next page went on onto the linked page.
    # A part across the gap kept from the bottom of its page left the gap when the next page got lower.
    'gap-ignored': ('popup', '            source.origin.y = NSMaxY(rects[1]) + [coder decodeDoubleForKey:gap];', '            ;'),
    'strip-height': ('popup', '        bounds = rects[anchor];\n', '        bounds = NSMakeRect(NSMinX(rects[anchor]), 0, NSWidth(rects[anchor]), size.height);\n'),
    # The fourth audit: away from a page turned a quarter, the popup came back upright.
    'away-turn-ignored': ('view', '            if (((home.rotation % 180) + 180) % 180 == 90)', '            if (NO)'),
    'strip-margin': ('popup', '        bounds = rects[anchor];\n', '        bounds = NSMakeRect(0, 0, size.width, size.height);\n'),
    # The second audit: pages of another size stretched the popup or lost it; a missing next page lost it.
    'source-cut': ('popup', '    source = TSLinkPreviewFitSource(source, bounds);', '    source = NSIntersectionRect(source, NSMakeRect(0, 0, size.width, size.height));'),
    'next-page-required': ('popup', '        if (!there) {\n            if (pages.count == 0) return nil;\n            break;\n        }', '        if (!there) return nil;'),
    'other-view-lost': ('view', '    if ([coder containsValueForKey:TSPreviewStateKey(other, @"PageStyle")]) {', '    if (NO) {'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
window_source = (root / 'Sources/Windows/TSPreviewWindow.m').read_text(encoding='latin1')

def region(source, start_marker, end_marker):
    assert source.count(start_marker) == 1
    start = source.index(start_marker)
    end_start = source.index(end_marker, start)
    return source[start:closing_brace(source, source.index('{', end_start))]

# The part: its state, place, popup, other view and rotation (MyPDFKitView.m).
view_text = region(view_source, '// Restoring the Preview on the next launch of TeXShop, as macOS does', '- (void)previewStateChanged')
# The product's own magnification and pinning, which the restoration goes through.
view_methods = [method(view_source, s) for s in ('- (void)setScaleFactor:(CGFloat)scale',
                                                 '- (void)setMagnification: (double)magnification',
                                                 '- (BOOL)placePinnedLinkPreview:(TSLinkPreviewView *)preview windowFrame:(NSRect)frame')]
# The window: split, part in use, rotation, arrangement, and the restorable state of a PDF opened by
# itself (TSPreviewWindow.m); the class method that asks NSDocumentController to reopen the file is left out.
window_text = region(window_source, '#pragma mark - The Preview on the next launch (#71)', '- (void)restoreStateWithCoder:(NSCoder *)coder\n{\n    [super')
fragments = [('statements: the state of a part', view_source, view_text),
             ('statements: the state of the window', window_source, window_text)] + \
            [('complete method: ' + m.split('\n')[0], view_source, m) for m in view_methods]
popup_source = (root / 'Sources/Preview/TSLinkPreviewView.m').read_text(encoding='latin1')
if args.mutation:
    which, old, new = MUTATIONS[args.mutation]
    if which == 'popup':
        assert popup_source.count(old) == 1, args.mutation
        popup_source = popup_source.replace(old, new)
    elif which == 'window':
        assert window_text.count(old) == 1, args.mutation
        window_text = window_text.replace(old, new)
    else:
        assert view_text.count(old) == 1, args.mutation
        view_text = view_text.replace(old, new)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewPanePlace.h"
#import "TSPreviewScrollerKeeper.h"
#import "TSLinkPreviewView.h"
#import "TSLinkPreviewGeometry.h"
#import "globals.h"

@interface TestDocument : NSObject
@property (strong) NSNumber *previewBookOverride, *previewDirectionOverride;
@property (strong) NSURL *fileURL;
@property NSInteger invalidations, layoutUpdates;
- (void)invalidateRestorableState;
- (void)updatePreviewLayoutControls;
@end
@implementation TestDocument
- (void)invalidateRestorableState { self.invalidations++; }
- (void)updatePreviewLayoutControls { self.layoutUpdates++; }
@end
#define TSDocument TestDocument

@interface MyPDFKitView : PDFView {
@public
    NSInteger pageStyle, firstPageStyle, resizeOption, totalRotation, scaleMag, mouseMode;
    BOOL _fittingContentWidth;
    id myScale, smyScale, myScale1, myStepper, smyStepper, myStepper1;
    TSLinkPreviewView *pinnedLinkPreview;
    TSPreviewPanePlace otherViewPlace;
    NSInteger otherViewPageStyle, otherViewFirstPageStyle, otherViewResizeOption;
    BOOL otherViewAutoScales;
    CGFloat otherViewScale;
    PDFSelection *otherViewSelection;
    TSLinkPreviewView *otherViewPinnedLinkPreview;
    NSRect otherViewPinnedLinkPreviewFrame;
    TSPreviewPanePlace restoringPlace;
    TSLinkPreviewView *restoringPopup;
    PDFPage *restoringPopupPage, *restoringPopupHome;
    NSRect restoringPopupOnPage, restoringPopupHomeOnPage;
}
@property (weak) TestDocument *myDocument;
@property BOOL oldUsed;
@property NSInteger handlingLink, arrangements, contentWidthFits, activations, otherViewObserved;
- (void)applyPreviewArrangement;
- (void)becomeActiveView;
- (BOOL)hasPinnedLinkPreview;
- (void)encodePreviewStateWithCoder:(NSCoder *)coder prefix:(NSString *)prefix;
- (BOOL)restorePreviewDisplayWithCoder:(NSCoder *)coder prefix:(NSString *)prefix;
- (void)finishRestoringPreview;
- (NSInteger)previewRotation;
- (void)restorePreviewRotation:(NSInteger)rotation;
- (BOOL)placePinnedLinkPreview:(TSLinkPreviewView *)preview windowFrame:(NSRect)frame;
- (void)setMagnification:(double)magnification;
@end

// AppKit's own part of a window's restorable state needs AppKit's coder; it is left out here.
@interface AppKitStateWindow : NSWindow
@end
@implementation AppKitStateWindow
- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {}
- (void)restoreStateWithCoder:(NSCoder *)coder {}
@end

@interface TestWindow : AppKitStateWindow <NSWindowRestoration>
@property BOOL windowIsSplit, horizontal;
@property (strong) PDFView *myPDFKitView, *myPDFKitView2, *activeView;
@property (strong) NSSplitView *pdfKitSplitView;
@property (strong) TestDocument *myDocument;
@property NSInteger splits;
- (void)encodePreviewStateWithCoder:(NSCoder *)coder;
- (BOOL)restorePreviewStateWithCoder:(NSCoder *)coder;
@end
#define TSPreviewWindow TestWindow
static void TSSplitToggleItemsFollowSplit(void) {}

@implementation MyPDFKitView
- (void)setupPageStyle {
    switch (pageStyle) {
        case PDF_SINGLE_PAGE_STYLE: self.displayMode = kPDFDisplaySinglePage; break;
        case PDF_TWO_PAGE_STYLE: self.displayMode = kPDFDisplayTwoUp; break;
        case PDF_MULTI_PAGE_STYLE: self.displayMode = kPDFDisplaySinglePageContinuous; break;
        case PDF_DOUBLE_MULTI_PAGE_STYLE: self.displayMode = kPDFDisplayTwoUpContinuous; break;
    }
}
- (void)scaleChanged:(NSNotification *)notification {}
- (void)cleanupMarqueeKeepingPinnedLinkPreview {}
- (void)killTransientLinkPreview {}
- (void)observeLinkPreviewEvents {}
- (void)fitContentWidth { self.contentWidthFits++; }
- (void)becomeActiveView { ((TestWindow *)self.window).activeView = self; self.activations++; }
- (void)applyPreviewArrangement { self.arrangements++; }
- (void)otherViewDocumentChanged:(NSNotification *)notification { self.otherViewObserved++; }
- (BOOL)hasPinnedLinkPreview { return pinnedLinkPreview.superview != nil; }
PRODUCTIONVIEWMETHODS
VIEWMETHODS
@end

@implementation TestWindow
- (void)mainSplitPdfKitWindow {
    self.windowIsSplit = YES;
    self.splits++;
    NSSplitView *s = self.pdfKitSplitView;
    CGFloat whole = (s.isVertical ? NSWidth(s.bounds) : NSHeight(s.bounds)) - s.dividerThickness;
    [s setPosition:round(whole / 2) ofDividerAtIndex:0];
    [s adjustSubviews];
}
- (void)showActivePart {}
+ (void)restoreWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler { completionHandler(nil, nil); }
WINDOWMETHODS
@end

static void check(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static BOOL near(CGFloat a, CGFloat b, CGFloat d) { return fabs(a - b) <= d; }
static void pump(void) {
    for (int i = 0; i < 5; i++) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
// Pages of the given sizes.
static PDFDocument *pagesOfSizes(NSArray<NSValue *> *sizes) {
    PDFDocument *document = [[PDFDocument alloc] init];
    for (NSUInteger i = 0; i < sizes.count; i++) {
        NSSize size = sizes[i].sizeValue;
        NSImage *image = [[NSImage alloc] initWithSize:size];
        [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, size.width, size.height)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return [[PDFDocument alloc] initWithData:document.dataRepresentation];
}
// Pages of the given widths, 792 points high.
static PDFDocument *pagesOfWidths(NSArray<NSNumber *> *widths) {
    PDFDocument *document = [[PDFDocument alloc] init];
    for (NSUInteger i = 0; i < widths.count; i++) {
        NSSize size = NSMakeSize(widths[i].doubleValue, 792);
        NSImage *image = [[NSImage alloc] initWithSize:size];
        [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, size.width, size.height)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return [[PDFDocument alloc] initWithData:document.dataRepresentation];
}
static PDFDocument *book(NSInteger pages) {
    PDFDocument *document = [[PDFDocument alloc] init];
    for (NSInteger i = 0; i < pages; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(612, 792)];
        [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, 612, 792)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return [[PDFDocument alloc] initWithData:document.dataRepresentation];
}

// A Preview window as TeXShop opens it: not split, MultiPage, Fit to Window.
static TestWindow *preview(PDFDocument *document) {
    TestWindow *w = [[TestWindow alloc] initWithContentRect:NSMakeRect(100, 100, 700, 760)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    w.myDocument = [TestDocument new];
    w.myDocument.fileURL = [NSURL fileURLWithPath:@"/tmp/issue71-paper.pdf"];
    NSSplitView *s = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
    s.dividerStyle = NSSplitViewDividerStyleThin;
    w.pdfKitSplitView = s;
    MyPDFKitView *parts[2];
    for (int i = 0; i < 2; i++) {
        MyPDFKitView *v = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 700, 380)];
        v.myDocument = w.myDocument;
        v->pageStyle = PDF_MULTI_PAGE_STYLE; v->firstPageStyle = PDF_FIRST_LEFT; v->resizeOption = NEW_PDF_FIT_TO_WINDOW;
        [v setupPageStyle];
        v.document = document;
        v.autoScales = YES;
        [s addSubview:v];
        parts[i] = v;
    }
    w.contentView = s;
    w.myPDFKitView = parts[0]; w.myPDFKitView2 = parts[1]; w.activeView = parts[0];
    [s setPosition:NSHeight(s.bounds) ofDividerAtIndex:0];
    [s adjustSubviews];
    [w layoutIfNeeded];
    return w;
}
static void scrollTo(PDFView *v, NSInteger index, CGFloat y) {
    [v goToDestination:[[PDFDestination alloc] initWithPage:[v.document pageAtIndex:index] atPoint:NSMakePoint(0, y)]];
    [v layoutDocumentView];
}
static NSData *archive(void (^encode)(NSKeyedArchiver *)) {
    NSKeyedArchiver *a = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    encode(a);
    [a finishEncoding];
    return a.encodedData;
}
static NSKeyedUnarchiver *unarchiver(NSData *data) {
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:NULL];
    u.requiresSecureCoding = YES;
    return u;
}
static CGFloat share(TestWindow *w) {
    NSSplitView *s = w.pdfKitSplitView;
    NSRect a = s.subviews[0].frame, b = s.subviews[1].frame;
    CGFloat one = s.isVertical ? NSWidth(a) : NSHeight(a), two = s.isVertical ? NSWidth(b) : NSHeight(b);
    return one / (one + two);
}
static void setShare(TestWindow *w, CGFloat value) {
    NSSplitView *s = w.pdfKitSplitView;
    [s setPosition:round(((s.isVertical ? NSWidth(s.bounds) : NSHeight(s.bounds)) - s.dividerThickness) * value) ofDividerAtIndex:0];
    [s adjustSubviews];
}
static void samePlace(PDFView *a, PDFView *b, NSString *what) {
    TSPreviewPanePlace p = TSPreviewPaneCapture(a), q = TSPreviewPaneCapture(b);
    check(p.valid && q.valid && p.pageIndex == q.pageIndex && near(p.pagePoint.y, q.pagePoint.y, 2) && near(p.pagePoint.x, q.pagePoint.x, 2),
          [NSString stringWithFormat:@"%@: the same place (page %lu at %@, not page %lu at %@)", what, (unsigned long)p.pageIndex + 1,
           NSStringFromPoint(p.pagePoint), (unsigned long)q.pageIndex + 1, NSStringFromPoint(q.pagePoint)]);
}
// A popup of the link to page `index`, going on with the next page, pinned in the part.
static TSLinkPreviewView *pin(MyPDFKitView *v, NSUInteger index, NSRect windowFrame, NSRect source) {
    NSArray *pages = @[[v.document pageAtIndex:index], [v.document pageAtIndex:index + 1]];
    NSSize a, b; CGAffineTransform t;
    TSLinkPreviewPageGeometry(pages[0], &a, &t); TSLinkPreviewPageGeometry(pages[1], &b, &t);
    NSRect rects[2];
    NSSize size = TSLinkPreviewStrip(a, b, &rects[0], &rects[1]);
    TSLinkPreviewView *popup = [[TSLinkPreviewView alloc] initWithFrame:NSZeroRect image:TSLinkPreviewStripImage(pages, rects, size)
                                                                  source:source pageSize:size pages:pages pageRects:rects];
    popup.pageLabel = [NSString stringWithFormat:@"Page %lu", (unsigned long)index + 1];
    check([v placePinnedLinkPreview:popup windowFrame:windowFrame], @"fixture: the popup is pinned");
    return popup;
}
static NSArray *popupPages(TSLinkPreviewView *popup) {
    NSData *data = archive(^(NSKeyedArchiver *a) { [popup encodeContentWithCoder:a prefix:@"P"]; });
    return [unarchiver(data) decodeObjectOfClasses:[NSSet setWithObjects:NSArray.class, NSNumber.class, nil] forKey:@"PPages"];
}
// The popup's frame on the page under its upper left corner, as TeXShop keeps it on its page.
static NSString *popupPlace(MyPDFKitView *v, TSLinkPreviewView *popup) {
    NSRect frame = [v convertRect:popup.frame fromView:popup.superview];
    PDFPage *page = [v pageForPoint:NSMakePoint(NSMinX(frame), v.isFlipped ? NSMinY(frame) : NSMaxY(frame)) nearest:YES];
    NSRect r = [v convertRect:frame toPage:page];
    return [NSString stringWithFormat:@"page %lu %.0f %.0f %.0f %.0f", (unsigned long)[v.document indexForPage:page] + 1,
            NSMinX(r), NSMinY(r), NSWidth(r), NSHeight(r)];
}

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    PDFDocument *pdf = book(7);

    for (NSNumber *sideBySide in @[@NO, @YES]) {
        NSString *name = sideBySide.boolValue ? @"side by side" : @"top and bottom";
        // The Preview as the user left it: split, each part with its own display format, place and popup.
        TestWindow *before = preview(pdf);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView, *two = (MyPDFKitView *)before.myPDFKitView2;
        one->pageStyle = PDF_DOUBLE_MULTI_PAGE_STYLE; [one setupPageStyle];
        one.autoScales = NO; [one setMagnification:1.4];
        [before.pdfKitSplitView setVertical:sideBySide.boolValue];
        before.horizontal = !sideBySide.boolValue;
        [before mainSplitPdfKitWindow];
        setShare(before, 0.35);
        two->pageStyle = PDF_SINGLE_PAGE_STYLE; [two setupPageStyle];
        two.autoScales = NO; [two setMagnification:0.9];
        [before layoutIfNeeded];
        scrollTo(one, 1, 400); scrollTo(two, 4, 300);
        NSRect oneFrame = [one convertRect:one.bounds toView:nil], twoFrame = [two convertRect:two.bounds toView:nil];
        TSLinkPreviewView *p1 = pin(one, 2, NSMakeRect(NSMinX(oneFrame) + 30, NSMinY(oneFrame) + 40, 180, 90), NSMakeRect(40, 700, 360, 180));
        TSLinkPreviewView *p2 = pin(two, 5, NSMakeRect(NSMinX(twoFrame) + 20, NSMinY(twoFrame) + 30, 150, 80), NSMakeRect(10, 900, 300, 160));
        before.activeView = two;
        before.myDocument.previewDirectionOverride = @YES;
        before.myDocument.previewBookOverride = @NO;
        NSData *state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });

        // The next launch: the PDF is opened again in a Preview as TeXShop opens it.
        TestWindow *after = preview(pdf);
        MyPDFKitView *a1 = (MyPDFKitView *)after.myPDFKitView, *a2 = (MyPDFKitView *)after.myPDFKitView2;
        check([after restorePreviewStateWithCoder:unarchiver(state)], [name stringByAppendingString:@": the state is restored"]);
        pump();
        check(after.windowIsSplit && after.splits == 1 && after.horizontal == !sideBySide.boolValue
              && after.pdfKitSplitView.isVertical == sideBySide.boolValue, [name stringByAppendingString:@": the window is split the same way"]);
        check(near(share(after), share(before), 0.01), [NSString stringWithFormat:@"%@: the divider is where it was (%.3f, not %.3f)",
                                                       name, share(before), share(after)]);
        check(after.activeView == a2 && a2.activations == 1, [name stringByAppendingString:@": the second part is in use again"]);
        check(a1->pageStyle == PDF_DOUBLE_MULTI_PAGE_STYLE && a1.displayMode == kPDFDisplayTwoUpContinuous
              && a2->pageStyle == PDF_SINGLE_PAGE_STYLE && a2.displayMode == kPDFDisplaySinglePage,
              [name stringByAppendingString:@": each part has its display format"]);
        check(!a1.autoScales && near(a1.scaleFactor, 1.4, 0.001) && !a2.autoScales && near(a2.scaleFactor, 0.9, 0.001)
              && a1->resizeOption == NEW_PDF_FIT_TO_NONE, [name stringByAppendingString:@": each part has its magnification"]);
        samePlace(one, a1, [name stringByAppendingString:@", first part"]);
        samePlace(two, a2, [name stringByAppendingString:@", second part"]);
        TSLinkPreviewView *r1 = a1->pinnedLinkPreview, *r2 = a2->pinnedLinkPreview;
        check(r1.pinned && r2.pinned && [a1 hasPinnedLinkPreview] && [a2 hasPinnedLinkPreview], [name stringByAppendingString:@": each part has its pinned popup"]);
        check([popupPages(r1) isEqual:popupPages(p1)] && [popupPages(r2) isEqual:popupPages(p2)] && [r1.pageLabel isEqual:@"Page 3"]
              && NSEqualRects(r1.source, p1.source) && NSEqualRects(r2.source, p2.source),
              [name stringByAppendingString:@": each popup shows the same part of the same pages, with its label"]);
        check([popupPlace(a1, r1) isEqual:popupPlace(one, p1)] && [popupPlace(a2, r2) isEqual:popupPlace(two, p2)],
              [NSString stringWithFormat:@"%@: each popup is at its place on its page (%@, not %@)", name, popupPlace(one, p1), popupPlace(a1, r1)]);
        check([after.myDocument.previewDirectionOverride isEqual:@YES] && [after.myDocument.previewBookOverride isEqual:@NO]
              && a1.arrangements == 1 && a2.arrangements == 1, [name stringByAppendingString:@": the Two-Page Arrangement chosen comes back"]);
        check(after.myDocument.layoutUpdates >= 1, [name stringByAppendingString:@": the toolbar follows"]);
        [before close]; [after close];
    }

    // A divider pushed to an end stays there.
    for (NSNumber *end in @[@0, @1]) for (NSNumber *sideBySide in @[@NO, @YES]) {
        TestWindow *before = preview(pdf);
        [before.pdfKitSplitView setVertical:sideBySide.boolValue];
        before.horizontal = !sideBySide.boolValue;
        [before mainSplitPdfKitWindow];
        setShare(before, end.doubleValue);
        CGFloat saved = share(before);
        NSData *state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
        TestWindow *after = preview(pdf);
        [after restorePreviewStateWithCoder:unarchiver(state)]; pump();
        check(near(share(after), saved, 0.01), [NSString stringWithFormat:@"a divider pushed to %@ (%@) stays there (%.3f, not %.3f)",
                                                end.boolValue ? @"the end" : @"the start", sideBySide.boolValue ? @"side by side" : @"top and bottom",
                                                saved, share(after)]);
    }

    {   // Not split, Fit to Width (the magnification fits the window again), the document's own arrangement,
        // and the other view of Switch Views with its own display, place and popup.
        TestWindow *before = preview(pdf);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
        one->pageStyle = PDF_SINGLE_PAGE_STYLE; [one setupPageStyle];
        one->resizeOption = NEW_PDF_FIT_TO_WIDTH; one.autoScales = YES;
        scrollTo(one, 2, 500);
        TSLinkPreviewView *other = pin(one, 4, NSMakeRect(130, 140, 160, 100), NSMakeRect(20, 800, 320, 200));
        // Switch Views as TeXShop does it: the popup goes with the view put aside.
        [other removeFromSuperview]; one->pinnedLinkPreview = nil;
        one.oldUsed = YES;
        one->otherViewPlace = (TSPreviewPanePlace){YES, 5, NSMakePoint(12, 345)};
        one->otherViewPageStyle = PDF_TWO_PAGE_STYLE; one->otherViewFirstPageStyle = PDF_FIRST_RIGHT;
        one->otherViewResizeOption = NEW_PDF_FIT_TO_NONE; one->otherViewAutoScales = NO; one->otherViewScale = 1.7;
        one->otherViewPinnedLinkPreview = other; one->otherViewPinnedLinkPreviewFrame = NSMakeRect(30, -200, 160, 100);
        NSData *state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
        TestWindow *after = preview(pdf);
        after.myDocument.previewDirectionOverride = @YES;
        MyPDFKitView *a1 = (MyPDFKitView *)after.myPDFKitView;
        check([after restorePreviewStateWithCoder:unarchiver(state)], @"not split: the state is restored");
        pump();
        check(!after.windowIsSplit && after.splits == 0 && after.activeView == a1, @"not split: the window stays unsplit");
        check(a1->pageStyle == PDF_SINGLE_PAGE_STYLE && a1.autoScales && a1->resizeOption == NEW_PDF_FIT_TO_WIDTH, @"not split: Single Page, Fit to Width");
        samePlace(one, a1, @"not split");
        check(after.myDocument.previewDirectionOverride == nil, @"not split: the document's own arrangement is used again");
        check(![a1 hasPinnedLinkPreview], @"not split: no popup was pinned in the view shown");
        check(a1.oldUsed && a1->otherViewPlace.valid && a1->otherViewPlace.pageIndex == 5 && NSEqualPoints(a1->otherViewPlace.pagePoint, NSMakePoint(12, 345))
              && a1->otherViewPageStyle == PDF_TWO_PAGE_STYLE && a1->otherViewFirstPageStyle == PDF_FIRST_RIGHT
              && a1->otherViewResizeOption == NEW_PDF_FIT_TO_NONE && !a1->otherViewAutoScales && near(a1->otherViewScale, 1.7, 0.001),
              @"the other view of Switch Views comes back with its place, display format and magnification");
        check(a1->otherViewPinnedLinkPreview && [popupPages(a1->otherViewPinnedLinkPreview) isEqual:popupPages(other)]
              && NSEqualRects(a1->otherViewPinnedLinkPreview.source, other.source)
              && NSEqualRects(a1->otherViewPinnedLinkPreviewFrame, NSMakeRect(30, -200, 160, 100)),
              @"the other view comes back with its popup at its place");
        [[NSNotificationCenter defaultCenter] postNotificationName:PDFViewDocumentChangedNotification object:a1];
        check(a1.otherViewObserved == 1, @"a new PDF still closes the popup of the other view");

        // Actual Size and Fit to Content Width stay chosen; the latter is fitted again in the window shown.
        for (NSNumber *option in @[@(NEW_PDF_ACTUAL_SIZE), @(NEW_PDF_FIT_TO_CONTENT_WIDTH)]) {
            one.autoScales = NO; [one setMagnification:option.integerValue == NEW_PDF_ACTUAL_SIZE ? 1.0 : 1.2];
            one->resizeOption = option.integerValue;
            state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
            after = preview(pdf); a1 = (MyPDFKitView *)after.myPDFKitView;
            [after restorePreviewStateWithCoder:unarchiver(state)]; pump();
            check(a1->resizeOption == option.integerValue, [NSString stringWithFormat:@"%@ stays chosen (%ld, not %ld)",
                  option.integerValue == NEW_PDF_ACTUAL_SIZE ? @"Actual Size" : @"Fit to Content Width", (long)option.integerValue, (long)a1->resizeOption]);
            check(a1.contentWidthFits == (option.integerValue == NEW_PDF_FIT_TO_CONTENT_WIDTH ? 1 : 0), @"Fit to Content Width is fitted again");
        }

        // The PDF has fewer pages since: its last page is shown, and a popup of pages no longer there is left out.
        one->resizeOption = NEW_PDF_FIT_TO_WIDTH; one.autoScales = YES;
        scrollTo(one, 6, 300);
        state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
        after = preview(book(3)); a1 = (MyPDFKitView *)after.myPDFKitView;
        [after restorePreviewStateWithCoder:unarchiver(state)]; pump();
        TSPreviewPanePlace shown = TSPreviewPaneCapture(a1);
        check(shown.valid && shown.pageIndex == 2, @"a shorter PDF shows its last page");
        check(a1->otherViewPinnedLinkPreview == nil, @"a popup of pages no longer there is left out");

        // A state saved by an earlier version has only the page: nothing here is restored.
        NSData *old = archive(^(NSKeyedArchiver *a) { [a encodeInteger:3 forKey:@"VisiblePDFPage"]; });
        after = preview(pdf); a1 = (MyPDFKitView *)after.myPDFKitView;
        check(![after restorePreviewStateWithCoder:unarchiver(old)] && a1->pageStyle == PDF_MULTI_PAGE_STYLE && a1.autoScales,
              @"an earlier version's state is left to the source's page restoration");
        // A Preview without a PDF keeps nothing.
        TestWindow *empty = preview(nil);
        NSData *none = archive(^(NSKeyedArchiver *a) { [empty encodePreviewStateWithCoder:a]; });
        check(![unarchiver(none) containsValueForKey:@"TSPreviewFirstPageStyle"], @"a Preview without a PDF keeps nothing");
    }

    {   // The pages turned by the user come back turned, and the place on them with them.
        PDFDocument *turned = book(7), *again = book(7);
        TestWindow *before = preview(turned);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
        [one restorePreviewRotation:90];
        check([one previewRotation] == 90 && [turned pageAtIndex:3].rotation == 90, @"fixture: the pages are turned");
        scrollTo(one, 3, 200);
        NSData *state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
        TestWindow *after = preview(again);
        MyPDFKitView *a1 = (MyPDFKitView *)after.myPDFKitView;
        [after restorePreviewStateWithCoder:unarchiver(state)]; pump();
        check([a1 previewRotation] == 90 && [again pageAtIndex:0].rotation == 90 && [again pageAtIndex:6].rotation == 90,
              @"the pages come back turned, once");
        samePlace(one, a1, @"turned pages");
    }

    {   // The Preview window of a PDF opened by itself keeps its file and frame; a source's does not.
        TestWindow *before = preview(pdf);
        // Inside the visible part of the screen, which setFrameFromString: keeps windows in.
        NSRect visible = NSScreen.mainScreen.visibleFrame;
        [before setFrame:NSMakeRect(NSMinX(visible) + 60, NSMinY(visible) + 40, 600, MIN(600, NSHeight(visible) - 80)) display:NO];
        NSData *own = archive(^(NSKeyedArchiver *a) { [before encodeRestorableStateWithCoder:a]; });
        check(![unarchiver(own) containsValueForKey:@"TSPreviewDocumentURL"], @"a source's Preview keeps no file of its own");
        before.restorationClass = [TestWindow class];
        own = archive(^(NSKeyedArchiver *a) { [before encodeRestorableStateWithCoder:a]; });
        NSKeyedUnarchiver *u = unarchiver(own);
        check([[u decodeObjectOfClass:[NSURL class] forKey:@"TSPreviewDocumentURL"] isEqual:before.myDocument.fileURL],
              @"a PDF opened by itself keeps its file");
        TestWindow *after = preview(pdf);
        after.restorationClass = [TestWindow class];
        [after restoreStateWithCoder:unarchiver(own)]; pump();
        check(NSEqualRects(after.frame, before.frame), [NSString stringWithFormat:@"the window comes back at its frame (%@, not %@)",
                                                        NSStringFromRect(before.frame), NSStringFromRect(after.frame)]);
        check([unarchiver(own) containsValueForKey:@"TSPreviewFirstPageStyle"], @"a PDF opened by itself keeps the state of its Preview");
    }
    {   // A popup away from its place, because its page is not shown in Single Page display, goes back to
        // its place on its page after the next launch too (#35).
        TestWindow *before = preview(pdf);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
        one->pageStyle = PDF_SINGLE_PAGE_STYLE; [one setupPageStyle];
        scrollTo(one, 5, 600);
        NSRect frame = [one convertRect:one.bounds toView:nil];
        TSLinkPreviewView *popup = pin(one, 2, NSMakeRect(NSMinX(frame) + 50, NSMinY(frame) + 60, 170, 90), NSMakeRect(30, 900, 300, 160));
        NSRect home = NSMakeRect(72, 500, 170, 90);
        [popup setAwayPlaceOnPage:[pdf pageAtIndex:1] rect:home];
        NSData *state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
        TestWindow *after = preview(pdf);
        MyPDFKitView *a1 = (MyPDFKitView *)after.myPDFKitView;
        [after restorePreviewStateWithCoder:unarchiver(state)]; pump();
        TSLinkPreviewView *back = a1->pinnedLinkPreview;
        NSRect kept = NSZeroRect;
        check(back && [back awayPlaceOnPage:&kept] == [pdf pageAtIndex:1] && NSEqualRects(kept, home),
              @"an away popup keeps the place it goes back to");
        check([popupPlace(a1, back) isEqual:popupPlace(one, popup)], @"an away popup stays where it was meanwhile");
        scrollTo(a1, 1, 700);
        check([back returnToPlaceIfAway], @"going back to its page brings the popup back to its place");
        NSRect onPage = [a1 convertRect:[a1 convertRect:back.frame fromView:back.superview] toPage:[pdf pageAtIndex:1]];
        check(near(NSMinX(onPage), 72, 1) && near(NSMinY(onPage), 500, 1) && near(NSWidth(onPage), 170, 1),
              [NSString stringWithFormat:@"the popup is at its place on its page (%@)", NSStringFromRect(onPage)]);
    }

    {   // The PDF typeset again: the pages of a popup changed size, or its next page is gone.
        TestWindow *before = preview(pdf);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
        TSLinkPreviewView *wide = pin(one, 1, NSMakeRect(100, 120, 180, 100), NSMakeRect(245, 900, 180, 100));
        NSData *content = archive(^(NSKeyedArchiver *a) { [wide encodeContentWithCoder:a prefix:@"C"]; });
        [wide removeFromSuperview]; one->pinnedLinkPreview = nil;
        // Pages 300 points wide instead of 612.
        PDFDocument *narrow = [[PDFDocument alloc] init];
        for (NSInteger i = 0; i < 7; i++) {
            NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(300, 792)];
            [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, 300, 792)); [image unlockFocus];
            [narrow insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
        }
        narrow = [[PDFDocument alloc] initWithData:narrow.dataRepresentation];
        TSLinkPreviewView *fitted = [TSLinkPreviewView linkPreviewWithCoder:unarchiver(content) prefix:@"C" document:narrow frame:NSMakeRect(0, 0, 180, 100)];
        check(fitted && near(NSWidth(fitted.source), 180, 0.5) && near(NSHeight(fitted.source), 100, 0.5) && NSMaxX(fitted.source) <= 300.5,
              [NSString stringWithFormat:@"narrower pages: the part in view keeps its size and lies on the page (%@)", NSStringFromRect(fitted.source)]);
        // A part larger than the page shrinks, keeping its proportions.
        TSLinkPreviewView *big = pin(one, 1, NSMakeRect(100, 120, 200, 100), NSMakeRect(100, 900, 400, 200));
        content = archive(^(NSKeyedArchiver *a) { [big encodeContentWithCoder:a prefix:@"C"]; });
        [big removeFromSuperview]; one->pinnedLinkPreview = nil;
        fitted = [TSLinkPreviewView linkPreviewWithCoder:unarchiver(content) prefix:@"C" document:narrow frame:NSMakeRect(0, 0, 200, 100)];
        check(fitted && NSWidth(fitted.source) <= 300.5 && near(NSWidth(fitted.source) / NSHeight(fitted.source), 2, 0.01),
              [NSString stringWithFormat:@"narrower pages: a larger part keeps its proportions (%@)", NSStringFromRect(fitted.source)]);
        // The popup of the last page but one, going on with the last page, in a PDF one page shorter.
        TSLinkPreviewView *strip = pin(one, 5, NSMakeRect(100, 120, 180, 100), NSMakeRect(40, 1000, 300, 160));
        // In the strip the linked page lies above the next one and the gap.
        NSRect onLinked = NSMakeRect(NSMinX(strip.source), NSMinY(strip.source) - (792 + TSLinkPreviewPageGap), 300, 160);
        content = archive(^(NSKeyedArchiver *a) { [strip encodeContentWithCoder:a prefix:@"C"]; });
        PDFDocument *shorter = book(6);
        fitted = [TSLinkPreviewView linkPreviewWithCoder:unarchiver(content) prefix:@"C" document:shorter frame:NSMakeRect(0, 0, 180, 100)];
        NSArray *pages = popupPages(fitted);
        check(fitted && [pages isEqual:@[@5]], [NSString stringWithFormat:@"without its next page the popup shows the linked page alone (%@, pages %@)", fitted, pages]);
        check(fitted && NSEqualRects(fitted.source, onLinked),
              [NSString stringWithFormat:@"the part in view stays at its place on the linked page (%@, not %@)",
               NSStringFromRect(fitted.source), NSStringFromRect(onLinked)]);
    }
    {   // The page an away popup was brought to is gone: it goes to its own place, or stays away from it
        // while its page is not shown (third audit).
        for (NSNumber *continuous in @[@NO, @YES]) {
            TestWindow *before = preview(pdf);
            MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
            one->pageStyle = continuous.boolValue ? PDF_MULTI_PAGE_STYLE : PDF_SINGLE_PAGE_STYLE; [one setupPageStyle];
            scrollTo(one, 5, 600);
            NSRect frame = [one convertRect:one.bounds toView:nil];
            TSLinkPreviewView *popup = pin(one, 2, NSMakeRect(NSMinX(frame) + 50, NSMinY(frame) + 60, 170, 90), NSMakeRect(30, 900, 300, 160));
            NSRect home = NSMakeRect(72, 500, 170, 90);
            [popup setAwayPlaceOnPage:[pdf pageAtIndex:1] rect:home];
            NSData *state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
            PDFDocument *shorter = book(4);
            TestWindow *after = preview(shorter);
            MyPDFKitView *a1 = (MyPDFKitView *)after.myPDFKitView;
            [after restorePreviewStateWithCoder:unarchiver(state)]; pump();
            TSLinkPreviewView *back = a1->pinnedLinkPreview;
            NSString *name = continuous.boolValue ? @"MultiPage" : @"Single Page";
            check(back && [a1 hasPinnedLinkPreview], [name stringByAppendingString:@": with the page it was brought to gone, the popup comes back"]);
            if (continuous.boolValue) {
                NSRect onPage = [a1 convertRect:[a1 convertRect:back.frame fromView:back.superview] toPage:[shorter pageAtIndex:1]];
                check(near(NSMinX(onPage), 72, 1) && near(NSMinY(onPage), 500, 1) && [back awayPlaceOnPage:NULL] == nil,
                      [NSString stringWithFormat:@"MultiPage: it is at its own place (%@)", NSStringFromRect(onPage)]);
            } else {
                NSRect kept = NSZeroRect;
                check([back awayPlaceOnPage:&kept] == [shorter pageAtIndex:1] && NSEqualRects(kept, home),
                      @"Single Page: it stays away from its place, which it keeps");
                scrollTo(a1, 1, 700);
                check([back returnToPlaceIfAway], @"Single Page: going to its page brings it back to its place");
            }
        }
    }

    {   // A narrower linked page above a wider next one: the part in view stays on the linked page, not in
        // the gray margin beside it (third audit).
        TestWindow *before = preview(pdf);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
        TSLinkPreviewView *popup = pin(one, 1, NSMakeRect(100, 120, 170, 100), NSMakeRect(245, 900, 170, 100));
        NSData *content = archive(^(NSKeyedArchiver *a) { [popup encodeContentWithCoder:a prefix:@"C"]; });
        PDFDocument *mixed = pagesOfWidths(@[@612, @300, @800, @612]);
        TSLinkPreviewView *fitted = [TSLinkPreviewView linkPreviewWithCoder:unarchiver(content) prefix:@"C" document:mixed frame:NSMakeRect(0, 0, 170, 100)];
        NSRect first, second;
        TSLinkPreviewStrip(NSMakeSize(300, 792), NSMakeSize(800, 792), &first, &second);
        check(fitted && NSMinX(fitted.source) >= NSMinX(first) - 0.5 && NSMaxX(fitted.source) <= NSMaxX(first) + 0.5
              && near(NSWidth(fitted.source), 170, 0.5),
              [NSString stringWithFormat:@"the part in view lies on the linked page (%@ within %@)", NSStringFromRect(fitted.source), NSStringFromRect(first)]);
    }

    {   // A popup scrolled onto the wider next page shows the same part after the next launch; with the
        // next page narrower since, the part lies on that page (fourth audit).
        PDFDocument *wideNext = pagesOfWidths(@[@612, @300, @800, @612]);
        TestWindow *before = preview(wideNext);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
        TSLinkPreviewView *popup = pin(one, 1, NSMakeRect(100, 120, 170, 100), NSMakeRect(630, 300, 170, 100));
        NSData *content = archive(^(NSKeyedArchiver *a) { [popup encodeContentWithCoder:a prefix:@"C"]; });
        TSLinkPreviewView *same = [TSLinkPreviewView linkPreviewWithCoder:unarchiver(content) prefix:@"C" document:wideNext frame:NSMakeRect(0, 0, 170, 100)];
        check(same && NSEqualRects(same.source, popup.source),
              [NSString stringWithFormat:@"the same PDF: the popup shows the same part (%@, not %@)", NSStringFromRect(popup.source), NSStringFromRect(same.source)]);
        // A part partly beside the linked page, over the gray margin, stays as it was in the same PDF.
        [popup removeFromSuperview]; one->pinnedLinkPreview = nil;
        TSLinkPreviewView *margin = pin(one, 1, NSMakeRect(100, 120, 170, 100), NSMakeRect(500, 1000, 170, 100));
        NSData *marginContent = archive(^(NSKeyedArchiver *a) { [margin encodeContentWithCoder:a prefix:@"C"]; });
        TSLinkPreviewView *kept = [TSLinkPreviewView linkPreviewWithCoder:unarchiver(marginContent) prefix:@"C" document:wideNext frame:NSMakeRect(0, 0, 170, 100)];
        check(kept && NSEqualRects(kept.source, margin.source),
              [NSString stringWithFormat:@"the same PDF: a part over the margin stays as it was (%@, not %@)", NSStringFromRect(margin.source), NSStringFromRect(kept.source)]);
        PDFDocument *narrowNext = pagesOfWidths(@[@612, @300, @612, @612]);
        TSLinkPreviewView *moved = [TSLinkPreviewView linkPreviewWithCoder:unarchiver(content) prefix:@"C" document:narrowNext frame:NSMakeRect(0, 0, 170, 100)];
        NSRect first, second;
        TSLinkPreviewStrip(NSMakeSize(300, 792), NSMakeSize(612, 792), &first, &second);
        // It showed the right end of the next page; it does so on the narrower page too.
        check(moved && near(NSMinX(moved.source), NSMaxX(second) - 170, 0.5) && near(NSMinY(moved.source), 300, 0.5)
              && near(NSWidth(moved.source), 170, 0.5),
              [NSString stringWithFormat:@"a narrower next page: the part lies on it (%@ within %@)", NSStringFromRect(moved.source), NSStringFromRect(second)]);
    }

    {   // Only one page of a popup changed size, the whole image keeping its size; or the next page is
        // lower: the part in view stays on the page it showed (fifth audit).
        PDFDocument *wide = pagesOfWidths(@[@612, @612, @800, @612]);
        TestWindow *before = preview(wide);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
        TSLinkPreviewView *onLinked = pin(one, 1, NSMakeRect(100, 120, 170, 100), NSMakeRect(500, 1000, 170, 100));
        NSData *content = archive(^(NSKeyedArchiver *a) { [onLinked encodeContentWithCoder:a prefix:@"C"]; });
        [onLinked removeFromSuperview]; one->pinnedLinkPreview = nil;
        PDFDocument *narrowLinked = pagesOfWidths(@[@612, @300, @800, @612]);
        TSLinkPreviewView *fitted = [TSLinkPreviewView linkPreviewWithCoder:unarchiver(content) prefix:@"C" document:narrowLinked frame:NSMakeRect(0, 0, 170, 100)];
        NSRect first, second;
        TSLinkPreviewStrip(NSMakeSize(300, 792), NSMakeSize(800, 792), &first, &second);
        check(fitted && NSContainsRect(NSInsetRect(first, -0.5, -0.5), fitted.source),
              [NSString stringWithFormat:@"only the linked page narrower: the part lies on it (%@ within %@)", NSStringFromRect(fitted.source), NSStringFromRect(first)]);

        PDFDocument *tall = pagesOfWidths(@[@612, @612, @612, @612]);
        before = preview(tall); one = (MyPDFKitView *)before.myPDFKitView;
        TSLinkPreviewView *onNext = pin(one, 1, NSMakeRect(100, 120, 170, 100), NSMakeRect(100, 600, 170, 100));
        content = archive(^(NSKeyedArchiver *a) { [onNext encodeContentWithCoder:a prefix:@"C"]; });
        [onNext removeFromSuperview]; one->pinnedLinkPreview = nil;
        PDFDocument *lowNext = pagesOfSizes(@[[NSValue valueWithSize:NSMakeSize(612, 792)], [NSValue valueWithSize:NSMakeSize(612, 792)],
                                              [NSValue valueWithSize:NSMakeSize(612, 340)], [NSValue valueWithSize:NSMakeSize(612, 792)]]);
        fitted = [TSLinkPreviewView linkPreviewWithCoder:unarchiver(content) prefix:@"C" document:lowNext frame:NSMakeRect(0, 0, 170, 100)];
        TSLinkPreviewStrip(NSMakeSize(612, 792), NSMakeSize(612, 340), &first, &second);
        check(fitted && NSContainsRect(NSInsetRect(second, -0.5, -0.5), fitted.source) && near(NSHeight(fitted.source), 100, 0.5),
              [NSString stringWithFormat:@"a lower next page: the part stays on it (%@ within %@)", NSStringFromRect(fitted.source), NSStringFromRect(second)]);

        // A part that went on across the gap still may, down the whole strip.
        TSLinkPreviewView *across = pin(one, 1, NSMakeRect(100, 120, 170, 100), NSMakeRect(100, 740, 170, 100));
        content = archive(^(NSKeyedArchiver *a) { [across encodeContentWithCoder:a prefix:@"C"]; });
        fitted = [TSLinkPreviewView linkPreviewWithCoder:unarchiver(content) prefix:@"C" document:lowNext frame:NSMakeRect(0, 0, 170, 100)];
        // It went from 52 points below the top of the next page across the gap; it still does.
        check(fitted && near(NSHeight(fitted.source), 100, 0.5) && near(NSMinY(fitted.source), NSMaxY(second) - 52, 0.5)
              && NSMaxY(fitted.source) > NSMinY(first),
              [NSString stringWithFormat:@"a part across the gap stays across it (%@)", NSStringFromRect(fitted.source)]);
    }

    {   // Away from its place on a page turned a quarter, with the page it was brought to gone, the popup
        // keeps the shape it has on the screen (fourth audit).
        for (NSNumber *turn in @[@90, @270]) {
            PDFDocument *turned = book(7), *shorter = book(4);
            [turned pageAtIndex:1].rotation = turn.integerValue; [shorter pageAtIndex:1].rotation = turn.integerValue;
            TestWindow *before = preview(turned);
            MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
            one->pageStyle = PDF_SINGLE_PAGE_STYLE; [one setupPageStyle];
            scrollTo(one, 5, 600);
            NSRect frame = [one convertRect:one.bounds toView:nil];
            TSLinkPreviewView *popup = pin(one, 2, NSMakeRect(NSMinX(frame) + 50, NSMinY(frame) + 60, 170, 90), NSMakeRect(30, 900, 300, 160));
            // On the turned page a popup 170 wide and 90 high on the screen is 90 wide and 170 high.
            [popup setAwayPlaceOnPage:[turned pageAtIndex:1] rect:NSMakeRect(100, 200, 90, 170)];
            NSData *state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
            TestWindow *after = preview(shorter);
            MyPDFKitView *a1 = (MyPDFKitView *)after.myPDFKitView;
            a1->pageStyle = PDF_SINGLE_PAGE_STYLE; [a1 setupPageStyle];
            [after restorePreviewStateWithCoder:unarchiver(state)]; pump();
            TSLinkPreviewView *back = a1->pinnedLinkPreview;
            check(back && NSWidth(back.frame) > NSHeight(back.frame) && near(NSWidth(back.frame) / NSHeight(back.frame), 170.0 / 90, 0.05),
                  [NSString stringWithFormat:@"turned %@: the popup keeps its shape on the screen (%@)", turn, NSStringFromRect(back.frame)]);
        }
    }

    {   // The other view's popup away from its place keeps it too (third audit).
        TestWindow *before = preview(pdf);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
        TSLinkPreviewView *other = pin(one, 4, NSMakeRect(130, 140, 160, 100), NSMakeRect(20, 800, 320, 200));
        [other setAwayPlaceOnPage:[pdf pageAtIndex:2] rect:NSMakeRect(15, 450, 160, 100)];
        [other removeFromSuperview]; one->pinnedLinkPreview = nil;
        one.oldUsed = YES;
        one->otherViewPlace = (TSPreviewPanePlace){YES, 5, NSMakePoint(12, 345)};
        one->otherViewPageStyle = PDF_SINGLE_PAGE_STYLE; one->otherViewFirstPageStyle = PDF_FIRST_LEFT;
        one->otherViewResizeOption = NEW_PDF_FIT_TO_NONE; one->otherViewScale = 1.0;
        one->otherViewPinnedLinkPreview = other; one->otherViewPinnedLinkPreviewFrame = NSMakeRect(30, -200, 160, 100);
        NSData *state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
        TestWindow *after = preview(pdf);
        MyPDFKitView *a1 = (MyPDFKitView *)after.myPDFKitView;
        [after restorePreviewStateWithCoder:unarchiver(state)]; pump();
        NSRect kept = NSZeroRect;
        check(a1->otherViewPinnedLinkPreview && [a1->otherViewPinnedLinkPreview awayPlaceOnPage:&kept] == [pdf pageAtIndex:2]
              && NSEqualRects(kept, NSMakeRect(15, 450, 160, 100)), @"the other view's popup keeps the place it goes back to");
    }
    puts("PASS: the Preview comes back as it was: split and divider, display format, magnification, place and popup of each part, the other view of Switch Views, rotation, the Two-Page Arrangement chosen and its frame");
} return 0; }
'''
program = program.replace('PRODUCTIONVIEWMETHODS', '\n'.join(view_methods)).replace('VIEWMETHODS', view_text).replace('WINDOWMETHODS', window_text)
verify_embedded(program, fragments if not args.mutation else [])
with tempfile.TemporaryDirectory(prefix='texshop-restore-state-') as directory:
    temp = Path(directory)
    (temp / 'test.m').write_text(program, encoding='latin1')
    # The popup class compiles from the source tree's include paths; a mutation changes this copy only.
    (temp / 'TSLinkPreviewView.m').write_text(popup_source, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    '-I', str(root / 'Tests'), *include_args(root), str(temp / 'test.m'),
                    str(root / 'Sources/Preview/TSPreviewScrollerKeeper.m'), str(temp / 'TSLinkPreviewView.m'),
                    str(root / 'Sources/Windows/TSDocumentWindowGlass.m'), '-o', str(temp / 'test')], check=True)
    home = temp / 'home'
    (home / 'Library' / 'Preferences').mkdir(parents=True)
    environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temp))
    result = subprocess.run([str(temp / 'test')], timeout=120, env=environment, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.splitlines()[-1])
    else:
        print(output)
        result.check_returncode()
