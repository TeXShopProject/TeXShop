#pragma once
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import <objc/runtime.h>
#import "TSContentWidth.h"

// Zoom to Content and Zoom to Content Width, in the Preview window and the Experiment preview,
// and Fit to Content Width, a magnification of the Preview window that follows the window.
// The content is the non-blank part of a page. Its edges are those seen on screen: the
// rotation of the page is applied, so the top of a page turned by 90 degrees is a side of the
// page in PDF space.
//
// The zooms take the page in the middle of the view. In two-page layouts the page beside it in
// its row is taken too. With one page across, the page after it (or, at the end, the page
// before it) gives the width as well: pages printed on both sides often have their text further
// left or right on every other page, and the next page should not lose its line ends.
// Fit to Content Width takes the content of all pages, measured away from the main
// thread when the document allows it and a few at a time otherwise, then fitted once.

// Margin around the content, in page units.
static const CGFloat TSContentZoomMargin = 8;

// The non-blank part of a page, in page coordinates; empty for a blank page. The page is drawn
// at up to resolutionLimit pixels per page unit.
static inline NSRect TSContentInkBoundsAt(PDFPage *page, PDFDisplayBox box, CGFloat resolutionLimit)
{
    if (!page) return NSZeroRect;
    NSRect bounds = [page boundsForBox:box];
    if (NSIsEmptyRect(bounds)) return NSZeroRect;
    // drawWithBox:toContext: draws the page as a preview shows it: the box origin at zero and
    // the rotation applied. transformForBox: takes page coordinates there.
    CGAffineTransform toDrawn = [page transformForBox:box];
    CGRect drawn = CGRectStandardize(CGRectApplyAffineTransform(NSRectToCGRect(bounds), toDrawn));
    if (CGRectIsEmpty(drawn)) return NSZeroRect;
    CGFloat resolution = MIN(resolutionLimit, 4000.0 / MAX(CGRectGetWidth(drawn), CGRectGetHeight(drawn)));
    size_t width = MAX(1, (size_t)ceil(CGRectGetWidth(drawn) * resolution));
    size_t height = MAX(1, (size_t)ceil(CGRectGetHeight(drawn) * resolution));
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, gray, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!context) return NSZeroRect;
    CGContextSetGrayFillColor(context, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGContextScaleCTM(context, resolution, resolution);
    CGContextTranslateCTM(context, -CGRectGetMinX(drawn), -CGRectGetMinY(drawn));
    [page drawWithBox:box toContext:context];
    const uint8_t *pixels = CGBitmapContextGetData(context);
    size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);
    NSInteger minX = width, minY = height, maxX = -1, maxY = -1;
    for (size_t row = 0; row < height; row++)
        for (size_t column = 0; column < width; column++)
            if (pixels[row * bytesPerRow + column] < 240) {
                minX = MIN(minX, (NSInteger)column); maxX = MAX(maxX, (NSInteger)column);
                minY = MIN(minY, (NSInteger)row); maxY = MAX(maxY, (NSInteger)row);
            }
    CGContextRelease(context);
    if (maxX < 0) return NSZeroRect;
    // Row 0 of the bitmap is the top of the page as shown.
    CGRect ink = CGRectMake(CGRectGetMinX(drawn) + minX / resolution, CGRectGetMinY(drawn) + (height - 1 - maxY) / resolution,
                            (maxX - minX + 1) / resolution, (maxY - minY + 1) / resolution);
    return NSRectFromCGRect(CGRectStandardize(CGRectApplyAffineTransform(ink, CGAffineTransformInvert(toDrawn))));
}

static inline NSRect TSContentInkBounds(PDFPage *page, PDFDisplayBox box)
{
    return TSContentInkBoundsAt(page, box, 2.0);
}

// The content of the pages of a document, remembered with the document for each display box:
// a typeset makes a new document. Being in page coordinates, it holds for any rotation.
static char TSContentInkStoreKey;

