// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Whether this launch replaces the whole settings domain with the factory defaults (TSAppDelegate,
/// -[TSPreferences registerFactoryDefaults]): TSHasBeenUsed is not true or TetexBinPath is missing. The one place that
/// decides who is a new user; the migrations of earlier users run only where it says NO.
FOUNDATION_EXPORT BOOL TSPreferencesNeedFactoryReset(NSUserDefaults *defaults);

/// For a user whose settings were kept (TSPreferencesNeedFactoryReset said NO): `savedSettings` is the persistent
/// domain read before anything was written. Once, at the first launch of 6.00, every earlier user moves to the
/// Advanced Find panel, whatever find method they had or if they never chose one. Those who came from the OgreKit
/// Find Panel write replacements the OgreKit way (`\1`), unless they already chose a way in the Advanced Find panel.
/// FindMethodSwitchedToAdvancedFind marks the switch as done, so a method chosen afterwards stays; the factory
/// defaults carry the mark, so new users and a reset to the factory settings never switch.
FOUNDATION_EXPORT void TSPreferencesMigrateEarlierUser(NSUserDefaults *defaults, NSDictionary<NSString *, id> *savedSettings);

NS_ASSUME_NONNULL_END
