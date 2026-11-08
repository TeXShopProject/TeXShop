// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferences.h"

// Nullability applies only to the live-settings API, not the legacy nib outlets.
NS_ASSUME_NONNULL_BEGIN
@interface TSPreferences ()
- (void)finishPreferencesForTermination;
- (void)showPreferenceError:(NSString *)message;
@property (copy, nullable) NSDictionary<NSString *, id> *lastSavedEditingColors;
@end
NS_ASSUME_NONNULL_END
