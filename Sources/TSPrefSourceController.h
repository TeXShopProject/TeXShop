// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefSourceController : TSPrefPaneController
@property (strong) IBOutlet NSButton *texAwareSpellCheckButton;
@property (strong) IBOutlet NSButton *editSpellingExclusionsButton;
@property (strong) IBOutlet NSButton *checkBraceButton;
@property (strong) IBOutlet NSButton *checkBracketButton;
@property (strong) IBOutlet NSButton *checkParenButton;
@property (strong) IBOutlet NSButton *checkSquareBracketButton;
@property (strong) IBOutlet NSMatrix *commandCompletionMatrix;
@property (strong) IBOutlet NSPopUpButton *defaultEncodeMatrix;
@property (strong) IBOutlet NSButton *docWindowPosButton;
@property (strong) IBOutlet NSTextField *documentFontTextField;
@property (strong) IBOutlet NSButton *externalEditorButton;
@property (strong) IBOutlet NSMatrix *findMatrix;
@property (strong) IBOutlet NSMatrix *lineSizeMatrix;
@property (strong) IBOutlet NSPopUpButton *openAsTabsMatrix;
@property (strong) IBOutlet NSButton *openEmptyButton;
@property (strong) IBOutlet NSMatrix *sourceWindowPosMatrix;
@property (strong) IBOutlet NSButtonCell *spellCheckCommands;
@property (strong) IBOutlet NSButtonCell *spellCheckComments;
@property (strong) IBOutlet NSButtonCell *spellCheckParameters;
@property (strong) IBOutlet NSPopUpButton *dictionaryPopup;
@end
NS_ASSUME_NONNULL_END