static inline NSMapTable<PDFPage *, NSValue *> *TSContentInkStore(PDFDocument *document, PDFDisplayBox box)
{
    if (!document) return nil;
    NSMutableDictionary *stores = objc_getAssociatedObject(document, &TSContentInkStoreKey);
    if (!stores) {
        stores = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(document, &TSContentInkStoreKey, stores, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSMapTable *store = stores[@(box)];
    if (!store) {
        store = [NSMapTable weakToStrongObjectsMapTable];
        stores[@(box)] = store;
    }
    return store;
}

// The content of a page with the margin around it, within the page; empty for a blank page.
// It is measured now if it is not known yet.
static inline NSRect TSContentPageContent(PDFPage *page, PDFDisplayBox box)
{
    NSMapTable *store = TSContentInkStore(page.document, box);
    NSValue *known = [store objectForKey:page];
    if (known) return known.rectValue;
    NSRect ink = TSContentInkBounds(page, box);
    if (!NSIsEmptyRect(ink))
        ink = NSIntersectionRect(NSInsetRect(ink, -TSContentZoomMargin, -TSContentZoomMargin), [page boundsForBox:box]);
    if (store) [store setObject:[NSValue valueWithRect:ink] forKey:page];
    return ink;
}

// Measures pages of the document that are not known yet, until the time is up. YES once every
// page is known.
static inline BOOL TSContentMeasurePages(PDFDocument *document, PDFDisplayBox box, NSTimeInterval seconds)
{
    NSMapTable *store = TSContentInkStore(document, box);
    if (!store) return YES;
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    NSUInteger count = document.pageCount;
    for (NSUInteger i = 0; i < count; i++) {
        PDFPage *page = [document pageAtIndex:i];
        if (!page || [store objectForKey:page]) continue;
        if (end.timeIntervalSinceNow < 0) return NO;
        // The width is all that counts here: a pixel per page unit is enough.
        NSRect ink = TSContentInkBoundsAt(page, box, 1.0);
        if (!NSIsEmptyRect(ink))
            ink = NSIntersectionRect(NSInsetRect(ink, -TSContentZoomMargin, -TSContentZoomMargin), [page boundsForBox:box]);
        [store setObject:[NSValue valueWithRect:ink] forKey:page];
    }
    return YES;
}

// Every page, into the resolution-1.0 store, on the caller's thread. A blank page stores an
// empty rect. Tests use this; the preview measures in slices or on the background workers.
static inline BOOL TSContentWidthMeasureAll(PDFDocument *document, PDFDisplayBox box)
{
    if (!document || document.isLocked || document.pageCount == 0) return NO;
    for (NSUInteger index = 0; index < document.pageCount; index++) {
        PDFPage *page = [document pageAtIndex:index];
        if (!page) return NO;
        TSContentWidthStoreRaw(document, box, page, TSContentInkBoundsAt(page, box, 1.0));
    }
    return YES;
}

static inline BOOL TSContentAllMeasured(PDFDocument *document, PDFDisplayBox box)
{
    NSMapTable *store = TSContentInkStore(document, box);
    if (!store) return YES;
    for (NSUInteger i = 0; i < document.pageCount; i++) {
        PDFPage *page = [document pageAtIndex:i];
        if (page && ![store objectForKey:page]) return NO;
    }
    return YES;
}

// The part of the view that is not under a toolbar or title bar, in clip view (document) units.
static inline NSRect TSContentVisibleArea(PDFView *view)
{
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    NSRect area = clip.bounds;
    if (!clip || NSHeight(clip.frame) <= 0) return area;
    CGFloat unit = NSHeight(area) / NSHeight(clip.frame);
    NSEdgeInsets insets = scroll.contentInsets;
    area.origin.x += insets.left * unit;
    area.size.width -= (insets.left + insets.right) * unit;
    // Above unit scale the top inset is already in clip bounds. At unit scale and
    // below it is in screen points, like the bottom inset.
    CGFloat magnification = scroll.magnification;
    if (!isfinite(magnification) || magnification <= 0) magnification = 1;
    CGFloat top = magnification > 1 ? insets.top : insets.top * unit;
    CGFloat bottom = insets.bottom * unit;
    area.origin.y += clip.isFlipped ? top : bottom;
    area.size.height -= top + bottom;
    return area;
}

// The size of that part in points on screen.
static inline NSSize TSContentVisibleSize(PDFView *view)
{
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!clip) return NSZeroSize;
    NSEdgeInsets insets = scroll.contentInsets;
    CGFloat magnification = scroll.magnification;
    if (!isfinite(magnification) || magnification <= 0)
        magnification = NSHeight(clip.bounds) > 0 ? NSHeight(clip.frame) / NSHeight(clip.bounds) : 1;
    CGFloat top = magnification > 1 ? insets.top * magnification : insets.top;
    return NSMakeSize(NSWidth(clip.frame) - insets.left - insets.right,
                       NSHeight(clip.frame) - top - insets.bottom);
}

static inline BOOL TSContentTwoUp(PDFView *view)
{
    return view.displayMode == kPDFDisplayTwoUp || view.displayMode == kPDFDisplayTwoUpContinuous;
}

static inline BOOL TSContentContinuous(PDFView *view)
{
    return view.displayMode == kPDFDisplaySinglePageContinuous || view.displayMode == kPDFDisplayTwoUpContinuous;
}

// The page in the middle of the view.
static inline PDFPage *TSContentMiddlePage(PDFView *view)
{
    NSClipView *clip = view.documentView.enclosingScrollView.contentView;
    if (!view.document.pageCount || !clip) return nil;
    NSRect area = TSContentVisibleArea(view);
    NSPoint middle = [view convertPoint:NSMakePoint(NSMidX(area), NSMidY(area)) fromView:clip];
    PDFPage *page = [view pageForPoint:middle nearest:YES];
    // One page or one row at a time: PDFKit also places pages of other rows there.
    NSArray<PDFPage *> *shown = view.visiblePages;
    if (page && shown.count && ![shown containsObject:page]) page = view.currentPage;
    return page;
}

// The pages of the row of a page: in two-page layouts, the page and the one beside it.
// Pages pair from the first one, or from the second one when the first is shown alone as a
// cover. The direction only swaps their sides.
static inline NSArray<PDFPage *> *TSContentRow(PDFView *view, PDFPage *page)
{
    if (!page) return @[];
    NSMutableArray<PDFPage *> *pages = [NSMutableArray arrayWithObject:page];
    if (TSContentTwoUp(view)) {
        NSInteger index = (NSInteger)[view.document indexForPage:page];
        NSInteger first = view.displaysAsBook ? 1 : 0;
        NSInteger other = index < first ? -1 : ((index - first) % 2 == 0 ? index + 1 : index - 1);
        if (other >= 0 && other < (NSInteger)view.document.pageCount) {
            // Also when it is out of sight at a high magnification.
            PDFPage *beside = [view.document pageAtIndex:other];
            if (beside) [pages addObject:beside];
        }
    }
    return pages;
}

// The pages whose content sets the width for a page: its row, and with one page across, the
// next page too (or the one before the last page).
static inline NSArray<PDFPage *> *TSContentAcross(PDFView *view, PDFPage *page)
{
    NSArray<PDFPage *> *row = TSContentRow(view, page);
    if (TSContentTwoUp(view) || !page) return row;
    NSInteger index = (NSInteger)[view.document indexForPage:page], count = (NSInteger)view.document.pageCount;
    NSInteger other = index + 1 < count ? index + 1 : index - 1;
    PDFPage *next = other >= 0 && other != index ? [view.document pageAtIndex:other] : nil;
    return next ? [row arrayByAddingObject:next] : row;
}

// The content of pages in view coordinates at the present magnification. One page or one row
// at a time, PDFKit places the pages that are not shown where the page or the row in view is.
static inline NSRect TSContentRectInView(PDFView *view, NSArray<PDFPage *> *pages)
{
    NSRect content = NSZeroRect;
    PDFDisplayBox box = view.displayBox;
    for (PDFPage *page in pages) {
        NSRect ink = TSContentPageContent(page, box);
        if (NSIsEmptyRect(ink)) continue;
        NSRect rect = [view convertRect:ink fromPage:page];
        content = NSIsEmptyRect(content) ? rect : NSUnionRect(content, rect);
    }
    return content;
}

// Kept for the tests of the earlier zoom: the pages of the row of the page in the middle, each
// with its content (keys "page" and "rect"); empty when they are blank.
static inline NSArray<NSDictionary *> *TSContentZoomParts(PDFView *view)
{
    NSMutableArray *parts = [NSMutableArray array];
    for (PDFPage *page in TSContentRow(view, TSContentMiddlePage(view))) {
        NSRect ink = TSContentPageContent(page, view.displayBox);
        if (!NSIsEmptyRect(ink)) [parts addObject:@{@"page": page, @"rect": [NSValue valueWithRect:ink]}];
    }
    return parts;
}

// Sets the magnification that makes a width of content, measured at the present magnification
// by contentWidth, fill the visible width (and, with contentHeight, a height fit the visible
// height), measuring again until it settles: the gap between the pages of a row does not grow
// with the pages, and a scroller that appears narrows the view. NO when there is no content.
static inline BOOL TSContentSettleScale(PDFView *view, CGFloat (^contentWidth)(void), CGFloat (^contentHeight)(void),
                                        CGFloat (^setScale)(CGFloat scale))
{
    for (int pass = 0; pass < 4; pass++) {
        CGFloat width = contentWidth(), height = contentHeight ? contentHeight() : 0;
        NSSize visible = TSContentVisibleSize(view);
        CGFloat current = view.scaleFactor;
        if (width <= 0 || visible.width <= 0 || visible.height <= 0 || current <= 0 || (contentHeight && height <= 0)) return pass > 0;
        CGFloat scale = visible.width / (width / current);
        if (contentHeight) scale = MIN(scale, visible.height / (height / current));
        CGFloat set = setScale(scale);
        [view layoutDocumentView];
        [view layoutSubtreeIfNeeded];
        if (fabs(set - current) < 1e-6) break;
    }
    return YES;
}

// Scrolls sideways so that a rect of the view is in the middle of the visible area, and, with
// a top, down so that the top is at the top of that area.
static inline void TSContentScrollTo(PDFView *view, NSRect rect, BOOL toTop, BOOL centreDown)
{
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!clip || NSIsEmptyRect(rect)) return;
    NSRect content = [view.documentView convertRect:rect fromView:view];
    NSRect area = TSContentVisibleArea(view), target = clip.bounds;
    target.origin.x += NSMidX(content) - NSMidX(area);
    if (centreDown)
        target.origin.y += NSMidY(content) - NSMidY(area);
    else if (toTop && clip.isFlipped)
        target.origin.y += NSMinY(content) - NSMinY(area);
    else if (toTop)
        target.origin.y += NSMaxY(content) - NSMaxY(area);
    target = [clip constrainBoundsRect:target];
    if (NSEqualPoints(target.origin, clip.bounds.origin)) return;
    [clip scrollToPoint:target.origin];
    [scroll reflectScrolledClipView:clip];
}

