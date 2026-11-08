// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefEnginesController : TSPrefPaneController
@property (strong) IBOutlet NSTextField *altPathField;
@property (strong) IBOutlet NSTextField *bibTeXengineField;
@property (strong) IBOutlet NSButton *escapeWarningButton;
@property (strong) IBOutlet NSTextField *gsBinPathField;
@property (strong) IBOutlet NSTextField *kpsetoolField;
@property (strong) IBOutlet NSTextField *latexCommandTextField;
@property (strong) IBOutlet NSTextField *latexGSCommandTextField;
@property (strong) IBOutlet NSButton *savePSButton;
@property (strong) IBOutlet NSTextField *tetexBinPathField;
@property (strong) IBOutlet NSTextField *texCommandTextField;
@property (strong) IBOutlet NSTextField *texGSCommandTextField;
@end
NS_ASSUME_NONNULL_END
