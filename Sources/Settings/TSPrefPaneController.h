// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSSettingsCategory.h"
@class TSPreferences;
NS_ASSUME_NONNULL_BEGIN
/// Owns a category's controls; the existing settings coordinator owns persistence.
@interface TSPrefPaneController : NSViewController
@property (weak, nullable) TSPreferences *preferences;
@property (nonatomic, copy, nullable) TSSettingsCategoryID categoryIdentifier;
@property (copy, readonly) NSArray<NSObject *> *nibObjects;
@end
NS_ASSUME_NONNULL_END
