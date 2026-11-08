// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefEditorController : TSPrefPaneController
@property (strong, nullable) IBOutlet NSPopUpButton *FullwidthSpaceCharacterKindPopup NS_SWIFT_NAME(fullwidthSpaceCharacterKindPopup);
@property (strong, nullable) IBOutlet NSPopUpButton *NewLineCharacterKindPopup NS_SWIFT_NAME(newLineCharacterKindPopup);
@property (strong, nullable) IBOutlet NSPopUpButton *SpaceCharacterKindPopup NS_SWIFT_NAME(spaceCharacterKindPopup);
@property (strong, nullable) IBOutlet NSPopUpButton *TabCharacterKindPopup NS_SWIFT_NAME(tabCharacterKindPopup);
@property (strong, nullable) IBOutlet NSButton *alwaysHighlightButton;
@property (strong, nullable) IBOutlet NSButtonCell *autoCompleteButton;
@property (strong, nullable) IBOutlet NSButtonCell *autoSpellCorrectButton;
@property (strong, nullable) IBOutlet NSButton *beepButton;
@property (strong, nullable) IBOutlet NSButtonCell *bibDeskCompleteButton;
@property (strong, nullable) IBOutlet NSButtonCell *editorAddBracketsButton;
@property (strong, nullable) IBOutlet NSButton *flashBackgroundButton;
@property (strong, nullable) IBOutlet NSButton *highlightContentButton;
@property (strong, nullable) IBOutlet NSButtonCell *lineNumberButton;
@property (strong, nullable) IBOutlet NSButtonCell *midEastButton;
@property (strong, nullable) IBOutlet NSButtonCell *parensMatchButton;
@property (strong, nullable) IBOutlet NSButtonCell *selectActivateButton;
@property (strong, nullable) IBOutlet NSButton *showFullwidthSpaceCharacterButton;
@property (strong, nullable) IBOutlet NSButton *showIndicatorForMoveButton;
@property (strong, nullable) IBOutlet NSButton *showInvisibleCharactersButton;
@property (strong, nullable) IBOutlet NSButton *showNewLineCharacterButton;
@property (strong, nullable) IBOutlet NSButton *showSpaceCharacterButton;
@property (strong, nullable) IBOutlet NSButton *showTabCharacterButton;
@property (strong, nullable) IBOutlet NSButtonCell *spellCheckButton;
@property (strong, nullable) IBOutlet NSButtonCell *syntaxColorButton;
@property (strong, nullable) IBOutlet NSButtonCell *makeatletterButton;
@property (strong, nullable) IBOutlet NSButtonCell *expl3SyntaxColorButton;
@property (strong, nullable) IBOutlet NSButton *syntaxColorLineButton;
@property (strong, nullable) IBOutlet NSButton *tabIndentButton;
@property (strong, nullable) IBOutlet NSButtonCell *tagMenuButton;
@property (strong, nullable) IBOutlet NSMatrix *wrapMatrix;
@property (strong, nullable) IBOutlet NSTextField *firstParagraphIndentField;
@property (strong, nullable) IBOutlet NSTextField *interlineSpacingField;
@property (strong, nullable) IBOutlet NSTextField *remainingParagraphIndentField;
@property (strong, nullable) IBOutlet NSTextField *tabIndentField;
@end
NS_ASSUME_NONNULL_END
