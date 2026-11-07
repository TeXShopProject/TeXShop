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

static inline NSRect TSLinkPreviewTextBounds(PDFPage *page, NSSize size, NSPoint point,
                                             CGAffineTransform transform, BOOL enlarged)
{
    CGFloat height = MIN(size.height, enlarged ? 360 : 120);
    CGFloat y = MIN(MAX(point.y - height + 10, 0), size.height - height);
    NSRect band = NSMakeRect(0, y, size.width, height);
    CGRect pageBand = CGRectApplyAffineTransform(NSRectToCGRect(band), CGAffineTransformInvert(transform));
    PDFSelection *selection = [page selectionForRect:NSRectFromCGRect(pageBand)];
    if (!selection.string.length) return NSZeroRect;
    CGRect bounds = CGRectApplyAffineTransform(NSRectToCGRect([selection boundsForPage:page]), transform);
    if (!isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
        !isfinite(bounds.size.width) || !isfinite(bounds.size.height)) return NSZeroRect;
    return NSIntersectionRect(band, NSRectFromCGRect(bounds));
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

    CGFloat width = MIN(pageSize.width, enlarged ? 445 : 400);
    CGFloat height = MIN(pageSize.height, enlarged ? 360 : 120);
    CGFloat padding = enlarged ? 10 : 5;
    CGFloat anchorX = TSLinkPreviewClamp(destination.x, 0, pageSize.width);
    CGFloat preferredX = anchorX - padding;
    NSRect text = NSIntersectionRect(NSMakeRect(0,0,pageSize.width,pageSize.height), textBounds);
    if (!NSIsEmptyRect(text)) preferredX = MIN(preferredX, NSMinX(text) - padding);
    CGFloat x = TSLinkPreviewClamp(preferredX, 0, pageSize.width - width);
    // Keep both the text's line beginnings and the actual destination in view.
    CGFloat right = anchorX + padding;
    if (enlarged && !NSIsEmptyRect(text)) right = MAX(right, NSMaxX(text) + padding);
    width = MIN(pageSize.width - x, MAX(width, right - x));
    CGFloat y = TSLinkPreviewClamp(destination.y - height + 10, 0, pageSize.height - height);
    *source = NSMakeRect(x, y, width, height);

    NSRect available = NSInsetRect(visible, 5, 5);
    CGFloat desiredScale = enlarged ? 1 : 2.0 / 3.0;
    CGFloat scale = MIN(desiredScale,
                        MIN(MIN(available.size.width, (enlarged ? 445 : 400) * desiredScale) / width,
                            MIN(available.size.height, (enlarged ? 360 : 120) * desiredScale) / height));
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
