// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSSettingsNavigationHistory.h"
#import "TSSettingsCategory.h"
NS_ASSUME_NONNULL_BEGIN
@protocol TSSettingsKeyboardPane <NSObject>
- (void)stopKeySearch;
- (BOOL)handleKeySearchEvent:(NSEvent *)event;
@end
@protocol TSSettingsWindowDelegate <NSObject>
- (BOOL)settingsMayChangeCategory;
- (void)settingsChangeFont:(NSFontManager *)sender;
@end
@interface TSSettingsWindowController : NSWindowController
@property (copy, nullable) NSViewController<TSSettingsKeyboardPane> * _Nullable (^keyboardPaneProvider)(void);
@property (weak, nullable) id<TSSettingsWindowDelegate> settingsDelegate;
@property (copy, readonly) NSArray<TSSettingsCategoryID> *categoryIdentifiers;
@property (strong, readonly) TSSettingsNavigationHistory *history;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (instancetype)initWithWindowNibName:(NSNibName)name NS_UNAVAILABLE;
- (instancetype)initWithWindowNibName:(NSNibName)name owner:(id)owner NS_UNAVAILABLE;
- (instancetype)initWithWindowNibPath:(NSString *)path owner:(id)owner NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
/// Keeps the nib's owner, identifiers, controls and profile selector intact.
- (void)hostLegacyContent:(NSView *)content tabView:(NSTabView *)tabs;
- (void)changeFont:(nullable id)sender;
- (nullable NSView *)legacyViewForCategoryIdentifier:(TSSettingsCategoryID)identifier;
- (void)beginSession;
- (void)endSession;
- (BOOL)selectCategoryIdentifier:(TSSettingsCategoryID)identifier;
- (void)goBack:(nullable id)sender;
- (void)goForward:(nullable id)sender;
@end
@interface TSSettingsWindow : NSWindow
@property (weak, nullable) TSSettingsWindowController *settingsController;
@end
NS_ASSUME_NONNULL_END