// Zoom to Content Width enlarges or reduces the content to the width of the view and shows its
// top at the top of the view; Zoom to Content fits the whole content of the page or row in
// the view and centres it. setScale sets a magnification between the limits and returns the
// one it set; NO if the page or row is blank.
static inline BOOL TSContentZoom(PDFView *view, BOOL widthOnly, CGFloat (^setScale)(CGFloat scale))
{
    PDFPage *page = TSContentMiddlePage(view);
    NSArray<PDFPage *> *row = TSContentRow(view, page), *across = TSContentAcross(view, page);
    if (NSIsEmptyRect(TSContentRectInView(view, row))) return NO;
    BOOL zoomed = TSContentSettleScale(view, ^CGFloat{ return NSWidth(TSContentRectInView(view, across)); },
                                       widthOnly ? nil : ^CGFloat{ return NSHeight(TSContentRectInView(view, row)); }, setScale);
    if (!zoomed) return NO;
    // Sideways by the pages that set the width; down by the page or row itself.
    NSRect wide = TSContentRectInView(view, across), shown = TSContentRectInView(view, row);
    NSRect target = NSMakeRect(NSMinX(wide), NSMinY(shown), NSWidth(wide), NSHeight(shown));
    TSContentScrollTo(view, target, widthOnly, !widthOnly);
    return YES;
}

