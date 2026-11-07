// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
@interface TSDockIconController : NSObject
+ (instancetype)sharedController;
- (instancetype)initWithBundle:(NSBundle *)bundle defaults:(NSUserDefaults *)defaults;
- (void)restoreSavedIcon;
- (void)installInPreferences:(NSTabView *)tabs;
@end
