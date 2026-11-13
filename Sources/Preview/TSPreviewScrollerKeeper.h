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

NS_ASSUME_NONNULL_END
