// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

// Runtime observers defer their work until a complete profile has been stored.
FOUNDATION_EXPORT BOOL TSPreferenceProfileIsApplying(void);
FOUNDATION_EXPORT NSSet<NSString *> *TSKnownPreferenceKeys(void);
FOUNDATION_EXPORT BOOL TSPreferenceProfilePreservesKey(NSString *key);

@interface TSPreferenceProfile : NSObject
@property (readonly, copy) NSDictionary<NSString *, id> *updates;
@property (readonly, copy) NSSet<NSString *> *removals;
@property (readonly, copy) NSString *enginePath;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (nullable instancetype)initWithProfile:(NSDictionary<NSString *, id> *)profile
                           documentFont:(NSData *)fontData NS_DESIGNATED_INITIALIZER;
- (void)applyToDefaults:(NSUserDefaults *)defaults;
@end
NS_ASSUME_NONNULL_END
