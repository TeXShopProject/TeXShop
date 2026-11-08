// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefEditorController.h"
#import "TSPreferences.h"
@implementation TSPrefEditorController
- (instancetype)init { return [super initWithNibName:@"SettingsEditor" bundle:nil]; }
- (IBAction)autoCompletePressed:(id)sender { [self.preferences autoCompletePressed:sender]; }
- (IBAction)bibDeskCompletePressed:(id)sender { [self.preferences bibDeskCompletePressed:sender]; }
- (IBAction)editorAddBracketsPressed:(id)sender { [self.preferences editorAddBracketsPressed:sender]; }
- (IBAction)expl3SyntaxColorPressed:(id)sender { [self.preferences expl3SyntaxColorPressed:sender]; }
- (IBAction)firstParagraphIndentPressed:(id)sender { [self.preferences firstParagraphIndentPressed:sender]; }
- (IBAction)highlightChanged:(id)sender { [self.preferences highlightChanged:sender]; }
- (IBAction)interlineSpacingPressed:(id)sender { [self.preferences interlineSpacingPressed:sender]; }
- (IBAction)invisibleCharacterChanged:(id)sender { [self.preferences invisibleCharacterChanged:sender]; }
- (IBAction)lineNumberButtonPressed:(id)sender { [self.preferences lineNumberButtonPressed:sender]; }
- (IBAction)makeatletterChanged:(id)sender { [self.preferences makeatletterChanged:sender]; }
- (IBAction)midEastButtonPressed:(id)sender { [self.preferences midEastButtonPressed:sender]; }
- (IBAction)parensMatchPressed:(id)sender { [self.preferences parensMatchPressed:sender]; }
- (IBAction)remainingParagraphIndentPressed:(id)sender { [self.preferences remainingParagraphIndentPressed:sender]; }
- (IBAction)selectActivatePressed:(id)sender { [self.preferences selectActivatePressed:sender]; }
- (IBAction)showInvisibleCharacterButtonPressed:(id)sender { [self.preferences showInvisibleCharacterButtonPressed:sender]; }
- (IBAction)spellCheckPressed:(id)sender { [self.preferences spellCheckPressed:sender]; }
- (IBAction)spellCorrectPressed:(id)sender { [self.preferences spellCorrectPressed:sender]; }
- (IBAction)syntaxColorLinePressed:(id)sender { [self.preferences syntaxColorLinePressed:sender]; }
- (IBAction)syntaxColorPressed:(id)sender { [self.preferences syntaxColorPressed:sender]; }
- (IBAction)tabIndentPressed:(id)sender { [self.preferences tabIndentPressed:sender]; }
- (IBAction)tagMenuButtonPressed:(id)sender { [self.preferences tagMenuButtonPressed:sender]; }
- (IBAction)useTabPressed:(id)sender { [self.preferences useTabPressed:sender]; }
- (IBAction)wrapPanelChanged:(id)sender { [self.preferences wrapPanelChanged:sender]; }
@end
