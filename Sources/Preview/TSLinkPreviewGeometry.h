#pragma once

#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <math.h>

// Both the image and the link destination use this normalized, rotated CropBox.
static inline BOOL TSLinkPreviewPageGeometry(PDFPage *page, NSSize *size,
                                             CGAffineTransform *transform)
{
    CGPDFPageRef reference = page.pageRef;
    if (!reference) return NO;
    CGRect box = CGPDFPageGetBoxRect(reference, kCGPDFCropBox);
    if (CGRectIsEmpty(box) || CGRectIsInfinite(box) || CGRectIsNull(box)) return NO;
    NSInteger rotation = ((CGPDFPageGetRotationAngle(reference) % 360) + 360) % 360;
    *size = NSMakeSize(box.size.width, box.size.height);
    if (rotation == 90 || rotation == 270)
        *size = NSMakeSize(box.size.height, box.size.width);
    *transform = CGPDFPageGetDrawingTransform(reference, kCGPDFCropBox,
                                             CGRectMake(0, 0, size->width, size->height), 0, true);
    return YES;
}

static inline NSImage *TSLinkPreviewImage(PDFPage *page, NSSize size)
{
    return [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect destination) {
        CGContextRef context = NSGraphicsContext.currentContext.CGContext;
        CGPDFPageRef reference = page.pageRef;
        if (!context || !reference) return NO;
        CGContextSaveGState(context);
        CGContextClipToRect(context, NSRectToCGRect(destination));
        CGContextConcatCTM(context, CGPDFPageGetDrawingTransform(reference, kCGPDFCropBox,
                                             NSRectToCGRect(destination), 0, true));
        CGContextDrawPDFPage(context, reference);
        CGContextRestoreGState(context);
        return YES;
    }];
}

static inline NSPoint TSLinkPreviewDestinationPoint(NSPoint point, NSSize size,
                                                       CGAffineTransform transform)
{
    // PDFKit represents omitted /Fit or /XYZ components with a finite sentinel.
    CGPoint topLeft = CGPointApplyAffineTransform(CGPointMake(0, size.height),
                                                   CGAffineTransformInvert(transform));
    if (point.x == kPDFDestinationUnspecifiedValue) point.x = topLeft.x;
    if (point.y == kPDFDestinationUnspecifiedValue) point.y = topLeft.y;
    return NSPointFromCGPoint(CGPointApplyAffineTransform(NSPointToCGPoint(point), transform));
}

static inline BOOL TSLinkPreviewHasHorizontalDestination(NSPoint raw, CGAffineTransform transform)
{
    return (fabs(transform.a) < 0.0001 || raw.x != kPDFDestinationUnspecifiedValue) &&
           (fabs(transform.c) < 0.0001 || raw.y != kPDFDestinationUnspecifiedValue);
}

// A text column narrower or wider than these (in PDF points) is not used to size the preview.
static const CGFloat TSLinkPreviewMinimumColumn = 150;
static const CGFloat TSLinkPreviewMaximumColumn = 600;
// Margin on each side of a text column, as a fraction of its width (about 105% in all).
static const CGFloat TSLinkPreviewColumnMargin = 0.025;
// Text narrower than this is shown in the nominal 400 point crop (390 + padding).
static const CGFloat TSLinkPreviewNominalColumn = 390;

