// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefEnginesController.h"
#import "TSPreferences.h"
@implementation TSPrefEnginesController
- (instancetype)init { return [super initWithNibName:@"SettingsEngines" bundle:nil]; }
- (IBAction)altPathChanged:(id)sender { [self.preferences altPathChanged:sender]; }
- (IBAction)bibTeXengineChanged:(id)sender { [self.preferences bibTeXengineChanged:sender]; }
- (IBAction)defaultEngineCall:(id)sender { [self.preferences defaultEngineCall:sender]; }
- (IBAction)discoverEnginePaths:(id)sender { [self.preferences discoverEnginePaths:sender]; }
- (IBAction)escapeWarningChanged:(id)sender { [self.preferences escapeWarningChanged:sender]; }
- (IBAction)gsBinPathChanged:(id)sender { [self.preferences gsBinPathChanged:sender]; }
- (IBAction)kpsetoolChanged:(id)sender { [self.preferences kpsetoolChanged:sender]; }
- (IBAction)latexGSProgramChanged:(id)sender { [self.preferences latexGSProgramChanged:sender]; }
- (IBAction)latexProgramChanged:(id)sender { [self.preferences latexProgramChanged:sender]; }
- (IBAction)savePSPressed:(id)sender { [self.preferences savePSPressed:sender]; }
- (IBAction)tetexBinPathChanged:(id)sender { [self.preferences tetexBinPathChanged:sender]; }
- (IBAction)texGSProgramChanged:(id)sender { [self.preferences texGSProgramChanged:sender]; }
- (IBAction)texProgramChanged:(id)sender { [self.preferences texProgramChanged:sender]; }
@end
