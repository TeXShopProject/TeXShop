// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefPreviewController : TSPrefPaneController
@property (strong) IBOutlet NSTextField *HtmlHomeField;
@property (strong) IBOutlet NSButton *antialiasButton;
@property (strong) IBOutlet NSButton *autoPDFButton;
@property (strong) IBOutlet NSButton *displayAsBookButton;
@property (strong) IBOutlet NSMatrix *firstPageMatrix;
@property (strong) IBOutlet NSButton *htmlWindowPosButton;
@property (strong) IBOutlet NSMatrix *htmlWindowPosMatrix;
@property (strong) IBOutlet NSTextField *magTextField;
@property (strong) IBOutlet NSPopUpButton *mouseModePopup;
@property (strong) IBOutlet NSPopUpButton *pageStylePopup;
@property (strong) IBOutlet NSButton *pdfWindowPosButton;
@property (strong) IBOutlet NSMatrix *pdfWindowPosMatrix;
@property (strong) IBOutlet NSPopUpButton *resizeOptionPopup;
@property (strong) IBOutlet NSButton *scrollButton;
@property (strong) IBOutlet NSButton *useLeftSourceButton;
@property (strong) IBOutlet NSButton *useOneWindowButton;
@property (strong) IBOutlet NSButton *useRightSourceButton;
@property (strong) IBOutlet NSButton *useTwoWindowsButton;
@end
NS_ASSUME_NONNULL_END