static inline NSRect TSLinkPreviewTextBounds(PDFPage *page, NSSize size, NSPoint point,
                                             CGAffineTransform transform, BOOL enlarged)
{
    CGFloat height = MIN(size.height, enlarged ? 360 : 120);
    CGFloat y = MIN(MAX(point.y - height + 10, 0), size.height - height);
    NSRect band = NSMakeRect(0, y, size.width, height);
    CGRect pageBand = CGRectApplyAffineTransform(NSRectToCGRect(band), CGAffineTransformInvert(transform));
    PDFSelection *selection = [page selectionForRect:NSRectFromCGRect(pageBand)];
    if (!selection.string.length) return NSZeroRect;
    // Retain the column intersecting the destination, not unrelated columns.
    // Exceptionally wide lines (posters, A3 prose) do not describe a readable column.
    CGFloat limit = TSLinkPreviewMaximumColumn;
    CGFloat nearest = CGFLOAT_MAX;
    NSMutableArray<NSValue *> *lines = [NSMutableArray array];
    for (PDFSelection *line in selection.selectionsByLine) {
        CGRect bounds = CGRectApplyAffineTransform(NSRectToCGRect([line boundsForPage:page]), transform);
        if (!isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
            !isfinite(bounds.size.width) || !isfinite(bounds.size.height)) continue;
        NSRect rect = NSIntersectionRect(band, NSRectFromCGRect(bounds));
        if (NSIsEmptyRect(rect) || rect.size.width > limit) continue;
        CGFloat distance = MAX(MAX(NSMinX(rect) - point.x, point.x - NSMaxX(rect)), 0);
        nearest = MIN(nearest, distance);
        [lines addObject:[NSValue valueWithRect:rect]];
    }
    NSRect result = NSZeroRect;
    for (NSValue *value in lines) {
        NSRect rect = value.rectValue;
        CGFloat distance = MAX(MAX(NSMinX(rect) - point.x, point.x - NSMaxX(rect)), 0);
        if (distance <= nearest + 2)
            result = NSIsEmptyRect(result) ? rect : NSUnionRect(result, rect);
    }
    return result;
}

// Extend the lines around the destination to the right margin of their column on the
// whole page, so a heading or a short line near the destination does not narrow the preview.
// Lines sharing the left margin of the destination's lines belong to its column; most of them
// are full lines, so the median right edge is the column's right margin.
// A column narrower than the nominal preview is kept narrow only when prose lines stand beside
// it, as in a two-column layout; otherwise it widens to the nominal 400 point crop (390 + padding).
static inline NSRect TSLinkPreviewColumnBounds(PDFPage *page, NSSize size, CGAffineTransform transform,
                                               NSRect local)
{
    if (NSIsEmptyRect(local)) return local;
    NSRect column = local;
    NSMutableArray<NSValue *> *lines = [NSMutableArray array];
    CGRect pageRect = CGRectApplyAffineTransform(CGRectMake(0, 0, size.width, size.height),
                                                 CGAffineTransformInvert(transform));
    NSArray<PDFSelection *> *selections = [page selectionForRect:NSRectFromCGRect(pageRect)].selectionsByLine;
    if (selections.count <= 600) for (PDFSelection *line in selections) {
        CGRect bounds = CGRectApplyAffineTransform(NSRectToCGRect([line boundsForPage:page]), transform);
        if (!isfinite(bounds.origin.x) || !isfinite(bounds.size.width) || bounds.size.width <= 0 ||
            bounds.size.width > TSLinkPreviewMaximumColumn) continue;
        [lines addObject:[NSValue valueWithRect:NSRectFromCGRect(bounds)]];
    }
    NSMutableArray<NSNumber *> *rights = [NSMutableArray array];
    for (NSValue *value in lines)
        if (fabs(NSMinX(value.rectValue) - NSMinX(local)) <= 30) [rights addObject:@(NSMaxX(value.rectValue))];
    if (rights.count >= 5) {
        [rights sortUsingSelector:@selector(compare:)];
        CGFloat right = MIN(rights[rights.count / 2].doubleValue, size.width);
        if (right > NSMaxX(column)) column.size.width = right - NSMinX(column);
    }
    NSUInteger beside = 0;
    for (NSValue *value in lines) {
        NSRect line = value.rectValue;
        if (line.size.width >= TSLinkPreviewMinimumColumn &&
            (NSMinX(line) >= NSMaxX(column) + 5 || NSMaxX(line) <= NSMinX(column) - 5)) beside++;
    }
    if (beside < 5 && column.size.width < TSLinkPreviewNominalColumn)
        column.size.width = MAX(column.size.width, MIN(TSLinkPreviewNominalColumn, size.width - NSMinX(column)));
    return column;
}

