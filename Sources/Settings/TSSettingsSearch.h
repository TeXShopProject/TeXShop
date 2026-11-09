// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSettingsCategory.h"
#import "TSSettingsSearchText.h"
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, TSSettingsSearchWeight) {
    TSSettingsSearchWeightCommand = 10,
    TSSettingsSearchWeightDescription = 20,
    TSSettingsSearchWeightChoice = 30,
    TSSettingsSearchWeightLabel = 50,
    TSSettingsSearchWeightHeading = 60,
    TSSettingsSearchWeightCategory = 100
};
typedef NS_ENUM(NSInteger, TSSettingsSearchBonus) {
    TSSettingsSearchBonusSubstring = 0,
    TSSettingsSearchBonusPrefix = 10,
    TSSettingsSearchBonusExact = 20
};
@interface TSSettingsSearchEntry : NSObject
@property (copy, readonly) TSSettingsCategoryID category;
@property (copy, readonly) NSString *targetIdentifier;
@property (copy, readonly) NSString *text;
@property (copy, readonly) NSString *normalizedText;
@property (readonly) TSSettingsSearchWeight weight;
@property (readonly) BOOL command;
- (instancetype)initWithCategory:(TSSettingsCategoryID)category target:(NSString *)target text:(NSString *)text weight:(TSSettingsSearchWeight)weight command:(BOOL)command NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
@interface TSSettingsSearchResult : NSObject
@property (copy, readonly) TSSettingsCategoryID category;
@property (copy, readonly) NSArray<TSSettingsSearchEntry *> *entries;
@property (copy, readonly) NSString *title;
@property (copy, readonly) NSString *targetIdentifier;
@property (readonly) NSInteger score;
- (instancetype)initWithCategory:(TSSettingsCategoryID)category entries:(NSArray<TSSettingsSearchEntry *> *)entries score:(NSInteger)score NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
@interface TSSettingsSearch : NSObject
@property (copy, readonly) NSArray<TSSettingsSearchEntry *> *entries;
@property (copy, readonly) NSArray<TSSettingsCategoryID> *categoryOrder;
- (instancetype)initWithBundle:(NSBundle *)bundle categoryOrder:(NSArray<TSSettingsCategoryID> *)order commandNames:(NSArray<NSString *> *)names NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (NSArray<TSSettingsSearchResult *> *)resultsForQuery:(NSString *)query;
- (NSString *)categoryDescription:(TSSettingsCategoryID)category;
@end
NS_ASSUME_NONNULL_END
