// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefThemeNameController.h"
#import "TSPreferences.h"
@implementation TSPrefThemeNameController
- (instancetype)init { return [super initWithNibName:@"SettingsThemeName" bundle:nil]; }
- (IBAction)cancelForStylePanel:(id)sender { [self.preferences cancelForStylePanel:sender]; }
- (IBAction)okForStylePanel:(id)sender { [self.preferences okForStylePanel:sender]; }
@end
