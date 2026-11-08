// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefFooterController.h"
#import "TSPreferences.h"
@implementation TSPrefFooterController
- (instancetype)init { return [super initWithNibName:@"SettingsFooter" bundle:nil]; }
- (IBAction)setDefaults:(id)sender { [self.preferences setDefaults:sender]; }
@end
