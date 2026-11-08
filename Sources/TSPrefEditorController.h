// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefEditorController : TSPrefPaneController
@property (strong) IBOutlet NSPopUpButton *FullwidthSpaceCharacterKindPopup;
@property (strong) IBOutlet NSPopUpButton *NewLineCharacterKindPopup;
@property (strong) IBOutlet NSPopUpButton *SpaceCharacterKindPopup;
@property (strong) IBOutlet NSPopUpButton *TabCharacterKindPopup;
@property (strong) IBOutlet NSButton *alwaysHighlightButton;
@property (strong) IBOutlet NSButtonCell *autoCompleteButton;
@property (strong) IBOutlet NSButtonCell *autoSpellCorrectButton;
@property (strong) IBOutlet NSButton *beepButton;
@property (strong) IBOutlet NSButtonCell *bibDeskCompleteButton;
@property (strong) IBOutlet NSButtonCell *editorAddBracketsButton;
@property (strong) IBOutlet NSButton *flashBackgroundButton;
@property (strong) IBOutlet NSButton *highlightContentButton;
@property (strong) IBOutlet NSButtonCell *lineNumberButton;
@property (strong) IBOutlet NSButtonCell *midEastButton;
@property (strong) IBOutlet NSButtonCell *parensMatchButton;
@property (strong) IBOutlet NSButtonCell *selectActivateButton;
@property (strong) IBOutlet NSButton *showFullwidthSpaceCharacterButton;
@property (strong) IBOutlet NSButton *showIndicatorForMoveButton;
@property (strong) IBOutlet NSButton *showInvisibleCharactersButton;
@property (strong) IBOutlet NSButton *showNewLineCharacterButton;
@property (strong) IBOutlet NSButton *showSpaceCharacterButton;
@property (strong) IBOutlet NSButton *showTabCharacterButton;
@property (strong) IBOutlet NSButtonCell *spellCheckButton;
@property (strong) IBOutlet NSButtonCell *syntaxColorButton;
@property (strong) IBOutlet NSButtonCell *makeatletterButton;
@property (strong) IBOutlet NSButtonCell *expl3SyntaxColorButton;
@property (strong) IBOutlet NSButton *syntaxColorLineButton;
@property (strong) IBOutlet NSButton *tabIndentButton;
@property (strong) IBOutlet NSButtonCell *tagMenuButton;
@property (strong) IBOutlet NSMatrix *wrapMatrix;
@property (strong) IBOutlet NSTextField *firstParagraphIndentField;
@property (strong) IBOutlet NSTextField *interlineSpacingField;
@property (strong) IBOutlet NSTextField *remainingParagraphIndentField;
@property (strong) IBOutlet NSTextField *tabIndentField;
@end
NS_ASSUME_NONNULL_END
