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
/// The programs that the TeX bin directory must contain for the profile.
FOUNDATION_EXPORT NSArray<NSString *> *TSEngineProfileRequiredPrograms(TSEngineProfile profile, BOOL latexmk);
/// Whether the profile converts PostScript with Ghostscript.
FOUNDATION_EXPORT BOOL TSEngineProfileNeedsGhostscript(TSEngineProfile profile);
/// The profile whose typesetting commands the settings have now, or TSEngineProfileNone.
/// *latexmk tells which of its two forms they match.
FOUNDATION_EXPORT TSEngineProfile TSEngineProfileMatchingSettings(NSUserDefaults *defaults, BOOL * _Nullable latexmk);
/// Whether the settings run latexmk now: the form of the matching profile, or, for commands
/// typed by hand, whether the LaTeX command of the default method starts with latexmk.
FOUNDATION_EXPORT BOOL TSEngineProfileSettingsUseLatexmk(NSUserDefaults *defaults);
/// The profile chosen beforehand on first launch for these preferred languages.
FOUNDATION_EXPORT TSEngineProfile TSEngineProfileForLanguages(NSArray<NSString *> *languages);
/// Of the TeX installations found (newest first), the newest that contains every required
/// program, else the newest. *missing lists the required programs that the chosen one lacks.
FOUNDATION_EXPORT NSDictionary * _Nullable TSEngineProfileTeXCandidate(NSArray<NSDictionary *> *candidates, NSArray<NSString *> *required,
    BOOL (^contains)(NSString *directory, NSArray<NSString *> *programs), NSArray<NSString *> * _Nullable * _Nullable missing);
/// Writes the values, holding back the observers of single keys until all are stored, and
/// returns the keys whose values changed.
FOUNDATION_EXPORT NSSet<TSPreferenceKey> *TSEngineProfileApply(NSUserDefaults *defaults, NSDictionary<TSPreferenceKey, id> *values);

// Runtime observers defer their work until a complete profile has been stored.
FOUNDATION_EXPORT BOOL TSPreferenceProfileIsApplying(void);
FOUNDATION_EXPORT TSPreferenceKey const TSSettingsSelectedCategoryKey;
NS_ASSUME_NONNULL_END
