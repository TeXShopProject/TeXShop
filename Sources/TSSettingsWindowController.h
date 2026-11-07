// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSSettingsNavigationHistory.h"
NS_ASSUME_NONNULL_BEGIN
@protocol TSSettingsWindowDelegate <NSObject>
- (BOOL)settingsMayChangeCategory;
- (void)settingsChangeFont:(id)sender;
@end
@interface TSSettingsWindowController : NSWindowController
@property (weak, nullable) id<TSSettingsWindowDelegate> settingsDelegate;
@property (copy, readonly) NSArray<NSString *> *categoryIdentifiers;
@property (strong, readonly) TSSettingsNavigationHistory *history;
@property (strong, readonly) NSTableView *categoryTable;
@property (strong, readonly) NSSegmentedControl *navigationControl;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
/// Keeps the nib's owner, identifiers, controls and profile selector intact.
- (void)hostLegacyContent:(NSView *)content tabView:(NSTabView *)tabs;
- (void)changeFont:(nullable id)sender;
- (nullable NSView *)legacyViewForCategoryIdentifier:(NSString *)identifier;
- (void)beginSession;
- (void)endSession;
- (BOOL)selectCategoryIdentifier:(NSString *)identifier;
- (void)goBack:(nullable id)sender;
- (void)goForward:(nullable id)sender;
@end
@interface TSSettingsWindow : NSWindow
@property (weak, nullable) TSSettingsWindowController *settingsController;
@end
NS_ASSUME_NONNULL_END
