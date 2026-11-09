// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategory.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSSettingsCategoryList : NSObject
@property (copy, readonly) NSArray<TSSettingsCategory *> *categories;
@property (copy, readonly) NSArray<TSSettingsCategoryID> *identifiers;
+ (instancetype)standardList;
- (instancetype)initWithCategories:(NSArray<TSSettingsCategory *> *)categories NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (nullable TSSettingsCategory *)categoryForIdentifier:(TSSettingsCategoryID)identifier;
@end
NS_ASSUME_NONNULL_END
