// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategory.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSSettingsSidebarRow : NSObject
+ (NSTableCellView *)cellForCategory:(TSSettingsCategory *)category title:(NSString *)title;
@end
NS_ASSUME_NONNULL_END
