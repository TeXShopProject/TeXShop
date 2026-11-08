// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefMiscOneController : TSPrefPaneController
@property (strong, nullable) IBOutlet NSColorWell *BlockCursorColorWell NS_SWIFT_NAME(blockCursorColorWell);
@property (strong, nullable) IBOutlet NSButton *blockCursorButton;
@property (strong, nullable) IBOutlet NSMatrix *blockSideMatrix;
@property (strong, nullable) IBOutlet NSMatrix *blockWidthMatrix;
@property (strong, nullable) IBOutlet NSButton *colorMapButton;
@property (strong, nullable) IBOutlet NSPopUpButton *colorParam1Popup;
@property (strong, nullable) IBOutlet NSPopUpButton *imageCopyTypePopup;
@property (strong, nullable) IBOutlet NSButton *autoSaveEnabledButton;
@property (strong, nullable) IBOutlet NSButton *keepBackupButton;
@property (strong, nullable) IBOutlet NSButton *saveEncodingMenuButton;
@end
NS_ASSUME_NONNULL_END
