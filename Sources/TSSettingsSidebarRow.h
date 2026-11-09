// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategory.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSSettingsSidebarRow : NSObject
+ (CGFloat)heightForTitle:(NSString *)title cellWidth:(CGFloat)width;
+ (NSTableCellView *)cellForCategory:(TSSettingsCategory *)category title:(NSString *)title;
+ (CGFloat)heightForSearchTitle:(NSString *)title categoryTitle:(NSString *)categoryTitle cellWidth:(CGFloat)width;
+ (NSTableCellView *)cellForSearchTitle:(NSString *)title categoryTitle:(NSString *)categoryTitle;
@end
NS_ASSUME_NONNULL_END
