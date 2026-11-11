#pragma once
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

// The magnifying glass of the Preview window and the Experiment preview.
// PDFKit scales its scroll view, so document view coordinates are page units.
// The lens is laid out in view points, so its size and its magnification of the
// screen do not depend on the preview magnification.

// Lens size in points on screen: normal, large (double click), whole window (triple click).
static inline NSSize TSMagnifyingGlassSize(NSInteger level)
{
    if (level <= 1) return NSMakeSize(150, 100);
    if (level == 2) return NSMakeSize(380, 250);
    return NSMakeSize(1800, 1500);
}

// Magnification of what the screen shows; with Shift the glass reduces instead.
static inline CGFloat TSMagnifyingGlassScale(NSEventModifierFlags flags)
{
    BOOL shrink = (flags & NSEventModifierFlagShift) != 0;
    if (flags & NSEventModifierFlagCommand) return shrink ? 1.0 : 2.0;
    if (flags & NSEventModifierFlagOption) return shrink ? 0.66666 : 2.5;
    if (flags & NSEventModifierFlagControl) return shrink ? 0.5 : 3.0;
    return 1.5;
}

// Draws the part of the page given by source, in the coordinates of the page as a
// preview draws it (the box origin at zero and the rotation applied), into lens in
// the current graphics context. Only the lens is drawn: an image of the whole page
// at the magnification of the glass took memory that grew with the square of the
// Preview magnification, gigabytes above 400%.
static inline void TSMagnifyingGlassDrawPage(PDFPage *page, PDFDisplayBox box, NSRect source, NSRect lens)
{
    NSGraphicsContext *context = NSGraphicsContext.currentContext;
    if (!page || !context || NSIsEmptyRect(source) || NSIsEmptyRect(lens)) return;
    CGContextRef cg = context.CGContext;
    CGContextSaveGState(cg);
    CGContextClipToRect(cg, NSRectToCGRect(lens));
    // The lens frame is drawn without antialiasing; the page is drawn as the preview draws it.
    CGContextSetShouldAntialias(cg, true);
    CGContextSetInterpolationQuality(cg, kCGInterpolationHigh);
    if (context.isFlipped) {
        // Draw the page upright in a flipped view, as respectFlipped: did for the page image.
        CGContextTranslateCTM(cg, 0, NSMinY(lens) + NSMaxY(lens));
        CGContextScaleCTM(cg, 1, -1);
    }
    CGContextTranslateCTM(cg, NSMinX(lens), NSMinY(lens));
    CGContextScaleCTM(cg, NSWidth(lens) / NSWidth(source), NSHeight(lens) / NSHeight(source));
    CGContextTranslateCTM(cg, -NSMinX(source), -NSMinY(source));
    [page drawWithBox:box toContext:cg];
    CGContextRestoreGState(cg);
}

// For a pointer at point (view coordinates): the lens in view coordinates, and the
// part of the page, as TSMagnifyingGlassDrawPage takes it, that the lens shows.
static inline void TSMagnifyingGlassLayout(PDFView *view, PDFPage *page, PDFDisplayBox box, NSPoint point,
                                           NSSize lens, CGFloat scale, NSRect *lensInView, NSRect *imageSource)
{
    NSRect source = NSMakeRect(point.x - lens.width / 2 / scale, point.y - lens.height / 2 / scale,
                               lens.width / scale, lens.height / scale);
    NSRect pageSource = [view convertRect:source toPage:page];
    *imageSource = NSRectFromCGRect(CGRectApplyAffineTransform(NSRectToCGRect(pageSource), [page transformForBox:box]));
    *lensInView = NSMakeRect(point.x - lens.width / 2, point.y - lens.height / 2, lens.width, lens.height);
}
