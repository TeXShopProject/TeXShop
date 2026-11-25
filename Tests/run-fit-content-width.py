#!/usr/bin/env python3
"""Fit to Content Width (#33), a magnification of the Preview window, with the production code
in windows that are never shown.

With pages one below the other, the content of all pages sets the magnification and the place
sideways, which stay as the pages scroll by. The magnification stays as it is until every page
is measured, then the content is fitted once. One page or one row at a time, the widest
content of a page or row sets the magnification and the content of each page or row comes to
the middle when it is shown. Going to a place, as the drawer, links, SyncTeX and Find do, keeps
that place sideways, so that the margins stay in view (#62). The text at the top of the view stays; a
narrower or wider view fits again; the same magnification set again keeps the mode, any other
leaves it."""
from pathlib import Path
import argparse, subprocess, sys, tempfile
from source_tree import include_args
from production_fragments import method, verify_embedded

MUTATIONS = {
    # #53: going to a page or a place right after a change of the size, in the same turn of the
    # event loop, does not tell the keeper, which brings back the text from the change.
    'page-not-told': ('view', '        TSPreviewScrollHorizontally(self.documentView.enclosingScrollView, x);\n    // A change of the size in the same turn of the event loop does not bring its text back (#53).\n    TSPreviewPlaceChosenByProgram(self);\n',
                      '        TSPreviewScrollHorizontally(self.documentView.enclosingScrollView, x);\n'),
    'destination-not-told': ('view', '        TSContentPlaceSideways(self);\n    // A change of the size in the same turn of the event loop, as when Split Window with Link\n    // widens a narrow part, does not bring its text back (#53).\n    TSPreviewPlaceChosenByProgram(self);\n',
                             '        TSContentPlaceSideways(self);\n'),
    # TSContentZoom.h
    'fits-before-measured': ('view', '        [self measureContentLater];\n        return;\n    }\n    _fittingContentWidth = YES;',
                             '        TSContentWidthMeasureAll(self.document, self.displayBox);\n    }\n    _fittingContentWidth = YES;'),
    'top-not-kept': ('zoom', '    top.page = topPage;\n    TSContentRestoreTop(view, top);', '    top.page = topPage;'),
    'not-centred-sideways': ('zoom', '        if (!NSIsEmptyRect(all)) TSContentScrollTo(view, all, NO, NO);', ''),
    'first-group-only': ('zoom', '        for (NSArray<PDFPage *> *group in groups) width = MAX(width, NSWidth(TSContentFitRectInView(view, group)));',
                         '        width = NSWidth(TSContentFitRectInView(view, groups.firstObject));'),
    'one-row-of-all': ('zoom', '    if (TSContentContinuous(view)) {\n        NSMutableArray *all', '    if (YES) {\n        NSMutableArray *all'),
    # MyPDFKitView.m
    'not-measured': ('view', '        if (!TSContentWidthMeasureSlice(document, self.displayBox, 0.008, &failed)) {',
                     '        if (YES) {'),
    'no-refit-on-resize': ('view', '    if (!refit) {', '    if (YES) {'),
    'top-after-resize': ('view', '    top.page = topPage;\n    [self fitContentWidthKeepingTop:top];', '    [self fitContentWidth];'),
    'same-scale-leaves': ('view', '        (resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH && fabs(scale - self.scaleFactor) < 1e-6);', '        NO;'),
    'page-not-centred': ('view', '            TSContentCentreRow(view);\n    });', '            ;\n    });'),
    'destination-moves-sideways': ('view', '    [self keepContentWidthPlaceDuring:^{ [super goToDestination:destination]; }];',
                                   '    [super goToDestination:destination];'),
    'result-moves-sideways': ('view', '        [self keepContentWidthPlaceDuring:^{ [super scrollSelectionToVisible:sender]; }];',
                              '        [super scrollSelectionToVisible:sender];'),
    'measured-pdf-waits': ('view', '        if (preserveZoom && !TSContentWidthIsComplete(document, self.displayBox))', '        if (preserveZoom)'),
    'new-pdf-not-measured': ('view', '        if (preserveZoom && !TSContentWidthIsComplete(document, self.displayBox))\n            [self measureContentLater];',
                             '        if (preserveZoom && !TSContentWidthIsComplete(document, self.displayBox))\n            ;'),
    # A bordered link comes back as PDFKit. Without this call the view never measures it.
    'no-pdfkit-fallback': ('view',
        '        if (result == TSContentWidthResultPDFKit) [view measureContentWithPDFKit];\n        else if (result == TSContentWidthResultRetry) [view measureContentLater];\n',
        '        if (result == TSContentWidthResultRetry) [view measureContentLater];\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
zoom_path = root / 'Sources/Preview/TSContentZoom.h'
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
zoom_text = zoom_path.read_text().replace('#pragma once\n', '', 1)
view_methods = [method(view_source, s) for s in (
    '- (void)setScaleFactor:(CGFloat)scale', '- (void)fitContentWidth\n{', '- (void)fitContentWidthKeepingTop:(TSContentTop)top',
    '- (void)applyMeasuredContentWidth', '- (void)measureContentLater', '- (void)measureContentWithPDFKit',
    '- (void)measureContentOf:(PDFDocument *)document token:(NSUInteger)token', '- (void)centreContentRowLater',
    '- (void)setFrameSize:(NSSize)newSize', '- (void)setDocument:(PDFDocument *)document',
    '- (void)keepContentWidthPlaceDuring:(void (NS_NOESCAPE ^)(void))navigation', '- (void)goToDestination:(PDFDestination *)destination',
    '- (void)keepHorizontalPositionDuring:(void (NS_NOESCAPE ^)(void))navigation', '- (void)goToPage:(PDFPage *)page', '- (void)layout\n{',
    '- (void)scrollSelectionToVisible:(id)sender')]
fragments = [('complete method: ' + t.split('\n')[0], view_source, t) for t in view_methods]
fragments.append(('header without #pragma once: TSContentZoom.h', zoom_path.read_text(), zoom_text))
view_text = '\n'.join(view_methods)
if args.mutation:
    which, old, new = MUTATIONS[args.mutation]
    text = zoom_text if which == 'zoom' else view_text
    assert text.count(old) == 1, args.mutation
    text = text.replace(old, new)
    if which == 'zoom': zoom_text = text
    else: view_text = text

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewScrollerKeeper.h"
#import "TSPreviewAppearance.h"
#import "TSPreviewHorizontalPosition.h"
ZOOMHEADER
#define PDF_MAX_SCALE 2000
enum { NEW_PDF_ACTUAL_SIZE = 1, NEW_PDF_FIT_TO_NONE = 2, NEW_PDF_FIT_TO_WINDOW = 3, NEW_PDF_FIT_TO_CONTENT_WIDTH = 6 };
static NSUInteger checks;
static NSString *context = @"";
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s [%s]\n", message.UTF8String, context.UTF8String); exit(1); }
}
static void settle(NSWindow *w) {
    for (int i = 0; i < 4; i++) {
        [w layoutIfNeeded];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}
@interface TSExternalPDFDocument : PDFDocument
@property (copy) NSString *snapshotDirectory;
@end
@interface TestDocument : NSObject
@property BOOL previewDisplaysAsBook, previewDisplaysRTL;
- (void)updatePreviewLayoutControls;
@end
@implementation TestDocument
- (void)updatePreviewLayoutControls {}
@end
@interface MyPDFKitView : PDFView {
    BOOL _fittingContentWidth, _measuringContent, _pdfViewReady;
    NSInteger resizeOption;
    NSView *pinnedLinkPreview;
}
@property (weak) TestDocument *myDocument;
@property NSInteger handlingLink;
@property NSInteger scaleUpdates;
- (void)fitContentWidth;
- (void)centreContentRowLater;
- (void)becomeReady;
@end
@implementation MyPDFKitView
- (NSInteger)resizeOption { return resizeOption; }
- (void)setResizeOption:(NSInteger)option { resizeOption = option; }
- (BOOL)measuring { return _measuringContent; }
// As MyPDFKitView once its first PDF is shown: later PDFs keep the magnification.
- (void)becomeReady { _pdfViewReady = YES; }
- (void)doKillPopup {}
- (void)updateDarkModeInversion {}
- (void)scaleChanged:(NSNotification *)notification { self.scaleUpdates++; }
- (void)keepPinnedLinkPreviewInView {}
VIEWMETHODS
@end

// A4 pages printed on both sides, as with the book class: the text further right on every
// other page, a page number at the foot. Page 13 has a figure wider than the text; page 16 is blank.
static const NSRect OddBody = {{107, 150}, {343, 600}}, EvenBody = {{161, 150}, {343, 600}}, Number = {{290, 40}, {15, 12}};
static const NSRect Wide = {{60, 400}, {480, 100}};
static const NSUInteger Count = 16, WidePage = 12, BlankPage = 15, FindPage = 9;
static NSRect inkOf(NSUInteger index, BOOL wide) {
    if (index == BlankPage) return NSZeroRect;
    NSRect ink = NSUnionRect(index % 2 ? EvenBody : OddBody, Number);
    if (wide && index == WidePage) ink = NSUnionRect(ink, Wide);
    return NSInsetRect(ink, -8, -8);
}
static PDFDocument *makeDocument(BOOL wide, BOOL blank) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect media = CGRectMake(0, 0, 595, 842);
    CGContextRef pdf = CGPDFContextCreate(consumer, &media, NULL);
    for (NSUInteger i = 0; i < Count; i++) {
        CGPDFContextBeginPage(pdf, NULL);
        CGContextSetGrayFillColor(pdf, 0, 1);
        if (!blank && i != BlankPage) {
            CGContextFillRect(pdf, NSRectToCGRect(i % 2 ? EvenBody : OddBody));
            CGContextFillRect(pdf, NSRectToCGRect(Number));
            if (wide && i == WidePage) CGContextFillRect(pdf, NSRectToCGRect(Wide));
            // A word to find, inside the body, near its left edge: the ink stays the same.
            if (i == FindPage) {
                [NSGraphicsContext saveGraphicsState];
                NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:pdf flipped:NO];
                [@"Target" drawAtPoint:NSMakePoint(NSMinX(EvenBody) + 4, 500) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12]}];
                [NSGraphicsContext restoreGraphicsState];
            }
        }
        CGPDFContextEndPage(pdf);
    }
    CGPDFContextClose(pdf); CGContextRelease(pdf); CGDataConsumerRelease(consumer);
    return [[PDFDocument alloc] initWithData:data];
}

