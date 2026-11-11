// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPreviewController.h"
#import "TSPreferences.h"
@implementation TSPrefPreviewController
- (instancetype)init { return [super initWithNibName:@"SettingsPreview" bundle:nil]; }
- (IBAction)HtmlHomeChanged:(id)sender { [self.preferences HtmlHomeChanged:sender]; }
- (IBAction)autoPDFChanged:(id)sender { [self.preferences autoPDFChanged:sender]; }
- (IBAction)currentHtmlWindowPosDefault:(id)sender { [self.preferences currentHtmlWindowPosDefault:sender]; }
- (IBAction)currentPdfWindowPosDefault:(id)sender { [self.preferences currentPdfWindowPosDefault:sender]; }
- (IBAction)displayAsBookChanged:(id)sender { [self.preferences displayAsBookChanged:sender]; }
- (IBAction)firstDoublePageChanged:(id)sender { [self.preferences firstDoublePageChanged:sender]; }
- (IBAction)htmlWindowPosChanged:(id)sender { [self.preferences htmlWindowPosChanged:sender]; }
- (IBAction)linkPopupsChanged:(id)sender { [self.preferences linkPopupsChanged:sender]; }
- (IBAction)scrollPageTurnChanged:(id)sender { [self.preferences scrollPageTurnChanged:sender]; }
- (IBAction)magChanged:(id)sender { [self.preferences magChanged:sender]; }
- (IBAction)mouseModeChanged:(id)sender { [self.preferences mouseModeChanged:sender]; }
- (IBAction)pageStyleChanged:(id)sender { [self.preferences pageStyleChanged:sender]; }
- (IBAction)pdfWindowPosChanged:(id)sender { [self.preferences pdfWindowPosChanged:sender]; }
- (IBAction)resizeOptionChanged:(id)sender { [self.preferences resizeOptionChanged:sender]; }
- (IBAction)sourceAndPreviewInSameWindowChanged:(id)sender { [self.preferences sourceAndPreviewInSameWindowChanged:sender]; }
- (IBAction)sourceOnLeftChanged:(id)sender { [self.preferences sourceOnLeftChanged:sender]; }
@end
