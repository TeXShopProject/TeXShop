// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefMiscOneController.h"
#import "TSPreferences.h"
@implementation TSPrefMiscOneController
- (instancetype)init { return [super initWithNibName:@"SettingsMiscOne" bundle:nil]; }
- (IBAction)BlockCursorColorChanged:(id)sender { [self.preferences BlockCursorColorChanged:sender]; }
- (IBAction)autoSaveEnabledPressed:(id)sender { [self.preferences autoSaveEnabledPressed:sender]; }
- (IBAction)blockCursorPressed:(id)sender { [self.preferences blockCursorPressed:sender]; }
- (IBAction)blockSidePressed:(id)sender { [self.preferences blockSidePressed:sender]; }
- (IBAction)blockWidthPressed:(id)sender { [self.preferences blockWidthPressed:sender]; }
- (IBAction)colorMapChanged:(id)sender { [self.preferences colorMapChanged:sender]; }
- (IBAction)colorParam1Changed:(id)sender { [self.preferences colorParam1Changed:sender]; }
- (IBAction)imageCopyTypeChanged:(id)sender { [self.preferences imageCopyTypeChanged:sender]; }
- (IBAction)keepBackupPressed:(id)sender { [self.preferences keepBackupPressed:sender]; }
- (IBAction)saveEncodingMenuPressed:(id)sender { [self.preferences saveEncodingMenuPressed:sender]; }
@end
