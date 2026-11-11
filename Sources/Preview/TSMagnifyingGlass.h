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

// The page as a preview draws it: the box origin at zero and the rotation applied.
static inline NSImage *TSMagnifyingGlassPageImage(PDFPage *page, PDFDisplayBox box)
{
    NSRect bounds = [page boundsForBox:box];
    NSSize size = page.rotation % 180 ? NSMakeSize(NSHeight(bounds), NSWidth(bounds)) : bounds.size;
    return [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [page drawWithBox:box toContext:NSGraphicsContext.currentContext.CGContext];
        return YES;
    }];
}

// For a pointer at point (view coordinates): the lens in view coordinates, and the
// part of the page image (TSMagnifyingGlassPageImage) that the lens shows.
static inline void TSMagnifyingGlassLayout(PDFView *view, PDFPage *page, PDFDisplayBox box, NSPoint point,
                                           NSSize lens, CGFloat scale, NSRect *lensInView, NSRect *imageSource)
{
    NSRect source = NSMakeRect(point.x - lens.width / 2 / scale, point.y - lens.height / 2 / scale,
                               lens.width / scale, lens.height / scale);
    NSRect pageSource = [view convertRect:source toPage:page];
    *imageSource = NSRectFromCGRect(CGRectApplyAffineTransform(NSRectToCGRect(pageSource), [page transformForBox:box]));
    *lensInView = NSMakeRect(point.x - lens.width / 2, point.y - lens.height / 2, lens.width, lens.height);
}
