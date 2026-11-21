#!/usr/bin/env python3
"""Split, unsplit and switch the preview panes with the production code in a window that is
never shown, and check that the place at the top edge of each pane does not move. With pages
one below the other, the first split into a top and a bottom part, and a split with Shift,
move nothing on the screen: the bottom part shows what was below its top edge, and gets a copy
of a pinned popup (#66)."""
from pathlib import Path
import argparse
import subprocess
import sys
import tempfile
from source_tree import include_args
from production_fragments import closing_brace, verify_embedded

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['band-counted', 'heights-with-band', 'first-not-restored', 'switch-not-swapped', 'shift-not-same',
                                           'second-not-saved', 'edge-ignores-flip',
                                           'deferred-restore', 'restore-before-layout',
                                           'not-continued', 'continued-when-saved', 'popup-not-copied', 'popups-pulled-in',
                                           'format-after-magnification'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
window_source = (root / 'Sources/Windows/TSPreviewWindow.m').read_text(encoding='latin1')
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
header_source = (root / 'Sources/Preview/TSPreviewPanePlace.h').read_text(encoding='latin1')
# The preview also keeps the top of each part while its divider is dragged (#24);
# run the split code together with it when it is there.
divider = root / 'Sources/Preview/TSPreviewSplitDivider.m'
uses_divider = divider.exists()

def last_method(source, signature):
    # TSPreviewWindow.m keeps an older copy of mainSplitPdfKitWindow in a comment.
    start = source.rindex(signature)
    return source[start:closing_brace(source, source.index('{', start))]

split = last_method(window_source, '- (void) mainSplitPdfKitWindow')
# The split places the parts by their frames (#55).
place = last_method(window_source, 'static void TSPreviewPlacePartByFrame(NSView *part)')
switch = last_method(window_source, '- (void)switchViews\n')
# Switching the parts of a split window (#25).
parts = last_method(window_source, '- (void)switchSplitParts\n')
splitter = last_method(window_source, '- (void) splitPdfKitWindow:')
view_methods = [last_method(view_source, s) for s in (
    '- (void)saveLocation\n', '- (void)restoreLocation\n', '- (NSInteger)index\n', '- (void)moveSplitToCorrectSpot:')]
fragments = [('complete method: ' + text.split('\n')[0], source, text)
             for source, text in [(window_source, place), (window_source, split), (window_source, switch), (window_source, parts), (window_source, splitter)]
             + [(view_source, m) for m in view_methods]]

for problem, old, new in (
        ('first-not-restored', 'TSPreviewPaneRestore(firstView, firstTop);', ''),
        ('switch-not-swapped', 'TSPreviewPaneRestore(upperView, lower);', 'TSPreviewPaneRestore(upperView, upper);'),
        ('shift-not-same', 'TSPreviewPaneRestore(secondView, firstTop);', ';'),
        ('second-not-saved', '[secondView saveLocation];', ''),
        # The band under the toolbar is counted as part of the first pane.
        ('band-counted', '            else\n                TSDocumentWindowSplitEvenly(self.pdfKitSplitView);\n', '            else\n                ;\n'),
        # The height saved for the first pane includes the band under the toolbar.
        ('heights-with-band', 'temp1 = MAX(0, theFrame1.size.height - TSDocumentWindowHiddenTop(self.pdfKitSplitView));', 'temp1 = theFrame1.size.height;'),
        # #66: the bottom part goes where it went before, to the top of the page.
        ('not-continued', '(topToBottom || ! secondView.locationSaved);', 'NO;'),
        ('continued-when-saved', '(topToBottom || ! secondView.locationSaved);', 'YES;'),
        ('popup-not-copied', '[secondView showCopyOfPinnedLinkPreviewOfView: firstView];', ''),
        # #66 audit: the bottom part is fitted before it has the display format of the top part.
        ('format-after-magnification', '        [(MyPDFKitView *)self.myPDFKitView2 setupPageStyle];\n        if ( [(MyPDFKitView *)self.myPDFKitView resizeOption]',
         '        if ( [(MyPDFKitView *)self.myPDFKitView resizeOption]'),
        ('popups-pulled-in', '    if (! continuesBelow)\n        [self keepPinnedLinkPreviewsInView];', '    [self keepPinnedLinkPreviewsInView];'),
        ('restore-before-layout', '    [self.pdfKitSplitView adjustSubviews];\n    [self.pdfKitSplitView layoutSubtreeIfNeeded];\n    TSPreviewPaneRestore', '    TSPreviewPaneRestore')):
    if args.mutation == problem:
        assert split.count(old) + parts.count(old) >= 1, problem
        split, parts = split.replace(old, new), parts.replace(old, new)
if args.mutation == 'deferred-restore':
    # Putting the place back once more later undoes what the user did in between.
    old = '    TSPreviewPaneRestore(firstView, firstTop);\n    if (self.windowIsSplit)'
    assert split.count(old) == 1
    split = split.replace(old, '    TSPreviewPaneRestore(firstView, firstTop);\n'
                          '    dispatch_async(dispatch_get_main_queue(), ^{ TSPreviewPaneRestore(firstView, firstTop); });\n    if (self.windowIsSplit)')
    old = '    TSPreviewPaneRestore(lowerView, upper);\n'
    assert parts.count(old) == 1
    parts = parts.replace(old, old + '    dispatch_async(dispatch_get_main_queue(), ^{ TSPreviewPaneRestore(upperView, lower); });\n')
if args.mutation == 'edge-ignores-flip':
    old = 'CGFloat top = clip.isFlipped ? NSMinY(bounds) + insets.top : NSMaxY(bounds) - insets.top;'
    assert header_source.count(old) == 1
    header_source = header_source.replace(old, 'CGFloat top = NSMaxY(bounds) - insets.top;')

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewPanePlace.h"
#import "TSDocumentWindowGlass.h"
DIVIDERIMPORT
#define NEW_PDF_FIT_TO_NONE 1
#define NEW_PDF_FIT_TO_WINDOW 4
#define NEW_PDF_FIT_TO_CONTENT_WIDTH 6
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSEventModifierFlags flags;
static NSEventModifierFlags currentFlags(id s, SEL c) { return flags; }
// The split toolbar buttons are checked in run-split-toggle-option.py.
static void TSSplitToggleItemsFollowSplit(void) {}
@interface TSLinkPreviewView : NSView @end
@implementation TSLinkPreviewView @end
@interface MyPDFKitView : PDFView {
    TSPreviewPanePlace splitPlace;
    NSInteger pageStyle, firstPageStyle, resizeOption;
}
@property BOOL locationSaved, verticalSplitSaved, horizontalSplitSaved;
@property double horizontalHeight1, horizontalHeight2, verticalWidth1, verticalWidth2, fixedScale;
@property BOOL oldUsed, doScroll; @property NSRect oldVisibleRect; @property NSInteger oldIndex;
@property BOOL singlePage;
// The display mode when the magnification was last set.
@property NSInteger modeAtScale;
- (void)moveSplitToCorrectSpot:(NSInteger)index;
- (void)notificationSetup;
- (void)saveLocation;
- (void)restoreLocation;
@end
@implementation MyPDFKitView
- (NSInteger)pageStyle { return pageStyle; }
- (NSInteger)firstPageStyle { return firstPageStyle; }
- (NSInteger)resizeOption { return resizeOption; }
- (void)setPageStyle:(NSInteger)s { pageStyle = s; }
- (void)setFirstPageStyle:(NSInteger)s { firstPageStyle = s; }
- (void)setResizeOption:(NSInteger)s { resizeOption = s; }
- (double)magnification { return self.scaleFactor; }
- (void)setMagnification:(double)m { self.modeAtScale = self.displayMode; [self setScaleFactor:m]; }
// pageStyle 1 is single page, 3 continuous single page (PDF_*_STYLE in globals.h).
- (void)setupPageStyle { [self setDisplayMode:pageStyle == 1 ? kPDFDisplaySinglePage : kPDFDisplaySinglePageContinuous]; [self setDisplaysPageBreaks:pageStyle != 1]; }
- (void)setupMagnificationStyle { self.modeAtScale = self.displayMode; if (resizeOption == NEW_PDF_FIT_TO_WINDOW) [self setAutoScales:YES]; else [self setScaleFactor:self.fixedScale]; }
// Fit to Content Width has its own test, run-fit-content-width.py.
- (void)fitContentWidth {}
- (void)measureContentLater {}
- (void)centreContentRowLater {}
- (void)cleanupMarqueeKeepingPinnedLinkPreview {}
// Watching the page number does not change the place shown.
- (void)notificationSetup {}
- (void)resetSearchDelegate {}
- (void)becomeActiveView {}
// Switch Views in a window that is not split has its own test, run-preview-switch-views.py.
- (void)switchToOtherView {}
- (BOOL)hasPinnedLinkPreview { return YES; }
- (TSLinkPreviewView *)detachPinnedLinkPreviewWithWindowFrame:(NSRect *)f { return nil; }
- (void)attachPinnedLinkPreview:(TSLinkPreviewView *)p windowFrame:(NSRect)f {}
- (BOOL)placePinnedLinkPreview:(TSLinkPreviewView *)p windowFrame:(NSRect)f { return NO; }
- (void)keepPinnedLinkPreviewInView {}
// The copy itself is checked in run-pinned-link-preview.py.
static NSUInteger popupCopies, popupKeeps;
- (void)showCopyOfPinnedLinkPreviewOfView:(MyPDFKitView *)other { if (other != self) popupCopies++; }
VIEWMETHODS
@end
// The document: it hears that the second part goes away (annotation text being edited for it is dropped).
@interface TestHost : NSObject
- (void)annotationPartWillCollapse:(id)view;
@end
@implementation TestHost
- (void)annotationPartWillCollapse:(id)view {}
@end
@interface TestWindow : NSWindow
@property (strong) TestHost *myDocument;
@property BOOL firstTime, windowIsSplit, horizontal;
@property PDFView *activeView, *myPDFKitView, *myPDFKitView2;
@property NSSplitView *pdfKitSplitView;
DIVIDERPROPERTY
- (void)mainSplitPdfKitWindow;
- (void)splitPdfKitWindow:(id)sender;
- (void)switchViews;
@end
@implementation TestWindow
- (void)keepPinnedLinkPreviewsInView { popupKeeps++; }
SPLITMETHOD
SWITCHMETHOD
PARTSMETHOD
SPLITTERMETHOD
@end

// The window's content runs under its toolbar, as the Preview window's on macOS 26 and later.
@interface GlassToolbar : NSObject <NSToolbarDelegate> @end
@implementation GlassToolbar
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return @[@"item"]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return @[@"item"]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = @"Item"; item.image = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:nil];
    return item;
}
@end
static GlassToolbar *glassToolbar;
static void runUnderToolbar(NSWindow *window) {
    if (!glassToolbar) glassToolbar = [GlassToolbar new];
    window.toolbarStyle = NSWindowToolbarStyleExpanded;
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"glass"];
    toolbar.delegate = glassToolbar; window.toolbar = toolbar;
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    [window layoutIfNeeded];
}
static void settle(NSWindow *w) {
    for (int i = 0; i < 4; i++) {
        [w layoutIfNeeded];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}
// Screen points between the top edge of a pane and the place, or a large number if the
// place is on a page that is not shown.
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
static TSPreviewPanePlace topOf(PDFView *v) {
    NSClipView *clip = v.documentView.enclosingScrollView.contentView;
    NSRect b = clip.bounds;
    NSPoint top = [v convertPoint:NSMakePoint(NSMidX(b), clip.isFlipped ? NSMinY(b) : NSMaxY(b)) fromView:clip];
    PDFPage *page = [v pageForPoint:top nearest:YES];
    return (TSPreviewPanePlace){YES, [v.document indexForPage:page], [v convertPoint:top toPage:page]};
}
static void scrollTo(PDFView *v, NSUInteger pageIndex, CGFloat y) {
    [v goToRect:NSMakeRect(100, y, 1, 1) onPage:[v.document pageAtIndex:pageIndex]];
}
static BOOL near(CGFloat d) { return fabs(d) < 0.01; }

typedef struct { TestWindow *window; MyPDFKitView *first, *second; } Preview;
static Preview makePreview(PDFDocument *doc, double scale, NSInteger style) {
    TestWindow *w = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 900)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    NSSplitView *sv = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [w.contentView addSubview:sv];
    MyPDFKitView *a = [[MyPDFKitView alloc] initWithFrame:sv.bounds], *b = [[MyPDFKitView alloc] initWithFrame:sv.bounds];
    for (MyPDFKitView *v in @[a, b]) {
        // As in TSDocument.nib.
        v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        v.autoresizesSubviews = NO; v.wantsLayer = YES;
        v.fixedScale = scale;
        [v setPageStyle:style];
        [v setResizeOption:scale > 0 ? NEW_PDF_FIT_TO_NONE : NEW_PDF_FIT_TO_WINDOW];
    }
    [sv addSubview:a];
    w.pdfKitSplitView = sv; w.myPDFKitView = a; w.myPDFKitView2 = b; w.activeView = a;
    w.firstTime = YES; w.horizontal = YES;
    a.document = doc; [a setupPageStyle]; [a setupMagnificationStyle];
    settle(w);
    return (Preview){w, a, b};
}
static void split(Preview p, NSEventModifierFlags modifiers) {
    flags = modifiers; [p.window splitPdfKitWindow:nil]; flags = 0; settle(p.window);
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    method_setImplementation(class_getClassMethod(NSEvent.class, @selector(modifierFlags)), (IMP)currentFlags);
    PDFDocument *doc = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];
    check(doc.pageCount >= 6, @"test document has pages");
    NSArray *scales = @[@1, @1.5, @0.75, @0];
    for (NSNumber *scale in scales) for (NSNumber *option in @[@NO, @YES]) {
        NSString *name = [NSString stringWithFormat:@"%@ at %@%%", option.boolValue ? @"side by side" : @"top and bottom",
                          scale.doubleValue ? @(scale.doubleValue * 100) : @"fit"];
        Preview p = makePreview(doc, scale.doubleValue, 3);
        scrollTo(p.first, 1, 500); settle(p.window);
        TSPreviewPanePlace start = topOf(p.first);
        for (int i = 1; i <= 3; i++) {
            split(p, option.boolValue ? NSEventModifierFlagOption : 0);
            check(p.window.windowIsSplit && p.second.superview, [name stringByAppendingString:@": the window is split"]);
            check(near(distanceFromTop(p.first, start)), [NSString stringWithFormat:@"%@: split %d keeps the top of the first pane (moved %.2f)", name, i, distanceFromTop(p.first, start)]);
            split(p, 0);
            check(!p.window.windowIsSplit && !p.second.superview, [name stringByAppendingString:@": the window is unsplit"]);
            check(near(distanceFromTop(p.first, start)), [NSString stringWithFormat:@"%@: unsplit %d keeps the top (moved %.2f)", name, i, distanceFromTop(p.first, start)]);
        }
        // Switching swaps exactly what the panes show at their top edges, however often.
        split(p, option.boolValue ? NSEventModifierFlagOption : 0);
        scrollTo(p.second, 3, 300); settle(p.window);
        TSPreviewPanePlace upper = topOf(p.first), lower = topOf(p.second);
        for (int i = 1; i <= 5; i++) {
            [p.window switchViews]; settle(p.window);
            TSPreviewPanePlace a = i % 2 ? lower : upper, b = i % 2 ? upper : lower;
            check(near(distanceFromTop(p.first, a)) && near(distanceFromTop(p.second, b)),
                  [NSString stringWithFormat:@"%@: switch %d swaps the panes exactly (%.2f, %.2f)", name, i, distanceFromTop(p.first, a), distanceFromTop(p.second, b)]);
        }
        // The second pane shows its place again when the window is split next time,
        // and the first pane still keeps its top.
        upper = topOf(p.first); lower = topOf(p.second);
        split(p, 0);
        check(near(distanceFromTop(p.first, upper)), [name stringByAppendingString:@": unsplitting after switching keeps the top"]);
        split(p, option.boolValue ? NSEventModifierFlagOption : 0);
        check(near(distanceFromTop(p.first, upper)) && near(distanceFromTop(p.second, lower)),
              [NSString stringWithFormat:@"%@: splitting again shows the second pane's place (%.2f)", name, distanceFromTop(p.second, lower)]);
        [p.window close];
    }
    // Pages one below the other, split into a top and a bottom part for the first time, or with
    // Shift after the bottom part was used: nothing moves on the screen (#66). The bottom part
    // shows what was below its top edge, at the same magnification, the popups are copied and
    // none is pulled into view. Splitting side by side, and later splits without Shift, are as before.
    // The bottom part takes the display format of the top part before its magnification, so that
    // Fit to Content Width fits the pages as they are laid out there (#66 audit).
    for (NSNumber *scale in @[@1, @0]) {
        Preview p = makePreview(doc, scale.doubleValue, 3);
        [p.second setPageStyle:1]; [p.second setupPageStyle]; p.second.modeAtScale = -1;
        split(p, 0);
        check(p.second.modeAtScale == kPDFDisplaySinglePageContinuous && p.second.displayMode == kPDFDisplaySinglePageContinuous,
              [NSString stringWithFormat:@"first split at %@: the bottom part has the display format before its magnification (%ld)",
               scale.doubleValue ? @"100%" : @"fit", (long)p.second.modeAtScale]);
        [p.window close];
    }
    for (NSNumber *scale in @[@1, @1.5, @0.75]) for (int shift = 0; shift < 2; shift++) {
        NSString *name = [NSString stringWithFormat:@"%@split at %@%%", shift ? @"shift-" : @"first ", @(scale.doubleValue * 100)];
        Preview p = makePreview(doc, scale.doubleValue, 3);
        if (shift) { split(p, 0); scrollTo(p.second, 5, 300); settle(p.window); split(p, 0); }
        scrollTo(p.first, 2, 600); settle(p.window);
        TSPreviewPanePlace start = topOf(p.first);
        CGFloat top = TSPreviewPaneWindowEdge(p.first).y;
        NSUInteger copies = popupCopies, keeps = popupKeeps;
        split(p, shift ? NSEventModifierFlagShift : 0);
        CGFloat below = top - TSPreviewPaneWindowEdge(p.second).y;
        check(below > 100, [NSString stringWithFormat:@"%@: the bottom part starts below the top (%.1f)", name, below]);
        check(near(distanceFromTop(p.first, start)), [name stringByAppendingString:@": the top part keeps its top"]);
        check(fabs(distanceFromTop(p.second, start) + below) < 0.5,
              [NSString stringWithFormat:@"%@: the bottom part shows what was below its top edge (%.2f, expected %.2f)", name, distanceFromTop(p.second, start), -below]);
        check(fabs(p.second.scaleFactor - p.first.scaleFactor) < 1e-6, [name stringByAppendingString:@": the same magnification"]);
        check(popupCopies == copies + 1 && popupKeeps == keeps, [name stringByAppendingString:@": the popup is copied, none pulled into view"]);
        if (shift)
            check(fabs(NSHeight(p.first.frame) - NSHeight(p.second.frame)) < 1, @"shift-split: the panes have the same size");
        // Unsplit and split again without Shift: the bottom part shows its place again.
        scrollTo(p.second, 4, 300); settle(p.window);
        TSPreviewPanePlace lower = topOf(p.second);
        split(p, 0); split(p, 0);
        check(near(distanceFromTop(p.second, lower)), [name stringByAppendingString:@": splitting again shows the bottom part's place"]);
        check(popupCopies == copies + 1, [name stringByAppendingString:@": no copy then"]);
        [p.window close];
    }
    {   // Side by side, the first time: as before, no copy.
        Preview p = makePreview(doc, 1, 3);
        scrollTo(p.first, 2, 600); settle(p.window);
        NSUInteger copies = popupCopies;
        split(p, NSEventModifierFlagOption);
        check(popupCopies == copies, @"side by side: no copy");
        [p.window close];
    }
    {   // Shift-split, one page at a time: both panes show the place that was at the top of the window.
        Preview p = makePreview(doc, 1.5, 1);
        split(p, 0); scrollTo(p.second, 5, 300); settle(p.window); split(p, 0);
        scrollTo(p.first, 2, 600); settle(p.window);
        TSPreviewPanePlace start = topOf(p.first);
        split(p, NSEventModifierFlagShift);
        check(near(distanceFromTop(p.first, start)), @"single page: shift-split keeps the top of the first pane");
        check(near(distanceFromTop(p.second, start)), [NSString stringWithFormat:@"single page: shift-split: the second pane shows the same place (%.2f)", distanceFromTop(p.second, start)]);
        [p.window close];
    }
    {   // Single page display: the panes can show different pages.
        Preview p = makePreview(doc, 1.5, 1);
        scrollTo(p.first, 2, 500); settle(p.window);
        TSPreviewPanePlace start = topOf(p.first);
        split(p, 0);
        check(near(distanceFromTop(p.first, start)), @"single page: split keeps the top");
        scrollTo(p.second, 4, 750); settle(p.window);
        TSPreviewPanePlace upper = topOf(p.first), lower = topOf(p.second);
        check(upper.pageIndex == 2 && lower.pageIndex == 4, @"single page: the panes show different pages");
        [p.window switchViews]; settle(p.window);
        check(near(distanceFromTop(p.first, lower)) && near(distanceFromTop(p.second, upper)), @"single page: switch swaps the pages and places");
        split(p, 0);
        check(near(distanceFromTop(p.first, lower)), [NSString stringWithFormat:@"single page: unsplit keeps the top (%.2f)", distanceFromTop(p.first, lower)]);
        [p.window close];
    }
    {   // Near the end of the document the larger pane cannot keep the top; it shows the end.
        Preview p = makePreview(doc, 1, 3);
        [p.first goToPage:[doc pageAtIndex:doc.pageCount - 1]];
        NSClipView *clip = p.first.documentView.enclosingScrollView.contentView;
        [p.first.documentView scrollPoint:NSMakePoint(0, NSMaxY(clip.documentRect))]; settle(p.window);
        split(p, 0);
        scrollTo(p.first, doc.pageCount - 1, 60); settle(p.window);
        split(p, 0);
        NSRect b = clip.bounds, d = clip.documentRect;
        check(fabs(NSMaxY(b) - NSMaxY(d)) < 1, @"unsplitting at the end of the document shows the end without a gap");
        [p.window close];
    }
    {   // Scrolling or switching right after splitting, before the run loop turns again, is kept.
        Preview p = makePreview(doc, 1, 3);
        scrollTo(p.first, 1, 500); settle(p.window);
        flags = 0; [p.window splitPdfKitWindow:nil];
        scrollTo(p.first, 4, 300);
        TSPreviewPanePlace moved = topOf(p.first);
        settle(p.window);
        check(near(distanceFromTop(p.first, moved)), [NSString stringWithFormat:@"scrolling right after splitting is kept (%.2f)", distanceFromTop(p.first, moved)]);
        [p.window splitPdfKitWindow:nil];
        scrollTo(p.first, 2, 400);
        moved = topOf(p.first);
        settle(p.window);
        check(near(distanceFromTop(p.first, moved)), @"scrolling right after unsplitting is kept");
        [p.window splitPdfKitWindow:nil]; settle(p.window);
        scrollTo(p.second, 5, 300); settle(p.window);
        TSPreviewPanePlace upper = topOf(p.first), lower = topOf(p.second);
        [p.window switchViews];
        [p.window switchViews];
        settle(p.window);
        check(near(distanceFromTop(p.first, upper)) && near(distanceFromTop(p.second, lower)),
              [NSString stringWithFormat:@"switching twice in a row returns both panes (%.2f, %.2f)", distanceFromTop(p.first, upper), distanceFromTop(p.second, lower)]);
        [p.window close];
    }
    if (@available(macOS 26.0, *)) {
        // A window whose content runs under the toolbar: the parts share the area below the
        // toolbar, and a divider moved by the user comes back with the same shares.
        Preview p = makePreview(doc, 1, 3);
        runUnderToolbar(p.window); settle(p.window);
        CGFloat band = TSDocumentWindowHiddenTop(p.window.pdfKitSplitView);
        check(band > 20, [NSString stringWithFormat:@"full-size window: the band under the toolbar is seen (%.1f)", band]);
        scrollTo(p.first, 1, 500); settle(p.window);
        TSPreviewPanePlace start = topOf(p.first);
        split(p, 0);
        CGFloat shown1 = NSHeight(p.first.frame) - band, shown2 = NSHeight(p.second.frame);
        check(fabs(shown1 - shown2) <= 1, [NSString stringWithFormat:@"full-size window: the parts share the area below the toolbar evenly (%.1f, %.1f)", shown1, shown2]);
        check(near(distanceFromTop(p.first, start)), @"full-size window: splitting keeps the top of the first pane");
        // From the top of the first pane's clip view, where topOf takes its place, also under the toolbar.
        NSClipView *firstClip = p.first.documentView.enclosingScrollView.contentView;
        NSRect fb = firstClip.bounds;
        CGFloat clipTop = [firstClip convertPoint:NSMakePoint(NSMinX(fb), firstClip.isFlipped ? NSMinY(fb) : NSMaxY(fb)) toView:nil].y;
        CGFloat below = clipTop - TSPreviewPaneWindowEdge(p.second).y;
        check(fabs(distanceFromTop(p.second, start) + below) < 0.5,
              [NSString stringWithFormat:@"full-size window: the bottom part shows what was below its top edge (%.2f, expected %.2f)", distanceFromTop(p.second, start), -below]);
        NSSplitView *sv = p.window.pdfKitSplitView;
        CGFloat usable = NSHeight(sv.bounds) - band - sv.dividerThickness;
        [sv setPosition:round(band + usable / 3) ofDividerAtIndex:0]; settle(p.window);
        CGFloat share = (NSHeight(p.first.frame) - band) / (NSHeight(p.first.frame) - band + NSHeight(p.second.frame));
        split(p, 0);
        NSRect frame = p.window.frame; frame.size.height -= 180; [p.window setFrame:frame display:NO]; settle(p.window);
        split(p, 0);
        CGFloat again = (NSHeight(p.first.frame) - band) / (NSHeight(p.first.frame) - band + NSHeight(p.second.frame));
        check(fabs(again - share) < 0.01, [NSString stringWithFormat:@"full-size window: the parts come back with the shares the user left (%.3f, %.3f)", share, again]);
        [p.window close];
    }
    printf("PASS: %lu checks\n", (unsigned long)checks);
    return 0;
}}
'''
program = (program.replace('DIVIDERIMPORT', '#import "TSPreviewSplitDivider.h"' if uses_divider else '')
           .replace('DIVIDERPROPERTY', '@property (strong) TSPreviewSplitDivider *previewSplitDivider;' if uses_divider else '')
           .replace('VIEWMETHODS', '\n'.join(view_methods))
           .replace('SPLITTERMETHOD', splitter).replace('SPLITMETHOD', place + '\n' + split).replace('SWITCHMETHOD', switch).replace('PARTSMETHOD', parts))
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    (temp / 'TSPreviewPanePlace.h').write_text(header_source, encoding='latin1')
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
                    '-I', str(temp), '-I', str(root / 'Tests'), *include_args(root),
                    str(temp / 'test.m'), *([str(divider), str(root / 'Sources/Preview/TSPreviewScrollerKeeper.m')] if uses_divider else []), str(root / 'Sources/Windows/TSDocumentWindowGlass.m'), '-o', str(temp / 'test')], check=True)
    result = subprocess.run([str(temp / 'test'), str(temp / 'doc.pdf')], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.strip().splitlines()[-1])
    else:
        print(output.strip())
        sys.exit(result.returncode)
