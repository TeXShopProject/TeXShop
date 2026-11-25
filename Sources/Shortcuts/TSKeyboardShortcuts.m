// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
NSNotificationName const TSRebuildMacrosNotification = @"TSRebuildMacros";
NSNotificationName const TSMacroShortcutsChangedNotification = @"TSMacroShortcutsChanged";
@interface TSKeyboardShortcuts ()
@property (strong, readwrite, nullable) TSShortcutStore *store;
@property BOOL menuRefreshPending;
@property NSArray *observedMenuBindings;
@property BOOL rebuildingMacros;
@property BOOL applyingMenus;
@property (copy) NSString *keyboardLayout;
@property BOOL layoutRefreshPending;
@property BOOL settleCheckPending;
@property NSUInteger settleRounds;
@end

void TSGiveFullScreenGlobeKey(NSMenu *menu)
{
    NSMutableArray<NSMenuItem *> *items = [NSMutableArray array];
    TSVisitMenu(menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.action == @selector(toggleFullScreen:) && !item.submenu) [items addObject:item];
    });
    for (NSMenuItem *item in items) {
        // A hidden copy that AppKit added for a key the item had keeps no key.
        if (item.hidden) { item.keyEquivalent = @""; continue; }
        // The modifier first: the key alone would be Command-F (Find) for a moment.
        item.allowsAutomaticKeyEquivalentLocalization = NO;
        item.keyEquivalentModifierMask = NSEventModifierFlagFunction;
        item.keyEquivalent = @"f";
        // Where AppKit does not take the Globe key, the item has no key rather than a bare F.
        if (item.keyEquivalentModifierMask != NSEventModifierFlagFunction) item.keyEquivalent = @"";
    }
}

@implementation TSKeyboardShortcuts
+ (instancetype)sharedController {
    static TSKeyboardShortcuts *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[self alloc] init]; });
    return controller;
}
- (void)startAfterLaunchWithConfiguration:(void (^)(TSKeyboardShortcuts *shortcuts))configuration {
    // Find-menu providers finish their launch observers before overrides are installed.
    dispatch_async(dispatch_get_main_queue(), ^{
        configuration(self);
        [self startObservingMenu];
    });
}
- (void)startObservingMenu {
    if (self.store != nil) { [self refreshMenuAndMacros]; return; }
    NSMenu *menu = NSApp.mainMenu;
    if (menu == nil) { return; }
    // The store reads Globe-F as the default of Enter Full Screen.
    TSGiveFullScreenGlobeKey(menu);
    self.store = [[TSShortcutStore alloc] initWithMenu:menu defaults:NSUserDefaults.standardUserDefaults];
    self.store.macroProvider = self.macroProvider;
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
    // AppKit shows other keys on another keyboard layout; conflicts are worked out again with them.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardLayoutChanged:)
        name:NSTextInputContextKeyboardSelectionDidChangeNotification object:nil];
    // A layout chosen while TeXShop was in the background.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardLayoutChanged:)
        name:NSApplicationDidBecomeActiveNotification object:nil];
}
- (void)keyboardLayoutChanged:(NSNotification *)notification {
    // Switching an input method, as between Japanese and ABC, keeps the keyboard layout. Before
    // the first refresh there is nothing to follow: it goes by the layout chosen then.
    if (!self.keyboardLayout || [TSKeyboardLayoutID() isEqual:self.keyboardLayout] || self.layoutRefreshPending) return;
    self.layoutRefreshPending = YES;
    // The keys of the new layout are worked out in the next pass, before the menus are refreshed.
    if (!self.applyingMenus && !self.rebuildingMacros) [self.store learnLayoutKeysThen:^(BOOL learned) {}];
    [self refreshForKeyboardLayout];
}
- (void)refreshForKeyboardLayout {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.applyingMenus || self.rebuildingMacros) { [self refreshForKeyboardLayout]; return; }
        self.layoutRefreshPending = NO;
        if (![TSKeyboardLayoutID() isEqual:self.keyboardLayout]) [self refreshMenuAndMacros];
    });
}
// AppKit adapts reassigned keys to the keyboard layout in a later pass of the run loop, and
// shows the keys of another layout a little after it is chosen. Once it has, the defaults are
// read as shown, the ones the store does not know on this layout are worked out, and when
// any key differs from what the last refresh saw, the menus are refreshed with them.
- (void)noteShownKeysAfterRefresh {
    if (self.settleCheckPending) return;
    self.settleCheckPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.settleCheckPending = NO;
        if (self.applyingMenus || self.rebuildingMacros) { [self noteShownKeysAfterRefresh]; return; }
        self.observedMenuBindings = [self menuBindingSnapshot];
        [self.store learnLayoutKeysThen:^(BOOL learned) {
            BOOL changed = [self.store shownKeysChangedSinceAssignment];
            if (changed && self.settleRounds < 2 && !self.applyingMenus && !self.rebuildingMacros) {
                self.settleRounds++;
                [self refreshMenuAndMacros];
                return;
            }
            self.settleRounds = 0;
            self.observedMenuBindings = [self menuBindingSnapshot];
            [[NSNotificationCenter defaultCenter] postNotificationName:TSMacroShortcutsChangedNotification object:self];
        }];
    });
}
- (void)beginMenuRebuild {
    self.rebuildingMacros = YES;
    [self.store refreshMenu];
}
- (void)endMenuRebuild {
    self.rebuildingMacros = NO;
    self.observedMenuBindings = [self menuBindingSnapshot];

    [[NSNotificationCenter defaultCenter] postNotificationName:TSMacroShortcutsChangedNotification object:self];
    [self noteShownKeysAfterRefresh];
}
- (void)refreshMenuAndMacros {
    if (self.applyingMenus || self.rebuildingMacros) return;
    self.applyingMenus = YES;
    self.keyboardLayout = TSKeyboardLayoutID();
    @try {
        [self.store refreshMenu];
        [[NSNotificationCenter defaultCenter] postNotificationName:TSRebuildMacrosNotification object:self];

    } @finally {
        self.observedMenuBindings = [self menuBindingSnapshot];
        self.applyingMenus = NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:TSMacroShortcutsChangedNotification object:self];
    [self noteShownKeysAfterRefresh];
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
    // Find Previous is ⇧⌘G. A key the user assigned is on the menu item and was compared above.
    if (!found && action == @selector(performFindPanelAction:) && tag >= 1 && tag <= 3) {
        NSString *character = tag == 1 ? @"f" : @"g";
        NSEventModifierFlags modifiers = NSEventModifierFlagCommand;
        if (tag == 3)
            modifiers |= NSEventModifierFlagShift;
        NSDictionary *key = TSBinding(TSShortcutCharacterForEvent(event), event.modifierFlags);
        return [key isEqual:TSBinding(character, modifiers)];
    }
    return matches;
}
@end
