// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// The commands of the Advanced Find panel in the Find submenu, while the find method is the Advanced Find panel
/// (FindMethod 3): Find All, Select All Matches, Use Selection for Replace, Replace, Replace and Find, Replace All,
/// Highlight All and Remove Highlights, in the order of CotEditor's Find menu. Each one is a performFindPanelAction:
/// item whose tag is the panel's action (TSAdvancedFindAction), so the text views pass it on to the panel as they do
/// Find Next, and gray it out when they refuse it. The panel need not be open. Where the localized menu lacks Find and
/// Replace… (only the Base menu has it), it is added after Find… as well.
/// The items are added in code to AppKit's Find submenu (the one of Find… with tag 1), never to OgreKit's, and taken
/// out again when another find method is chosen: with the other methods the menu stays as it was.
NS_SWIFT_NAME(AdvancedFindMenu)
@interface TSAdvancedFindMenu : NSObject

/// The identifiers of the items that may be added, in menu order (separators included); Find and Replace… only where
/// the menu lacks it. Each command's is
/// "TSShortcut.performFindPanelAction:.<tag>", so Settings › Keyboard lists it and keeps a changed key.
@property (class, nonatomic, readonly) NSArray<NSString *> *itemIdentifiers;

/// Adds the items to the Find submenu of `mainMenu` when `findMethod` is the Advanced Find panel, and removes them
/// otherwise. Does nothing without AppKit's Find submenu. Calling it again with the same method changes nothing.
+ (void)updateMainMenu:(NSMenu *)mainMenu findMethod:(NSInteger)findMethod;

/// Updates the application's main menu now and whenever the find method changes in Settings.
+ (void)startFollowingFindMethod;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