static inline CGFloat TSLinkPreviewClamp(CGFloat value, CGFloat lower, CGFloat upper)
{
    return MIN(MAX(value, lower), upper);
}

static inline BOOL TSLinkPreviewRects(NSSize pageSize, NSPoint destination, NSRect textBounds,
                                      NSRect visible, NSPoint cursor, BOOL enlarged,
                                      BOOL above, BOOL flipped, NSRect *source, NSRect *output)
{
    if (!isfinite(pageSize.width) || !isfinite(pageSize.height) ||
        pageSize.width <= 0 || pageSize.height <= 0 ||
        !isfinite(destination.x) || !isfinite(destination.y) ||
        !isfinite(visible.origin.x) || !isfinite(visible.origin.y) ||
        !isfinite(visible.size.width) || !isfinite(visible.size.height) ||
        !isfinite(cursor.x) || !isfinite(cursor.y) ||
        visible.size.width <= 10 || visible.size.height <= 10) return NO;

    CGFloat nominal = enlarged ? 445 : 400;
    CGFloat height = MIN(pageSize.height, enlarged ? 360 : 120);
    CGFloat padding = enlarged ? 10 : 5;
    CGFloat anchorX = TSLinkPreviewClamp(destination.x, 0, pageSize.width);
    CGFloat maximum = MIN(pageSize.width - 10, TSLinkPreviewMaximumColumn);
    NSRect text = NSIntersectionRect(NSMakeRect(0,0,pageSize.width,pageSize.height), textBounds);
    BOOL hasText = !NSIsEmptyRect(text);
    CGFloat x, width;
    if (hasText && text.size.width >= TSLinkPreviewMinimumColumn && text.size.width <= maximum) {
        // Show the whole text column at the nominal scale; the popup grows instead of shrinking.
        // A column wider than the nominal crop gets a preview of about 105% of its width,
        // leaving room to scroll a pinned preview; narrower text already has room.
        if (text.size.width > TSLinkPreviewNominalColumn)
            padding = MAX(padding, round(text.size.width * TSLinkPreviewColumnMargin));
        x = TSLinkPreviewClamp(MIN(anchorX, NSMinX(text)) - padding, 0, pageSize.width);
        width = TSLinkPreviewClamp(MAX(anchorX, NSMaxX(text)) + padding, x, pageSize.width) - x;
    } else {
        width = MIN(pageSize.width, nominal);
        CGFloat preferredX = anchorX - padding;
        if (hasText) preferredX = MIN(preferredX, NSMinX(text) - padding);
        x = TSLinkPreviewClamp(preferredX, 0, pageSize.width - width);
        // Keep both the text's line beginnings and the actual destination in view.
        CGFloat right = anchorX + (enlarged ? padding : 200);
        if (hasText) right = MAX(right, NSMaxX(text) + padding);
        width = MIN(pageSize.width - x, MAX(width, right - x));
    }
    if (width > maximum + 2 * padding) {
        // Context too far from the destination: prefer a readable destination.
        width = MIN(pageSize.width, nominal);
        x = TSLinkPreviewClamp(anchorX - padding, 0, pageSize.width - width);
    }
    CGFloat y = TSLinkPreviewClamp(destination.y - height + 10, 0, pageSize.height - height);

    // Shrink only for lack of room, continuously, down to a readable floor; beyond that,
    // narrow the crop from the right, sliding it only to keep the destination visible.
    NSRect available = NSInsetRect(visible, 5, 5);
    CGFloat desiredScale = enlarged ? 1 : 2.0 / 3.0;
    CGFloat floorScale = enlarged ? 0.75 : 0.5;
    CGFloat scale = MAX(floorScale, MIN(desiredScale, available.size.width / width));
    scale = MIN(scale, available.size.height / height);
    CGFloat shown = MIN(width, available.size.width / scale);
    if (shown < width) {
        x = TSLinkPreviewClamp(MAX(x, anchorX + padding - shown), 0, pageSize.width - shown);
        width = shown;
    }
    *source = NSMakeRect(x, y, width, height);

    width *= scale;
    height *= scale;
    x = cursor.x + (enlarged ? -5 : 10);
    BOOL positiveY = above != flipped;
    y = positiveY ? cursor.y + 10 : cursor.y - height - 10;
    if (y < NSMinY(available) || y + height > NSMaxY(available)) {
        CGFloat alternative = positiveY ? cursor.y - height - 10 : cursor.y + 10;
        if (alternative >= NSMinY(available) && alternative + height <= NSMaxY(available))
            y = alternative;
    }
    *output = NSMakeRect(TSLinkPreviewClamp(x, NSMinX(available), NSMaxX(available) - width),
                        TSLinkPreviewClamp(y, NSMinY(available), NSMaxY(available) - height),
                        width, height);
    return YES;
}

