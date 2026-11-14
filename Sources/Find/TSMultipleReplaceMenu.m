// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSMultipleReplaceMenu.h"
#import "TSAdvancedFindController+MultipleReplace.h"
#import "TSAdvancedFindTextView.h"

#define TSLocalized TSAdvancedFindLocalized

static NSString *const TSShowMultipleReplaceIdentifier = @"TSShortcut.showMultipleReplace:.0";
static TSMultipleReplaceMenu *TSSharedMultipleReplaceMenu;

/// The submenu that holds Find…, searched through the whole menu: AppKit's (tag 1 of performFindPanelAction:), or
/// OgreKit's (showFindPanel:), which replaces it at launch when the find method is OgreKit.
static NSMenu *_Nullable TSFindSubmenu(NSMenu *menu)
{
    for (NSMenuItem *item in menu.itemArray) {
        if ((item.action == @selector(performFindPanelAction:) && item.tag == NSFindPanelActionShowFindPanel)
            || item.action == NSSelectorFromString(@"showFindPanel:"))
            return menu;
        NSMenu *found = item.submenu ? TSFindSubmenu((NSMenu *_Nonnull)item.submenu) : nil;
        if (found)
            return found;
    }
    return nil;
}

@interface TSMultipleReplaceMenu ()
@property (nonatomic, readwrite, nullable) TSMultipleReplaceWindowController *madeWindowController;
@end

@implementation TSMultipleReplaceMenu

+ (nullable TSMultipleReplaceMenu *)sharedMenu
{
    return TSSharedMultipleReplaceMenu;
}

+ (void)installInMainMenu:(NSMenu *)mainMenu directory:(NSURL *)directory
{
    NSMenu *findMenu = TSFindSubmenu(mainMenu);
    if (!findMenu)
        return;
    for (NSMenuItem *item in findMenu.itemArray)
        if ([item.identifier isEqualToString:TSShowMultipleReplaceIdentifier])
            return;
    if (!TSSharedMultipleReplaceMenu)
        TSSharedMultipleReplaceMenu = [[TSMultipleReplaceMenu alloc] initWithFindController:TSAdvancedFindController.sharedController
                                                                                    library:[[TSMultipleReplaceLibrary alloc] initWithDirectory:directory]];
    [TSSharedMultipleReplaceMenu addItemsToMenu:findMenu];
}

- (instancetype)initWithFindController:(TSAdvancedFindController *)findController library:(TSMultipleReplaceLibrary *)library
{
    if ((self = [super init])) {
        _findController = findController;
        _library = library;
    }
    return self;
}

- (TSMultipleReplaceWindowController *)windowController
{
    if (!self.madeWindowController)
        self.madeWindowController = [[TSMultipleReplaceWindowController alloc] initWithFindController:self.findController library:self.library];
    return (TSMultipleReplaceWindowController *_Nonnull)self.madeWindowController;
}

- (void)addItemsToMenu:(NSMenu *)findMenu
{
    NSInteger index = findMenu.numberOfItems;
    for (NSInteger i = 0; i < findMenu.numberOfItems; i++)
        if ([findMenu itemAtIndex:i].action == @selector(centerSelectionInVisibleArea:))
            index = i + 1;
    NSMenuItem *show = [[NSMenuItem alloc] initWithTitle:TSLocalized(@"MultipleReplace.EditMenu", @"Edit Multiple Replace…")
                                                  action:@selector(showMultipleReplace:) keyEquivalent:@""];
    show.target = self;
    show.identifier = TSShowMultipleReplaceIdentifier;
    NSMenuItem *sets = [[NSMenuItem alloc] initWithTitle:TSLocalized(@"MultipleReplace.Title", @"Multiple Replace") action:@selector(applySet:) keyEquivalent:@""];
    // The action only lets the item be validated: it is gray while there is no set to choose.
    sets.target = self;
    NSMenu *submenu = [[NSMenu alloc] initWithTitle:sets.title];
    submenu.delegate = self;
    sets.submenu = submenu;
    [findMenu insertItem:NSMenuItem.separatorItem atIndex:index];
    [findMenu insertItem:show atIndex:index + 1];
    [findMenu insertItem:sets atIndex:index + 2];
}

/// The saved sets, read again each time the submenu opens.
- (void)menuNeedsUpdate:(NSMenu *)menu
{
    [menu removeAllItems];
    for (NSString *name in self.library.setNames) {
        NSMenuItem *item = [menu addItemWithTitle:name action:@selector(applySet:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = name;
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(applySet:)) {
        if (item.submenu)
            return self.library.setNames.count > 0;
        NSTextView *target = TSAdvancedFindController.targetTextView;
        return target && [self.findController validateAction:TSAdvancedFindActionReplaceAll forTextView:(NSTextView *_Nonnull)target];
    }
    return YES;
}

- (IBAction)showMultipleReplace:(nullable id)sender
{
    [self.windowController reloadSets];
    [self.windowController showWindow:sender];
}

- (IBAction)applySet:(nullable id)sender
{
    NSString *name = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    NSTextView *target = TSAdvancedFindController.targetTextView;
    NSError *error = nil;
    TSRegexMultipleReplace *set = [name isKindOfClass:[NSString class]] ? [self.library setNamed:name error:&error] : nil;
    if (!set || !target) {
        self.findController.beepHandler();
        return;
    }
    [self.findController applyMultipleReplace:(TSRegexMultipleReplace *_Nonnull)set inTextView:(NSTextView *_Nonnull)target inSelection:NO completion:nil];
}

@end