// Fit to Content Width.
//
// With pages one below the other, the content of all pages sets the magnification and the
// place sideways, which then stay as the pages scroll by. One page or one row at a time, the
// widest content of a page or row sets the magnification, and the content of the page or row
// in view is put in the middle; TSContentCentreRow does that again when another page comes.

// The pages of the document grouped as they are shown side by side: one group with pages one
// below the other, otherwise each page or row.
static inline NSArray<NSArray<PDFPage *> *> *TSContentGroups(PDFView *view)
{
    PDFDocument *document = view.document;
    NSUInteger count = document.pageCount;
    if (!count) return @[];
    if (TSContentContinuous(view)) {
        NSMutableArray *all = [NSMutableArray arrayWithCapacity:count];
        for (NSUInteger i = 0; i < count; i++) {
            PDFPage *page = [document pageAtIndex:i];
            if (page) [all addObject:page];
        }
        return @[all];
    }
    NSMutableArray *groups = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSUInteger i = 0; i < count; i++) {
        PDFPage *page = [document pageAtIndex:i];
        if (!page || [seen containsObject:page]) continue;
        NSArray *row = TSContentRow(view, page);
        [seen addObjectsFromArray:row];
        [groups addObject:row];
    }
    return groups;
}

// The resolution-1.0 content of pages, with the margin, in view coordinates. Pages that are
// not in that store are left out. Zoom to Content keeps using TSContentRectInView.
static inline NSRect TSContentFitRectInView(PDFView *view, NSArray<PDFPage *> *pages)
{
    NSRect content = NSZeroRect;
    PDFDisplayBox box = view.displayBox;
    for (PDFPage *page in pages) {
        BOOL known = NO;
        NSRect ink = TSContentWidthRawInk(view.document, box, page, &known);
        if (!known || NSIsEmptyRect(ink)) continue;
        ink = NSIntersectionRect(NSInsetRect(ink, -TSContentZoomMargin, -TSContentZoomMargin), [page boundsForBox:box]);
        if (NSIsEmptyRect(ink)) continue;
        NSRect rect = [view convertRect:ink fromPage:page];
        content = NSIsEmptyRect(content) ? rect : NSUnionRect(content, rect);
    }
    return content;
}

