// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSPreviewScrollerKeeper.h
 *
 * When a horizontal scroller appears at the bottom of a preview view or goes away,
 * as when the view gets narrower or wider than the pages or when the magnification
 * changes, the text in the view stays where it is: the scroller only covers or
 * uncovers a strip at the bottom.
 *
 * With scroll bars that are always shown, the scroller takes its height from the
 * visible area. Up to macOS 26 the document view of a PDFView is not flipped, so the
 * scroll view keeps the bottom of the visible area and the text jumped up or down by
 * the height of the scroller. When the magnification changes, PDFKit keeps the text at
 * the centre of the visible area, which moves by half the height of the scroller.
 */

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSPreviewScrollerKeeper : NSObject

// Keeps the text at the top edge of the view in place when its horizontal scroller
// comes or goes. It may be called again, for instance when the view gets a document.
+ (void)installInView:(PDFView *)view;

- (instancetype)init NS_UNAVAILABLE;

@end

// Changes the magnification of a preview view. When a horizontal scroller comes or goes
// with it, the text at the centre of the visible area stays at the same distance from
// the top edge, as if the scroller were laid over the bottom of the view.
void TSPreviewChangeScale(PDFView *view, void (NS_NOESCAPE ^change)(void));

// Changes the size of a preview view. The text at the top of the area where it can be read,
// below the toolbar of a window whose content runs under it, stays there, also when the
// magnification follows the size, as with Fit to Window. Up to macOS 26 the
// scroll view keeps the bottom of the visible area instead, so the text jumped when a
// horizontal scroller came or went, in a view narrower than about half the width of the
// page it moved down by the height of the scroller at every step of a resize, and with
// automatic scaling PDFKit moved it by hundreds of points (#53, measured in macOS 15.6.1
// and 26.6.2).
void TSPreviewChangeSize(PDFView *view, void (NS_NOESCAPE ^change)(void));

// Whether the last change of the size of a preview view kept the text at the top of the
// area where it can be read, and the view has not been scrolled since.
BOOL TSPreviewSizeChangeKeptText(PDFView *view);

// Tells that the program, not the user, scrolled a preview view while its size changed, as the
// split divider does to keep the top of each part: once the views are laid out, the text kept
// by the last change of the size still goes to the top of the area where it can be read.
void TSPreviewPlaceSetByProgram(PDFView *view);

// Called by a preview view after it was laid out: the part of the band under the toolbar that
// lies over it is noted for the next change of its size.
void TSPreviewViewDidLayout(PDFView *view);

// Tells that the program put a chosen place in a preview view, as when the parts of a split
// window are switched: the text kept by the last change of the size is not put back.
void TSPreviewPlaceChosenByProgram(PDFView *view);

// The scroll position of a clip view for the bounds, as far as the document allows; only
// the vertical position is limited. PDFKit's clip view answers a place one scroller
// higher in the document when AppKit lays the scrollers over the content, as it does in a
// narrow view on macOS 26 (#53), so a place put back through it stayed where PDFKit had
// moved it. Only its answers at the ends of the document are used.
static inline NSPoint TSPreviewConstrainedOrigin(NSClipView *clip, NSRect bounds)
{
    NSRect documentRect = clip.documentRect, lower = bounds, upper = bounds;
    NSEdgeInsets insets = clip.contentInsets;
    CGFloat margin = NSHeight(bounds) + fabs(insets.top) + fabs(insets.bottom) + 1;
    lower.origin.y = NSMinY(documentRect) - margin;
    upper.origin.y = NSMaxY(documentRect) + margin;
    CGFloat minimum = NSMinY([clip constrainBoundsRect:lower]);
    CGFloat maximum = NSMinY([clip constrainBoundsRect:upper]);
    NSPoint origin = bounds.origin;
    if (isfinite(minimum) && isfinite(maximum))
        origin.y = maximum < minimum ? minimum : fmin(fmax(origin.y, minimum), maximum);
    return origin;
}

NS_ASSUME_NONNULL_END
