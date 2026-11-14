// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
NSString * const TSMenuShortcutOverridesKey = @"TSMenuShortcutOverrides";
@interface TSShortcutCommand (PathUpdates)
@property (nonatomic, readwrite, copy) NSString *path;
@end
@interface TSShortcutStore ()
@property NSMenu *menu;
@property NSUserDefaults *defaults;
@property NSMutableDictionary<NSString *, TSShortcutBinding *> *overrides;
@property (readwrite, copy) NSArray<TSShortcutCommand *> *commands;
@property (readwrite, copy) NSArray<NSString *> *unavailableCommands;
@end
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
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        NSString *identifier = item.identifier ?: @"";
        if (![identifier hasPrefix:@"TSShortcut."] || !item.action || item.submenu || [seen containsObject:identifier]) return;
        [seen addObject:identifier];
        TSShortcutCommand *command = [previous objectForKey:item];
        if (!command) {
            command = [[TSShortcutCommand alloc] initWithItem:item identifier:identifier path:path];
        }
        command.path = path; [commands addObject:command];
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
- (void)applySavedOverrides {
    NSMutableSet *active = [NSMutableSet set];
    NSMutableOrderedSet *unavailable = [NSMutableOrderedSet orderedSet];
    for (TSShortcutCommand *command in self.commands)
        if (self.overrides[command.commandID]) [active addObject:command.commandID];
    NSMapTable<NSMenuItem *, TSShortcutBinding *> *planned = [NSMapTable strongToStrongObjectsMapTable];
    BOOL changed;
    do {
        changed = NO;
        TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
            if (!item.submenu && item.action != TSMacroAction()) [planned setObject:TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask) forKey:item];
        });
        for (TSShortcutCommand *command in self.commands) {
            TSShortcutBinding *value = [active containsObject:command.commandID] ? self.overrides[command.commandID] : TSBinding(command.defaultKey, command.defaultModifiers);
            [planned setObject:value forKey:command.item];
        }
        NSMutableSet *rejected = [NSMutableSet set];
        for (TSShortcutCommand *command in self.commands) {
            if (![active containsObject:command.commandID]) continue;
            TSShortcutBinding *value = [planned objectForKey:command.item];
            if (![value[@"key"] length]) continue;
            for (NSMenuItem *other in planned.keyEnumerator) {
                if (other != command.item && [[planned objectForKey:other] isEqual:value]) {
                    [rejected addObject:command.commandID]; [unavailable addObject:command.path]; break;
                }
            }
        }
        if (rejected.count) { [active minusSet:rejected]; changed = YES; }
    } while (changed);
    // Remove old macro keys before assigning menus; AppKit can otherwise suppress
    // a menu assignment which duplicates an installed macro. Rebuild macros next.
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.action == TSMacroAction()) item.keyEquivalent = @"";
    });
    // Avoid transient duplicates when restoring defaults or swapping two saved bindings.
    for (TSShortcutCommand *command in self.commands) command.item.keyEquivalent = @"";
    for (TSShortcutCommand *command in self.commands) {
        if ([active containsObject:command.commandID]) [self apply:self.overrides[command.commandID] to:command];
        else {
            command.item.allowsAutomaticKeyEquivalentLocalization = command.defaultLocalization;
            command.item.keyEquivalentModifierMask = command.defaultModifiers;
            command.item.keyEquivalent = command.defaultKey;
        }
    }
    for (TSShortcutCommand *command in self.commands) {
        if ([active containsObject:command.commandID] &&
            ![TSBinding(command.item.keyEquivalent, command.item.keyEquivalentModifierMask) isEqual:[planned objectForKey:command.item]])
            [unavailable addObject:command.path];
    }
    self.unavailableCommands = unavailable.array;
}
// Only the effective menu bindings reserve keys. AppKit-inserted commands
// participate while present, but without a stable identifier cannot be customized.
+ (NSArray<NSDictionary *> *)menuBindings:(NSMenu *)menu {
    NSMutableArray *result = [NSMutableArray array];
    TSVisitMenu(menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.hidden && !item.allowsKeyEquivalentWhenHidden) return;
        if (!item.submenu && item.action != TSMacroAction() && item.keyEquivalent.length)
            [result addObject:@{@"path":path, @"key":item.keyEquivalent,
                @"modifiers":@(item.keyEquivalentModifierMask), @"macro":@NO}];
    });
    return result;
}
+ (TSShortcutBinding *)normalizedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags { return TSBinding(key, flags); }
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
        NSDictionary *other = reserved[binding];
        if (other) [result addObject:@{@"index":@(index), @"other":other}];
        else {
            NSMutableDictionary *entry = [candidate mutableCopy]; entry[@"macro"] = @YES;
            reserved[binding] = entry;
        }
    }];
    return result;
}
+ (NSString *)reasonForMacroConflict:(NSDictionary *)conflict {
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
            [TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask) isEqual:binding])
            [result addObject:[NSString stringWithFormat:@"%@ (%@)", path,
                [TSShortcutStore displayKey:item.keyEquivalent modifiers:item.keyEquivalentModifierMask]]];
    });
    return result.array;
}
- (NSArray<NSString *> *)macrosAffectedByRestoringAll {
    NSMutableOrderedSet *result = [NSMutableOrderedSet orderedSet];
    for (TSShortcutCommand *command in self.commands)
        [result addObjectsFromArray:[self macrosUsingKey:command.defaultKey modifiers:command.defaultModifiers]];
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
        if (![TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask) isEqual:binding]) { return; }
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
    NSArray *bindings = TSRestorationBindings(command.defaultKey, command.defaultModifiers, data, LMGetKbdType());
    if (source) CFRelease(source);
    return bindings;
}
- (nullable NSString *)conflictForRestoringCommand:(TSShortcutCommand *)command {
    NSString *rawConflict = [self conflictForKey:command.defaultKey modifiers:command.defaultModifiers except:command.item restoring:command];
    if (rawConflict) return rawConflict;
    // Preserve shipped defaults even where their physical spellings overlap on a layout.
    // Only live, user-assigned menu keys participate in the additional restoration check.
    NSMutableSet *customItems = [NSMutableSet set];
    for (TSShortcutCommand *other in self.commands)
        if (other.item != command.item && self.overrides[other.commandID] && other.item.keyEquivalent.length &&
            [TSBinding(other.item.keyEquivalent, other.item.keyEquivalentModifierMask) isEqual:self.overrides[other.commandID]])
            [customItems addObject:other.item];
    if (!customItems.count) return nil;
    NSArray *bindings = [self restorationBindingsForCommand:command];
    __block NSString *conflict = nil;
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (conflict || item.submenu || item.action == TSMacroAction() || ![customItems containsObject:item]) return;
        if ([bindings containsObject:TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask)]) conflict = path;
    });
    return conflict;
}
- (void)persist {
    if (self.overrides.count) [self.defaults setObject:self.overrides.copy forKey:TSMenuShortcutOverridesKey];
    else [self.defaults removeObjectForKey:TSMenuShortcutOverridesKey];
}
- (nullable NSString *)setKey:(NSString *)key modifiers:(NSEventModifierFlags)flags forCommand:(TSShortcutCommand *)command {
    if (![self.commands containsObject:command]) return NSLocalizedString(@"This command is no longer available.", @"");
    if (![TSShortcutStore isAllowedKey:key modifiers:flags]) return NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.", @"");
    TSShortcutBinding *binding = TSBinding(key, flags);
    if ([binding isEqual:TSBinding(command.defaultKey, command.defaultModifiers)]) return [self restoreCommand:command];
    NSString *conflict = [self conflictForKey:key modifiers:flags except:command.item restoring:nil];
    if (conflict) return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), conflict];
    self.overrides[command.commandID] = binding;
    [self applySavedOverrides];
    [self persist];
    return [self.unavailableCommands containsObject:command.path] ? NSLocalizedString(@"Shortcut Unavailable", @"") : nil;
}
- (nullable NSString *)restoreCommand:(TSShortcutCommand *)command {
    if (![self.commands containsObject:command]) return NSLocalizedString(@"This command is no longer available.", @"");
    NSString *conflict = [self conflictForRestoringCommand:command];
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
    if (!key.length) return @"—";
    // Display the actual menu definition. Canonicalization is for comparison only.
    if (key.length == 1 && [key characterAtIndex:0] >= 'A' && [key characterAtIndex:0] <= 'Z')
        flags |= NSEventModifierFlagShift;
    NSMutableString *text = [NSMutableString string];
    if (flags & NSEventModifierFlagControl) [text appendString:@"⌃"];
    if (flags & NSEventModifierFlagOption) [text appendString:@"⌥"];
    if (flags & NSEventModifierFlagShift) [text appendString:@"⇧"];
    if (flags & NSEventModifierFlagCommand) [text appendString:@"⌘"];
    unichar c = [key characterAtIndex:0];
    NSDictionary *symbols = @{@(NSLeftArrowFunctionKey):@"←", @(NSRightArrowFunctionKey):@"→", @(NSUpArrowFunctionKey):@"↑", @(NSDownArrowFunctionKey):@"↓", @13:@"↩", @9:@"⇥", @27:@"⎋", @32:@"␣", @127:@"⌫", @(NSDeleteFunctionKey):@"⌦"};
    if (c >= NSF1FunctionKey && c <= NSF20FunctionKey) [text appendFormat:@"F%u", c - NSF1FunctionKey + 1];
    else [text appendString:symbols[@(c)] ?: key.uppercaseString];
    return text;
}
+ (BOOL)event:(NSEvent *)event matchesItem:(NSMenuItem *)item {
    if (!item.keyEquivalent.length) return NO;
    return [TSEventBindings(event, [event charactersByApplyingModifiers:0]) containsObject:TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask)];
}
@end

