// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSPreferenceKey.h"
NS_ASSUME_NONNULL_BEGIN

// An engine profile sets the typesetting commands of one kind of TeX engine and, for the
// Japanese engines, the settings that go with them. It writes only the keys of its own
// table (TSEngineProfileValues); every other setting is left as it is.
typedef NS_ENUM(NSInteger, TSEngineProfile) {
    TSEngineProfileNone = 0,
    TSEngineProfilePdfLaTeX = 1,
    TSEngineProfileXeLaTeX = 2,
    TSEngineProfileLuaLaTeX = 3,
    TSEngineProfileLaTeXDvipdfmx = 4,
    TSEngineProfileLuaLaTeXJapanese = 5,
    TSEngineProfilePLaTeXDvipdfmx = 6,
    TSEngineProfileUpLaTeXDvipdfmx = 7,
    TSEngineProfileLaTeXDvipsGhostscript = 8,
};

/// The profiles in menu order, in sections: Western, Japanese, and Other. The Other section
/// is not offered on first launch.
FOUNDATION_EXPORT NSArray<NSArray<NSNumber *> *> *TSEngineProfileMenuSections(void);
/// The name shown in menus; nil for TSEngineProfileNone or an unknown value.
FOUNDATION_EXPORT NSString * _Nullable TSEngineProfileTitle(TSEngineProfile profile);
FOUNDATION_EXPORT BOOL TSEngineProfileIsJapanese(TSEngineProfile profile);
/// The keys and values that applying the profile writes. Empty for an unknown profile.
FOUNDATION_EXPORT NSDictionary<TSPreferenceKey, id> *TSEngineProfileValues(TSEngineProfile profile, BOOL latexmk);
/// The profile all of whose values the settings have now, or TSEngineProfileNone (Custom).
/// *latexmk tells which of its two forms they match.
FOUNDATION_EXPORT TSEngineProfile TSEngineProfileMatchingSettings(NSUserDefaults *defaults, BOOL * _Nullable latexmk);
/// Whether the settings run latexmk now: the form of the matching profile, or, for commands
/// typed by hand, whether the LaTeX command of the default method starts with latexmk.
FOUNDATION_EXPORT BOOL TSEngineProfileSettingsUseLatexmk(NSUserDefaults *defaults);
/// Every key that some profile writes, in either form.
FOUNDATION_EXPORT NSArray<TSPreferenceKey> *TSEngineProfileKeys(void);
/// Calls the handler on the main queue, once for a burst of changes, after any key of
/// TSEngineProfileKeys changes in the defaults, also from another process. Stops when released.
@interface TSEngineProfileWatcher : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults handler:(void (^)(void))handler NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end
/// The profile chosen beforehand on first launch for these preferred languages.
FOUNDATION_EXPORT TSEngineProfile TSEngineProfileForLanguages(NSArray<NSString *> *languages);
/// Writes the values, holding back the observers of single keys until all are stored, and
/// returns the keys whose values changed.
FOUNDATION_EXPORT NSSet<TSPreferenceKey> *TSEngineProfileApply(NSUserDefaults *defaults, NSDictionary<TSPreferenceKey, id> *values);
/// The factory engine file was XeLaTeX before 6.00. Whoever already typesets new documents
/// with the factory engine file keeps XeLaTeX. Settings stores the engine file whenever this
/// choice is made, so only an earlier choice has no engine file stored. stored is the
/// persistent domain of the application.
FOUNDATION_EXPORT void TSKeepEarlierFactoryEngineFile(NSUserDefaults *defaults, NSDictionary *stored);

// Runtime observers defer their work until a complete profile has been stored.
FOUNDATION_EXPORT BOOL TSPreferenceProfileIsApplying(void);
FOUNDATION_EXPORT TSPreferenceKey const TSSettingsSelectedCategoryKey;
NS_ASSUME_NONNULL_END
