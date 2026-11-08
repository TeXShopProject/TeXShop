// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefSourceController : TSPrefPaneController
@property (strong, nullable) IBOutlet NSButton *texAwareSpellCheckButton;
@property (strong, nullable) IBOutlet NSButton *editSpellingExclusionsButton;
@property (strong, nullable) IBOutlet NSButton *checkBraceButton;
@property (strong, nullable) IBOutlet NSButton *checkBracketButton;
@property (strong, nullable) IBOutlet NSButton *checkParenButton;
@property (strong, nullable) IBOutlet NSButton *checkSquareBracketButton;
@property (strong, nullable) IBOutlet NSMatrix *commandCompletionMatrix;
@property (strong, nullable) IBOutlet NSPopUpButton *defaultEncodeMatrix;
@property (strong, nullable) IBOutlet NSButton *docWindowPosButton;
@property (strong, nullable) IBOutlet NSTextField *documentFontTextField;
@property (strong, nullable) IBOutlet NSButton *externalEditorButton;
@property (strong, nullable) IBOutlet NSMatrix *findMatrix;
@property (strong, nullable) IBOutlet NSMatrix *lineSizeMatrix;
@property (strong, nullable) IBOutlet NSPopUpButton *openAsTabsMatrix;
@property (strong, nullable) IBOutlet NSButton *openEmptyButton;
@property (strong, nullable) IBOutlet NSMatrix *sourceWindowPosMatrix;
@property (strong, nullable) IBOutlet NSButtonCell *spellCheckCommands;
@property (strong, nullable) IBOutlet NSButtonCell *spellCheckComments;
@property (strong, nullable) IBOutlet NSButtonCell *spellCheckParameters;
@property (strong, nullable) IBOutlet NSPopUpButton *dictionaryPopup;
@end
NS_ASSUME_NONNULL_END
