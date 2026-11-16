#!/usr/bin/env python3
"""Fit to Content Width (#33), a magnification of the Preview window, with the production code
in windows that are never shown.

With pages one below the other, the content of all pages sets the magnification and the place
sideways, which stay as the pages scroll by; pages not measured yet are measured a few at a time
and the content is fitted again once all are known. One page or one row at a time, the widest
content of a page or row sets the magnification and the content of each page or row comes to
the middle when it is shown. The text at the top of the view stays; a narrower or wider view
fits again; the same magnification set again keeps the mode, any other leaves it."""
from pathlib import Path
import argparse, subprocess, sys, tempfile
from source_tree import include_args
from production_fragments import method, verify_embedded

MUTATIONS = {
    # TSContentZoom.h
    'in-view-pages-only': ('zoom', '            if ([store objectForKey:page] || [current containsObject:page]) [pages addObject:page];',
                           '            if ([current containsObject:page]) [pages addObject:page];'),
    'top-not-kept': ('zoom', '    top.page = topPage;\n    TSContentRestoreTop(view, top);', '    top.page = topPage;'),
    'not-centred-sideways': ('zoom', '        if (!NSIsEmptyRect(all)) TSContentScrollTo(view, all, NO, NO);', ''),
    'first-group-only': ('zoom', '        for (NSArray<PDFPage *> *group in groups) width = MAX(width, NSWidth(TSContentRectInView(view, group)));',
                         '        width = NSWidth(TSContentRectInView(view, groups.firstObject));'),
    'one-row-of-all': ('zoom', '    if (TSContentContinuous(view)) {\n        NSMutableArray *all', '    if (YES) {\n        NSMutableArray *all'),
    # MyPDFKitView.m
    'not-measured': ('view', '    else if (TSContentMeasurePages(document, self.displayBox, 0.008))\n        [self fitContentWidth];',
                     '    else if (YES)\n        [self fitContentWidth];'),
    'no-refit-on-resize': ('view', '    if (refit) {\n        top.page = topPage;', '    if (NO) {\n        top.page = topPage;'),
    'top-after-resize': ('view', '    TSContentTop top = refit ? TSContentTopOf(self) : (TSContentTop){nil, NSZeroPoint};',
                         '    TSContentTop top = {nil, NSZeroPoint};'),
    'same-scale-leaves': ('view', '        (resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH && fabs(scale - self.scaleFactor) < 1e-6);', '        NO;'),
    'page-not-centred': ('view', '            TSContentCentreRow(view);\n    });', '            ;\n    });'),
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
    '- (void)measureContentLater', '- (void)measureContentOf:(PDFDocument *)document', '- (void)centreContentRowLater',
    '- (void)setFrameSize:(NSSize)newSize')]
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
@interface MyPDFKitView : PDFView {
    BOOL _fittingContentWidth, _measuringContent;
    NSInteger resizeOption;
}
@property NSInteger scaleUpdates;
- (void)fitContentWidth;
- (void)centreContentRowLater;
@end
@implementation MyPDFKitView
- (NSInteger)resizeOption { return resizeOption; }
- (void)setResizeOption:(NSInteger)option { resizeOption = option; }
- (BOOL)measuring { return _measuringContent; }
- (void)scaleChanged:(NSNotification *)notification { self.scaleUpdates++; }
- (void)keepPinnedLinkPreviewInView {}
VIEWMETHODS
@end

// A4 pages printed on both sides, as with the book class: the text further right on every
// other page, a page number at the foot. Page 13 has a figure wider than the text; page 16 is blank.
static const NSRect OddBody = {{107, 150}, {343, 600}}, EvenBody = {{161, 150}, {343, 600}}, Number = {{290, 40}, {15, 12}};
static const NSRect Wide = {{60, 400}, {480, 100}};
static const NSUInteger Count = 16, WidePage = 12, BlankPage = 15;
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
// Lets the pages be measured, a few at a time.
static void measureAll(MyPDFKitView *view) {
    for (int i = 0; i < 300 && ([view measuring] || !TSContentAllMeasured(view.document, view.displayBox)); i++)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    settle(view.window);
    check(TSContentAllMeasured(view.document, view.displayBox) && ![view measuring], @"all pages measured");
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
        view.resizeOption = NEW_PDF_FIT_TO_CONTENT_WIDTH;
        [view fitContentWidth];
        // Right away, the page in view and the next one give the width.
        CGFloat firstScale = view.scaleFactor;
        check(view.resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH && !view.autoScales && [view measuring], @"the mode is set, the rest is being measured");
        measureAll(view);
        CGFloat scale = view.scaleFactor, left, right;
        check(scale < firstScale - 0.01, [NSString stringWithFormat:@"the wide page, measured later, makes it smaller (%.3f, then %.3f)", firstScale, scale]);
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
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    '-I', str(root / 'Tests'), *include_args(root), str(temp / 'test.m'),
                    str(root / 'Sources/Preview/TSPreviewScrollerKeeper.m'), '-o', str(temp / 'test')], check=True)
    result = subprocess.run([str(temp / 'test')], capture_output=True, text=True, timeout=600)
    output = result.stdout + result.stderr
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.strip().splitlines()[-1])
    else:
        print(output.strip())
        sys.exit(result.returncode)
