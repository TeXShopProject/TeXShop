// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Whether this launch replaces the whole settings domain with the factory defaults (TSAppDelegate,
/// -[TSPreferences registerFactoryDefaults]): TSHasBeenUsed is not true or TetexBinPath is missing. The one place that
/// decides who is a new user; the migrations of earlier users run only where it says NO.
FOUNDATION_EXPORT BOOL TSPreferencesNeedFactoryReset(NSUserDefaults *defaults);

/// For a user whose settings were kept (TSPreferencesNeedFactoryReset said NO): `savedSettings` is the persistent
/// domain read before anything was written. Users from before the Advanced Find panel who never chose a find method
/// were on the factory default of that time, the find bar, and keep it; new users start with the Advanced Find panel
/// (FactoryDefaults.plist).
FOUNDATION_EXPORT void TSPreferencesMigrateEarlierUser(NSUserDefaults *defaults, NSDictionary<NSString *, id> *savedSettings);

NS_ASSUME_NONNULL_END
