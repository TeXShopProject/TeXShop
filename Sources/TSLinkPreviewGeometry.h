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

static inline CGFloat TSLinkPreviewClamp(CGFloat value, CGFloat lower, CGFloat upper)
{
    return MIN(MAX(value, lower), upper);
}

static inline BOOL TSLinkPreviewRects(NSSize pageSize, NSPoint destination,
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
    CGFloat x = TSLinkPreviewClamp(destination.x - (enlarged ? 10 : 5), 0, pageSize.width - width);
    CGFloat y = TSLinkPreviewClamp(destination.y - height + 10, 0, pageSize.height - height);
    *source = NSMakeRect(x, y, width, height);

    NSRect available = NSInsetRect(visible, 5, 5);
    CGFloat scale = MIN(enlarged ? 1 : 2.0 / 3.0,
                        MIN(available.size.width / width, available.size.height / height));
    width *= scale;
    height *= scale;
    x = cursor.x + (enlarged ? -5 : 10);
    y = (above != flipped) ? cursor.y + 10 : cursor.y - height - 10;
    *output = NSMakeRect(TSLinkPreviewClamp(x, NSMinX(available), NSMaxX(available) - width),
                        TSLinkPreviewClamp(y, NSMinY(available), NSMaxY(available) - height),
                        width, height);
    return YES;
}