static inline NSRect TSContentRawRectInView(PDFView *view, NSArray<PDFPage *> *pages)
{
    NSRect content = NSZeroRect;
    PDFDisplayBox box = view.displayBox;
    for (PDFPage *page in pages) {
        BOOL known = NO;
        NSRect ink = TSContentWidthRawInk(view.document, box, page, &known);
        if (!known || NSIsEmptyRect(ink)) continue;
        NSRect rect = [view convertRect:ink fromPage:page];
        content = NSIsEmptyRect(content) ? rect : NSUnionRect(content, rect);
    }
    return content;
}

// No group until every page is in the resolution-1.0 store. A partial union moves the
// left and right edges more than once (#62).
static inline NSArray<NSArray<PDFPage *> *> *TSContentKnownGroups(PDFView *view)
{
    if (!TSContentWidthIsComplete(view.document, view.displayBox)) return @[];
    return TSContentGroups(view);
}

// Puts the content of the page or row in view in the middle, sideways (one page or one row at
// a time). An unfinished store does not move the view: the current row can be known while
// later pages are not (#62).
static inline void TSContentCentreRow(PDFView *view)
{
    if (TSContentContinuous(view) || !TSContentWidthIsComplete(view.document, view.displayBox)) return;
    NSRect shown = TSContentFitRectInView(view, TSContentRow(view, TSContentMiddlePage(view)));
    if (NSIsEmptyRect(shown)) return;
    TSContentScrollTo(view, shown, NO, NO);
}

