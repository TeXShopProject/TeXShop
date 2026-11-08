// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefConsoleController.h"
#import "TSPreferences.h"
@implementation TSPrefConsoleController
- (void)loadView
{
    [super loadView];
    self.consoleFontTextField.accessibilityIdentifier = @"settings.user-data";
}

- (instancetype)init { return [super initWithNibName:@"SettingsConsole" bundle:nil]; }
- (IBAction)MacroPressed:(id)sender { [self.preferences MacroPressed:sender]; }
- (IBAction)changeConsoleFont:(id)sender { [self.preferences changeConsoleFont:sender]; }
- (IBAction)changeConsoleResize:(id)sender { [self.preferences changeConsoleResize:sender]; }
- (IBAction)consoleBehaviorChanged:(id)sender { [self.preferences consoleBehaviorChanged:sender]; }
- (IBAction)consoleWindowPosChanged:(id)sender { [self.preferences consoleWindowPosChanged:sender]; }
- (IBAction)consoleWindowPosDefault:(id)sender { [self.preferences consoleWindowPosDefault:sender]; }
@end
