// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSPreferenceKey.h"
NS_ASSUME_NONNULL_BEGIN

// Runtime observers defer their work until a complete profile has been stored.
FOUNDATION_EXPORT BOOL TSPreferenceProfileIsApplying(void);
FOUNDATION_EXPORT NSSet<TSPreferenceKey> *TSKnownPreferenceKeys(void);
FOUNDATION_EXPORT BOOL TSPreferenceProfilePreservesKey(TSPreferenceKey key);

@interface TSPreferenceProfile : NSObject
@property (readonly, copy) NSDictionary<NSString *, id> *updates;
@property (readonly, copy) NSSet<NSString *> *removals;
@property (readonly, copy) NSString *enginePath;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (nullable instancetype)initWithProfile:(NSDictionary<NSString *, id> *)profile
                           documentFont:(NSData *)fontData;
- (nullable instancetype)initWithProfile:(NSDictionary<NSString *, id> *)profile
                           documentFont:(NSData *)fontData
                     registeredDefaults:(NSDictionary<NSString *, id> *)registeredDefaults NS_DESIGNATED_INITIALIZER;
- (void)applyToDefaults:(NSUserDefaults *)defaults;
@end
FOUNDATION_EXPORT TSPreferenceKey const TSSettingsSelectedCategoryKey;
NS_ASSUME_NONNULL_END