// The point at the top edge of the visible area, as a point on a page.
typedef struct { __unsafe_unretained PDFPage *page; NSPoint point; } TSContentTop;

static inline TSContentTop TSContentTopOf(PDFView *view)
{
    TSContentTop top = {nil, NSZeroPoint};
    NSClipView *clip = view.documentView.enclosingScrollView.contentView;
    if (!clip || NSIsEmptyRect(clip.bounds)) return top;
    NSRect area = TSContentVisibleArea(view);
    NSPoint edge = [view convertPoint:NSMakePoint(NSMidX(area), clip.isFlipped ? NSMinY(area) : NSMaxY(area)) fromView:clip];
    PDFPage *page = [view pageForPoint:edge nearest:YES];
    if (!page) return top;
    top.page = page;
    top.point = [view convertPoint:edge toPage:page];
    return top;
}

// Scrolls down or up so that the point is at the top edge of the visible area again.
static inline void TSContentRestoreTop(PDFView *view, TSContentTop top)
{
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!top.page || !clip || top.page.document != view.document) return;
    NSPoint point = [clip convertPoint:[view convertPoint:top.point fromPage:top.page] fromView:view];
    NSRect area = TSContentVisibleArea(view), target = clip.bounds;
    target.origin.y += point.y - (clip.isFlipped ? NSMinY(area) : NSMaxY(area));
    target = [clip constrainBoundsRect:target];
    if (NSEqualPoints(target.origin, clip.bounds.origin)) return;
    [clip scrollToPoint:target.origin];
    [scroll reflectScrolledClipView:clip];
}

// The place sideways of Fit to Content Width: with pages one below the other, the content of
// the pages known (the first of the groups) in the middle; otherwise that of the page or row in
// view.
static inline void TSContentPlaceSidewaysIn(PDFView *view, NSArray<NSArray<PDFPage *> *> *groups)
{
    if (TSContentContinuous(view)) {
        NSRect all = TSContentFitRectInView(view, groups.firstObject ?: @[]);
        if (!NSIsEmptyRect(all)) TSContentScrollTo(view, all, NO, NO);
    } else
        TSContentCentreRow(view);
}

// The same place again, after PDFKit has gone to a place and moved sideways with it (#62).
static inline void TSContentPlaceSideways(PDFView *view)
{
    if (view.document.pageCount)
        TSContentPlaceSidewaysIn(view, TSContentKnownGroups(view));
}

// Sets the magnification and the place sideways of Fit to Content Width, keeping the text at
// the top of the view. NO when no content is known.
// The top is taken by the caller, before the view changes its size.
static inline BOOL TSContentFitWidthKeeping(PDFView *view, TSContentTop top, CGFloat (^setScale)(CGFloat scale))
{
    if (!view.document.pageCount) return NO;
    PDFPage *topPage = top.page; // kept while the magnification changes
    NSArray<NSArray<PDFPage *> *> *groups = TSContentKnownGroups(view);
    CGFloat (^widest)(void) = ^CGFloat{
        CGFloat width = 0;
        for (NSArray<PDFPage *> *group in groups) width = MAX(width, NSWidth(TSContentFitRectInView(view, group)));
        return width;
    };
    if (widest() <= 0) return NO;
    BOOL fitted = TSContentSettleScale(view, widest, nil, setScale);
    top.page = topPage;
    TSContentRestoreTop(view, top);
    TSContentPlaceSidewaysIn(view, groups);
    return fitted;
}

static inline BOOL TSContentFitWidth(PDFView *view, CGFloat (^setScale)(CGFloat scale))
{
    return TSContentFitWidthKeeping(view, TSContentTopOf(view), setScale);
}

