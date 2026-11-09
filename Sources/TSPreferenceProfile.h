// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSPreferenceKey.h"
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSPreferenceProfileTag) {
    TSPreferenceProfileFactory = 1,
    TSPreferenceProfileUpTeXPtex2pdf = 2,
    TSPreferenceProfileUpTeXLatexmk = 3,
    TSPreferenceProfileUpTeXScript = 4,
    TSPreferenceProfilePTeXPtex2pdf = 5,
    TSPreferenceProfilePTeXLatexmk = 6,
    TSPreferenceProfilePTeXScript = 7,
    TSPreferenceProfilePTeXShiftJIS = 8,
    TSPreferenceProfilePTeXEUC = 9,
};

static inline NSString * _Nullable TSPreferenceProfileNameForTag(TSPreferenceProfileTag tag) {
    NSDictionary<NSNumber *, NSString *> *names = @{
        @(TSPreferenceProfileFactory): @"FactoryDefaults",
        @(TSPreferenceProfileUpTeXPtex2pdf): @"Defaults_upTeX_ptex2pdf",
        @(TSPreferenceProfileUpTeXLatexmk): @"Defaults_upTeX_latexmk",
        @(TSPreferenceProfileUpTeXScript): @"Defaults_upTeX_script",
        @(TSPreferenceProfilePTeXPtex2pdf): @"Defaults_pTeX_ptex2pdf",
        @(TSPreferenceProfilePTeXLatexmk): @"Defaults_pTeX_latexmk",
        @(TSPreferenceProfilePTeXScript): @"Defaults_pTeX_script",
        @(TSPreferenceProfilePTeXShiftJIS): @"Defaults_pTeX_sjis",
        @(TSPreferenceProfilePTeXEUC): @"Defaults_pTeX_euc"
    };
    return names[@(tag)];
}

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
