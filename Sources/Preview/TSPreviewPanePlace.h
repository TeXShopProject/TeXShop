// The place shown at the top edge of a preview pane, kept as a point on a page.
// Splitting, unsplitting and switching the panes put it back at the top edge exactly,
// whatever PDFKit does to the scroll position while the panes change size.
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSPreviewScrollerKeeper.h"

typedef struct {
    BOOL valid;
    NSUInteger pageIndex;
    NSPoint pagePoint;
} TSPreviewPanePlace;

// The left end of the top edge of the visible area, in clip view coordinates.
static inline NSPoint TSPreviewPaneEdge(NSScrollView *scroll)
{
    NSClipView *clip = scroll.contentView;
    NSRect bounds = clip.bounds;
    NSEdgeInsets insets = scroll.contentInsets;
    CGFloat top = clip.isFlipped ? NSMinY(bounds) + insets.top : NSMaxY(bounds) - insets.top;
    return NSMakePoint(NSMinX(bounds) + insets.left, top);
}

static inline TSPreviewPanePlace TSPreviewPaneCapture(PDFView *view)
{
    TSPreviewPanePlace place = {0};
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!view.document.pageCount || !clip || NSIsEmptyRect(clip.bounds)) return place;
    NSPoint edge = [view convertPoint:TSPreviewPaneEdge(scroll) fromView:clip];
    PDFPage *page = [view pageForPoint:edge nearest:YES];
    if (!page) return place;
    place.valid = YES;
    place.pageIndex = [view.document indexForPage:page];
    place.pagePoint = [view convertPoint:edge toPage:page];
    return place;
}

// The place under a point given in window coordinates, also below or above the pane, where
// the pages go on as they are laid out.
static inline TSPreviewPanePlace TSPreviewPaneCaptureAt(PDFView *view, NSPoint windowPoint)
{
    TSPreviewPanePlace place = {0};
    if (!view.document.pageCount || !view.window) return place;
    NSPoint point = [view convertPoint:windowPoint fromView:nil];
    PDFPage *page = [view pageForPoint:point nearest:YES];
    if (!page) return place;
    place.valid = YES;
    place.pageIndex = [view.document indexForPage:page];
    place.pagePoint = [view convertPoint:point toPage:page];
    return place;
}

// The left end of the top edge of a pane's visible area, in window coordinates.
static inline NSPoint TSPreviewPaneWindowEdge(PDFView *view)
{
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    return clip ? [clip convertPoint:TSPreviewPaneEdge(scroll) toView:nil] : NSZeroPoint;
}

// Scrolls so that the place is at the left end of the top edge, as far as the document allows.
static inline void TSPreviewPaneRestore(PDFView *view, TSPreviewPanePlace place)
{
    if (!place.valid || !view.document.pageCount) return;
    PDFPage *page = [view.document pageAtIndex:MIN(place.pageIndex, view.document.pageCount - 1)];
    // Pages that are not laid out, as in single page display, have no position yet.
    if (view.currentPage != page) [view goToPage:page];
    [view layoutDocumentView];
    [view layoutSubtreeIfNeeded];
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!clip || NSIsEmptyRect(clip.bounds)) return;
    NSPoint point = [clip convertPoint:[view convertPoint:place.pagePoint fromPage:page] fromView:view];
    NSPoint edge = TSPreviewPaneEdge(scroll);
    NSRect target = clip.bounds;
    target.origin.x += point.x - edge.x;
    target.origin.y += point.y - edge.y;
    // Clamp to the scroll limits, found at the document edges as in TSExternalPDFRestore,
    // without changing an interior position.
    NSRect documentRect = clip.documentRect;
    NSEdgeInsets insets = scroll.contentInsets;
    CGFloat horizontalMargin = target.size.width + fabs(insets.left) + fabs(insets.right) + 1;
    CGFloat verticalMargin = target.size.height + fabs(insets.top) + fabs(insets.bottom) + 1;
    NSRect lower = target, upper = target;
    lower.origin = NSMakePoint(NSMinX(documentRect) - horizontalMargin, NSMinY(documentRect) - verticalMargin);
    upper.origin = NSMakePoint(NSMaxX(documentRect) + horizontalMargin, NSMaxY(documentRect) + verticalMargin);
    lower = [clip constrainBoundsRect:lower];
    upper = [clip constrainBoundsRect:upper];
    target.origin.x = fmin(fmax(target.origin.x, lower.origin.x), upper.origin.x);
    target.origin.y = fmin(fmax(target.origin.y, lower.origin.y), upper.origin.y);
    [clip scrollToPoint:target.origin];
    [scroll reflectScrolledClipView:clip];
    // A change of the size in the same turn of the event loop does not bring its own text back.
    TSPreviewPlaceChosenByProgram(view);
}
// The place of a pinned popup on the page under its upper left corner, from its frame in window
// coordinates, as the popup keeps it when the preview is zoomed (#56).
typedef struct { __unsafe_unretained PDFPage *page; NSRect rect; } TSPopupPlace;
static inline TSPopupPlace TSPopupPlaceOnPage(PDFView *view, NSRect windowFrame)
{
    TSPopupPlace place = { nil, NSZeroRect };
    if (NSIsEmptyRect(windowFrame)) return place;
    NSRect frame = [view convertRect:windowFrame fromView:nil];
    NSPoint corner = NSMakePoint(NSMinX(frame), view.isFlipped ? NSMinY(frame) : NSMaxY(frame));
    place.page = [view pageForPoint:corner nearest:YES];
    if (place.page) place.rect = [view convertRect:frame toPage:place.page];
    return place;
}
// The frame in window coordinates of that place in a view showing the page; the frame it had,
// without a page.
static inline NSRect TSPopupFrameInView(PDFView *view, TSPopupPlace place, NSRect windowFrame)
{
    if (!place.page || place.page.document != view.document) return windowFrame;
    NSRect frame = [view convertRect:[view convertRect:place.rect fromPage:place.page] toView:nil];
    if (!isfinite(NSMinX(frame)) || !isfinite(NSMinY(frame)) || NSWidth(frame) <= 0 || NSHeight(frame) <= 0) return windowFrame;
    return frame;
}

