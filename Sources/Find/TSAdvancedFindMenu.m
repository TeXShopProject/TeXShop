// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindMenu.h"
#import "TSAdvancedFindController.h"
#import "TSFindInterface.h"
#import "TSPreferenceKey.h"

#define TSLocalized TSAdvancedFindLocalized

// FindMethodKey of globals.m: the Find sources are built without the rest of TeXShop in the tests.
static NSString *const TSFindMethodKey = @"FindMethod";
static NSString *const TSSeparatorPrefix = @"TSAdvancedFindMenu.separator.";
/// The representedObject of every item added here, so that only these are taken out again.
static NSString *const TSAddedItemMark = @"TSAdvancedFindMenu";

/// One added item: a command (the panel's action as its tag, the default key) or a separator (`key` nil).
typedef struct {
    TSAdvancedFindAction action;
    const char *_Nullable key;
    NSEventModifierFlags modifiers;
} TSAdvancedFindMenuCommand;

static NSString *TSCommandIdentifier(TSAdvancedFindAction action)
{
    return [NSString stringWithFormat:@"TSShortcut.performFindPanelAction:.%ld", (long)action];
}

static NSString *_Nullable TSCommandTitle(TSAdvancedFindAction action)
{
    switch (action) {
        case TSAdvancedFindActionFindAll: return TSLocalized(@"AdvancedFind.Menu.FindAll", @"Find All");
        case TSAdvancedFindActionSelectAll: return TSLocalized(@"AdvancedFind.Menu.SelectAll", @"Select All Matches");
        case TSAdvancedFindActionSetReplaceString: return TSLocalized(@"AdvancedFind.Menu.SetReplaceString", @"Use Selection for Replace");
        case TSAdvancedFindActionReplace: return TSLocalized(@"AdvancedFind.Menu.Replace", @"Replace");
        case TSAdvancedFindActionReplaceAndFind: return TSLocalized(@"AdvancedFind.Menu.ReplaceAndFind", @"Replace and Find");
        case TSAdvancedFindActionReplaceAll: return TSLocalized(@"AdvancedFind.Menu.ReplaceAll", @"Replace All");
        case TSAdvancedFindActionHighlight: return TSLocalized(@"AdvancedFind.Menu.Highlight", @"Highlight All");
        case TSAdvancedFindActionUnhighlight: return TSLocalized(@"AdvancedFind.Menu.Unhighlight", @"Remove Highlights");
        default: return nil;
    }
}

static NSMenuItem *TSCommandItem(TSAdvancedFindAction action, const char *key, NSEventModifierFlags modifiers)
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:TSCommandTitle(action) ?: @"" action:@selector(performFindPanelAction:)
                                           keyEquivalent:[NSString stringWithUTF8String:key] ?: @""];
    item.keyEquivalentModifierMask = item.keyEquivalent.length ? modifiers : 0;
    item.tag = action;
    item.identifier = TSCommandIdentifier(action);
    item.representedObject = TSAddedItemMark;
    return item; // no target: the first responder, as for the other commands of the Find submenu
}

static NSMenuItem *TSSeparatorItem(NSString *name)
{
    NSMenuItem *item = NSMenuItem.separatorItem;
    item.identifier = [TSSeparatorPrefix stringByAppendingString:name];
    item.representedObject = TSAddedItemMark;
    return item;
}

static const NSEventModifierFlags TSCommand = NSEventModifierFlagCommand;
static const NSEventModifierFlags TSShiftCommand = NSEventModifierFlagShift | NSEventModifierFlagCommand;

/// AppKit's Find submenu: the one with Find… (performFindPanelAction: with tag 1). OgreKit's has showFindPanel:.
static NSMenu *_Nullable TSAppKitFindSubmenu(NSMenu *menu)
{
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(performFindPanelAction:) && item.tag == NSFindPanelActionShowFindPanel)
            return menu;
        NSMenu *found = item.submenu ? TSAppKitFindSubmenu((NSMenu *_Nonnull)item.submenu) : nil;
        if (found)
            return found;
    }
    return nil;
}

/// The index after the last item that `matches`, or NSNotFound.
static NSInteger TSIndexAfter(NSMenu *menu, BOOL (^matches)(NSMenuItem *item))
{
    NSInteger found = NSNotFound;
    for (NSInteger i = 0; i < menu.numberOfItems; i++)
        if (matches([menu itemAtIndex:i]))
            found = i + 1;
    return found;
}

static NSInteger TSIndexAfterFindPanelAction(NSMenu *menu, NSInteger tag)
{
    return TSIndexAfter(menu, ^BOOL(NSMenuItem *item) { return item.action == @selector(performFindPanelAction:) && item.tag == tag; });
}

@implementation TSAdvancedFindMenu

