// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferenceLaunch.h"
#import "TSFindInterface.h"
#import "globals.h"

BOOL TSPreferencesNeedFactoryReset(NSUserDefaults *defaults)
{
    return [defaults boolForKey:TSHasBeenUsedKey] == NO || [defaults objectForKey:TetexBinPath] == nil;
}

void TSPreferencesMigrateEarlierUser(NSUserDefaults *defaults, NSDictionary<NSString *, id> *savedSettings)
{
    if (savedSettings[FindMethodKey] == nil)
        [defaults setInteger:TSFindMethodFindBar forKey:FindMethodKey];
}
