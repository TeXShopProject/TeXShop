// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
@class TSThemeFileStore;
NS_ASSUME_NONNULL_BEGIN

/// What the theme list asks of Settings, which keeps the colors being edited and the themes of Light and Dark Mode.
@protocol TSSettingsThemeListOwner <NSObject>
/// The window for the list's sheets and panels.
@property (readonly, nullable) NSWindow *themeListWindow;
/// The theme whose colors the wells show.
@property (readonly, copy, nullable) NSString *editingThemeTitle;
/// The themes chosen for Light and Dark Mode.
@property (readonly, copy, nullable) NSString *lightThemeTitle;
@property (readonly, copy, nullable) NSString *darkThemeTitle;
/// The colors a new theme starts with.
@property (readonly, copy, nullable) NSDictionary<NSString *, id> *newThemeColors;
/// The list chose a theme: its colors are edited.
- (void)themeListDidChooseTitle:(nullable NSString *)title;
/// A theme was added (oldTitle nil), renamed, or moved to the Trash (newTitle nil), or its colors were restored
/// (both the same).
- (void)themeListDidChangeTitle:(nullable NSString *)oldTitle to:(nullable NSString *)newTitle;
- (void)themeListShowError:(NSString *)message;
@optional
/// Whether a file being imported holds colors TeXShop can read as a theme.
- (BOOL)themeListAcceptsData:(NSData *)data;
@end

/// Settings › Themes › Edit Themes: the themes in ~/Library/TeXShop/Themes, with ＋, − and the actions menu under them
/// and the same actions in each row's contextual menu. A theme that comes with TeXShop cannot be renamed or deleted;
/// one whose colors differ from TeXShop's can be restored.
@interface TSSettingsThemeList : NSObject
- (instancetype)initWithStore:(TSThemeFileStore *)store bundledDirectory:(nullable NSURL *)bundledDirectory
                        owner:(id<TSSettingsThemeListOwner>)owner text:(NSString *(^)(NSString *key))text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (readonly) NSView *view;
@property (readonly) NSTableView *tableView;
@property (readonly) NSButton *addButton;
@property (readonly) NSButton *removeButton;
@property (readonly) NSPopUpButton *actionsButton;
@property (readonly, copy) NSArray<NSString *> *titles;

/// Shows the marks of a theme again, after its colors were saved.
- (void)refreshTitle:(NSString *)title;
/// The theme being edited is no longer in the folder (renamed or deleted elsewhere): says so, and edits another.
- (void)themeWentMissing:(NSString *)title;
/// Reads the folder again and selects the owner's editing theme.
- (void)reload;
/// The theme comes with TeXShop / has colors that differ from TeXShop's copy.
- (BOOL)isBundledTitle:(NSString *)title;
- (BOOL)isChangedTitle:(NSString *)title;

- (IBAction)addTheme:(nullable id)sender;
- (IBAction)duplicateTheme:(nullable id)sender;
- (IBAction)renameTheme:(nullable id)sender;
- (IBAction)restoreTheme:(nullable id)sender;
- (IBAction)deleteTheme:(nullable id)sender;
- (IBAction)exportTheme:(nullable id)sender;
- (IBAction)importThemes:(nullable id)sender;
- (IBAction)showThemeInFinder:(nullable id)sender;
/// Adds the theme files; returns the titles given to them.
- (NSArray<NSString *> *)importURLs:(NSArray<NSURL *> *)urls;
@end

NS_ASSUME_NONNULL_END
