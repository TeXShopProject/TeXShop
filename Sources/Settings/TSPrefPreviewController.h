// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneController.h"
NS_ASSUME_NONNULL_BEGIN
@interface TSPrefPreviewController : TSPrefPaneController
@property (strong, nullable) IBOutlet NSTextField *HtmlHomeField NS_SWIFT_NAME(htmlHomeField);
@property (strong, nullable) IBOutlet NSButton *antialiasButton;
@property (strong, nullable) IBOutlet NSButton *autoPDFButton;
@property (strong, nullable) IBOutlet NSButton *displayAsBookButton;
@property (strong, nullable) IBOutlet NSMatrix *firstPageMatrix;
@property (strong, nullable) IBOutlet NSButton *htmlWindowPosButton;
@property (strong, nullable) IBOutlet NSMatrix *htmlWindowPosMatrix;
@property (strong, nullable) IBOutlet NSButton *linkPopupsButton;
@property (strong, nullable) IBOutlet NSTextField *magTextField;
@property (strong, nullable) IBOutlet NSPopUpButton *mouseModePopup;
@property (strong, nullable) IBOutlet NSPopUpButton *pageStylePopup;
@property (strong, nullable) IBOutlet NSButton *pdfWindowPosButton;
@property (strong, nullable) IBOutlet NSMatrix *pdfWindowPosMatrix;
@property (strong, nullable) IBOutlet NSPopUpButton *resizeOptionPopup;
@property (strong, nullable) IBOutlet NSButton *scrollButton;
@property (strong, nullable) IBOutlet NSButton *useLeftSourceButton;
@property (strong, nullable) IBOutlet NSButton *useOneWindowButton;
@property (strong, nullable) IBOutlet NSButton *useRightSourceButton;
@property (strong, nullable) IBOutlet NSButton *useTwoWindowsButton;
@end
NS_ASSUME_NONNULL_END
