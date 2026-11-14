// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefTypesettingController : TSPrefPaneController
@property (strong, nullable) IBOutlet NSMatrix *afterTypesettingMatrix;
@property (strong, nullable) IBOutlet NSMatrix *defaultCommandMatrix;
@property (strong, nullable) IBOutlet NSMatrix *defaultScriptMatrix;
@property (strong, nullable) IBOutlet NSButton *saveRelatedButton;
@property (strong, nullable) IBOutlet NSMatrix *syncMatrix;
@property (strong, nullable) IBOutlet NSButton *syncTabButton;
@property (strong, nullable) IBOutlet NSButton *useTransparencyButton;
@end
NS_ASSUME_NONNULL_END
