// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
NSString * const TSMenuShortcutOverridesKey = @"TSMenuShortcutOverrides";
static NSString * const TSFullScreenCommandID = @"TSShortcut.toggleFullScreen:.0";
@interface TSShortcutCommand (PathUpdates)
@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic, readwrite) BOOL managedBySystem;
@end
@interface TSShortcutStore ()
@property NSMenu *menu;
@property NSUserDefaults *defaults;
@property NSMutableDictionary<NSString *, TSShortcutBinding *> *overrides;
@property (readwrite, copy) NSArray<TSShortcutCommand *> *commands;
@property (readwrite, copy) NSArray<NSString *> *unavailableCommands;
// Commands whose item does not have its default key: a saved key or, for a yielding default, none.
@property (copy) NSSet<NSString *> *heldCommandIDs;
// The keys each menu item had at the last refresh, as given and as AppKit showed them.
@property NSMapTable<NSMenuItem *, NSSet<TSShortcutBinding *> *> *itemBindings;
// For each keyboard layout, the keys AppKit shows for keys given with Command, and with
// Command and Shift (-learnLayoutKeysThen:).
@property NSMutableDictionary<NSString *, NSDictionary<TSShortcutBinding *, TSShortcutBinding *> *> *layoutKeys;
// For keys whose items all met other items and more than one key could be the one shown: those keys.
@property NSMutableDictionary<NSString *, NSDictionary<TSShortcutBinding *, NSSet<TSShortcutBinding *> *> *> *possibleLayoutKeys;
// Saved keys of commands restored before the keys of the current layout were known.
@property (nullable, copy) NSDictionary<NSString *, NSArray *> *restoredBeforeLayoutKeys;
// Commands given a key before the keys of the current layout were known, with that layout.
@property (nullable, copy) NSDictionary<NSString *, NSString *> *recordedBeforeLayoutKeys;
@property (copy) NSArray *assignedShownKeys;
@property (copy) NSString *assignedLayout;
// The hidden items AppKit shows keys in, while they are in the menu, and who waits for them.
@property (nullable) NSMenuItem *learningHolder;
@property (nullable, copy) NSString *learningLayout;
@property NSMutableArray<void (^)(BOOL)> *learningCompletions;
@end
// Commands whose default key is only a proposal: they take it only when no other menu
// command (with its key as resolved) and no macro (as its file names it) has it, and
// they never make another command's key unavailable. F5 is Complete Label or Citation
// Key. The other five are the Advanced Find shortcuts added in 6.00.
static NSSet<NSString *> *TSYieldingDefaultCommands(void) {
    return [NSSet setWithObjects:
        @"TSShortcut.completeLabelOrCitationKey:.0",
        @"TSShortcut.performFindPanelAction:.106",
        @"TSShortcut.performFindPanelAction:.101",
        @"TSShortcut.performFindPanelAction:.6",
        @"TSShortcut.performFindPanelAction:.102",
        @"TSShortcut.performFindPanelAction:.103",
        nil];
}
// Every Show All Tabs item, including a hidden copy, is this one command. AppKit's ⇧⌘\
// is cleared before the command is created: initWithItem: keeps the first key it sees
// as defaultKey and never updates it. An empty item is left untouched, because writing
// the key again is not what schedules the next refresh (only item insertion and removal
// are observed). A key saved in Settings is applied afterwards. That assignment does not
// make the command run while AppKit leaves the item disabled; the key is consumed and
// the window beeps.
static void TSClearAppKitTabOverviewKey(NSMenu *menu) {
    TSVisitMenu(menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.action != NSSelectorFromString(@"toggleTabOverview:")) return;
        (void)path;
        if (item.keyEquivalent.length == 0 && item.keyEquivalentModifierMask == 0) return;
        item.keyEquivalent = @"";
        item.keyEquivalentModifierMask = 0;
    });
}
@implementation TSShortcutStore
- (NSArray<NSString *> *)settingsSearchCommandNames
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (TSShortcutCommand *command in self.commands)
        if (!command.item.hidden || command.item.allowsKeyEquivalentWhenHidden) [names addObject:command.path];
    return [names copy];
}
- (instancetype)initWithMenu:(NSMenu *)menu defaults:(NSUserDefaults *)defaults {
    if (!(self = [super init])) return nil;
    _menu = menu; _defaults = defaults;
    id saved = [defaults objectForKey:TSMenuShortcutOverridesKey];
    _overrides = [NSMutableDictionary dictionary];
    // Treat a malformed preference as absent, including invalid individual entries.
    if ([saved isKindOfClass:NSDictionary.class]) {
        [saved enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSDictionary.class]) return;
            // Enter Full Screen has Globe-F since 6.00; a key saved for it before is left out.
            if ([key isEqual:TSFullScreenCommandID]) return;
            id character = value[@"key"], modifiers = value[@"modifiers"];
            if ([character isKindOfClass:NSString.class] && [modifiers isKindOfClass:NSNumber.class] &&
                [TSShortcutStore isAllowedKey:character modifiers:[modifiers unsignedIntegerValue]])
                self.overrides[key] = TSBinding(character, [modifiers unsignedIntegerValue]);
        }];
    }
    [self refreshMenu];
    return self;
}
- (void)refreshMenu {
    TSClearAppKitTabOverviewKey(self.menu);
    TSPrepareMenuIdentifiers(self.menu);
    NSMapTable *previous = [NSMapTable strongToStrongObjectsMapTable];
    for (TSShortcutCommand *command in self.commands) [previous setObject:command forKey:command.item];
    NSMutableArray *commands = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray<NSMenuItem *> *hiddenTabCopies = [NSMutableArray array];
    NSMutableArray<NSString *> *hiddenTabPaths = [NSMutableArray array];
    // When documents autosave, AppKit adds Duplicate and resets Save As… to ⌥⇧⌘S whenever
    // it updates the menu, so Save As… keeps the shortcut macOS gives it, as in Xcode.
    __block BOOL appKitSaveAs = NO;
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.action == @selector(duplicateDocument:)) appKitSaveAs = YES;
    });
    void (^addCommand)(NSMenuItem *, NSString *) = ^(NSMenuItem *item, NSString *path) {
        NSString *identifier = item.identifier ?: @"";
        if ([seen containsObject:identifier]) return;
        [seen addObject:identifier];
        TSShortcutCommand *command = [previous objectForKey:item];
        if (!command) {
            command = [[TSShortcutCommand alloc] initWithItem:item identifier:identifier path:path];
        }
        // Enter Full Screen has Globe-F, which macOS gives only its own items (TSGiveFullScreenGlobeKey).
        command.path = path; command.managedBySystem = (appKitSaveAs && item.action == @selector(saveDocumentAs:)) || item.action == @selector(toggleFullScreen:);
        [commands addObject:command];
    };
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        NSString *identifier = item.identifier ?: @"";
        if (![identifier hasPrefix:@"TSShortcut."] || !item.action || item.submenu) return;
        // A hidden Show All Tabs copy cannot show a key. Prefer a visible copy, so a key
        // saved in Settings is attached to the item the user can see.
        if (item.action == NSSelectorFromString(@"toggleTabOverview:") && item.hidden && !item.allowsKeyEquivalentWhenHidden) {
            [hiddenTabCopies addObject:item];
            [hiddenTabPaths addObject:path ?: @""];
            return;
        }
        addCommand(item, path);
    });
    if (![seen containsObject:@"TSShortcut.toggleTabOverview:.0"] && hiddenTabCopies.count)
        addCommand(hiddenTabCopies[0], hiddenTabPaths[0]);
    self.commands = commands;
    [self adoptRenamedCommands];
    [self applySavedOverrides];
}
// Before 6.00, the Italian File Encoding and TeXShop item had the identifier of the
// ConTeXt item. A shortcut saved for it moves to the item it was assigned to, unless
// the menu has an item with the old identifier or the item already has a shortcut.
- (void)adoptRenamedCommands {
    NSDictionary<NSString *, NSString *> *renamed = @{@"TSShortcut.displayGettingStartedConTeXt:.0": @"TSShortcut.displayFileEncoding:.0"};
    NSSet *present = [NSSet setWithArray:[self.commands valueForKey:@"commandID"]];
    [renamed enumerateKeysAndObjectsUsingBlock:^(NSString *old, NSString *current, BOOL *stop) {
        if (!self.overrides[old] || self.overrides[current] || [present containsObject:old] || ![present containsObject:current]) return;
        self.overrides[current] = self.overrides[old];
        [self.overrides removeObjectForKey:old];
    }];
}
// Whether the item of a command has its default key now, as the store assigned it.
- (BOOL)commandHoldsDefault:(TSShortcutCommand *)command {
    return ![self.heldCommandIDs containsObject:command.commandID] && !command.managedBySystem &&
        command.item.allowsAutomaticKeyEquivalentLocalization == command.defaultLocalization;
}
// Keys AppKit adapts to the layout: not letters, which every layout keeps, nor function keys.
static BOOL TSLayoutAdaptsKey(NSString *key) {
    if (key.length != 1) return NO;
    unichar c = [key characterAtIndex:0];
    return !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c >= 0x7f || c < 0x21);
}
// The keys a layout's table has: every such key with Command, and with Command and Shift.
static NSUInteger TSLayoutKeyCount(void) { return 2 * (0x7f - 0x21 - 52); }
// The modifiers each key of a layout's table is given with, Command first.
static NSArray<NSNumber *> *TSLayoutKeyVariants(void) {
    const NSEventModifierFlags C = NSEventModifierFlagCommand, K = NSEventModifierFlagControl, O = NSEventModifierFlagOption;
    return @[@(C), @(C | K | O), @(C | K), @(C | O), @(K), @(O)];
}
// AppKit adapts a key with any modifiers as it adapts the same key with Command, or with
// Command and Shift when the modifiers include Shift: the shown key and Shift come from that,
// the other modifiers stay. The keys AppKit shows with Command and with Command and Shift are
// worked out for each layout (-learnLayoutKeysThen:).
- (nullable TSShortcutBinding *)layoutShownKey:(NSString *)key modifiers:(NSEventModifierFlags)flags layout:(NSString *)layout {
    TSShortcutBinding *given = TSBinding(key, flags);
    if (!TSLayoutAdaptsKey(given.key)) return given;
    NSDictionary<TSShortcutBinding *, TSShortcutBinding *> *keys = self.layoutKeys[layout];
    if (!keys) return nil;
    TSShortcutBinding *base = keys[TSBinding(given.key, NSEventModifierFlagCommand | (given.modifiers & NSEventModifierFlagShift))];
    if (!base) return nil;
    return TSBinding(base.key, (given.modifiers & ~NSEventModifierFlagShift) | (base.modifiers & NSEventModifierFlagShift));
}
// A key as AppKit shows it on the current layout, or the key itself while that is not known.
- (TSShortcutBinding *)shownBindingForGivenKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    return [self layoutShownKey:key modifiers:flags layout:TSKeyboardLayoutID()] ?: TSBinding(key, flags);
}
// The keys of the current layout are known, or the layout is the one the keys were last
// assigned on, whose defaults the items showed.
- (BOOL)knowsKeysOfCurrentLayout {
    NSString *layout = TSKeyboardLayoutID();
    return self.layoutKeys[layout] != nil || [layout isEqual:self.assignedLayout];
}
// The default of a command as AppKit shows it on the current keyboard layout.
- (TSShortcutBinding *)shownDefaultForCommand:(TSShortcutCommand *)command {
    TSShortcutBinding *given = TSBinding(command.defaultKey, command.defaultModifiers);
    if (!command.defaultLocalization || !TSLayoutAdaptsKey(given.key)) return given;
    NSString *layout = TSKeyboardLayoutID();
    TSShortcutBinding *shown = [self layoutShownKey:command.defaultKey modifiers:command.defaultModifiers layout:layout];
    if (shown) return shown;
    // Before the layout's keys are worked out: the key the item shows while it has the default,
    // or the key it showed on this layout before.
    TSShortcutBinding *known = command.shownDefaults[layout];
    if ([self commandHoldsDefault:command]) {
        // Until AppKit adapts a key assigned again, the item shows the given key.
        TSShortcutBinding *live = TSShownBinding(command.item);
        if (!live.key.length || ([live isEqual:given] && known)) return known ?: given;
        command.shownDefaults[layout] = live;
        return live;
    }
    return known ?: given;
}
- (void)noteShownDefaultsSettled {
    NSString *layout = TSKeyboardLayoutID();
    for (TSShortcutCommand *command in self.commands) {
        if (!command.defaultLocalization || !TSLayoutAdaptsKey(command.defaultKey) || ![self commandHoldsDefault:command]) continue;
        TSShortcutBinding *shown = TSShownBinding(command.item);
        if (shown.key.length) command.shownDefaults[layout] = shown;
    }
}
- (TSShortcutBinding *)shownBindingForCommand:(TSShortcutCommand *)command {
    if (!command.item.keyEquivalent.length || ![self commandHoldsDefault:command]) return TSShownBinding(command.item);
    return [self shownDefaultForCommand:command];
}
- (void)learnLayoutKeysThen:(void (^)(BOOL learned))completion {
    NSString *layout = TSKeyboardLayoutID();
    NSDictionary *known = self.layoutKeys[layout];
    if ((known && known.count == TSLayoutKeyCount()) || !self.menu) { completion(NO); return; }
    if (!self.learningCompletions) self.learningCompletions = [NSMutableArray array];
    [self.learningCompletions addObject:[completion copy]];
    // One working out per layout: whoever asks while it runs waits for the same one.
    if (self.learningHolder && [self.learningLayout isEqual:layout]) return;
    [self stopLearning];
    // Hidden items without an action, in the menu for one pass of the run loop, never run.
    // AppKit leaves a key empty when another item shows it, so each key comes again with other
    // modifiers, which AppKit keeps as they are while it adapts the key in the same way.
    const NSEventModifierFlags C = NSEventModifierFlagCommand;
    NSArray<NSNumber *> *variants = TSLayoutKeyVariants();
    NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    holder.identifier = TSShortcutLearningIdentifier; holder.hidden = YES;
    holder.submenu = [[NSMenu alloc] initWithTitle:@""];
    NSMutableArray<TSShortcutBinding *> *bases = [NSMutableArray array];
    NSMutableArray<NSArray<NSMenuItem *> *> *items = [NSMutableArray array];
    for (unichar c = 0x21; c < 0x7f; c++) {
        NSString *key = [NSString stringWithCharacters:&c length:1];
        if (!TSLayoutAdaptsKey(key)) continue;
        for (NSNumber *shift in @[@0, @(NSEventModifierFlagShift)]) {
            NSEventModifierFlags flags = C | shift.unsignedIntegerValue;
            if (known[TSBinding(key, flags)]) continue;
            NSMutableArray *pair = [NSMutableArray array];
            for (NSNumber *variant in variants) {
                NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
                item.hidden = YES; item.keyEquivalentModifierMask = variant.unsignedIntegerValue | shift.unsignedIntegerValue; item.keyEquivalent = key;
                [holder.submenu addItem:item]; [pair addObject:item];
            }
            [bases addObject:TSBinding(key, flags)]; [items addObject:pair];
        }
    }
    [self.menu addItem:holder];
    self.learningHolder = holder; self.learningLayout = layout;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Assigning keys removes the items first (-applySavedOverrides): AppKit would empty a
        // key assigned later that one of them shows. That working out then starts again.
        if (self.learningHolder != holder) return;
        BOOL learned = NO;
        if ([TSKeyboardLayoutID() isEqual:layout]) {
            NSMutableDictionary *keys = [self.layoutKeys[layout] mutableCopy] ?: [NSMutableDictionary dictionary];
            // A key AppKit left empty with every variant shows as another item's key with each of
            // them: when only one key has items with all of them, that is the key.
            NSMutableDictionary<TSShortcutBinding *, NSSet *> *possible = [NSMutableDictionary dictionary];
            NSMutableSet<TSShortcutBinding *> *occupied = [NSMutableSet set];
            NSMutableSet<NSString *> *characters = [NSMutableSet set];
            TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
                if (item.submenu || !item.keyEquivalent.length) return;
                TSShortcutBinding *shown = TSShownBinding(item);
                [occupied addObject:shown]; [characters addObject:shown.key];
            });
            [bases enumerateObjectsUsingBlock:^(TSShortcutBinding *base, NSUInteger index, BOOL *stop) {
                [variants enumerateObjectsUsingBlock:^(NSNumber *variant, NSUInteger position, BOOL *found) {
                    TSShortcutBinding *shown = TSShownBinding(items[index][position]);
                    NSEventModifierFlags asked = variant.unsignedIntegerValue;
                    if (!shown.key.length || (shown.modifiers & asked) != asked) return;
                    keys[base] = TSBinding(shown.key, C | (shown.modifiers & NSEventModifierFlagShift)); *found = YES;
                }];
                if (keys[base]) return;
                NSMutableSet<TSShortcutBinding *> *candidates = [NSMutableSet set];
                for (NSString *character in characters)
                    for (NSNumber *shift in @[@0, @(NSEventModifierFlagShift)]) {
                        BOOL everywhere = YES;
                        for (NSNumber *variant in variants)
                            if (![occupied containsObject:TSBinding(character, variant.unsignedIntegerValue | shift.unsignedIntegerValue)]) { everywhere = NO; break; }
                        if (everywhere) [candidates addObject:TSBinding(character, C | shift.unsignedIntegerValue)];
                    }
                if (candidates.count == 1) keys[base] = candidates.anyObject;
                else if (candidates.count > 1) possible[base] = candidates;
            }];
            if (!self.layoutKeys) self.layoutKeys = [NSMutableDictionary dictionary];
            learned = keys.count > [self.layoutKeys[layout] count] || !self.layoutKeys[layout];
            self.layoutKeys[layout] = keys;
            if (!self.possibleLayoutKeys) self.possibleLayoutKeys = [NSMutableDictionary dictionary];
            self.possibleLayoutKeys[layout] = possible;
        }
        [self stopLearning];
        NSArray<void (^)(BOOL)> *waiting = [self.learningCompletions copy];
        [self.learningCompletions removeAllObjects];
        if (learned) [self checkChangesMadeBeforeLayoutKeys:layout];
        for (void (^waiter)(BOOL) in waiting) waiter(learned);
    });
}
// Recording or restoring before the layout's keys were known went by the given default. Once
// the keys of the layout it happened on are known, a recorded key that the layout shows for
// the default restores the command, and a restored default that another command's saved key,
// a macro or a menu item meets gives way to the key it had; neither takes a key from another.
- (BOOL)defaultOfCommandIsTaken:(TSShortcutCommand *)command {
    NSSet<TSShortcutBinding *> *defaults = [self defaultBindingsForCommand:command];
    for (TSShortcutCommand *other in self.commands) {
        TSShortcutBinding *saved = self.overrides[other.commandID];
        if (other != command && saved && [defaults containsObject:saved]) return YES;
    }
    for (TSShortcutMacro *macro in (self.macroProvider ? self.macroProvider() : @[]))
        for (TSShortcutBinding *binding in [self bindingsForMacroKey:macro.key modifiers:macro.modifiers])
            if (binding.key.length && [defaults containsObject:binding]) return YES;
    return [self conflictForRestoringCommand:command] != nil;
}
- (void)checkChangesMadeBeforeLayoutKeys:(NSString *)layout {
    NSMutableDictionary<NSString *, NSArray *> *restored = [self.restoredBeforeLayoutKeys mutableCopy];
    NSMutableDictionary<NSString *, NSString *> *recorded = [self.recordedBeforeLayoutKeys mutableCopy];
    BOOL changed = NO;
    for (TSShortcutCommand *command in self.commands) {
        NSString *identifier = command.commandID;
        TSShortcutBinding *saved = self.overrides[identifier];
        if ([recorded[identifier] isEqual:layout]) {
            [recorded removeObjectForKey:identifier];
            if (saved && [saved isEqual:[self layoutShownKey:command.defaultKey modifiers:command.defaultModifiers layout:layout]]) {
                [self.overrides removeObjectForKey:identifier];
                if ([self defaultOfCommandIsTaken:command]) self.overrides[identifier] = saved;
                else changed = YES;
            }
        }
        if ([restored[identifier][1] isEqual:layout]) {
            if (!saved && [self defaultOfCommandIsTaken:command]) { self.overrides[identifier] = restored[identifier][0]; changed = YES; }
            [restored removeObjectForKey:identifier];
        }
    }
    self.restoredBeforeLayoutKeys = restored.count ? restored : nil;
    self.recordedBeforeLayoutKeys = recorded.count ? recorded : nil;
    if (changed) { [self applySavedOverrides]; [self persist]; }
}
- (NSArray<TSShortcutBinding *> *)bindingsForMacroKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    TSShortcutBinding *given = TSBinding(key, flags);
    NSMutableOrderedSet<TSShortcutBinding *> *result = [NSMutableOrderedSet orderedSetWithObject:given];
    [result addObject:[self shownBindingForGivenKey:key modifiers:flags]];
    // When the layout could show the key as one of several, each of them is taken as its key,
    // so that a key another item has is never let through unseen.
    if (TSLayoutAdaptsKey(given.key)) {
        TSShortcutBinding *base = TSBinding(given.key, NSEventModifierFlagCommand | (given.modifiers & NSEventModifierFlagShift));
        for (TSShortcutBinding *possible in self.possibleLayoutKeys[TSKeyboardLayoutID()][base])
            [result addObject:TSBinding(possible.key, (given.modifiers & ~NSEventModifierFlagShift) | (possible.modifiers & NSEventModifierFlagShift))];
    }
    return result.array;
}
// The key a macro item was given: the macro whose key the layout shows as the item's.
- (TSShortcutBinding *)givenBindingForMacroItem:(NSMenuItem *)item {
    return [self givenBindingForMacroItem:item path:nil];
}
// The macro an item was made for is the one at its place in the Macros menu; two macros can
// show the same key on a layout, of which only the first has it. Without a place that tells,
// the macro whose key the layout shows as the item's.
- (TSShortcutBinding *)givenBindingForMacroItem:(NSMenuItem *)item path:(nullable NSString *)path {
    TSShortcutBinding *shown = TSShownBinding(item);
    NSArray<TSShortcutMacro *> *macros = self.macroProvider ? self.macroProvider() : @[];
    // The Macros menu names each item after the place of its macro in the macro file.
    if (item.identifier.length)
        for (TSShortcutMacro *macro in macros)
            if (macro.key.length && [TSMacroItemIdentifier(macro.indexPath) isEqual:item.identifier]) return TSBinding(macro.key, macro.modifiers);
    NSMutableArray<TSShortcutMacro *> *placed = [NSMutableArray array];
    // The menu's own name for Macros can differ from the one macro paths start with.
    NSString *(^withinMacros)(NSString *) = ^NSString *(NSString *full) {
        NSRange first = [full rangeOfString:@" › "];
        return first.location == NSNotFound ? full : [full substringFromIndex:NSMaxRange(first)];
    };
    if (path) for (TSShortcutMacro *macro in macros) if (macro.key.length && [withinMacros(macro.path) isEqual:withinMacros(path)]) [placed addObject:macro];
    if (placed.count == 1) return TSBinding(placed[0].key, placed[0].modifiers);
    if (placed.count > 1) macros = placed;
    for (TSShortcutMacro *macro in macros)
        if (macro.key.length && [[self shownBindingForGivenKey:macro.key modifiers:macro.modifiers] isEqual:shown]) return TSBinding(macro.key, macro.modifiers);
    // A key the layout could show as one of several: the macro one of whose keys the item shows.
    for (TSShortcutMacro *macro in macros)
        if (macro.key.length && [[self bindingsForMacroKey:macro.key modifiers:macro.modifiers] containsObject:shown]) return TSBinding(macro.key, macro.modifiers);
    return shown;
}
// The shown keys the last assignment went by: the defaults, the other items and the macros.
- (NSArray *)shownKeySignature {
    NSMutableArray *signature = [NSMutableArray array];
    NSMutableSet *commandItems = [NSMutableSet set];
    for (TSShortcutCommand *command in self.commands) {
        [signature addObject:[self shownDefaultForCommand:command]];
        [commandItems addObject:[NSValue valueWithNonretainedObject:command.item]];
    }
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.submenu || item.action == TSMacroAction() || !item.keyEquivalent.length) return;
        if (![commandItems containsObject:[NSValue valueWithNonretainedObject:item]]) [signature addObject:TSShownBinding(item)];
    });
    for (TSShortcutMacro *macro in (self.macroProvider ? self.macroProvider() : @[]))
        if (macro.key.length) [signature addObject:[self shownBindingForGivenKey:macro.key modifiers:macro.modifiers]];
    return signature;
}
- (BOOL)shownKeysChangedSinceAssignment {
    [self noteShownDefaultsSettled];
    return ![[self shownKeySignature] isEqual:self.assignedShownKeys];
}
// A default reserves its key as given and as shown: the given key is the one it shows
// again on a layout like the one the menu was made for.
- (NSSet<TSShortcutBinding *> *)defaultBindingsForCommand:(TSShortcutCommand *)command {
    TSShortcutBinding *given = TSBinding(command.defaultKey, command.defaultModifiers);
    if (!given.key.length) return [NSSet set];
    return [NSSet setWithObjects:given, [self shownDefaultForCommand:command], nil];
}
// Whether the item has the key already. Assigning a key again makes AppKit show the given
// key until it adapts the key once more, so unchanged items are left alone.
- (BOOL)command:(TSShortcutCommand *)command hasKey:(TSShortcutBinding *)target localized:(BOOL)localized {
    NSMenuItem *item = command.item;
    TSShortcutBinding *shown = TSShownBinding(item);
    if (!target.key.length) return !shown.key.length;
    if (item.allowsAutomaticKeyEquivalentLocalization != localized) return NO;
    if ([shown isEqual:target]) return YES;
    if (!localized) return NO;
    if ([target isEqual:TSBinding(command.defaultKey, command.defaultModifiers)] && [shown isEqual:[self shownDefaultForCommand:command]]) return YES;
    return [TSGivenBinding(item) isEqual:target];
}
- (void)stopLearning {
    NSMenuItem *holder = self.learningHolder;
    self.learningHolder = nil; self.learningLayout = nil;
    if (holder.menu) [holder.menu removeItem:holder];
}
// Assigning keys took the hidden items away before AppKit showed their keys: whoever waits
// for them gets a new working out.
- (void)resumeLearning {
    if (self.learningHolder || !self.learningCompletions.count) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.learningHolder || !self.learningCompletions.count) return;
        NSArray<void (^)(BOOL)> *waiting = [self.learningCompletions copy];
        [self.learningCompletions removeAllObjects];
        for (void (^waiter)(BOOL) in waiting) [self learnLayoutKeysThen:waiter];
    });
}
- (void)applySavedOverrides {
    [self stopLearning];
    // What AppKit shows before anything is assigned; reading given keys below makes items
    // show those until AppKit adapts them again.
    self.assignedShownKeys = [self shownKeySignature];
    NSMutableSet *active = [NSMutableSet set];
    NSMutableOrderedSet *unavailable = [NSMutableOrderedSet orderedSet];
    NSSet<NSString *> *yielding = TSYieldingDefaultCommands();
    // A saved shortcut of a command macOS keeps stays saved and applies when macOS lets it.
    for (TSShortcutCommand *command in self.commands)
        if (self.overrides[command.commandID] && !command.managedBySystem) [active addObject:command.commandID];
    NSMapTable<NSMenuItem *, TSShortcutCommand *> *commandItems = [NSMapTable strongToStrongObjectsMapTable];
    NSMapTable<NSMenuItem *, NSSet<TSShortcutBinding *> *> *defaults = [NSMapTable strongToStrongObjectsMapTable];
    for (TSShortcutCommand *command in self.commands) {
        [commandItems setObject:command forKey:command.item];
        [defaults setObject:[self defaultBindingsForCommand:command] forKey:command.item];
    }
    // Other menu items keep their keys, as given and as shown on this layout.
    NSMapTable<NSMenuItem *, NSSet<TSShortcutBinding *> *> *planned = [NSMapTable strongToStrongObjectsMapTable];
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.submenu || item.action == TSMacroAction() || [commandItems objectForKey:item]) return;
        TSShortcutBinding *shown = TSShownBinding(item);
        if (shown.key.length) [planned setObject:[NSSet setWithObjects:shown, TSGivenBinding(item), nil] forKey:item];
    });
    BOOL changed;
    do {
        changed = NO;
        for (TSShortcutCommand *command in self.commands) {
            // A yielding default is held back while the other commands are resolved.
            TSShortcutBinding *saved = self.overrides[command.commandID];
            NSSet *value = saved && [active containsObject:command.commandID] ? [NSSet setWithObject:saved]
                : [yielding containsObject:command.commandID] ? [NSSet set] : [defaults objectForKey:command.item];
            [planned setObject:value forKey:command.item];
        }
        NSMutableSet *rejected = [NSMutableSet set];
        for (TSShortcutCommand *command in self.commands) {
            if (![active containsObject:command.commandID]) continue;
            TSShortcutBinding *value = self.overrides[command.commandID];
            if (![value[@"key"] length]) continue;
            for (NSMenuItem *other in planned.keyEnumerator) {
                if (other != command.item && [[planned objectForKey:other] containsObject:value]) {
                    [rejected addObject:command.commandID]; [unavailable addObject:command.path]; break;
                }
            }
        }
        if (rejected.count) { [active minusSet:rejected]; changed = YES; }
    } while (changed);
    // With every other command resolved, a yielding default takes its key only if no menu
    // command and no macro has it.
    NSMutableSet *yielded = [NSMutableSet set];
    NSArray<TSShortcutMacro *> *macros = self.macroProvider ? self.macroProvider() : @[];
    for (TSShortcutCommand *command in self.commands) {
        if ([active containsObject:command.commandID] || ![yielding containsObject:command.commandID]) continue;
        NSSet<TSShortcutBinding *> *proposal = [defaults objectForKey:command.item];
        if (!proposal.count) continue;
        BOOL owned = NO;
        for (NSMenuItem *other in planned.keyEnumerator)
            if (other != command.item && [[planned objectForKey:other] intersectsSet:proposal]) { owned = YES; break; }
        for (TSShortcutMacro *macro in macros)
            if (!owned && [proposal containsObject:TSBinding(macro.key, macro.modifiers)]) owned = YES;
        if (owned) [yielded addObject:command.commandID];
        else [planned setObject:proposal forKey:command.item];
    }
    // Remove old macro keys before assigning menus; AppKit can otherwise suppress
    // a menu assignment which duplicates an installed macro. Rebuild macros next.
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.action == TSMacroAction()) item.keyEquivalent = @"";
    });
    // A default is assigned as the menu gives it, so that AppKit adapts it to the keyboard
    // layout as it does the menu's own keys; a saved key is assigned as recorded.
    NSMutableArray<TSShortcutCommand *> *changing = [NSMutableArray array];
    for (TSShortcutCommand *command in self.commands) {
        // Globe-F stays as it was given: assigning it again could lose the Globe key.
        if (command.managedBySystem && command.item.action == @selector(toggleFullScreen:)) continue;
        BOOL saved = [active containsObject:command.commandID], none = [yielded containsObject:command.commandID];
        TSShortcutBinding *target = saved ? self.overrides[command.commandID] : none ? TSBinding(@"", 0) : TSBinding(command.defaultKey, command.defaultModifiers);
        if (![self command:command hasKey:target localized:saved ? NO : none ? command.item.allowsAutomaticKeyEquivalentLocalization : command.defaultLocalization])
            [changing addObject:command];
    }
    // Avoid transient duplicates when restoring defaults or swapping two saved bindings.
    for (TSShortcutCommand *command in changing) command.item.keyEquivalent = @"";
    for (TSShortcutCommand *command in changing) {
        if ([active containsObject:command.commandID]) [self apply:self.overrides[command.commandID] to:command];
        else if ([yielded containsObject:command.commandID]) {
            command.item.keyEquivalentModifierMask = 0;
            command.item.keyEquivalent = @"";
        } else {
            command.item.allowsAutomaticKeyEquivalentLocalization = command.defaultLocalization;
            command.item.keyEquivalentModifierMask = command.defaultModifiers;
            command.item.keyEquivalent = command.defaultKey;
        }
    }
    for (TSShortcutCommand *command in self.commands) {
        if ([active containsObject:command.commandID] &&
            ![TSShownBinding(command.item) isEqual:self.overrides[command.commandID]])
            [unavailable addObject:command.path];
    }
    NSMutableSet *held = [active mutableCopy]; [held unionSet:yielded];
    self.heldCommandIDs = held;
    self.itemBindings = planned;
    if (!self.assignedLayout) self.assignedLayout = TSKeyboardLayoutID();
    self.unavailableCommands = unavailable.array;
    [self resumeLearning];
}
// Only the effective menu bindings reserve keys. AppKit-inserted commands
// participate while present; only those TSFindCommandID names can be customized.
// Each item reserves its key as shown on this keyboard layout and as given: macros are
// given keys too, which AppKit adapts in the same way.
// A command Keyboard settings can clear carries its commandID, so the macro editor can
// remove that key. A command macOS keeps, and an item with no command, do not.
+ (NSArray<NSDictionary *> *)menuBindings:(NSMenu *)menu {
    TSShortcutStore *store = TSKeyboardShortcuts.sharedController.store;
    NSMapTable *known = store.menu == menu ? store.itemBindings : nil;
    NSMapTable<NSMenuItem *, NSString *> *removable = nil;
    if (store.menu == menu) {
        removable = [NSMapTable strongToStrongObjectsMapTable];
        for (TSShortcutCommand *command in store.commands)
            if (!command.managedBySystem) [removable setObject:command.commandID forKey:command.item];
    }
    NSMutableArray *result = [NSMutableArray array];
    TSVisitMenu(menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.hidden && !item.allowsKeyEquivalentWhenHidden) return;
        if (item.submenu || item.action == TSMacroAction() || !item.keyEquivalent.length) return;
        NSMutableOrderedSet<TSShortcutBinding *> *bindings = [NSMutableOrderedSet orderedSetWithObject:TSShownBinding(item)];
        NSSet *previous = [known objectForKey:item];
        if (previous) [bindings addObjectsFromArray:previous.allObjects];
        else [bindings addObject:TSGivenBinding(item)];
        NSString *commandID = [removable objectForKey:item];
        NSUInteger added = result.count;
        for (TSShortcutBinding *binding in bindings)
            if (binding.key.length)
                [result addObject:@{@"path":path, @"key":binding.key, @"modifiers":@(binding.modifiers), @"macro":@NO}];
        if (commandID)
            for (NSUInteger index = added; index < result.count; index++) {
                NSMutableDictionary *entry = [result[index] mutableCopy];
                entry[@"commandID"] = commandID;
                result[index] = entry;
            }
    });
    return result;
}
+ (TSShortcutBinding *)normalizedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags { return TSBinding(key, flags); }
+ (NSArray<TSShortcutBinding *> *)bindingsForMacroKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    TSShortcutStore *store = TSKeyboardShortcuts.sharedController.store;
    return store ? [store bindingsForMacroKey:key modifiers:flags] : @[TSBinding(key, flags)];
}
- (NSArray<NSDictionary *> *)conflictsForMacroShortcuts:(NSArray<NSDictionary *> *)candidates {
    NSMutableDictionary *reserved = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in [TSShortcutStore menuBindings:self.menu]) {
        TSShortcutBinding *binding = TSBinding(entry[@"key"], [entry[@"modifiers"] unsignedIntegerValue]);
        if (!reserved[binding]) reserved[binding] = entry;
    }
    NSMutableArray *result = [NSMutableArray array];
    [candidates enumerateObjectsUsingBlock:^(NSDictionary *candidate, NSUInteger index, BOOL *stop) {
        TSShortcutBinding *binding = TSBinding(candidate[@"key"], [candidate[@"modifiers"] unsignedIntegerValue]);
        if (!binding.key.length) return;
        // A macro has its key as the file names it and as the keyboard layout shows it.
        NSArray<TSShortcutBinding *> *bindings = [self bindingsForMacroKey:binding.key modifiers:binding.modifiers];
        // A key that recording refuses (a macro file can still name one, such as Control-Escape) never runs.
        if (![TSShortcutStore isAllowedKey:binding.key modifiers:binding.modifiers]) {
            [result addObject:@{@"index":@(index), @"refused":@YES}];
            return;
        }
        NSDictionary *other = nil;
        for (TSShortcutBinding *spelling in bindings) if (!other) other = reserved[spelling];
        if (other) [result addObject:@{@"index":@(index), @"other":other}];
        else {
            NSMutableDictionary *entry = [candidate mutableCopy]; entry[@"macro"] = @YES;
            for (TSShortcutBinding *spelling in bindings) reserved[spelling] = entry;
        }
    }];
    return result;
}
+ (NSString *)reasonForMacroConflict:(NSDictionary *)conflict {
    if ([conflict[@"refused"] boolValue])
        return NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.", @"");
    NSDictionary *other = conflict[@"other"];
    NSString *key = [self displayKey:other[@"key"] ?: @"" modifiers:[other[@"modifiers"] unsignedIntegerValue]];
    NSString *format = [conflict[@"displaced"] boolValue]
        ? NSLocalizedString(@"This shortcut conflicts with macro “%@” (%@), whose shortcut will be inactive because it appears later.", @"")
        : [other[@"macro"] boolValue]
        ? NSLocalizedString(@"This shortcut is inactive because macro “%@” (%@) uses it first.", @"")
        : NSLocalizedString(@"This shortcut is inactive because it conflicts with “%@” (%@).", @"");
    return [NSString stringWithFormat:format, other[@"path"], key];
}
- (NSArray<NSString *> *)macrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    NSMutableOrderedSet *result = [NSMutableOrderedSet orderedSet];
    if (!key.length) return @[];
    TSShortcutBinding *binding = TSBinding(key, flags);
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.action != TSMacroAction() || !item.keyEquivalent.length) return;
        // The keys a macro has, as the macro menu compares them: as its file names the key, as
        // the layout shows it, and each key the layout could show it as.
        TSShortcutBinding *given = [self givenBindingForMacroItem:item path:path];
        if ([TSShownBinding(item) isEqual:binding] || [[self bindingsForMacroKey:given.key modifiers:given.modifiers] containsObject:binding])
            [result addObject:[NSString stringWithFormat:@"%@ (%@)", path,
                [TSShortcutStore displayKey:item.keyEquivalent modifiers:item.keyEquivalentModifierMask]]];
    });
    return result.array;
}
- (NSArray<NSString *> *)macrosAffectedByRestoringAll {
    NSMutableOrderedSet *result = [NSMutableOrderedSet orderedSet];
    // A yielding default leaves its key to a macro, so restoring it disables no macro.
    for (TSShortcutCommand *command in self.commands)
        if (![TSYieldingDefaultCommands() containsObject:command.commandID])
            for (TSShortcutBinding *binding in [self defaultBindingsForCommand:command])
                [result addObjectsFromArray:[self macrosUsingKey:binding.key modifiers:binding.modifiers]];
    return result.array;
}
+ (BOOL)isAllowedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    if (key.length == 0) return YES;
    if (key.length != 1 || (flags & ~TSShortcutModifiers)) return NO;
    unichar c = [key characterAtIndex:0];
    if (c >= NSF1FunctionKey && c <= NSF20FunctionKey) return YES;
    // Avoid taking plain typing, navigation, or dead-key combinations away from editors.
    return (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) &&
        c >= 0x20 && c != 0x7f && !(c >= 0xd800 && c <= 0xdfff);
}
- (void)apply:(TSShortcutBinding *)binding to:(TSShortcutCommand *)command {
    command.item.allowsAutomaticKeyEquivalentLocalization = NO;
    command.item.keyEquivalent = @"";
    command.item.keyEquivalentModifierMask = binding.modifiers;
    command.item.keyEquivalent = binding.key;
}
- (NSArray<TSShortcutMatch *> *)menuMatchesKey:(NSString *)key modifiers:(NSEventModifierFlags)flags excluding:(NSMenuItem *)excluded {
    if (key.length == 0) { return @[]; }
    TSShortcutBinding *binding = TSBinding(key, flags);
    NSMutableArray<TSShortcutMatch *> *matches = [NSMutableArray array];
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item == excluded || item.submenu != nil || item.action == TSMacroAction() || item.keyEquivalent.length == 0) { return; }
        // The key as AppKit shows it now, or as the item had it at the last refresh.
        if (![TSShownBinding(item) isEqual:binding] && ![[self.itemBindings objectForKey:item] containsObject:binding]) { return; }
        TSShortcutCommand *command = nil;
        for (TSShortcutCommand *candidate in self.commands) { if (candidate.item == item) { command = candidate; break; } }
        [matches addObject:[[TSShortcutMatch alloc] initWithPath:path menuItem:item command:command macro:nil winner:matches.count == 0]];
    });
    return [matches copy];
}
- (nullable NSString *)conflictForKey:(NSString *)key modifiers:(NSEventModifierFlags)flags except:(NSMenuItem *)excluded restoring:(nullable TSShortcutCommand *)restoring {
    TSShortcutMatch *match = [self menuMatchesKey:key modifiers:flags excluding:excluded].lastObject;
    return match != nil ? match.path : nil;
}
- (NSArray<TSShortcutBinding *> *)restorationBindingsForCommand:(TSShortcutCommand *)command {
    TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
    CFDataRef data = source ? TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) : NULL;
    NSMutableOrderedSet *bindings = [NSMutableOrderedSet orderedSet];
    for (TSShortcutBinding *binding in [self defaultBindingsForCommand:command])
        [bindings addObjectsFromArray:TSRestorationBindings(binding.key, binding.modifiers, data, LMGetKbdType())];
    if (source) CFRelease(source);
    return bindings.array;
}
- (nullable NSString *)conflictForRestoringCommand:(TSShortcutCommand *)command {
    for (TSShortcutBinding *binding in [self defaultBindingsForCommand:command]) {
        NSString *rawConflict = [self conflictForKey:binding.key modifiers:binding.modifiers except:command.item restoring:command];
        if (rawConflict) return rawConflict;
    }
    // Preserve shipped defaults even where their physical spellings overlap on a layout.
    // Only live, user-assigned menu keys participate in the additional restoration check.
    NSMutableSet *customItems = [NSMutableSet set];
    for (TSShortcutCommand *other in self.commands)
        if (other.item != command.item && self.overrides[other.commandID] && other.item.keyEquivalent.length &&
            [TSShownBinding(other.item) isEqual:self.overrides[other.commandID]])
            [customItems addObject:other.item];
    if (!customItems.count) return nil;
    NSArray *bindings = [self restorationBindingsForCommand:command];
    __block NSString *conflict = nil;
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (conflict || item.submenu || item.action == TSMacroAction() || ![customItems containsObject:item]) return;
        if ([bindings containsObject:TSShownBinding(item)]) conflict = path;
    });
    return conflict;
}
- (void)persist {
    if (self.overrides.count) [self.defaults setObject:self.overrides.copy forKey:TSMenuShortcutOverridesKey];
    else [self.defaults removeObjectForKey:TSMenuShortcutOverridesKey];
}
- (nullable NSString *)setKey:(NSString *)key modifiers:(NSEventModifierFlags)flags forCommand:(TSShortcutCommand *)command {
    if (![self.commands containsObject:command]) return NSLocalizedString(@"This command is no longer available.", @"");
    if (command.managedBySystem) return NSLocalizedString(@"Shortcut Unavailable", @"");
    if (![TSShortcutStore isAllowedKey:key modifiers:flags]) return NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.", @"");
    TSShortcutBinding *binding = TSBinding(key, flags);
    // The default, as given or as this keyboard layout shows it, restores the command.
    if ([[self defaultBindingsForCommand:command] containsObject:binding]) {
        // Recording a yielding default that a menu command or a macro has is refused, as any
        // key in use, and the saved key stays.
        if ([self commandYieldsDefault:command]) {
            NSString *owner = [self conflictForKey:key modifiers:flags except:command.item restoring:nil] ?: [self macroNamingKey:key modifiers:flags];
            if (owner) return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), owner];
        }
        return [self restoreCommand:command];
    }
    NSString *conflict = [self conflictForKey:key modifiers:flags except:command.item restoring:nil];
    if (conflict) return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), conflict];
    self.overrides[command.commandID] = binding;
    if (![self knowsKeysOfCurrentLayout] && TSLayoutAdaptsKey(command.defaultKey)) {
        NSMutableDictionary *recorded = [self.recordedBeforeLayoutKeys mutableCopy] ?: [NSMutableDictionary dictionary];
        recorded[command.commandID] = TSKeyboardLayoutID();
        self.recordedBeforeLayoutKeys = recorded;
    }
    [self applySavedOverrides];
    [self persist];
    return [self.unavailableCommands containsObject:command.path] ? NSLocalizedString(@"Shortcut Unavailable", @"") : nil;
}
- (BOOL)commandYieldsDefault:(TSShortcutCommand *)command {
    return [TSYieldingDefaultCommands() containsObject:command.commandID];
}
- (nullable NSString *)macroNamingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    TSShortcutBinding *wanted = TSBinding(key, flags);
    for (TSShortcutMacro *macro in (self.macroProvider ? self.macroProvider() : @[]))
        if ([TSBinding(macro.key, macro.modifiers) isEqual:wanted]) return macro.path;
    return nil;
}
- (nullable NSString *)restoreCommand:(TSShortcutCommand *)command {
    if (![self.commands containsObject:command]) return NSLocalizedString(@"This command is no longer available.", @"");
    if (command.managedBySystem) return nil;
    // A yielding default is restored by forgetting the saved key; the default then takes
    // F5 or leaves it to its owner, so there is nothing to refuse.
    NSString *conflict = [self commandYieldsDefault:command] ? nil : [self conflictForRestoringCommand:command];
    if (conflict) return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), conflict];
    TSShortcutBinding *saved = self.overrides[command.commandID];
    if (saved && ![self knowsKeysOfCurrentLayout] && TSLayoutAdaptsKey(command.defaultKey)) {
        NSMutableDictionary *restored = [self.restoredBeforeLayoutKeys mutableCopy] ?: [NSMutableDictionary dictionary];
        restored[command.commandID] = @[saved, TSKeyboardLayoutID()];
        self.restoredBeforeLayoutKeys = restored;
    }
    [self.overrides removeObjectForKey:command.commandID];
    [self applySavedOverrides]; [self persist];
    return nil;
}
- (void)restoreAll {
    [self.overrides removeAllObjects];
    [self applySavedOverrides]; [self persist];
}
+ (NSString *)displayKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    return TSShortcutDisplayKey(key, flags);
}
// A command whose key macOS keeps shows it as the menu does, with the Globe key that the bindings leave out (TSBinding).
- (NSString *)displayKeyForCommand:(TSShortcutCommand *)command {
    if (command.managedBySystem && (command.item.keyEquivalentModifierMask & NSEventModifierFlagFunction))
        return TSShortcutDisplayKey(command.item.keyEquivalent, command.item.keyEquivalentModifierMask);
    TSShortcutBinding *shown = [self shownBindingForCommand:command];
    return TSShortcutDisplayKey(shown.key, shown.modifiers);
}
- (NSString *)displayDefaultKeyForCommand:(TSShortcutCommand *)command {
    if (command.managedBySystem && (command.defaultModifiers & NSEventModifierFlagFunction))
        return TSShortcutDisplayKey(command.defaultKey, command.defaultModifiers);
    TSShortcutBinding *shown = [self shownDefaultForCommand:command];
    return TSShortcutDisplayKey(shown.key, shown.modifiers);
}
+ (BOOL)event:(NSEvent *)event matchesItem:(NSMenuItem *)item {
    if (!item.keyEquivalent.length) return NO;
    return [TSEventBindings(event, [event charactersByApplyingModifiers:0]) containsObject:TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask)];
}
@end