// A pinned preview is a window onto the page at a fixed scale: it can be moved, resized
// from any edge or corner, and its contents scrolled. Rectangles are handled with y up;
// `flipped` converts a flipped view's rectangles (the source is always in page space).
typedef NS_OPTIONS(NSUInteger, TSLinkPreviewEdge) {
    TSLinkPreviewEdgeNone = 0,
    TSLinkPreviewEdgeLeft = 1 << 0,
    TSLinkPreviewEdgeRight = 1 << 1,
    TSLinkPreviewEdgeTop = 1 << 2,
    TSLinkPreviewEdgeBottom = 1 << 3,
};

static inline NSRect TSLinkPreviewUpward(NSRect rect, BOOL flipped)
{
    return flipped ? NSMakeRect(NSMinX(rect), -NSMaxY(rect), NSWidth(rect), NSHeight(rect)) : rect;
}

static inline TSLinkPreviewEdge TSLinkPreviewEdgeAt(NSRect frame, NSPoint point, CGFloat grip,
                                                    BOOL flipped)
{
    if (!NSPointInRect(point, frame)) return TSLinkPreviewEdgeNone;
    frame = TSLinkPreviewUpward(frame, flipped);
    if (flipped) point.y = -point.y;
    grip = MIN(grip, MIN(NSWidth(frame), NSHeight(frame)) / 3);
    TSLinkPreviewEdge edges = TSLinkPreviewEdgeNone;
    CGFloat left = point.x - NSMinX(frame), right = NSMaxX(frame) - point.x;
    CGFloat bottom = point.y - NSMinY(frame), top = NSMaxY(frame) - point.y;
    if (MIN(left, right) < grip) edges |= left <= right ? TSLinkPreviewEdgeLeft : TSLinkPreviewEdgeRight;
    if (MIN(bottom, top) < grip) edges |= top <= bottom ? TSLinkPreviewEdgeTop : TSLinkPreviewEdgeBottom;
    return edges;
}

// Keeps the whole frame inside the available area; a frame larger than the area keeps
// its left and top edges visible.
static inline NSRect TSLinkPreviewMove(NSRect frame, NSSize delta, NSRect available, BOOL flipped)
{
    NSRect up = TSLinkPreviewUpward(frame, flipped), area = TSLinkPreviewUpward(available, flipped);
    CGFloat x = NSMinX(up) + delta.width, y = NSMinY(up) + (flipped ? -delta.height : delta.height);
    x = NSWidth(up) > NSWidth(area) ? NSMinX(area) : TSLinkPreviewClamp(x, NSMinX(area), NSMaxX(area) - NSWidth(up));
    y = NSHeight(up) > NSHeight(area) ? NSMaxY(area) - NSHeight(up)
                                      : TSLinkPreviewClamp(y, NSMinY(area), NSMaxY(area) - NSHeight(up));
    up.origin = NSMakePoint(x, y);
    return TSLinkPreviewUpward(up, flipped);
}

