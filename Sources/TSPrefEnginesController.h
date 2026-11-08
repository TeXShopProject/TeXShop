// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefEnginesController : TSPrefPaneController
@property (strong, nullable) IBOutlet NSTextField *altPathField;
@property (strong, nullable) IBOutlet NSTextField *bibTeXengineField;
@property (strong, nullable) IBOutlet NSButton *escapeWarningButton;
@property (strong, nullable) IBOutlet NSTextField *gsBinPathField;
@property (strong, nullable) IBOutlet NSTextField *kpsetoolField;
@property (strong, nullable) IBOutlet NSTextField *latexCommandTextField;
@property (strong, nullable) IBOutlet NSTextField *latexGSCommandTextField;
@property (strong, nullable) IBOutlet NSButton *savePSButton;
@property (strong, nullable) IBOutlet NSTextField *tetexBinPathField;
@property (strong, nullable) IBOutlet NSTextField *texCommandTextField;
@property (strong, nullable) IBOutlet NSTextField *texGSCommandTextField;
@end
NS_ASSUME_NONNULL_END
