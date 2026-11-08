// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
@interface TSSettingsGroupStyle : NSObject
+ (CGFloat)cornerRadiusForMajorVersion:(NSInteger)version;
+ (void)applyToBox:(NSBox *)box;
@end
@interface TSPrefPaneLayout : NSObject
+ (void)arrangeView:(NSView *)view;
@end
NS_ASSUME_NONNULL_END