+ (NSArray<NSString *> *)itemIdentifiers
{
    return @[TSCommandIdentifier(TSAdvancedFindActionFindAll), TSCommandIdentifier(TSAdvancedFindActionSelectAll),
             [TSSeparatorPrefix stringByAppendingString:@"find"],
             TSCommandIdentifier(TSAdvancedFindActionSetReplaceString),
             [TSSeparatorPrefix stringByAppendingString:@"replace"],
             TSCommandIdentifier(TSAdvancedFindActionReplace), TSCommandIdentifier(TSAdvancedFindActionReplaceAndFind),
             TSCommandIdentifier(TSAdvancedFindActionReplaceAll),
             [TSSeparatorPrefix stringByAppendingString:@"highlight"],
             TSCommandIdentifier(TSAdvancedFindActionHighlight), TSCommandIdentifier(TSAdvancedFindActionUnhighlight)];
}

+ (void)removeItemsFromMenu:(NSMenu *)findMenu
{
    for (NSMenuItem *item in [findMenu.itemArray copy])
        if ([item.representedObject isEqual:TSAddedItemMark])
            [findMenu removeItem:item];
}

+ (void)addItemsToMenu:(NSMenu *)findMenu
{
    // Find Next and Find Previous, then Find All ⇧⌘F, Select All Matches and a separator.
    NSInteger index = TSIndexAfterFindPanelAction(findMenu, NSFindPanelActionPrevious);
    if (index == NSNotFound)
        index = TSIndexAfterFindPanelAction(findMenu, NSFindPanelActionShowFindPanel);
    [findMenu insertItem:TSCommandItem(TSAdvancedFindActionFindAll, "F", TSShiftCommand) atIndex:index];
    [findMenu insertItem:TSCommandItem(TSAdvancedFindActionSelectAll, "", 0) atIndex:index + 1];
    [findMenu insertItem:TSSeparatorItem(@"find") atIndex:index + 2];

    // Use Selection for Find, then Use Selection for Replace ⇧⌘E.
    index = TSIndexAfterFindPanelAction(findMenu, NSFindPanelActionSetFindString);
    if (index == NSNotFound)
        index = TSIndexAfter(findMenu, ^BOOL(NSMenuItem *item) { return [item.identifier hasPrefix:TSSeparatorPrefix]; });
    [findMenu insertItem:TSCommandItem(TSAdvancedFindActionSetReplaceString, "E", TSShiftCommand) atIndex:index];

    // Replace, Replace and Find ⌥⌘G and Replace All, before the Multiple Replace items (after their separator);
    // without them, after Jump to Selection and a separator of their own.
    NSInteger multiple = NSNotFound;
    for (NSInteger i = 0; i < findMenu.numberOfItems; i++)
        if ([[findMenu itemAtIndex:i].identifier isEqualToString:@"TSShortcut.showMultipleReplace:.0"])
            multiple = i;
    if (multiple != NSNotFound && multiple > 0 && [findMenu itemAtIndex:multiple - 1].separatorItem) {
        index = multiple;
    } else {
        index = TSIndexAfter(findMenu, ^BOOL(NSMenuItem *item) { return item.action == @selector(centerSelectionInVisibleArea:); });
        if (index == NSNotFound)
            index = findMenu.numberOfItems;
        [findMenu insertItem:TSSeparatorItem(@"replace") atIndex:index++];
    }
    [findMenu insertItem:TSCommandItem(TSAdvancedFindActionReplace, "", 0) atIndex:index];
    [findMenu insertItem:TSCommandItem(TSAdvancedFindActionReplaceAndFind, "g", NSEventModifierFlagOption | TSCommand) atIndex:index + 1];
    [findMenu insertItem:TSCommandItem(TSAdvancedFindActionReplaceAll, "", 0) atIndex:index + 2];

    // At the end: Highlight All ⇧⌘H and Remove Highlights ⌃⇧⌘H.
    [findMenu addItem:TSSeparatorItem(@"highlight")];
    [findMenu addItem:TSCommandItem(TSAdvancedFindActionHighlight, "H", TSShiftCommand)];
    [findMenu addItem:TSCommandItem(TSAdvancedFindActionUnhighlight, "H", NSEventModifierFlagControl | TSShiftCommand)];
}

+ (void)updateMainMenu:(NSMenu *)mainMenu findMethod:(NSInteger)findMethod
{
    NSMenu *findMenu = TSAppKitFindSubmenu(mainMenu);
    if (!findMenu)
        return;
    BOOL present = NO;
    for (NSMenuItem *item in findMenu.itemArray)
        if ([item.identifier isEqualToString:TSCommandIdentifier(TSAdvancedFindActionFindAll)])
            present = YES;
    BOOL wanted = findMethod == TSFindMethodAdvancedPanel;
    if (present == wanted)
        return;
    if (wanted)
        [self addItemsToMenu:findMenu];
    else
        [self removeItemsFromMenu:findMenu];
}

+ (void)startFollowingFindMethod
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void (^update)(NSNotification *_Nullable) = ^(NSNotification *_Nullable notification) {
            NSMenu *mainMenu = NSApp.mainMenu;
            if (mainMenu)
                [TSAdvancedFindMenu updateMainMenu:(NSMenu *_Nonnull)mainMenu
                                        findMethod:[NSUserDefaults.standardUserDefaults integerForKey:TSFindMethodKey]];
        };
        [NSNotificationCenter.defaultCenter addObserverForName:TSFindMethodChangedNotification object:nil queue:nil usingBlock:update];
        update(nil);
    });
}

@end
