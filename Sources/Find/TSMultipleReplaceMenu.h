// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSMultipleReplaceWindowController.h"

NS_ASSUME_NONNULL_BEGIN

/// The multiple replacement items of the Find submenu: "Edit Multiple Replace…" opens the window, and "Multiple Replace" ▸
/// lists the saved sets, each applied at once to the whole text of the main window. The items are added in code,
/// after Jump to Selection, so the localized menus need no change.
NS_SWIFT_NAME(MultipleReplaceMenu)
@interface TSMultipleReplaceMenu : NSObject <NSMenuDelegate, NSMenuItemValidation>

/// The application's: the shared find controller and the sets in `directory`, made by +installInMainMenu:directory:.
@property (class, nonatomic, readonly, nullable) TSMultipleReplaceMenu *sharedMenu;
/// Adds the items to the Find submenu of `mainMenu` (the submenu of Find…, AppKit's or OgreKit's). Does nothing when
/// there is no such submenu or the items are there already.
+ (void)installInMainMenu:(NSMenu *)mainMenu directory:(NSURL *)directory;

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly) TSAdvancedFindController *findController;
@property (nonatomic, readonly) TSMultipleReplaceLibrary *library;
/// Made when it is first needed.
@property (nonatomic, readonly) TSMultipleReplaceWindowController *windowController;

/// Adds "Edit Multiple Replace…" and "Multiple Replace" ▸ to `findMenu` after Jump to Selection, or at the end
/// (OgreKit's Find submenu has no Jump to Selection).
- (void)addItemsToMenu:(NSMenu *)findMenu;

- (IBAction)showMultipleReplace:(nullable id)sender;
/// The set named by the item's represented object, on the main window's text view.
- (IBAction)applySet:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
