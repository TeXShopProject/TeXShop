// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategory.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSSettingsNavigationHistory : NSObject
@property (copy, readonly, nullable) TSSettingsCategoryID currentIdentifier;
@property (copy, readonly, nullable) TSSettingsCategoryID backIdentifier;
@property (copy, readonly, nullable) TSSettingsCategoryID forwardIdentifier;
@property (readonly) NSUInteger count;
- (void)resetWithIdentifier:(TSSettingsCategoryID )identifier;
- (void)visitIdentifier:(TSSettingsCategoryID )identifier;
- (void)goBack;
- (void)goForward;
@end
NS_ASSUME_NONNULL_END
