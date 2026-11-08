// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefSourceController.h"
#import "TSPreferences.h"
@implementation TSPrefSourceController
- (instancetype)init { return [super initWithNibName:@"SettingsSource" bundle:nil]; }
- (IBAction)changeDocumentFont:(id)sender { [self.preferences changeDocumentFont:sender]; }
- (IBAction)commandCompletionChanged:(id)sender { [self.preferences commandCompletionChanged:sender]; }
- (IBAction)currentDocumentWindowPosDefault:(id)sender { [self.preferences currentDocumentWindowPosDefault:sender]; }
- (IBAction)dictionaryPressed:(id)sender { [self.preferences dictionaryPressed:sender]; }
- (IBAction)editSpellingExclusions:(id)sender { [self.preferences editSpellingExclusions:sender]; }
- (IBAction)emptyButtonPressed:(id)sender { [self.preferences emptyButtonPressed:sender]; }
- (IBAction)encodingChanged:(id)sender { [self.preferences encodingChanged:sender]; }
- (IBAction)externalEditorButtonPressed:(id)sender { [self.preferences externalEditorButtonPressed:sender]; }
- (IBAction)findPanelChanged:(id)sender { [self.preferences findPanelChanged:sender]; }
- (IBAction)highlightChanged:(id)sender { [self.preferences highlightChanged:sender]; }
- (IBAction)lineSizeChanged:(id)sender { [self.preferences lineSizeChanged:sender]; }
- (IBAction)openAsTabsChanged:(id)sender { [self.preferences openAsTabsChanged:sender]; }
- (IBAction)sourceWindowPosChanged:(id)sender { [self.preferences sourceWindowPosChanged:sender]; }
- (IBAction)spellCheckCommandPressed:(id)sender { [self.preferences spellCheckCommandPressed:sender]; }
- (IBAction)spellCheckCommentPressed:(id)sender { [self.preferences spellCheckCommentPressed:sender]; }
- (IBAction)spellCheckParameterPressed:(id)sender { [self.preferences spellCheckParameterPressed:sender]; }
- (IBAction)texAwareSpellCheckPressed:(id)sender { [self.preferences texAwareSpellCheckPressed:sender]; }
@end
