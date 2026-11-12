// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSMacroContentKind) {
	TSMacroContentKindTeX = 0,
	TSMacroContentKindAppleScript,
	TSMacroContentKindAppleScriptDirect,
};

// How a macro's contents are run. AppleScript macros begin with "--applescript"
// or "-- applescript" (in any case); "direct" after that runs the script in
// TeXShop itself instead of through ScriptRunner. Anything else is TeX text.
FOUNDATION_EXPORT TSMacroContentKind TSMacroContentKindForString(NSString * _Nullable string);

NS_ASSUME_NONNULL_END
