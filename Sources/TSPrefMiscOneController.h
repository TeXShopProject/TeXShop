// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefMiscOneController : TSPrefPaneController
@property (strong) IBOutlet NSColorWell *BlockCursorColorWell;
@property (strong) IBOutlet NSButton *blockCursorButton;
@property (strong) IBOutlet NSMatrix *blockSideMatrix;
@property (strong) IBOutlet NSMatrix *blockWidthMatrix;
@property (strong) IBOutlet NSButton *colorMapButton;
@property (strong) IBOutlet NSPopUpButton *colorParam1Popup;
@property (strong) IBOutlet NSPopUpButton *imageCopyTypePopup;
@property (strong) IBOutlet NSButton *autoSaveEnabledButton;
@property (strong) IBOutlet NSButton *keepBackupButton;
@property (strong) IBOutlet NSButton *saveEncodingMenuButton;
@end
NS_ASSUME_NONNULL_END