// Whether finishing a measurement should move this view. A window resize does not ask:
// it fits from the stored rects whenever they are complete.
// The left and right edges are compared in screen points. One point of the page, and one
// point of the clip view, are not that unit (#62). A blank row does not skip the decision:
// the widest row still sets the magnification. Raw ink, before the margin, forces a fit
// when it crosses the visible edge by a fraction of a screen point. A symmetric change of
// the width is the same test, not a second one: each edge has to move by more than a point.
static inline BOOL TSContentWidthShouldRefit(PDFView *view)
{
    PDFDocument *document = view.document;
    PDFDisplayBox box = view.displayBox;
    if (!TSContentWidthIsComplete(document, box)) return NO;
    NSClipView *clip = view.documentView.enclosingScrollView.contentView;
    NSRect visible = TSContentVisibleArea(view);
    if (!clip || NSWidth(visible) <= 0 || NSWidth(clip.frame) <= 0 || NSWidth(clip.bounds) <= 0) return NO;
    NSArray<NSArray<PDFPage *> *> *groups = TSContentGroups(view);
    CGFloat widest = 0;
    NSRect placed = NSZeroRect, raw = NSZeroRect, widestRect = NSZeroRect;
    if (TSContentContinuous(view)) {
        NSMutableArray<PDFPage *> *all = [NSMutableArray array];
        for (NSArray<PDFPage *> *group in groups) [all addObjectsFromArray:group];
        placed = TSContentFitRectInView(view, all);
        raw = TSContentRawRectInView(view, all);
        widestRect = placed;
    } else {
        for (NSArray<PDFPage *> *group in groups) {
            NSRect fit = TSContentFitRectInView(view, group);
            CGFloat width = NSWidth([clip convertRect:fit fromView:view]);
            if (width > widest) {
                widest = width;
                widestRect = fit;
            }
        }
        NSArray<PDFPage *> *row = TSContentRow(view, TSContentMiddlePage(view));
        placed = TSContentFitRectInView(view, row);
        raw = TSContentRawRectInView(view, row);
        // The row in view may be blank. The magnification still follows the widest row.
        if (NSIsEmptyRect(placed)) placed = widestRect;
    }
    if (NSIsEmptyRect(placed)) return NO;
    NSRect placedClip = [clip convertRect:placed fromView:view];
    if (TSContentContinuous(view)) widest = NSWidth(placedClip);
    if (widest <= 0) return NO;
    CGFloat toScreen = NSWidth(clip.frame) / NSWidth(clip.bounds);
    CGFloat targetWidth = NSWidth(placedClip) * NSWidth(visible) / widest;
    CGFloat targetLeft = NSMidX(visible) - targetWidth / 2.0;
    CGFloat delta = MAX(fabs(targetLeft - NSMinX(placedClip)), fabs(targetLeft + targetWidth - NSMaxX(placedClip)));
    BOOL rawClipped = NO;
    if (!NSIsEmptyRect(raw)) {
        NSRect rawClip = [clip convertRect:raw fromView:view];
        rawClipped = (NSMinX(visible) - NSMinX(rawClip)) * toScreen > 0.05 ||
            (NSMaxX(rawClip) - NSMaxX(visible)) * toScreen > 0.05;
    }
    return delta * toScreen > 1.0 || rawClipped;
}

// Names and symbols of the two buttons, in both previews.
static inline NSArray<NSString *> *TSContentZoomLabels(void)
{
    NSString *whole = NSLocalizedStringFromTable(@"ExperimentZoomToContent", @"ToolbarItems", @"");
    NSString *width = NSLocalizedStringFromTable(@"ExperimentZoomToContentWidth", @"ToolbarItems", @"");
    return @[whole.length && ![whole isEqualToString:@"ExperimentZoomToContent"] ? whole : @"Zoom to Content",
             width.length && ![width isEqualToString:@"ExperimentZoomToContentWidth"] ? width : @"Zoom to Content Width"];
}

static inline NSArray<NSString *> *TSContentZoomSymbols(void)
{
    return @[@"viewfinder", @"arrow.left.and.right"];
}
