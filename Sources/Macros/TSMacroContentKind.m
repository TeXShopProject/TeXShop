// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSMacroContentKind.h"

static BOOL TSMacroContentHasPrefix(NSString *string, NSString *prefix)
{
	NSUInteger length = [prefix length];
	return [string length] >= length
		&& [[[string substringToIndex: length] lowercaseString] isEqualToString: prefix];
}

TSMacroContentKind TSMacroContentKindForString(NSString *string)
{
	if ([string length] < 14 ||
		(!TSMacroContentHasPrefix(string, @"--applescript")
		 && !TSMacroContentHasPrefix(string, @"-- applescript")))
		return TSMacroContentKindTeX;
	if (TSMacroContentHasPrefix(string, @"--applescript direct")
		|| TSMacroContentHasPrefix(string, @"-- applescript direct"))
		return TSMacroContentKindAppleScriptDirect;
	return TSMacroContentKindAppleScript;
}
