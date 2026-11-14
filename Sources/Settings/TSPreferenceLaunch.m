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

void TSPreferencesMigrateEarlierUser(NSUserDefaults *defaults, NSDictionary<NSString *, id> *savedSettings)
{
    if ([TSSavedScalar(savedSettings, FindMethodSwitchedToAdvancedFindKey) boolValue])
        return;
    BOOL fromOgreKit = [TSSavedScalar(savedSettings, FindMethodKey) integerValue] == TSFindMethodOgreKit;
    if (fromOgreKit && savedSettings[TSAdvancedFindReplacementSyntaxKey] == nil)
        [defaults setInteger:TSRegexReplacementSyntaxOgreKit forKey:TSAdvancedFindReplacementSyntaxKey];
    [defaults setInteger:TSFindMethodAdvancedPanel forKey:FindMethodKey];
    [defaults setBool:YES forKey:FindMethodSwitchedToAdvancedFindKey];
}
