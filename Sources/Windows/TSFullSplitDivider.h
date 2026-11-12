// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSFullSplitDivider.h
 *
 * In the window that shows the source and the Preview side by side, remembers
 * how wide the source is, as a share of the window, whenever the user drags the
 * divider. The next time such a window opens, the divider goes back there. One
 * share is kept for all documents, and it belongs to the source whichever side
 * the source is on.
 */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSFullSplitDivider : NSObject

// splitView holds the two sides; sourceView is the source, or a view inside it.
- (instancetype)initWithSplitView:(NSSplitView *)splitView sourceView:(NSView *)sourceView;
- (instancetype)init NS_UNAVAILABLE;

// Moves the divider to the remembered share. Nothing happens before the user
// has dragged a divider for the first time.
- (void)restore;

// A remembered share kept away from the edges, or 0 when there is none.
+ (CGFloat)usableFraction:(double)fraction;

@end

NS_ASSUME_NONNULL_END
