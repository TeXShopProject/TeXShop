// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefTypesettingController.h"
#import "TSPreferences.h"
@implementation TSPrefTypesettingController
- (instancetype)init { return [super initWithNibName:@"SettingsTypesetting" bundle:nil]; }
- (IBAction)afterTypesettingChanged:(id)sender { [self.preferences afterTypesettingChanged:sender]; }
- (IBAction)defaultProgramChanged:(id)sender { [self.preferences defaultProgramChanged:sender]; }
- (IBAction)defaultScriptChanged:(id)sender { [self.preferences defaultScriptChanged:sender]; }
- (IBAction)saveRelatedButtonPressed:(id)sender { [self.preferences saveRelatedButtonPressed:sender]; }
- (IBAction)syncChanged:(id)sender { [self.preferences syncChanged:sender]; }
- (IBAction)syncTabButtonPressed:(id)sender { [self.preferences syncTabButtonPressed:sender]; }
- (IBAction)useTransparencyPressed:(id)sender { [self.preferences useTransparencyPressed:sender]; }
@end