typedef struct { NSWindow *window; MyPDFKitView *view; } Preview;
static Preview makePreview(PDFDocument *document, PDFDisplayMode mode) {
    Preview p;
    p.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 700)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    p.window.releasedWhenClosed = NO;
    p.view = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 600, 700)];
    [p.window.contentView addSubview:p.view];
    p.view.displayBox = kPDFDisplayBoxCropBox;
    p.view.displayMode = mode;
    p.view.displaysPageBreaks = YES;
    p.view.document = document;
    [TSPreviewScrollerKeeper installInView:p.view];
    // As pageChanged: does in MyPDFKitView.
    __weak MyPDFKitView *view = p.view;
    [NSNotificationCenter.defaultCenter addObserverForName:PDFViewPageChangedNotification object:p.view queue:nil
        usingBlock:^(NSNotification *note) { [view centreContentRowLater]; }];
    p.view.autoScales = YES;
    settle(p.window);
    return p;
}
static NSClipView *clipOf(PDFView *view) { return view.documentView.enclosingScrollView.contentView; }
// A window whose content runs under the toolbar, as the Preview window on macOS 26 and later.
static Preview makeFullSizePreview(PDFDocument *document) {
    Preview p;
    p.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 700)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
          backing:NSBackingStoreBuffered defer:NO];
    p.window.releasedWhenClosed = NO;
    p.window.toolbarStyle = NSWindowToolbarStyleExpanded;
    p.window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"preview"];
    p.view = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 600, 700)];
    [p.window.contentView addSubview:p.view];
    p.view.displayBox = kPDFDisplayBoxCropBox;
    p.view.displayMode = kPDFDisplaySinglePageContinuous;
    p.view.displaysPageBreaks = YES;
    p.view.document = document;
    [TSPreviewScrollerKeeper installInView:p.view];
    p.view.resizeOption = NEW_PDF_FIT_TO_WINDOW;
    p.view.autoScales = YES;
    settle(p.window);
    return p;
}
// How far below the top edge of the clip view a point of a page is shown, in points.
static CGFloat belowEdge(PDFView *view, PDFPage *page, NSPoint pagePoint) {
    NSClipView *clip = clipOf(view);
    NSPoint point = [clip convertPoint:[view convertPoint:pagePoint fromPage:page] fromView:view];
    NSRect b = clip.bounds;
    return (clip.isFlipped ? point.y - NSMinY(b) : NSMaxY(b) - point.y) * NSHeight(clip.frame) / NSHeight(b);
}
// A point of the clip view (left/right 0..1, top 0..1 from the top) on a page, in page coordinates.
static NSPoint shown(PDFView *view, PDFPage *page, CGFloat across, CGFloat down) {
    NSClipView *clip = clipOf(view);
    NSRect b = clip.bounds;
    NSPoint point = NSMakePoint(NSMinX(b) + across * NSWidth(b), clip.isFlipped ? NSMinY(b) + down * NSHeight(b) : NSMaxY(b) - down * NSHeight(b));
    return [view convertPoint:[view convertPoint:point fromView:clip] toPage:page];
}
static void show(PDFView *view, NSUInteger index) {
    [view goToPage:[view.document pageAtIndex:index]];
    settle(view.window);
}
// Lets every page reach the resolution-1.0 store. The magnification does not move until then.
static void measureAll(MyPDFKitView *view) {
    for (int i = 0; i < 400 && ([view measuring] || !TSContentWidthIsComplete(view.document, view.displayBox)); i++)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    settle(view.window);
    check(TSContentWidthIsComplete(view.document, view.displayBox) && ![view measuring], @"all pages measured");
}
static void fit(MyPDFKitView *view) {
    view.resizeOption = NEW_PDF_FIT_TO_CONTENT_WIDTH;
    [view setAutoScales:NO];
    [view fitContentWidth];
    settle(view.window);
}
// The left and right edges of the view on a page, in page coordinates.
static void edges(MyPDFKitView *view, NSUInteger index, CGFloat *left, CGFloat *right) {
    PDFPage *page = [view.document pageAtIndex:index];
    *left = shown(view, page, 0, .5).x; *right = shown(view, page, 1, .5).x;
}
// Moves stored raw ink. dx is added to the origin. leftGrow and rightGrow widen that side.
static void nudgeInk(PDFView *view, CGFloat dx, CGFloat leftGrow, CGFloat rightGrow) {
    PDFDocument *document = view.document;
    PDFDisplayBox box = view.displayBox;
    for (NSUInteger i = 0; i < document.pageCount; i++) {
        PDFPage *page = [document pageAtIndex:i];
        BOOL known = NO;
        NSRect ink = TSContentWidthRawInk(document, box, page, &known);
        if (!known || NSIsEmptyRect(ink)) continue;
        ink.origin.x += dx - leftGrow;
        ink.size.width += leftGrow + rightGrow;
        TSContentWidthStoreRaw(document, box, page, ink);
    }
}
static NSRect contentClip(PDFView *view) {
    NSMutableArray<PDFPage *> *all = [NSMutableArray array];
    for (NSUInteger i = 0; i < view.document.pageCount; i++) {
        PDFPage *page = [view.document pageAtIndex:i];
        if (page) [all addObject:page];
    }
    return [clipOf(view) convertRect:TSContentFitRectInView(view, all) fromView:view];
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];

    // Pages one below the other: all pages, the wide one included, fill the width, from
    // anywhere in the document, and stay so as the pages go by.
    for (NSNumber *mode in @[@(kPDFDisplaySinglePageContinuous), @(kPDFDisplayTwoUpContinuous)]) {
        BOOL twoUp = mode.integerValue == kPDFDisplayTwoUpContinuous;
        context = [NSString stringWithFormat:@"pages one below the other, mode %ld", (long)mode.integerValue];
        PDFDocument *document = makeDocument(YES, NO);
        Preview p = makePreview(document, (PDFDisplayMode)mode.integerValue);
        MyPDFKitView *view = p.view;
        show(view, 2);
        CGFloat before = view.scaleFactor;
        view.resizeOption = NEW_PDF_FIT_TO_CONTENT_WIDTH;
        [view fitContentWidth];
        // Nothing moves until every page is in the resolution-1.0 store (#62).
        CGFloat firstScale = view.scaleFactor;
        check(view.resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH && !view.autoScales && [view measuring] && fabs(firstScale - before) < 1e-6,
              @"the mode is set and the magnification stays until every page is measured");
        measureAll(view);
        CGFloat scale = view.scaleFactor, left, right;
        check(fabs(scale - firstScale) > 0.01, [NSString stringWithFormat:@"measured pages set the magnification once (%.3f, was %.3f)", scale, firstScale]);
        // The content of every page, in view coordinates, fills the width.
        NSRect all = NSZeroRect;
        for (NSUInteger i = 0; i < Count; i++) {
            if (i == BlankPage) continue;
            NSRect rect = [view convertRect:inkOf(i, YES) fromPage:[document pageAtIndex:i]];
            all = NSIsEmptyRect(all) ? rect : NSUnionRect(all, rect);
        }
        NSRect visible = [view convertRect:TSContentVisibleArea(view) fromView:clipOf(view)];
        check(fabs(NSMinX(all) - NSMinX(visible)) < 1.5 && fabs(NSMaxX(all) - NSMaxX(visible)) < 1.5,
              [NSString stringWithFormat:@"all content %@ fills the view %@", NSStringFromRect(all), NSStringFromRect(visible)]);
        if (!twoUp) {
            edges(view, 2, &left, &right);
            CGFloat wideRight = MAX(NSMaxX(inkOf(WidePage, YES)), NSMaxX(inkOf(3, YES)));
            check(fabs(left - NSMinX(inkOf(WidePage, YES))) < 1.5 && fabs(right - wideRight) < 1.5,
                  [NSString stringWithFormat:@"across the wide figure and the text of all pages (%.1f to %.1f)", left, right]);
        }
        CGFloat x = NSMinX(clipOf(view).bounds);
        for (NSNumber *index in @[@3, @9, @14]) {
            show(view, index.unsignedIntegerValue);
            check(fabs(view.scaleFactor - scale) < 1e-6 && fabs(NSMinX(clipOf(view).bounds) - x) < 0.5 && view.resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH,
                  [NSString stringWithFormat:@"the same magnification and place sideways on page %@", index]);
        }
        // Fitting again changes nothing; the same magnification set again keeps the mode.
        [view fitContentWidth]; settle(p.window);
        check(fabs(view.scaleFactor - scale) < 1e-6, @"fitting again keeps the magnification");
        view.scaleFactor = view.scaleFactor;
        check(view.resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH, @"the same magnification keeps Fit to Content Width");
        [p.window close];
    }

    // Going to a place near the left edge of the text, as the drawer, links, SyncTeX and Find
    // do: PDFKit would scroll sideways to put it at the left edge, and the margins would leave
    // the view. The content keeps its place sideways (#62).
    for (NSNumber *mode in @[@(kPDFDisplaySinglePageContinuous), @(kPDFDisplayTwoUpContinuous), @(kPDFDisplaySinglePage), @(kPDFDisplayTwoUp)]) {
        BOOL continuous = mode.integerValue == kPDFDisplaySinglePageContinuous || mode.integerValue == kPDFDisplayTwoUpContinuous;
        BOOL twoUp = mode.integerValue == kPDFDisplayTwoUpContinuous || mode.integerValue == kPDFDisplayTwoUp;
        PDFDocument *document = makeDocument(YES, NO);
        Preview p = makePreview(document, (PDFDisplayMode)mode.integerValue);
        MyPDFKitView *view = p.view;
        show(view, 2);
        fit(view); measureAll(view);
        PDFPage *target = [document pageAtIndex:FindPage];
        PDFSelection *word = [document findString:@"Target" withOptions:0].firstObject;
        check(word != nil && [word.pages containsObject:target], @"the word to find is on its page");
        NSArray *ways = @[@"destination", @"result", @"destination on the same page", @"result on the same page"];
        for (NSString *way in ways) {
            context = [NSString stringWithFormat:@"going to a place by %@, mode %ld", way, (long)mode.integerValue];
            if (![way hasSuffix:@"same page"]) { show(view, 2); fit(view); }
            NSClipView *clip = clipOf(view);
            CGFloat x = NSMinX(clip.bounds);
            NSPoint point = NSMakePoint(NSMinX(EvenBody) + 2, NSMaxY(EvenBody) - 100);
            if ([way hasPrefix:@"destination"])
                [view goToDestination:[[PDFDestination alloc] initWithPage:target atPoint:point]];
            else {
                // As SyncTeX and Find show their result. Scrolled sideways first: on macOS 27
                // the result alone scrolls only as far as needed, which from the place itself
                // would not move at all.
                // To the side where there is room.
                NSRect off = clip.bounds;
                off.origin.x += 24;
                if (NSMinX([clip constrainBoundsRect:off]) < x + 12) off.origin.x -= 48;
                [clip scrollToPoint:[clip constrainBoundsRect:off].origin];
                [clip.enclosingScrollView reflectScrolledClipView:clip];
                settle(p.window);
                check(fabs(NSMinX(clip.bounds) - x) > 12, @"scrolled sideways before the result is shown");
                view.currentSelection = word;
                [view scrollSelectionToVisible:nil];
                view.currentSelection = nil;
            }
            settle(p.window);
            check(TSContentMiddlePage(view) == target || [TSContentRow(view, TSContentMiddlePage(view)) containsObject:target] ||
                  [view.visiblePages containsObject:target], @"the page is shown");
            NSUInteger index = [document indexForPage:target];
            NSRect content = [view convertRect:inkOf(index, YES) fromPage:target];
            if (twoUp) content = NSUnionRect(content, [view convertRect:inkOf(index - 1, YES) fromPage:[document pageAtIndex:index - 1]]);
            NSRect area = [view convertRect:TSContentVisibleArea(view) fromView:clip];
            check(NSMinX(content) >= NSMinX(area) - 1.5 && NSMaxX(content) <= NSMaxX(area) + 1.5,
                  [NSString stringWithFormat:@"the content with its margins in view (%.1f to %.1f, view %.1f to %.1f)",
                   NSMinX(content), NSMaxX(content), NSMinX(area), NSMaxX(area)]);
            if (continuous)
                check(fabs(NSMinX(clip.bounds) - x) < 0.5, [NSString stringWithFormat:@"the same place sideways (%.1f, was %.1f)", NSMinX(clip.bounds), x]);
            check(view.resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH, @"the mode stays");
        }
        [p.window close];
    }

    // The text at the top of the view stays where it is when the mode is chosen, and when the
    // view gets narrower or wider, which fits the content to the new width.
    context = @"top and size";
    {
        PDFDocument *document = makeDocument(NO, NO);
        Preview p = makePreview(document, kPDFDisplaySinglePageContinuous);
        MyPDFKitView *view = p.view;
        show(view, 5);
        NSClipView *clip = clipOf(view);
        NSRect bounds = clip.bounds;
        bounds.origin.y += clip.isFlipped ? 180 : -180;
        [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin]; settle(p.window);
        PDFPage *page = [document pageAtIndex:5];
        NSPoint top = shown(view, page, .5, 0);
        fit(view); measureAll(view);
        check(fabs(shown(view, page, .5, 0).y - top.y) < 1.5,
              [NSString stringWithFormat:@"the text at the top stays (%.1f, was %.1f)", shown(view, page, .5, 0).y, top.y]);
        CGFloat left, right, scale = view.scaleFactor;
        edges(view, 5, &left, &right);
        check(left <= NSMinX(inkOf(4, NO)) + 1.5 && right >= NSMaxX(inkOf(5, NO)) - 1.5 && left > NSMinX(inkOf(4, NO)) - 1.5,
              @"odd and even pages fill the width");
        for (NSNumber *width in @[@420, @780]) {
            top = shown(view, page, .5, 0);
            [p.window setContentSize:NSMakeSize(width.doubleValue, 700)];
            [view setFrameSize:NSMakeSize(width.doubleValue, 700)]; settle(p.window);
            CGFloat ratio = view.scaleFactor / scale;
            check(fabs(ratio - width.doubleValue / 600) < 0.03,
                  [NSString stringWithFormat:@"%@ points wide: the magnification follows (%.3f)", width, ratio]);
            edges(view, 5, &left, &right);
            check(fabs(left - NSMinX(inkOf(4, NO))) < 1.5 && fabs(right - NSMaxX(inkOf(5, NO))) < 1.5,
                  [NSString stringWithFormat:@"%@ points wide: the content fills the width (%.1f to %.1f)", width, left, right]);
            check(fabs(shown(view, page, .5, 0).y - top.y) < 2 && view.resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH,
                  [NSString stringWithFormat:@"%@ points wide: the top stays (%.1f, was %.1f)", width, shown(view, page, .5, 0).y, top.y]);
        }
        // Zoom In and the like leave it.
        view.scaleFactor = view.scaleFactor * 1.1;
        check(view.resizeOption == NEW_PDF_FIT_TO_NONE, @"another magnification makes it fixed");
        [p.window close];
    }

    // One page at a time: the widest content of a page sets the magnification, and the content
    // of each page comes to the middle as the pages are turned.
    // One row at a time: the same with the content of both pages of a row.
    for (NSNumber *mode in @[@(kPDFDisplaySinglePage), @(kPDFDisplayTwoUp)]) for (int wide = 0; wide < 2; wide++) {
        BOOL twoUp = mode.integerValue == kPDFDisplayTwoUp;
        context = [NSString stringWithFormat:@"one %@ at a time%@", twoUp ? @"row" : @"page", wide ? @", with a wide page" : @""];
        PDFDocument *document = makeDocument(wide, NO);
        Preview p = makePreview(document, (PDFDisplayMode)mode.integerValue);
        MyPDFKitView *view = p.view;
        show(view, 2);
        fit(view); measureAll(view);
        NSRect visible = [view convertRect:TSContentVisibleArea(view) fromView:clipOf(view)];
        // The widest page or row, as it would be shown: all pages are the same size.
        CGFloat widest = 0;
        for (NSUInteger i = 0; i < Count; i += twoUp ? 2 : 1) {
            if (i == BlankPage) continue;
            NSRect rect = [view convertRect:inkOf(i, wide) fromPage:[document pageAtIndex:i]];
            if (twoUp && i + 1 != BlankPage) rect = NSUnionRect(rect, [view convertRect:inkOf(i + 1, wide) fromPage:[document pageAtIndex:i + 1]]);
            widest = MAX(widest, NSWidth(rect));
        }
        check(fabs(widest - NSWidth(visible)) < 1.5,
              [NSString stringWithFormat:@"the widest content %.1f fills the view %.1f", widest, NSWidth(visible)]);
        if (!twoUp && !wide)
            check(fabs(view.scaleFactor * NSWidth(inkOf(2, NO)) - NSWidth(visible)) < 1.5,
                  @"larger than with all pages one below the other: the text alone fills the width");
        CGFloat scale = view.scaleFactor;
        for (NSUInteger step = 0; step < (twoUp ? 7 : 13); step++) {
            [view goToNextPage:nil];
            settle(p.window);
            PDFPage *page = TSContentMiddlePage(view);
            NSUInteger index = [document indexForPage:page];
            NSRect content = [view convertRect:inkOf(index, wide) fromPage:page];
            if (index == BlankPage) continue;
            NSUInteger other = index % 2 ? index - 1 : index + 1;
            if (twoUp && other != BlankPage)
                content = NSUnionRect(content, [view convertRect:inkOf(other, wide) fromPage:[document pageAtIndex:other]]);
            NSRect area = [view convertRect:TSContentVisibleArea(view) fromView:clipOf(view)];
            // In the middle, or as near as the edge of the document allows, as with a row of
            // one page beside a blank one.
            NSClipView *clip = clipOf(view);
            NSRect further = clip.bounds;
            further.origin.x += NSMidX(content) < NSMidX(area) ? -1 : 1;
            BOOL atEdge = fabs(NSMinX([clip constrainBoundsRect:further]) - NSMinX(clip.bounds)) < 0.5;
            check((fabs(NSMidX(content) - NSMidX(area)) < 1.5 || atEdge) && NSMinX(content) >= NSMinX(area) - 1.5 && NSMaxX(content) <= NSMaxX(area) + 1.5,
                  [NSString stringWithFormat:@"page %lu: its content in the middle (%.1f, view %.1f)", (unsigned long)index, NSMidX(content), NSMidX(area)]);
            check(fabs(view.scaleFactor - scale) < 1e-6 && view.resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH,
                  @"turning the page keeps the magnification");
        }
        [p.window close];
    }

    // A new PDF, as after typesetting: one whose pages are all known already, as when the other
    // part of a split window showed it first, is fitted at once; another keeps the magnification
    // until its pages are measured, then is fitted.
    context = @"a new PDF";
    {
        PDFDocument *narrow = makeDocument(NO, NO), *wide = makeDocument(YES, NO), *again = makeDocument(NO, NO);
        Preview p = makePreview(narrow, kPDFDisplaySinglePageContinuous);
        MyPDFKitView *view = p.view;
        [view becomeReady];
        show(view, 3);
        fit(view); measureAll(view);
        CGFloat narrowScale = view.scaleFactor;
        check(TSContentWidthMeasureAll(wide, view.displayBox), @"the other PDF is measured before it is shown");
        view.document = wide;
        CGFloat wideScale = view.scaleFactor;
        check(view.resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH && wideScale < narrowScale - 0.01,
              [NSString stringWithFormat:@"a measured PDF is fitted at once (%.3f, was %.3f)", wideScale, narrowScale]);
        view.document = again;
        check(fabs(view.scaleFactor - wideScale) < 1e-6 && view.resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH,
              @"a PDF not measured yet keeps the magnification");
        measureAll(view);
        check(fabs(view.scaleFactor - narrowScale) < 0.005,
              [NSString stringWithFormat:@"and is fitted once measured (%.3f, expected %.3f)", view.scaleFactor, narrowScale]);
        [p.window close];
    }

    // Turned pages: the width as seen.
    context = @"turned pages";
    {
        PDFDocument *document = makeDocument(NO, NO);
        Preview p = makePreview(document, kPDFDisplaySinglePageContinuous);
        MyPDFKitView *view = p.view;
        fit(view); measureAll(view);
        for (NSUInteger i = 0; i < Count; i++) [document pageAtIndex:i].rotation = 90;
        [view layoutDocumentView];
        [view fitContentWidth]; settle(p.window);
        NSRect visible = [view convertRect:TSContentVisibleArea(view) fromView:clipOf(view)];
        // Across the screen, a page turned by 90 degrees shows its height.
        CGFloat seen = view.scaleFactor * NSHeight(NSUnionRect(inkOf(0, NO), inkOf(1, NO)));
        check(fabs(seen - NSWidth(visible)) < 1.5, [NSString stringWithFormat:@"turned content %.1f fills %.1f", seen, NSWidth(visible)]);
        [p.window close];
    }

    // Blank pages leave the magnification alone.
    context = @"blank document";
    {
        Preview p = makePreview(makeDocument(NO, YES), kPDFDisplaySinglePageContinuous);
        p.view.autoScales = NO; p.view.scaleFactor = 0.7;
        fit(p.view); measureAll(p.view);
        check(fabs(p.view.scaleFactor - 0.7) < 1e-6, @"no change");
        [p.window close];
    }
    // #53: in a window whose content runs under the toolbar, going to a page or to a place a few
    // points from what is shown, right after a change of the size in the same turn of the event
    // loop, stays there once the views are laid out (goToPage:, goToDestination:).
    if (@available(macOS 26.0, *)) for (int toPage = 0; toPage < 2; toPage++) for (NSNumber *apart in @[@8, @24]) {
        context = [NSString stringWithFormat:@"#53 %s, %@pt apart", toPage ? "goToPage:" : "goToDestination:", apart];
        Preview p = makeFullSizePreview(makeDocument(NO, NO));
        PDFPage *page = [p.view.document pageAtIndex:4];
        CGFloat top = NSMaxY([page boundsForBox:p.view.displayBox]);
        CGFloat targetY = toPage ? top : top - 200;
        [p.view goToDestination:[[PDFDestination alloc] initWithPage:page atPoint:NSMakePoint(100, targetY - apart.doubleValue)]];
        settle(p.window);
        [p.view setFrameSize:NSMakeSize(450, 700)];
        if (toPage) [p.view goToPage:page];
        else [p.view goToDestination:[[PDFDestination alloc] initWithPage:page atPoint:NSMakePoint(100, targetY)]];
        CGFloat atOnce = belowEdge(p.view, page, NSMakePoint(100, targetY));
        settle(p.window);
        CGFloat settled = belowEdge(p.view, page, NSMakePoint(100, targetY));
        check(fabs(settled - atOnce) < 0.6, [NSString stringWithFormat:@"the place gone to stays (%.2f, then %.2f below the top edge)", atOnce, settled]);
        [p.window close];
    }
    // One page at a time, before every page is stored: the current page must not move sideways.
    context = @"unfinished single page";
    {
        PDFDocument *document = makeDocument(NO, NO);
        Preview p = makePreview(document, kPDFDisplaySinglePage);
        MyPDFKitView *view = p.view;
        view.autoScales = NO;
        view.scaleFactor = 2;
        show(view, 0);
        TSContentWidthStoreRaw(document, view.displayBox, [document pageAtIndex:0], NSUnionRect(OddBody, Number));
        NSClipView *clip = clipOf(view);
        NSRect bounds = clip.bounds;
        bounds.origin.x = 50;
        [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
        [clip.enclosingScrollView reflectScrolledClipView:clip];
        settle(p.window);
        CGFloat x = NSMinX(clip.bounds);
        check(!TSContentWidthIsComplete(document, view.displayBox) && fabs(x - 50) < 1, @"one stored page, scrolled sideways");
        TSContentPlaceSideways(view);
        settle(p.window);
        check(fabs(NSMinX(clip.bounds) - x) < 0.5 && fabs(view.scaleFactor - 2) < 1e-6,
              @"an unfinished document does not move sideways");
        view.resizeOption = NEW_PDF_FIT_TO_CONTENT_WIDTH;
        [view centreContentRowLater];
        settle(p.window);
        check(fabs(NSMinX(clip.bounds) - x) < 0.5 && fabs(view.scaleFactor - 2) < 1e-6,
              @"a page change of an unfinished document does not move it");
        [p.window close];
    }
    context = @"unfinished two-up";
    {
        PDFDocument *document = makeDocument(NO, NO);
        Preview p = makePreview(document, kPDFDisplayTwoUp);
        MyPDFKitView *view = p.view;
        view.autoScales = NO;
        view.scaleFactor = 2;
        show(view, 0);
        TSContentWidthStoreRaw(document, view.displayBox, [document pageAtIndex:0], NSUnionRect(OddBody, Number));
        NSClipView *clip = clipOf(view);
        NSRect bounds = clip.bounds;
        bounds.origin.x = 50;
        [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
        [clip.enclosingScrollView reflectScrolledClipView:clip];
        settle(p.window);
        CGFloat x = NSMinX(clip.bounds);
        check(!TSContentWidthIsComplete(document, view.displayBox) && fabs(x - 50) < 1, @"one stored page of a two-up row, scrolled sideways");
        TSContentPlaceSideways(view);
        settle(p.window);
        check(fabs(NSMinX(clip.bounds) - x) < 0.5 && fabs(view.scaleFactor - 2) < 1e-6,
              @"an unfinished two-up document does not move sideways");
        view.resizeOption = NEW_PDF_FIT_TO_CONTENT_WIDTH;
        [view centreContentRowLater];
        settle(p.window);
        check(fabs(NSMinX(clip.bounds) - x) < 0.5 && fabs(view.scaleFactor - 2) < 1e-6,
              @"a page change of an unfinished two-up document does not move it");
        [p.window close];
    }

    // The dead band is one screen point on an edge, not one clip-view unit and not the width.
    context = @"screen point threshold";
    {
        PDFDocument *document = makeDocument(NO, NO);
        Preview p = makePreview(document, kPDFDisplaySinglePageContinuous);
        MyPDFKitView *view = p.view;
        show(view, 2);
        fit(view); measureAll(view);
        check(!TSContentWidthShouldRefit(view), @"a view that already fits does not refit");
        NSClipView *clip = clipOf(view);
        CGFloat toScreen = NSWidth(clip.frame) / NSWidth(clip.bounds);
        NSRect atRest = contentClip(view);
        nudgeInk(view, 1, 0, 0);
        CGFloat perPage = NSMinX(contentClip(view)) - NSMinX(atRest);
        nudgeInk(view, -1, 0, 0);
        check(fabs(perPage) > 0.01 && !TSContentWidthShouldRefit(view), @"a page unit of ink can be put back");
        CGFloat over = 1.3 / toScreen / perPage;
        nudgeInk(view, over, 0, 0);
        check(TSContentWidthShouldRefit(view), @"more than one screen point refits");
        nudgeInk(view, -over, 0, 0);
        CGFloat under = 0.6 / toScreen / fabs(perPage);
        nudgeInk(view, 0, under, under);
        check(!TSContentWidthShouldRefit(view), @"each edge under one screen point does not refit");
        nudgeInk(view, 0, -under, -under);
        nudgeInk(view, 0, 0, 1.3 / toScreen / fabs(perPage));
        check(TSContentWidthShouldRefit(view), @"one edge past one screen point refits");
        [p.window close];
    }

    // The page in view is blank. Other pages have ink, so finishing the measurement sets the
    // magnification. A document that is blank throughout still does not.
    context = @"blank row still sets the magnification";
    {
        PDFDocument *document = makeDocument(NO, NO);
        Preview p = makePreview(document, kPDFDisplaySinglePage);
        MyPDFKitView *view = p.view;
        view.autoScales = NO;
        view.scaleFactor = 0.7;
        show(view, BlankPage);
        fit(view); measureAll(view);
        CGFloat fitted = view.scaleFactor;
        check(fitted > 1.0, [NSString stringWithFormat:@"a blank page still sets the magnification (%.3f)", fitted]);
        show(view, 2);
        NSRect content = [view convertRect:inkOf(2, NO) fromPage:[document pageAtIndex:2]];
        NSRect area = [view convertRect:TSContentVisibleArea(view) fromView:clipOf(view)];
        check(fabs(view.scaleFactor - fitted) < 1e-4 && fabs(NSMidX(content) - NSMidX(area)) < 2,
              @"the next page keeps that magnification and is centred");
        [p.window close];
    }

    // A link with a border is in the file before it is opened. The workers reject it,
    // and the view measures that page with PDFKit and fits once.
    context = @"bordered link";
    {
        // The link's /Border is in the file before the document opens. The workers
        // reject that border, and the view then measures the page with PDFKit.
        NSString *pdf =
            @"%PDF-1.4\n"
            "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
            "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
            "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 4 0 R /Resources << >> /Annots [5 0 R] >>\nendobj\n"
            "4 0 obj\n<< /Length 21 >>\nstream\n0 g\n30 20 40 30 re f\nendstream\nendobj\n"
            "5 0 obj\n<< /Type /Annot /Subtype /Link /Rect [1 1 12 12] /Border [0 0 1] >>\nendobj\n"
            "xref\n0 6\n"
            "0000000000 65535 f \n"
            "0000000009 00000 n \n"
            "0000000058 00000 n \n"
            "0000000115 00000 n \n"
            "0000000235 00000 n \n"
            "0000000305 00000 n \n"
            "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n388\n%%EOF\n";
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
        NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"snapshot.pdf"]];
        check([[pdf dataUsingEncoding:NSASCIIStringEncoding] writeToURL:url atomically:YES], @"the bordered link is written before it is opened");
        TSExternalPDFDocument *document = [[TSExternalPDFDocument alloc] initWithURL:url];
        document.snapshotDirectory = directory;
        Preview p = makePreview(document, kPDFDisplaySinglePageContinuous);
        MyPDFKitView *view = p.view;
        view.autoScales = NO;
        view.scaleFactor = 1;
        view.resizeOption = NEW_PDF_FIT_TO_CONTENT_WIDTH;
        [view measureContentLater];
        for (int i = 0; i < 500 && !TSContentWidthIsComplete(document, view.displayBox); i++)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        check(TSContentWidthIsComplete(document, view.displayBox) && view.scaleFactor > 2,
              [NSString stringWithFormat:@"a bordered link is measured with PDFKit and fitted (%.3f)", view.scaleFactor]);
        [p.window close];
    }

    context = @"";
    printf("PASS: %lu checks\n", (unsigned long)checks);
    return 0;
}}
'''
program = program.replace('ZOOMHEADER', zoom_text).replace('VIEWMETHODS', view_text)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    (temp / 'test.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'Quartz', '-framework', 'PDFKit',
                    '-I', str(root / 'Tests'), *include_args(root), str(temp / 'test.m'),
                    str(root / 'Sources/Preview/TSContentWidth.m'), str(root / 'Sources/Preview/TSExternalPDFSnapshot.m'),
                    str(root / 'Sources/Preview/TSPreviewScrollerKeeper.m'), '-o', str(temp / 'test')], check=True)
    result = subprocess.run([str(temp / 'test')], capture_output=True, text=True, timeout=600)
    output = result.stdout + result.stderr
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.strip().splitlines()[-1])
    else:
        print(output.strip())
        sys.exit(result.returncode)
