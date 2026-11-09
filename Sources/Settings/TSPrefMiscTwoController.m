// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefMiscTwoController.h"
#import "TSPreferences.h"
@implementation TSPrefMiscTwoController
- (instancetype)init { return [super initWithNibName:@"SettingsMiscTwo" bundle:nil]; }
- (IBAction)XMLChapterButtonChanged:(id)sender { [self.preferences XMLChapterButtonChanged:sender]; }
- (IBAction)XMLConclusionButtonChanged:(id)sender { [self.preferences XMLConclusionButtonChanged:sender]; }
- (IBAction)XMLExercisesButtonChanged:(id)sender { [self.preferences XMLExercisesButtonChanged:sender]; }
- (IBAction)XMLFigureButtonChanged:(id)sender { [self.preferences XMLFigureButtonChanged:sender]; }
- (IBAction)XMLIntroductionButtonChanged:(id)sender { [self.preferences XMLIntroductionButtonChanged:sender]; }
- (IBAction)XMLMarkButtonChanged:(id)sender { [self.preferences XMLMarkButtonChanged:sender]; }
- (IBAction)XMLProjectButtonChanged:(id)sender { [self.preferences XMLProjectButtonChanged:sender]; }
- (IBAction)XMLSectionButtonChanged:(id)sender { [self.preferences XMLSectionButtonChanged:sender]; }
- (IBAction)XMLSubsectionButtonChanged:(id)sender { [self.preferences XMLSubsectionButtonChanged:sender]; }
- (IBAction)XMLSubsubsectionButtonChanged:(id)sender { [self.preferences XMLSubsubsectionButtonChanged:sender]; }
- (IBAction)XMLTableButtonChanged:(id)sender { [self.preferences XMLTableButtonChanged:sender]; }
- (IBAction)alternateEngineChanged:(id)sender { [self.preferences alternateEngineChanged:sender]; }
- (IBAction)convertUTFPressed:(id)sender { [self.preferences convertUTFPressed:sender]; }
- (IBAction)distillerChanged:(id)sender { [self.preferences distillerChanged:sender]; }
- (IBAction)latexScriptProgramChanged:(id)sender { [self.preferences latexScriptProgramChanged:sender]; }
- (IBAction)miniaturizeRootFilePressed:(id)sender { [self.preferences miniaturizeRootFilePressed:sender]; }
- (IBAction)openRootFilePressed:(id)sender { [self.preferences openRootFilePressed:sender]; }
- (IBAction)ptexUtfOutputPressed:(id)sender { [self.preferences ptexUtfOutputPressed:sender]; }
- (IBAction)sparkleAutomaticCheck:(id)sender { [self.preferences sparkleAutomaticCheck:sender]; }
- (IBAction)sparkleInterval:(id)sender { [self.preferences sparkleInterval:sender]; }
- (IBAction)texScriptProgramChanged:(id)sender { [self.preferences texScriptProgramChanged:sender]; }
@end
