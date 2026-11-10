// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefThemesController.h"
#import "TSPreferences.h"
@implementation TSPrefThemesController
- (void)loadView
{
    [super loadView];
    self.DarkStyle.accessibilityIdentifier = @"settings.user-data";
    self.EditingStyle.accessibilityIdentifier = @"settings.user-data";
    self.LiteStyle.accessibilityIdentifier = @"settings.user-data";
}

- (instancetype)init { return [super initWithNibName:@"SettingsThemes" bundle:nil]; }
- (IBAction)ConsoleAlphaChanged:(id)sender { [self.preferences ConsoleAlphaChanged:sender]; }
- (IBAction)ConsoleBackgroundColorChanged:(id)sender { [self.preferences ConsoleBackgroundColorChanged:sender]; }
- (IBAction)ConsoleTextColorChanged:(id)sender { [self.preferences ConsoleTextColorChanged:sender]; }
- (IBAction)EditingStyleChoice:(id)sender { [self.preferences EditingStyleChoice:sender]; }
- (IBAction)EditorFlashChanged:(id)sender { [self.preferences EditorFlashChanged:sender]; }
- (IBAction)EditorHighlightBracesChanged:(id)sender { [self.preferences EditorHighlightBracesChanged:sender]; }
- (IBAction)EditorHighlightContentChanged:(id)sender { [self.preferences EditorHighlightContentChanged:sender]; }
- (IBAction)EditorInvisibleCharChanged:(id)sender { [self.preferences EditorInvisibleCharChanged:sender]; }
- (IBAction)EditorHighlightZenkakuSymbolChanged:(id)sender { [self.preferences EditorHighlightZenkakuSymbolChanged:sender]; }
- (IBAction)EditorHighlightZenkakuSymbolBackgroundChanged:(id)sender { [self.preferences EditorHighlightZenkakuSymbolBackgroundChanged:sender]; }
- (IBAction)EditorReverseSyncChanged:(id)sender { [self.preferences EditorReverseSyncChanged:sender]; }
- (IBAction)EntryColorChanged:(id)sender { [self.preferences EntryColorChanged:sender]; }
- (IBAction)FootnoteColorChanged:(id)sender { [self.preferences FootnoteColorChanged:sender]; }
- (IBAction)ImageBackgroundChanged:(id)sender { [self.preferences ImageBackgroundChanged:sender]; }
- (IBAction)ImageForegroundChanged:(id)sender { [self.preferences ImageForegroundChanged:sender]; }
- (IBAction)LogBackgroundColorChanged:(id)sender { [self.preferences LogBackgroundColorChanged:sender]; }
- (IBAction)LogTextColorChanged:(id)sender { [self.preferences LogTextColorChanged:sender]; }
- (IBAction)NewStyleFromPrefs:(id)sender { [self.preferences NewStyleFromPrefs:sender]; }
- (IBAction)PreviewAlphaChanged:(id)sender { [self.preferences PreviewAlphaChanged:sender]; }
- (IBAction)PreviewBackgroundColorChanged:(id)sender { [self.preferences PreviewBackgroundColorChanged:sender]; }
- (IBAction)PreviewDirectSyncChanged:(id)sender { [self.preferences PreviewDirectSyncChanged:sender]; }
- (IBAction)SaveNewStyle:(id)sender { [self.preferences SaveNewStyle:sender]; }
- (IBAction)SourceAlphaChanged:(id)sender { [self.preferences SourceAlphaChanged:sender]; }
- (IBAction)SourceBackgroundColorChanged:(id)sender { [self.preferences SourceBackgroundColorChanged:sender]; }
- (IBAction)SourceInsertionPointColorChanged:(id)sender { [self.preferences SourceInsertionPointColorChanged:sender]; }
- (IBAction)SourceTextColorChanged:(id)sender { [self.preferences SourceTextColorChanged:sender]; }
- (IBAction)SyntaxCommandColorChanged:(id)sender { [self.preferences SyntaxCommandColorChanged:sender]; }
- (IBAction)SyntaxCommentColorChanged:(id)sender { [self.preferences SyntaxCommentColorChanged:sender]; }
- (IBAction)SyntaxIndexColorChanged:(id)sender { [self.preferences SyntaxIndexColorChanged:sender]; }
- (IBAction)SyntaxMarkerColorChanged:(id)sender { [self.preferences SyntaxMarkerColorChanged:sender]; }
- (IBAction)XMLCommentChanged:(id)sender { [self.preferences XMLCommentChanged:sender]; }
- (IBAction)XMLParameterChanged:(id)sender { [self.preferences XMLParameterChanged:sender]; }
- (IBAction)XMLSpecialChanged:(id)sender { [self.preferences XMLSpecialChanged:sender]; }
- (IBAction)XMLTagChanged:(id)sender { [self.preferences XMLTagChanged:sender]; }
- (IBAction)XMLValueChanged:(id)sender { [self.preferences XMLValueChanged:sender]; }
- (IBAction)explFunctionColorChanged:(id)sender { [self.preferences explFunctionColorChanged:sender]; }
- (IBAction)explIntenseFunctionColorChanged:(id)sender { [self.preferences explIntenseFunctionColorChanged:sender]; }
- (IBAction)explIntenseVariableColorChanged:(id)sender { [self.preferences explIntenseVariableColorChanged:sender]; }
- (IBAction)explVariableColorChanged:(id)sender { [self.preferences explVariableColorChanged:sender]; }
- (IBAction)explmsgColorChanged:(id)sender { [self.preferences explmsgColorChanged:sender]; }
- (IBAction)explmykeyArgumentColorChanged:(id)sender { [self.preferences explmykeyArgumentColorChanged:sender]; }
- (IBAction)explmykeyColorChanged:(id)sender { [self.preferences explmykeyColorChanged:sender]; }
- (IBAction)markerCurlyColorChanged:(id)sender { [self.preferences markerCurlyColorChanged:sender]; }
- (IBAction)markerParenColorChanged:(id)sender { [self.preferences markerParenColorChanged:sender]; }
- (IBAction)markerSquareColorChanged:(id)sender { [self.preferences markerSquareColorChanged:sender]; }
- (IBAction)themeSelectionChanged:(id)sender { [self.preferences themeSelectionChanged:sender]; }
@end
