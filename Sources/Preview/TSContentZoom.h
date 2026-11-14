#pragma once
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

// Zoom to Content and Zoom to Content Width, in the Preview window and the Experiment preview.
// The content is the non-blank part of the page in the middle of the view, together with the
// page beside it in two-page layouts. Its edges are those seen on screen: the rotation of the
// page is applied, so the top of a page turned by 90 degrees is a side of the page in PDF space.

// Margin around the content, in page units.
static const CGFloat TSContentZoomMargin = 8;

// The non-blank part of a page, in page coordinates; empty for a blank page.
static inline NSRect TSContentInkBounds(PDFPage *page, PDFDisplayBox box)
{
    if (!page) return NSZeroRect;
    NSRect bounds = [page boundsForBox:box];
    if (NSIsEmptyRect(bounds)) return NSZeroRect;
    // drawWithBox:toContext: draws the page as a preview shows it: the box origin at zero and
    // the rotation applied. transformForBox: takes page coordinates there.
    CGAffineTransform toDrawn = [page transformForBox:box];
    CGRect drawn = CGRectStandardize(CGRectApplyAffineTransform(NSRectToCGRect(bounds), toDrawn));
    if (CGRectIsEmpty(drawn)) return NSZeroRect;
    CGFloat resolution = MIN(2.0, 4000.0 / MAX(CGRectGetWidth(drawn), CGRectGetHeight(drawn)));
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
    area.origin.y += (clip.isFlipped ? insets.top : insets.bottom) * unit;
    area.size.height -= (insets.top + insets.bottom) * unit;
    return area;
}

// The size of that part in points on screen.
static inline NSSize TSContentVisibleSize(PDFView *view)
{
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!clip) return NSZeroSize;
    NSEdgeInsets insets = scroll.contentInsets;
    return NSMakeSize(NSWidth(clip.frame) - insets.left - insets.right, NSHeight(clip.frame) - insets.top - insets.bottom);
}

// The pages whose content is zoomed, each with its content in page coordinates
// (keys "page" and "rect"); empty when they are blank.
static inline NSArray<NSDictionary *> *TSContentZoomParts(PDFView *view)
{
    NSClipView *clip = view.documentView.enclosingScrollView.contentView;
    if (!view.document.pageCount || !clip) return @[];
    NSRect area = TSContentVisibleArea(view);
    NSPoint middle = [view convertPoint:NSMakePoint(NSMidX(area), NSMidY(area)) fromView:clip];
    PDFPage *page = [view pageForPoint:middle nearest:YES];
    // One page or one row at a time: PDFKit also places pages of other rows there.
    NSArray<PDFPage *> *shown = view.visiblePages;
    if (page && shown.count && ![shown containsObject:page]) page = view.currentPage;
    if (!page) return @[];
    PDFDisplayBox box = view.displayBox;
    NSMutableArray<PDFPage *> *pages = [NSMutableArray arrayWithObject:page];
    if (view.displayMode == kPDFDisplayTwoUp || view.displayMode == kPDFDisplayTwoUpContinuous) {
        // The page beside it in its row: pages pair from the first one, or from the second one
        // when the first is shown alone as a cover. The direction only swaps their sides.
        NSInteger index = (NSInteger)[view.document indexForPage:page];
        NSInteger first = view.displaysAsBook ? 1 : 0;
        NSInteger other = index < first ? -1 : ((index - first) % 2 == 0 ? index + 1 : index - 1);
        if (other >= 0 && other < (NSInteger)view.document.pageCount) {
            // Also when it is out of sight at a high magnification.
            PDFPage *beside = [view.document pageAtIndex:other];
            if (beside) [pages addObject:beside];
        }
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (PDFPage *each in pages) {
        NSRect ink = TSContentInkBounds(each, box);
        if (NSIsEmptyRect(ink)) continue;
        ink = NSIntersectionRect(NSInsetRect(ink, -TSContentZoomMargin, -TSContentZoomMargin), [each boundsForBox:box]);
        [parts addObject:@{@"page": each, @"rect": [NSValue valueWithRect:ink]}];
    }
    return parts;
}

// The content in view coordinates at the present magnification.
static inline NSRect TSContentZoomRectInView(PDFView *view, NSArray<NSDictionary *> *parts)
{
    NSRect content = NSZeroRect;
    for (NSDictionary *part in parts) {
        PDFPage *page = part[@"page"];
        if (!page) continue;
        NSRect rect = [view convertRect:[part[@"rect"] rectValue] fromPage:page];
        content = NSIsEmptyRect(content) ? rect : NSUnionRect(content, rect);
    }
    return content;
}

// Enlarges or reduces the content to the width of the view and shows its top at the top of
// the view, or, unless widthOnly, fits the whole content in the view and centres it.
// setScale sets a magnification between the limits and returns the one it set; NO if the
// pages are blank.
static inline BOOL TSContentZoom(PDFView *view, BOOL widthOnly, CGFloat (^setScale)(CGFloat scale))
{
    NSArray *parts = TSContentZoomParts(view);
    if (!parts.count) return NO;
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    // Measured again until the magnification settles: the gap between the pages of a row
    // does not grow with the pages, and a scroller that appears narrows the view.
    for (int pass = 0; pass < 4; pass++) {
        NSRect content = TSContentZoomRectInView(view, parts);
        NSSize visible = TSContentVisibleSize(view);
        CGFloat current = view.scaleFactor;
        if (NSIsEmptyRect(content) || visible.width <= 0 || visible.height <= 0 || current <= 0) return NO;
        CGFloat scale = visible.width / (NSWidth(content) / current);
        if (!widthOnly) scale = MIN(scale, visible.height / (NSHeight(content) / current));
        CGFloat set = setScale(scale);
        [view layoutDocumentView];
        [view layoutSubtreeIfNeeded];
        if (fabs(set - current) < 1e-6) break;
    }
    NSRect content = [view.documentView convertRect:TSContentZoomRectInView(view, parts) fromView:view];
    NSRect area = TSContentVisibleArea(view), target = clip.bounds;
    target.origin.x += NSMidX(content) - NSMidX(area);
    if (!widthOnly)
        target.origin.y += NSMidY(content) - NSMidY(area);
    else if (clip.isFlipped)
        target.origin.y += NSMinY(content) - NSMinY(area);
    else
        target.origin.y += NSMaxY(content) - NSMaxY(area);
    target = [clip constrainBoundsRect:target];
    [clip scrollToPoint:target.origin];
    [scroll reflectScrolledClipView:clip];
    return YES;
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
