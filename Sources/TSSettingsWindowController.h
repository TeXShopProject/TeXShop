// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSSettingsNavigationHistory.h"
#import "TSSettingsCategory.h"
#import "TSSettingsSearch.h"
#import "TSSettingsChangeNote.h"
NS_ASSUME_NONNULL_BEGIN
@protocol TSSettingsKeyboardPane <NSObject>
- (void)stopKeySearch;
- (BOOL)handleKeySearchEvent:(NSEvent *)event;
@optional
@property (readonly) BOOL searchingByKey;
- (void)applySettingsQuery:(NSString *)query targets:(NSArray<NSString *> *)targets filterCommands:(BOOL)filter;
@end
@protocol TSSettingsWindowDelegate <NSObject>
- (BOOL)settingsMayChangeCategory;
- (void)settingsChangeFont:(NSFontManager *)sender;
@optional
- (void)settingsWillDisplayCategory:(TSSettingsCategoryID)identifier;
@end
@interface TSSettingsWindowController : NSWindowController
@property (copy, nullable) NSViewController<TSSettingsKeyboardPane> * _Nullable (^keyboardPaneProvider)(void);
@property (weak, nullable) id<TSSettingsWindowDelegate> settingsDelegate;
@property (copy, nullable) NSArray<NSString *> *(^commandNamesProvider)(void);
@property (nonatomic, strong) NSBundle *searchBundle;
@property (strong, nullable) TSSettingsChangeNotes *changeNotes;
@property (copy, readonly) NSString *searchQuery;
@property (copy, readonly) NSArray<TSSettingsSearchResult *> *searchResults;
- (BOOL)setSettingsSearchQuery:(NSString *)query;
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
/// Category controllers retain their controls and use stable identifiers.
- (void)hostPaneControllers:(NSDictionary<TSSettingsCategoryID, NSViewController *> *)panes footer:(NSView *)footer;
- (void)changeFont:(nullable id)sender;
- (nullable NSView *)viewForCategoryIdentifier:(TSSettingsCategoryID)identifier;
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
