// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategory.h"
#import "TSPreferenceProfile.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSSettingsStateStore : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (TSSettingsCategoryID)selectedCategoryInIdentifiers:(NSArray<TSSettingsCategoryID> *)identifiers;
- (void)saveSelectedCategory:(TSSettingsCategoryID)identifier;
@end
NS_ASSUME_NONNULL_END
