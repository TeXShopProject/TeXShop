// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferenceLaunch.h"
#import "TSFindInterface.h"
#import "TSAdvancedFindSettings.h"
#import "globals.h"

BOOL TSPreferencesNeedFactoryReset(NSUserDefaults *defaults)
{
    return [defaults boolForKey:TSHasBeenUsedKey] == NO || [defaults objectForKey:TetexBinPath] == nil;
}

/// A stored number or string as NSUserDefaults reads it (integerForKey:, boolForKey:); anything else is missing.
static id TSSavedScalar(NSDictionary<NSString *, id> *savedSettings, NSString *key)
{
    id value = savedSettings[key];
    return [value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class] ? value : nil;
}

/// Values an earlier version could save that no longer apply, replaced at every launch. /usr/texbin cannot exist on the
/// macOS versions TeXShop runs on; MacTeX's link is /Library/TeX/texbin. The TeX path is set, not removed: a missing
/// TetexBinPath makes the next launch reset every setting. An empty kpsewhich command or HTML home page is removed, so
/// that the default applies, as when the field is emptied in Settings.
static void TSPreferencesReplaceRetiredValues(NSUserDefaults *defaults, NSDictionary<NSString *, id> *savedSettings)
{
    NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    id binPath = savedSettings[TetexBinPath];
    if ([binPath isKindOfClass:NSString.class] && [[binPath stringByTrimmingCharactersInSet:spaces].stringByStandardizingPath isEqualToString:@"/usr/texbin"])
        [defaults setObject:@"/Library/TeX/texbin" forKey:TetexBinPath];
    for (NSString *key in @[KpsetoolKey, HtmlHomeKey]) {
        id value = savedSettings[key];
        if ([value isKindOfClass:NSString.class] && [value stringByTrimmingCharactersInSet:spaces].length == 0)
            [defaults removeObjectForKey:key];
    }
}

/// Once, at the first launch of 6.00, the Advanced Find panel; see TSPreferencesMigrateEarlierUser.
static void TSPreferencesSwitchToAdvancedFind(NSUserDefaults *defaults, NSDictionary<NSString *, id> *savedSettings)
{
    if ([TSSavedScalar(savedSettings, FindMethodSwitchedToAdvancedFindKey) boolValue])
        return;
    BOOL fromOgreKit = [TSSavedScalar(savedSettings, FindMethodKey) integerValue] == TSFindMethodOgreKit;
    if (fromOgreKit && savedSettings[TSAdvancedFindReplacementSyntaxKey] == nil)
        [defaults setInteger:TSRegexReplacementSyntaxOgreKit forKey:TSAdvancedFindReplacementSyntaxKey];
    [defaults setInteger:TSFindMethodAdvancedPanel forKey:FindMethodKey];
    [defaults setBool:YES forKey:FindMethodSwitchedToAdvancedFindKey];
}

void TSPreferencesMigrateEarlierUser(NSUserDefaults *defaults, NSDictionary<NSString *, id> *savedSettings)
{
    TSPreferencesReplaceRetiredValues(defaults, savedSettings);
    TSPreferencesSwitchToAdvancedFind(defaults, savedSettings);
}
