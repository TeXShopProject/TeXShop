// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
NSString * const TSRebuildMacrosNotification = @"TSRebuildMacros";
NSString * const TSMacroShortcutsChangedNotification = @"TSMacroShortcutsChanged";
@interface TSKeyboardShortcuts ()
@property (strong, readwrite, nullable) TSShortcutStore *store;
@property BOOL menuRefreshPending;
@property NSArray *observedMenuBindings;
@property BOOL rebuildingMacros;
@property BOOL applyingMenus;
@end

@implementation TSKeyboardShortcuts
+ (instancetype)sharedController {
    static TSKeyboardShortcuts *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[self alloc] init]; });
    return controller;
}
- (void)startObservingMenu {
    if (self.store != nil) { [self refreshMenuAndMacros]; return; }
    NSMenu *menu = NSApp.mainMenu;
    if (menu == nil) { return; }
    self.store = [[TSShortcutStore alloc] initWithMenu:menu defaults:NSUserDefaults.standardUserDefaults];
    [self observeMenuChanges];
    [self refreshMenuAndMacros];
}
- (void)showKeyboardShortcuts:(id)sender {
    if (self.showSettings == nil) { return; }
    self.showSettings();
}
- (NSArray *)menuBindingSnapshot {
    NSMutableArray *bindings = [NSMutableArray array];
    TSVisitMenu(NSApp.mainMenu, @"", ^(NSMenuItem *item, NSString *path) {
        SEL action = item.action;
        // AppKit may hide a newly inserted item's key until the existing macro key is cleared.
        if (!item.submenu && !item.separatorItem && item.action != TSMacroAction())
            [bindings addObject:@[[NSValue valueWithNonretainedObject:item], item.keyEquivalent,
                @(item.keyEquivalentModifierMask), (action ? NSStringFromSelector(action) : @"") ?: @"", item.identifier ?: @""]];
    });
    return bindings;
}
- (void)observeMenuChanges {
    self.observedMenuBindings = [self menuBindingSnapshot];
    for (NSNotificationName name in @[NSMenuDidAddItemNotification, NSMenuDidRemoveItemNotification])
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuStructureChanged:) name:name object:nil];
}
- (void)beginMenuRebuild {
    self.rebuildingMacros = YES;
    [self.store refreshMenu];
}
- (void)endMenuRebuild {
    self.rebuildingMacros = NO;
    self.observedMenuBindings = [self menuBindingSnapshot];

    [[NSNotificationCenter defaultCenter] postNotificationName:TSMacroShortcutsChangedNotification object:self];
}
- (void)refreshMenuAndMacros {
    if (self.applyingMenus || self.rebuildingMacros) return;
    self.applyingMenus = YES;
    @try {
        [self.store refreshMenu];
        [[NSNotificationCenter defaultCenter] postNotificationName:TSRebuildMacrosNotification object:self];

    } @finally {
        self.observedMenuBindings = [self menuBindingSnapshot];
        self.applyingMenus = NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:TSMacroShortcutsChangedNotification object:self];
}
- (NSArray<NSDictionary *> *)conflictsForMacroShortcuts:(NSArray<NSDictionary *> *)candidates {
    return [self.store conflictsForMacroShortcuts:candidates] ?: @[];
}
- (void)menuStructureChanged:(NSNotification *)notification {
    NSMenu *menu = notification.object;
    while (menu.supermenu) menu = menu.supermenu;
    if (menu != NSApp.mainMenu || self.menuRefreshPending || self.applyingMenus || self.rebuildingMacros) return;
    if ([[self menuBindingSnapshot] isEqual:self.observedMenuBindings]) return;
    self.menuRefreshPending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.menuRefreshPending = NO;
        if (![[self menuBindingSnapshot] isEqual:self.observedMenuBindings]) [self refreshMenuAndMacros];
    });
}
+ (BOOL)event:(NSEvent *)event matchesAction:(SEL)action tag:(NSInteger)tag {
    __block BOOL matches = NO, found = NO;
    NSString *commandID = [NSString stringWithFormat:@"TSShortcut.%@.%ld", NSStringFromSelector(action), (long)tag];
    TSVisitMenu(NSApp.mainMenu, @"", ^(NSMenuItem *item, NSString *path) {
        if ((item.action == action && item.tag == tag) || [item.identifier isEqual:commandID] || [TSFindCommandID(item) isEqual:commandID]) {
            found = YES;
            if ([TSShortcutStore event:event matchesItem:item]) matches = YES;
        }
    });
    // Preserve PDF search if a custom menu entirely omits the standard Find commands.
    if (!found && action == @selector(performFindPanelAction:) && (tag == 1 || tag == 2)) {
        NSDictionary *key = TSBinding(TSShortcutCharacterForEvent(event), event.modifierFlags);
        return [key isEqual:TSBinding(tag == 1 ? @"f" : @"g", NSEventModifierFlagCommand)];
    }
    return matches;
}
@end
