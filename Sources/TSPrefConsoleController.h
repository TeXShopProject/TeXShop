// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefConsoleController : TSPrefPaneController
@property (strong) IBOutlet NSTextField *consoleFontTextField;
@property (strong) IBOutlet NSMatrix *consoleMatrix;
@property (strong) IBOutlet NSMatrix *consoleResizeMatrix;
@property (strong) IBOutlet NSButton *consoleWindowPosButton;
@property (strong) IBOutlet NSMatrix *consoleWindowPosMatrix;
@property (strong) IBOutlet NSButton *macroButton;
@end
NS_ASSUME_NONNULL_END
