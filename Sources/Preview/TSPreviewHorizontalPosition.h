// The horizontal scroll position of a preview, kept when the preview moves to
// another page or to a SyncTeX or search result, as long as what is shown is in view.
// On macOS 27, PDFKit moves single and double page display to a page corner
// whenever the page changes, and centers the result of scrollSelectionToVisible:.
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>

// The leftmost and rightmost clip view origins, found at the document edges as in
// TSExternalPDFRestore: constrainBoundsRect: may offset an interior origin.
static inline void TSPreviewHorizontalLimits(NSScrollView *scroll, CGFloat *minimum, CGFloat *maximum)
{
    NSClipView *clip = scroll.contentView;
    NSRect bounds = clip.bounds, lower = bounds, upper = bounds;
    NSRect documentRect = clip.documentRect;
    NSEdgeInsets insets = scroll.contentInsets;
    CGFloat margin = NSWidth(bounds) + fabs(insets.left) + fabs(insets.right) + 1;
    lower.origin.x = NSMinX(documentRect) - margin;
    upper.origin.x = NSMaxX(documentRect) + margin;
    *minimum = NSMinX([clip constrainBoundsRect:lower]);
    *maximum = NSMinX([clip constrainBoundsRect:upper]);
}

// Scrolls sideways to x, as far as the document allows, and leaves the vertical position.
static inline void TSPreviewScrollHorizontally(NSScrollView *scroll, CGFloat x)
{
    NSClipView *clip = scroll.contentView;
    if (!clip || NSIsEmptyRect(clip.bounds) || !isfinite(x)) return;
    CGFloat minimum, maximum;
    TSPreviewHorizontalLimits(scroll, &minimum, &maximum);
    if (!isfinite(minimum) || !isfinite(maximum)) return;
    NSPoint origin = clip.bounds.origin;
    origin.x = maximum < minimum ? minimum : fmin(fmax(x, minimum), maximum);
    if (fabs(origin.x - NSMinX(clip.bounds)) < 0.01) return;
    [clip scrollToPoint:origin];
    [scroll reflectScrolledClipView:clip];
}

// The left edge of the visible area that shows the span from left to right, in
// clip view coordinates, starting from the present left edge x and width:
// - a span already in view keeps x;
// - a span that fits is moved just into view, with up to `margin` to spare;
// - a span wider than the view keeps x while some of it is in view.
// Returns NAN when no part of a wider span is in view, so the caller keeps what PDFKit chose.
static inline CGFloat TSPreviewHorizontalOriginShowing(CGFloat left, CGFloat right, CGFloat x, CGFloat width, CGFloat margin)
{
    if (!(right >= left) || !(width > 0)) return x;
    if (right - left <= width) {
        CGFloat spare = fmin(fmax(margin, 0), (width - (right - left)) / 2);
        if (left < x) return left - spare;
        if (right > x + width) return right - width + spare;
        return x;
    }
    if (right <= x || left >= x + width) return NAN;
    return x;
}

// The same for a result made of lines, in clip view coordinates, once PDFKit has
// scrolled it into view vertically: visible has the vertical range then and the
// width of the view, and x is the left edge before. Each line counts by itself: the
// room between the lines of a result that runs on to another page or column is not
// part of it.
// - a line in view vertically and fully in view sideways at x keeps x;
// - otherwise the first line in view vertically (or the first line) decides, as above.
static inline CGFloat TSPreviewHorizontalOriginShowingLines(const NSRect *lines, NSUInteger count, NSRect visible,
                                                           CGFloat x, CGFloat margin)
{
    CGFloat width = NSWidth(visible);
    NSUInteger first = NSNotFound;
    for (NSUInteger i = 0; i < count; i++) {
        NSRect line = lines[i];
        if (!(NSMaxY(line) > NSMinY(visible) && NSMinY(line) < NSMaxY(visible))) continue;
        if (first == NSNotFound) first = i;
        if (NSMinX(line) >= x && NSMaxX(line) <= x + width) return x;
    }
    if (!count) return x;
    if (first == NSNotFound) first = 0;
    return TSPreviewHorizontalOriginShowing(NSMinX(lines[first]), NSMaxX(lines[first]), x, width, margin);
}
