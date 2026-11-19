// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
NSString * const TSMenuShortcutOverridesKey = @"TSMenuShortcutOverrides";
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
// Macro keys as their files name them and as AppKit showed them, by keyboard layout. A macro
// whose key is taken shows none, so the key it showed before stays known.
@property NSMutableDictionary<NSString *, NSMutableDictionary<TSShortcutBinding *, TSShortcutBinding *> *> *macroShownKeys;
@property (copy) NSArray *assignedShownKeys;
// The hidden items AppKit shows defaults in, while they are in the menu.
@property (nullable) NSMenuItem *learningHolder;
@end
// Commands whose default key is only a proposal: they take it only when no other menu
// command (with its key as resolved) and no macro (as its file names it) has it, and
// they never make another command's key unavailable.
static NSSet<NSString *> *TSYieldingDefaultCommands(void) {
    return [NSSet setWithObject:@"TSShortcut.completeLabelOrCitationKey:.0"];
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
    TSPrepareMenuIdentifiers(self.menu);
    NSMapTable *previous = [NSMapTable strongToStrongObjectsMapTable];
    for (TSShortcutCommand *command in self.commands) [previous setObject:command forKey:command.item];
    NSMutableArray *commands = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    // When documents autosave, AppKit adds Duplicate and resets Save As… to ⌥⇧⌘S whenever
    // it updates the menu, so Save As… keeps the shortcut macOS gives it, as in Xcode.
    __block BOOL appKitSaveAs = NO;
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.action == @selector(duplicateDocument:)) appKitSaveAs = YES;
    });
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        NSString *identifier = item.identifier ?: @"";
        if (![identifier hasPrefix:@"TSShortcut."] || !item.action || item.submenu || [seen containsObject:identifier]) return;
        [seen addObject:identifier];
        TSShortcutCommand *command = [previous objectForKey:item];
        if (!command) {
            command = [[TSShortcutCommand alloc] initWithItem:item identifier:identifier path:path];
        }
        command.path = path; command.managedBySystem = appKitSaveAs && item.action == @selector(saveDocumentAs:);
        [commands addObject:command];
    });
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
    return !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c >= 0xf700 || c < 0x21);
}
// The default of a command as AppKit shows it on the current keyboard layout: the key its
// item shows while it has the default, otherwise the key AppKit showed on this layout before
// (TSShortcutCommand reads it at launch; -learnShownDefaultsThen: works out the rest).
- (TSShortcutBinding *)shownDefaultForCommand:(TSShortcutCommand *)command {
    TSShortcutBinding *given = TSBinding(command.defaultKey, command.defaultModifiers);
    if (!command.defaultLocalization || !TSLayoutAdaptsKey(given.key)) return given;
    NSString *layout = TSKeyboardLayoutID();
    TSShortcutBinding *known = command.shownDefaults[layout];
    if ([self commandHoldsDefault:command]) {
        // Until AppKit adapts a key assigned again, the item shows the given key.
        TSShortcutBinding *shown = TSShownBinding(command.item);
        if (!shown.key.length || ([shown isEqual:given] && known)) return known ?: given;
        command.shownDefaults[layout] = shown;
        return shown;
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
- (void)learnShownDefaultsThen:(void (^)(BOOL learned))completion {
    [self stopLearning];
    NSString *layout = TSKeyboardLayoutID();
    NSMutableArray<TSShortcutCommand *> *pending = [NSMutableArray array];
    for (TSShortcutCommand *command in self.commands)
        if (command.defaultLocalization && TSLayoutAdaptsKey(command.defaultKey) && !command.shownDefaults[layout] &&
            ![self commandHoldsDefault:command]) [pending addObject:command];
    if (!pending.count || !self.menu) { completion(NO); return; }
    // Hidden items without an action, given each default for one pass of the run loop, never
    // run; AppKit leaves a key empty when another item shows it, so each default comes again
    // with Control and Option added, whose key it then shows.
    const NSEventModifierFlags extra = NSEventModifierFlagControl | NSEventModifierFlagOption;
    NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    holder.identifier = TSShortcutLearningIdentifier; holder.hidden = YES;
    holder.submenu = [[NSMenu alloc] initWithTitle:@""];
    NSMutableArray<NSArray<NSMenuItem *> *> *items = [NSMutableArray array];
    for (TSShortcutCommand *command in pending) {
        NSMutableArray *pair = [NSMutableArray array];
        for (NSNumber *flags in @[@(command.defaultModifiers), @(command.defaultModifiers | extra)]) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
            item.hidden = YES; item.keyEquivalentModifierMask = flags.unsignedIntegerValue; item.keyEquivalent = command.defaultKey;
            [holder.submenu addItem:item]; [pair addObject:item];
        }
        [items addObject:pair];
    }
    [self.menu addItem:holder];
    self.learningHolder = holder;
    dispatch_async(dispatch_get_main_queue(), ^{
        __block BOOL learned = NO;
        // Assigning keys removes the items first (-applySavedOverrides): AppKit would empty a
        // key assigned later that one of them shows.
        if (self.learningHolder == holder && [TSKeyboardLayoutID() isEqual:layout]) {
            [pending enumerateObjectsUsingBlock:^(TSShortcutCommand *command, NSUInteger index, BOOL *stop) {
                TSShortcutBinding *shown = TSShownBinding(items[index][0]), *variant = TSShownBinding(items[index][1]);
                if (!shown.key.length && variant.key.length && !(command.defaultModifiers & NSEventModifierFlagShift) &&
                    variant.modifiers == TSBinding(@"x", command.defaultModifiers | extra).modifiers)
                    shown = TSBinding(variant.key, command.defaultModifiers);
                if (shown.key.length) { command.shownDefaults[layout] = shown; learned = YES; }
            }];
        }
        if (self.learningHolder == holder) [self stopLearning];
        completion(learned);
    });
}
- (NSArray<TSShortcutBinding *> *)bindingsForMacroKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    TSShortcutBinding *given = TSBinding(key, flags);
    NSMutableOrderedSet<TSShortcutBinding *> *result = [NSMutableOrderedSet orderedSetWithObject:given];
    if (!TSLayoutAdaptsKey(given.key)) return result.array;
    TSShortcutBinding *known = self.macroShownKeys[TSKeyboardLayoutID()][given];
    if (known) [result addObject:known];
    return result.array;
}
// The key a macro item was given, from the keys the macro items showed when the store last
// read them. Reading the given key of an item directly makes it show the given key until
// AppKit adapts it again, so lookups during a search or a check go through what was read.
- (TSShortcutBinding *)givenBindingForMacroItem:(NSMenuItem *)item {
    TSShortcutBinding *shown = TSShownBinding(item);
    __block TSShortcutBinding *given = nil;
    [self.macroShownKeys[TSKeyboardLayoutID()] enumerateKeysAndObjectsUsingBlock:^(TSShortcutBinding *key, TSShortcutBinding *value, BOOL *stop) {
        if ([value isEqual:shown]) { given = key; *stop = YES; }
    }];
    return given ?: shown;
}
// Reads the macro items' keys, as given and as shown, into the keys known on this layout.
- (void)noteMacroKeys {
    if (!self.macroShownKeys) self.macroShownKeys = [NSMutableDictionary dictionary];
    NSString *layout = TSKeyboardLayoutID();
    NSMutableDictionary *macroKeys = self.macroShownKeys[layout] ?: [NSMutableDictionary dictionary];
    self.macroShownKeys[layout] = macroKeys;
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.action != TSMacroAction() || !item.keyEquivalent.length) return;
        TSShortcutBinding *shown = TSShownBinding(item), *given = TSGivenBinding(item);
        // Until AppKit adapts a key assigned again, the item shows the given key.
        if (![shown isEqual:given] || !macroKeys[given]) macroKeys[given] = shown;
    });
}
// The shown keys the last assignment went by: the defaults, the other items and the macros.
- (NSArray *)shownKeySignature {
    NSMutableArray *signature = [NSMutableArray array];
    for (TSShortcutCommand *command in self.commands) [signature addObject:[self shownDefaultForCommand:command]];
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.submenu || item.action == TSMacroAction() || !item.keyEquivalent.length) return;
        BOOL command = NO;
        for (TSShortcutCommand *candidate in self.commands) if (candidate.item == item) { command = YES; break; }
        if (!command) [signature addObject:TSShownBinding(item)];
    });
    [signature addObject:[self.macroShownKeys[TSKeyboardLayoutID()] copy] ?: @{}];
    return signature;
}
- (BOOL)shownKeysChangedSinceAssignment {
    [self noteShownDefaultsSettled];
    [self noteMacroKeys];
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
    if ([shown isEqual:command.shownDefaults[TSKeyboardLayoutID()]] &&
        [target isEqual:TSBinding(command.defaultKey, command.defaultModifiers)]) return YES;
    return [TSGivenBinding(item) isEqual:target];
}
- (void)stopLearning {
    NSMenuItem *holder = self.learningHolder;
    self.learningHolder = nil;
    if (holder.menu) [holder.menu removeItem:holder];
}
- (void)applySavedOverrides {
    [self stopLearning];
    // What AppKit shows before anything is assigned; reading given keys below makes items
    // show those until AppKit adapts them again.
    [self noteMacroKeys];
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
    self.unavailableCommands = unavailable.array;
}
// Only the effective menu bindings reserve keys. AppKit-inserted commands
// participate while present; only those TSFindCommandID names can be customized.
// Each item reserves its key as shown on this keyboard layout and as given: macros are
// given keys too, which AppKit adapts in the same way.
+ (NSArray<NSDictionary *> *)menuBindings:(NSMenu *)menu {
    TSShortcutStore *store = TSKeyboardShortcuts.sharedController.store;
    NSMapTable *known = store.menu == menu ? store.itemBindings : nil;
    NSMutableArray *result = [NSMutableArray array];
    TSVisitMenu(menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.hidden && !item.allowsKeyEquivalentWhenHidden) return;
        if (item.submenu || item.action == TSMacroAction() || !item.keyEquivalent.length) return;
        NSMutableOrderedSet<TSShortcutBinding *> *bindings = [NSMutableOrderedSet orderedSetWithObject:TSShownBinding(item)];
        NSSet *previous = [known objectForKey:item];
        if (previous) [bindings addObjectsFromArray:previous.allObjects];
        else [bindings addObject:TSGivenBinding(item)];
        for (TSShortcutBinding *binding in bindings)
            if (binding.key.length)
                [result addObject:@{@"path":path, @"key":binding.key, @"modifiers":@(binding.modifiers), @"macro":@NO}];
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
        if (item.action == TSMacroAction() && item.keyEquivalent.length &&
            ([TSShownBinding(item) isEqual:binding] || [[self givenBindingForMacroItem:item] isEqual:binding]))
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
+ (BOOL)event:(NSEvent *)event matchesItem:(NSMenuItem *)item {
    if (!item.keyEquivalent.length) return NO;
    return [TSEventBindings(event, [event charactersByApplyingModifiers:0]) containsObject:TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask)];
}
@end

