// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSPreviewSplitDivider.h
 *
 * When the divider of a Preview window split into a top and a bottom part is
 * dragged, each part keeps the text at its top edge where it is: the top part
 * shows more or less below it, and the text of the bottom part moves with the
 * divider, like a sheet of paper laid over the lower part of a page.
 */

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSPreviewSplitDivider : NSObject

- (instancetype)initWithSplitView:(NSSplitView *)splitView;
- (instancetype)init NS_UNAVAILABLE;

// Whether the resize described by a split view notification comes from the user
// dragging a divider, and not from a window resize or from the program.
+ (BOOL)isDividerDrag:(NSNotification *)notification;

@end

NS_ASSUME_NONNULL_END
