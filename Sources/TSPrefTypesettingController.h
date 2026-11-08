// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefTypesettingController : TSPrefPaneController
@property (strong) IBOutlet NSMatrix *afterTypesettingMatrix;
@property (strong) IBOutlet NSMatrix *defaultCommandMatrix;
@property (strong) IBOutlet NSMatrix *defaultScriptMatrix;
@property (strong) IBOutlet NSTextField *engineTextField;
@property (strong) IBOutlet NSButton *saveRelatedButton;
@property (strong) IBOutlet NSMatrix *syncMatrix;
@property (strong) IBOutlet NSButton *syncTabButton;
@property (strong) IBOutlet NSButton *useTransparencyButton;
@end
NS_ASSUME_NONNULL_END
