// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSAdvancedFindController.h"
#import "TSMultipleReplaceLibrary.h"
#import "TSTeXRootSearchWindowController.h"
#import "TSTeXRootEntryRules.h"

NS_ASSUME_NONNULL_BEGIN

/// The entry points of the window of the TeX sources of a root: the item in the Advanced Find panel's Find All menu,
/// the one in the Multiple Replace window's Replace All menu, and the one in the Find submenu (which can be given a
/// key in Settings › Keyboard). It finds the root of the main window's document as typesetting does, from its text on
/// screen, and gives the window what it needs from TeXShop: the open documents and their texts, the way files are
/// read and written, and the tracking of edits.
NS_SWIFT_NAME(TeXRootSearchEntry)
@interface TSTeXRootSearchEntry : NSObject <TSTeXRootSearchActions>

/// The application's: made by +installInMainMenu:findController:library:.
@property (class, nonatomic, readonly, nullable) TSTeXRootSearchEntry *sharedEntry;
/// Makes the shared entry, puts its item into the Find submenu (after the Multiple Replace items) and makes it the
/// target of the panel's and the Multiple Replace window's items.
+ (void)installInMainMenu:(NSMenu *)mainMenu findController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library;

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly) TSTeXRootSearchWindowController *windowController;

@end

NS_ASSUME_NONNULL_END