// Moves one edge to `target`, keeping it between `lower` and `upper`; a limit the frame
// already exceeds never pulls the edge past where it is now.
static inline CGFloat TSLinkPreviewEdgeTarget(CGFloat current, CGFloat target, CGFloat lower, CGFloat upper)
{
    return TSLinkPreviewClamp(target, MIN(lower, current), MAX(upper, current));
}

// Moving edges reveal or hide page content; the content under the other edges stays put.
static inline void TSLinkPreviewResize(NSRect frame, NSRect source, TSLinkPreviewEdge edges, NSSize delta,
                                       NSSize minimum, NSRect available, NSSize pageSize, BOOL flipped,
                                       NSRect *outputFrame, NSRect *outputSource)
{
    NSRect up = TSLinkPreviewUpward(frame, flipped), area = TSLinkPreviewUpward(available, flipped);
    CGFloat dy = flipped ? -delta.height : delta.height;
    CGFloat sx = NSWidth(source) > 0 ? NSWidth(up) / NSWidth(source) : 1;
    CGFloat sy = NSHeight(source) > 0 ? NSHeight(up) / NSHeight(source) : 1;
    if (edges & TSLinkPreviewEdgeLeft) {
        CGFloat edge = TSLinkPreviewEdgeTarget(NSMinX(up), NSMinX(up) + delta.width,
            MAX(MIN(NSMinX(area), NSMinX(up)), NSMinX(up) - NSMinX(source) * sx), NSMaxX(up) - minimum.width);
        CGFloat change = edge - NSMinX(up);
        up.origin.x += change; up.size.width -= change;
        source.origin.x += change / sx; source.size.width -= change / sx;
    } else if (edges & TSLinkPreviewEdgeRight) {
        CGFloat edge = TSLinkPreviewEdgeTarget(NSMaxX(up), NSMaxX(up) + delta.width, NSMinX(up) + minimum.width,
            MIN(MAX(NSMaxX(area), NSMaxX(up)), NSMaxX(up) + (pageSize.width - NSMaxX(source)) * sx));
        CGFloat change = edge - NSMaxX(up);
        up.size.width += change; source.size.width += change / sx;
    }
    if (edges & TSLinkPreviewEdgeBottom) {
        CGFloat edge = TSLinkPreviewEdgeTarget(NSMinY(up), NSMinY(up) + dy,
            MAX(MIN(NSMinY(area), NSMinY(up)), NSMinY(up) - NSMinY(source) * sy), NSMaxY(up) - minimum.height);
        CGFloat change = edge - NSMinY(up);
        up.origin.y += change; up.size.height -= change;
        source.origin.y += change / sy; source.size.height -= change / sy;
    } else if (edges & TSLinkPreviewEdgeTop) {
        CGFloat edge = TSLinkPreviewEdgeTarget(NSMaxY(up), NSMaxY(up) + dy, NSMinY(up) + minimum.height,
            MIN(MAX(NSMaxY(area), NSMaxY(up)), NSMaxY(up) + (pageSize.height - NSMaxY(source)) * sy));
        CGFloat change = edge - NSMaxY(up);
        up.size.height += change; source.size.height += change / sy;
    }
    *outputFrame = TSLinkPreviewUpward(up, flipped);
    *outputSource = source;
}

// Scrolls the page under the preview; `contentDelta` is how far the content moves, in page
// points with y up. The source stays on the page.
static inline NSRect TSLinkPreviewPan(NSRect source, NSSize contentDelta, NSSize pageSize)
{
    source.origin.x = TSLinkPreviewClamp(NSMinX(source) - contentDelta.width, 0,
                                         MAX(0, pageSize.width - NSWidth(source)));
    source.origin.y = TSLinkPreviewClamp(NSMinY(source) - contentDelta.height, 0,
                                         MAX(0, pageSize.height - NSHeight(source)));
    return source;
}
