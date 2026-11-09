// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefConsoleController : TSPrefPaneController
@property (strong, nullable) IBOutlet NSTextField *consoleFontTextField;
@property (strong, nullable) IBOutlet NSMatrix *consoleMatrix;
@property (strong, nullable) IBOutlet NSMatrix *consoleResizeMatrix;
@property (strong, nullable) IBOutlet NSButton *consoleWindowPosButton;
@property (strong, nullable) IBOutlet NSMatrix *consoleWindowPosMatrix;
@property (strong, nullable) IBOutlet NSButton *macroButton;
@end
NS_ASSUME_NONNULL_END
