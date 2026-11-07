#import "TSKeyboardShortcuts.h"
#import "TSShortcutPaneController.h"
#import <Carbon/Carbon.h>

NSString * const TSMenuShortcutOverridesKey = @"TSMenuShortcutOverrides";
static const NSEventModifierFlags TSShortcutModifiers = NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift;

NSString * const TSRebuildMacrosNotification = @"TSRebuildMacros";
NSString * const TSMacroShortcutsChangedNotification = @"TSMacroShortcutsChanged";
NSModalResponse TSRunShortcutAlert(NSAlert *alert) {
    id monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (NSApp.modalWindow == alert.window && event.keyCode == 53) {
            [NSApp stopModalWithCode:NSAlertFirstButtonReturn];
            return nil;
        }
        return event;
    }];
    @try { return [alert runModal]; }
    @finally { [NSEvent removeMonitor:monitor]; }
}

// Translate event input and restoration candidates; never use this for binding equality.
static NSString *TSTranslateKey(CFDataRef data, UInt16 keyCode, BOOL shifted, UInt32 keyboardType) {
    if (!data) return nil;
    UniChar chars[8]; UniCharCount count = 0; UInt32 dead = 0;
    OSStatus result = UCKeyTranslate((const UCKeyboardLayout *)CFDataGetBytePtr(data), keyCode,
        kUCKeyActionDown, shifted ? (shiftKey >> 8) : 0, keyboardType,
        kUCKeyTranslateNoDeadKeysBit, &dead, 8, &count, chars);
    return result == noErr && count == 1 ? [NSString stringWithCharacters:chars length:count] : nil;
}
// Compare AppKit key equivalents without consulting a keyboard layout.
static NSDictionary *TSBinding(NSString *key, NSEventModifierFlags flags) {
    flags &= TSShortcutModifiers;
    if (!key.length) return @{@"key":@"", @"modifiers":@0};
    if (key.length == 1 && [key characterAtIndex:0] >= 'A' && [key characterAtIndex:0] <= 'Z') {
        key = key.lowercaseString;
        flags |= NSEventModifierFlagShift;
    }
    return @{@"key":key, @"modifiers":@(flags)};
}
// Honor the Command layer, including Dvorak–QWERTY Command. Do not use
// characters directly for Option/Control combinations (for example Option-G = ©).
static NSString *TSShortcutCharacterForEvent(NSEvent *event) {
    NSString *key = event.charactersIgnoringModifiers ?: @"";
    if (!(event.modifierFlags & NSEventModifierFlagCommand)) return key;
    NSString *characters = event.characters;
    unichar c = characters.length == 1 ? [characters characterAtIndex:0] : 0;
    BOOL plainASCII = !(event.modifierFlags & (NSEventModifierFlagOption | NSEventModifierFlagControl)) && c >= 0x20 && c < 0x7f;
    if (plainASCII && ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')))
        // Shift comes from the event flags; Caps Lock must not add Shift.
        return characters.lowercaseString;
    // Command layers can suppress Shift for punctuation. Keep the normal layer
    // here so recording cannot turn, for example, Swedish Command-colon into Command-period.
    if (key.length == 1 && ([key characterAtIndex:0] < 0x80 || [key characterAtIndex:0] >= 0xf700)) return key;
    if (key.length == 1 && ![[NSCharacterSet letterCharacterSet] characterIsMember:[key characterAtIndex:0]]) return key;
    if (plainASCII) return key.length ? key : characters;
    if (key.length != 1) return key;
    TISInputSourceRef source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    CFDataRef data = source ? TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) : NULL;
    NSString *latin = TSTranslateKey(data, event.keyCode, (event.modifierFlags & NSEventModifierFlagShift) != 0, LMGetKbdType());
    if (source) CFRelease(source);
    return latin.length == 1 && [latin characterAtIndex:0] >= 0x20 && [latin characterAtIndex:0] < 0x7f ? latin : key;
}
// A shifted punctuation character already encodes Shift in AppKit's key
// equivalent. Canonicalize only captured input, never stored menu/macro bindings.
static NSDictionary *TSRecordedBinding(NSEvent *event, NSString *unshifted) {
    NSString *key = TSShortcutCharacterForEvent(event);
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    if ((flags & NSEventModifierFlagShift) && key.length == 1 &&
        ![key isEqual:unshifted] && [key characterAtIndex:0] < 0xf700 &&
        ![[NSCharacterSet letterCharacterSet] characterIsMember:[key characterAtIndex:0]])
        flags &= ~NSEventModifierFlagShift;
    return TSBinding(key, flags);
}
// These spellings describe the captured event only. They are never used to
// compare saved menu bindings with macro bindings or written to preferences.
static NSArray<NSDictionary *> *TSEventBindings(NSEvent *event, NSString *unshifted) {
    NSString *key = TSShortcutCharacterForEvent(event);
    NSMutableOrderedSet *bindings = [NSMutableOrderedSet orderedSetWithObject:TSRecordedBinding(event, unshifted)];
    [bindings addObject:TSBinding(key, event.modifierFlags)];
    if ((event.modifierFlags & NSEventModifierFlagShift) && key.length == 1 && unshifted.length == 1 &&
        [key characterAtIndex:0] < 0xf700 &&
        ![[NSCharacterSet letterCharacterSet] characterIsMember:[key characterAtIndex:0]])
        [bindings addObject:TSBinding(unshifted, event.modifierFlags)];
    return bindings.array;
}
// Extra spellings are transient and used only to reject a conflicting default restore.
// Stored assignments, macro comparison and launch-time application remain raw.
static BOOL TSRestorationSymbol(NSString *key) {
    if (key.length != 1) return NO;
    unichar c = [key characterAtIndex:0];
    return [[NSCharacterSet punctuationCharacterSet] characterIsMember:c] ||
        [[NSCharacterSet symbolCharacterSet] characterIsMember:c];
}
static NSString *TSRestorationCharacters(CFDataRef data, UInt16 code, NSEventModifierFlags flags, UInt32 keyboardType) {
    UInt32 modifiers = ((flags & NSEventModifierFlagCommand) ? cmdKey : 0) |
        ((flags & NSEventModifierFlagShift) ? shiftKey : 0) |
        ((flags & NSEventModifierFlagOption) ? optionKey : 0) |
        ((flags & NSEventModifierFlagControl) ? controlKey : 0);
    UniChar chars[8]; UniCharCount count = 0; UInt32 dead = 0;
    OSStatus result = UCKeyTranslate((const UCKeyboardLayout *)CFDataGetBytePtr(data), code,
        kUCKeyActionDown, modifiers >> 8, keyboardType, kUCKeyTranslateNoDeadKeysBit, &dead, 8, &count, chars);
    return result == noErr ? [NSString stringWithCharacters:chars length:count] : @"";
}
static NSArray<NSDictionary *> *TSRestorationBindings(NSString *key, NSEventModifierFlags flags, CFDataRef data, UInt32 keyboardType) {
    NSDictionary *original = TSBinding(key, flags);
    NSMutableOrderedSet *bindings = [NSMutableOrderedSet orderedSetWithObject:original];
    if (!data || !TSRestorationSymbol(key)) return bindings.array;
    // Reuse the recorder's spellings, including the Command layer and symbols on number keys.
    // This constructs events for comparison only; it never posts them or changes the input source.
    for (UInt16 code = 0; code < 128; code++) {
        if (code == 66 || code == 68 || code == 70 || code == 72 || code == 73 || code == 74 || code == 77) continue;
        NSString *plain = TSRestorationCharacters(data, code, 0, keyboardType);
        for (NSUInteger shift = 0; shift < 2; shift++) {
            NSEventModifierFlags modifiers = (flags & ~NSEventModifierFlagShift) | (shift ? NSEventModifierFlagShift : 0);
            NSString *characters = TSRestorationCharacters(data, code, modifiers, keyboardType);
            NSString *ignoring = TSRestorationCharacters(data, code, modifiers & NSEventModifierFlagShift, keyboardType);
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:modifiers
                timestamp:0 windowNumber:0 context:nil characters:characters charactersIgnoringModifiers:ignoring isARepeat:NO keyCode:code];
            NSArray *spellings = TSEventBindings(event, plain);
            NSDictionary *recorded = spellings.firstObject;
            if ([TSShortcutStore isAllowedKey:recorded[@"key"] modifiers:[recorded[@"modifiers"] unsignedIntegerValue]] &&
                [spellings containsObject:original]) [bindings addObjectsFromArray:spellings];
        }
    }
    return bindings.array;
}
static void TSVisitMenu(NSMenu *menu, NSString *path, void (^visit)(NSMenuItem *, NSString *)) {
    for (NSMenuItem *item in menu.itemArray) {
        NSString *title = path.length ? [path stringByAppendingFormat:@" › %@", item.title] : item.title;
        if (item.submenu == NSApp.servicesMenu && item.submenu) continue;
        visit(item, title);
        if (item.submenu && item.submenu != NSApp.servicesMenu) TSVisitMenu(item.submenu, title, visit);
    }
}
static NSString *TSFindCommandID(NSMenuItem *item) {
    if (item.action == NSSelectorFromString(@"jumpToSelection:")) return @"TSShortcut.centerSelectionInVisibleArea:.0";
    NSDictionary *tags = @{@"showFindPanel:":@1, @"findNext:":@2, @"findPrevious:":@3,
        @"replaceAll:":@4, @"replace:":@5, @"replaceAndFind:":@6,
        @"useSelectionForFind:":@7};
    NSNumber *tag = tags[NSStringFromSelector(item.action) ?: @""];
    if (tag) return [NSString stringWithFormat:@"TSShortcut.performFindPanelAction:.%@", tag];
    return nil;
}
static void TSPrepareMenuIdentifiers(NSMenu *menu) {
    TSVisitMenu(menu, @"", ^(NSMenuItem *item, NSString *path) {
        if ([item.identifier hasPrefix:@"TSShortcut."] || !item.action || item.submenu) return;
        NSString *sharedID = TSFindCommandID(item);
        if (sharedID) item.identifier = sharedID;
        else if ([NSStringFromClass([item.target class]) hasPrefix:@"Ogre"])
            item.identifier = [NSString stringWithFormat:@"TSShortcut.Ogre.%@.%ld", NSStringFromSelector(item.action), (long)item.tag];
    });
}
@implementation TSShortcutMacro
- (instancetype)initWithName:(NSString *)name path:(NSString *)path indexPath:(NSIndexPath *)indexPath serializedKey:(NSString *)serializedKey key:(NSString *)key modifiers:(NSEventModifierFlags)modifiers {
    self = [super init];
    if (self == nil) { return nil; }
    _name = [name copy]; _path = [path copy]; _indexPath = [indexPath copy];
    _serializedKey = [serializedKey copy]; _key = [key copy]; _modifiers = modifiers;
    return self;
}
@end
@implementation TSShortcutMatch
- (instancetype)initWithPath:(NSString *)path menuItem:(NSMenuItem *)menuItem command:(TSShortcutCommand *)command macro:(TSShortcutMacro *)macro winner:(BOOL)winner {
    self = [super init];
    if (self == nil) { return nil; }
    _path = [path copy]; _menuItem = menuItem; _command = command; _macro = macro; _winner = winner;
    return self;
}
@end
@implementation TSShortcutCommand
@end

@interface TSShortcutStore ()
@property NSMenu *menu;
@property NSUserDefaults *defaults;
@property NSMutableDictionary *overrides;
@property (readwrite) NSArray<TSShortcutCommand *> *commands;
@property (readwrite) NSArray<NSString *> *unavailableCommands;
@end
@implementation TSShortcutStore
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
        if (![item.identifier hasPrefix:@"TSShortcut."] || !item.action || item.submenu || [seen containsObject:item.identifier]) return;
        [seen addObject:item.identifier];
        TSShortcutCommand *command = [previous objectForKey:item];
        if (!command) {
            command = [TSShortcutCommand new];
            command.item = item; command.commandID = item.identifier;
            command.defaultKey = item.keyEquivalent; command.defaultModifiers = item.keyEquivalentModifierMask;
            command.defaultLocalization = item.allowsAutomaticKeyEquivalentLocalization;
        }
        command.path = path; [commands addObject:command];
    });
    self.commands = commands;
    [self applySavedOverrides];
}
- (void)applySavedOverrides {
    NSMutableSet *active = [NSMutableSet set];
    NSMutableOrderedSet *unavailable = [NSMutableOrderedSet orderedSet];
    for (TSShortcutCommand *command in self.commands)
        if (self.overrides[command.commandID]) [active addObject:command.commandID];
    NSMapTable *planned = [NSMapTable strongToStrongObjectsMapTable];
    BOOL changed;
    do {
        changed = NO;
        TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
            if (!item.submenu && item.action != NSSelectorFromString(@"doMacro:")) [planned setObject:TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask) forKey:item];
        });
        for (TSShortcutCommand *command in self.commands) {
            NSDictionary *value = [active containsObject:command.commandID] ? self.overrides[command.commandID] : TSBinding(command.defaultKey, command.defaultModifiers);
            [planned setObject:value forKey:command.item];
        }
        NSMutableSet *rejected = [NSMutableSet set];
        for (TSShortcutCommand *command in self.commands) {
            if (![active containsObject:command.commandID]) continue;
            NSDictionary *value = [planned objectForKey:command.item];
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
        if (item.action == NSSelectorFromString(@"doMacro:")) item.keyEquivalent = @"";
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
        if (!item.submenu && item.action != NSSelectorFromString(@"doMacro:") && item.keyEquivalent.length)
            [result addObject:@{@"path":path, @"key":item.keyEquivalent,
                @"modifiers":@(item.keyEquivalentModifierMask), @"macro":@NO}];
    });
    return result;
}
+ (NSDictionary *)normalizedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags { return TSBinding(key, flags); }
- (NSArray<NSDictionary *> *)conflictsForMacroShortcuts:(NSArray<NSDictionary *> *)candidates {
    NSMutableDictionary *reserved = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in [TSShortcutStore menuBindings:self.menu]) {
        NSDictionary *binding = TSBinding(entry[@"key"], [entry[@"modifiers"] unsignedIntegerValue]);
        if (!reserved[binding]) reserved[binding] = entry;
    }
    NSMutableArray *result = [NSMutableArray array];
    [candidates enumerateObjectsUsingBlock:^(NSDictionary *candidate, NSUInteger index, BOOL *stop) {
        NSDictionary *binding = TSBinding(candidate[@"key"], [candidate[@"modifiers"] unsignedIntegerValue]);
        if (![binding[@"key"] length]) return;
        if (reserved[binding]) [result addObject:@{@"index":@(index), @"other":reserved[binding]}];
        else {
            NSMutableDictionary *entry = [candidate mutableCopy]; entry[@"macro"] = @YES;
            reserved[binding] = entry;
        }
    }];
    return result;
}
+ (NSString *)reasonForMacroConflict:(NSDictionary *)conflict {
    NSDictionary *other = conflict[@"other"];
    NSString *key = [self displayKey:other[@"key"] modifiers:[other[@"modifiers"] unsignedIntegerValue]];
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
    NSDictionary *binding = TSBinding(key, flags);
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item.action == NSSelectorFromString(@"doMacro:") && item.keyEquivalent.length &&
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
- (void)apply:(NSDictionary *)binding to:(TSShortcutCommand *)command {
    command.item.allowsAutomaticKeyEquivalentLocalization = NO;
    command.item.keyEquivalent = @"";
    command.item.keyEquivalentModifierMask = [binding[@"modifiers"] unsignedIntegerValue];
    command.item.keyEquivalent = binding[@"key"];
}
- (NSArray<TSShortcutMatch *> *)menuMatchesKey:(NSString *)key modifiers:(NSEventModifierFlags)flags excluding:(NSMenuItem *)excluded {
    if (key.length == 0) { return @[]; }
    NSDictionary *binding = TSBinding(key, flags);
    NSMutableArray<TSShortcutMatch *> *matches = [NSMutableArray array];
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item == excluded || item.submenu != nil || item.action == NSSelectorFromString(@"doMacro:") || item.keyEquivalent.length == 0) { return; }
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
- (NSArray<NSDictionary *> *)restorationBindingsForCommand:(TSShortcutCommand *)command {
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
        if (conflict || item.submenu || item.action == NSSelectorFromString(@"doMacro:") || ![customItems containsObject:item]) return;
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
    if (![TSShortcutStore isAllowedKey:key modifiers:flags]) return NSLocalizedString(@"Use Command or Control with a key, or a function key (F1–F20).", @"");
    NSDictionary *binding = TSBinding(key, flags);
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

@implementation TSShortcutSearch
+ (NSArray<TSShortcutMatch *> *)matchesKey:(NSString *)key modifiers:(NSEventModifierFlags)flags store:(TSShortcutStore *)store macros:(NSArray<TSShortcutMacro *> *)macros {
    NSMutableArray<TSShortcutMatch *> *matches = [[store menuMatchesKey:key modifiers:flags excluding:nil] mutableCopy];
    // Reuse the same raw comparison and file-order ownership used by the macro editor.
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    for (TSShortcutMacro *macro in macros) {
        [candidates addObject:@{@"path":macro.path, @"key":macro.key, @"modifiers":@(macro.modifiers)}];
    }
    NSMutableIndexSet *inactive = [NSMutableIndexSet indexSet];
    for (NSDictionary *conflict in [store conflictsForMacroShortcuts:candidates]) { [inactive addIndex:[conflict[@"index"] unsignedIntegerValue]]; }
    NSDictionary *binding = TSBinding(key, flags);
    [macros enumerateObjectsUsingBlock:^(TSShortcutMacro *macro, NSUInteger index, BOOL *stop) {
        if (macro.key.length == 0 || ![TSBinding(macro.key, macro.modifiers) isEqual:binding]) { return; }
        [matches addObject:[[TSShortcutMatch alloc] initWithPath:macro.path menuItem:nil command:nil macro:macro winner:![inactive containsIndex:index]]];
    }];
    return [matches copy];
}
+ (NSArray<TSShortcutMatch *> *)matchesEvent:(NSEvent *)event store:(TSShortcutStore *)store macros:(NSArray<TSShortcutMacro *> *)macros {
    NSMutableArray<TSShortcutMatch *> *menus = [NSMutableArray array], *macroMatches = [NSMutableArray array];
    NSMutableSet<NSMenuItem *> *seenMenus = [NSMutableSet set];
    NSMutableSet<NSIndexPath *> *seenMacros = [NSMutableSet set];
    // These are only the recorder's spellings of this input. Ownership stays raw;
    // no restoration aliases or keyboard-layout comparison of assignments is used.
    for (NSDictionary *binding in TSEventBindings(event, [event charactersByApplyingModifiers:0])) {
        NSString *key = binding[@"key"] ?: @"";
        for (TSShortcutMatch *match in [self matchesKey:key modifiers:[binding[@"modifiers"] unsignedIntegerValue] store:store macros:macros]) {
            NSMenuItem *item = match.menuItem;
            TSShortcutMacro *macro = match.macro;
            if (item != nil && ![seenMenus containsObject:item]) {
                [seenMenus addObject:item]; [menus addObject:match];
            } else if (macro != nil && ![seenMacros containsObject:macro.indexPath]) {
                [seenMacros addObject:macro.indexPath]; [macroMatches addObject:match];
            }
        }
    }
    // A single input can have several recorder spellings. Display ownership in
    // menu order across all matches, without changing raw assignment comparisons.
    NSMutableArray<TSShortcutMatch *> *ordered = [NSMutableArray array];
    NSMapTable<NSMenuItem *, TSShortcutMatch *> *byItem = [NSMapTable strongToStrongObjectsMapTable];
    for (TSShortcutMatch *match in menus) { [byItem setObject:match forKey:match.menuItem]; }
    TSVisitMenu(store.menu, @"", ^(NSMenuItem *item, NSString *path) {
        TSShortcutMatch *match = [byItem objectForKey:item];
        if (match == nil) { return; }
        [ordered addObject:[[TSShortcutMatch alloc] initWithPath:match.path menuItem:item command:match.command macro:nil winner:ordered.count == 0]];
    });
    BOOL hasWinner = ordered.count > 0;
    for (TSShortcutMacro *macro in macros) {
        for (TSShortcutMatch *match in macroMatches) {
            if (match.macro != macro) { continue; }
            BOOL winner = match.winner && !hasWinner;
            [ordered addObject:[[TSShortcutMatch alloc] initWithPath:match.path menuItem:nil command:nil macro:macro winner:winner]];
            hasWinner = hasWinner || winner;
        }
    }
    return [ordered copy];
}
@end

@interface TSShortcutKeySearchView : NSView
@property (copy, nullable) BOOL (^handleEvent)(NSEvent *event);
@end
@implementation TSShortcutKeySearchView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityTextFieldRole; }
- (NSString *)accessibilityLabel { return NSLocalizedString(@"Search by Key", @""); }
- (void)keyDown:(NSEvent *)event { [self performKeyEquivalent:event]; }
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.handleEvent == nil) { return NO; }
    return self.handleEvent(event);
}
@end

@interface TSShortcutRecorder : NSView
@property (copy) void (^record)(NSEvent *);
@property (copy) dispatch_block_t accept;
@property (copy) dispatch_block_t cancel;
@end
@implementation TSShortcutRecorder
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityTextFieldRole; }
- (NSString *)accessibilityLabel { return NSLocalizedString(@"Change Shortcut", @""); }
- (NSString *)accessibilityHelp { return NSLocalizedString(@"Press the new shortcut (Escape to cancel).", @""); }
- (void)keyDown:(NSEvent *)event { [self performKeyEquivalent:event]; }
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers;
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    if ([key isEqual:@"\r"] && !flags) { if (self.accept) self.accept(); return YES; }
    if ([key isEqual:@"\033"] && !flags) { if (self.cancel) self.cancel(); return YES; }
    if (([key isEqual:@"\t"] || [key isEqual:@"\031"]) && !(flags & ~NSEventModifierFlagShift)) {
        if ((flags & NSEventModifierFlagShift) || [key isEqual:@"\031"]) [self.window selectPreviousKeyView:self];
        else [self.window selectNextKeyView:self];
        return YES;
    }
    if (self.record) self.record(event);
    return YES;
}
@end
@interface TSShortcutCapturePanel : NSPanel
@property TSShortcutRecorder *recorder;
@end
@implementation TSShortcutCapturePanel
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers;
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    BOOL buttonNavigation = (([key isEqual:@"\t"] || [key isEqual:@"\031"]) && !(flags & ~NSEventModifierFlagShift)) ||
        (([key isEqual:@"\r"] || [key isEqual:@" "]) && !flags);
    if (self.firstResponder != self.recorder && buttonNavigation) return [super performKeyEquivalent:event];
    return [self.recorder performKeyEquivalent:event];
}
@end

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
        // AppKit may hide a newly inserted item's key until the existing macro key is cleared.
        if (!item.submenu && !item.separatorItem && item.action != NSSelectorFromString(@"doMacro:"))
            [bindings addObject:@[[NSValue valueWithNonretainedObject:item], item.keyEquivalent,
                @(item.keyEquivalentModifierMask), NSStringFromSelector(item.action) ?: @"", item.identifier ?: @""]];
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

typedef NS_ENUM(NSInteger, TSShortcutSearchMode) {
    TSShortcutSearchByFunction,
    TSShortcutSearchByKey
};

@interface TSShortcutPaneController () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (strong) TSKeyboardShortcuts *shortcuts;
@property (readwrite) BOOL searchingByKey;
@property (strong) NSSegmentedControl *searchMode;
@property (strong) TSShortcutKeySearchView *keySearchView;
@property (strong) NSButton *macroButton;
@property (copy) NSString *textQuery;
@property (strong, nullable) NSEvent *searchEvent;
@property (copy) NSArray<TSShortcutMatch *> *searchMatches;
@property (copy) NSString *searchMessage;
@property (strong, nullable) TSShortcutStore *store;
@property (strong, nullable, readonly) NSWindow *window;
@property NSTextField *hint;
@property NSTableView *table;
@property NSSearchField *search;
@property NSArray<TSShortcutCommand *> *visibleCommands;
@property NSArray<NSButton *> *selectionButtons;
@property TSShortcutCapturePanel *capturePanel;
@property TSShortcutCommand *editingCommand;
@property NSTextField *captureDisplay;
@property NSTextField *captureError;
@property NSButton *applyButton;
@property NSString *capturedKey;
@property NSArray<NSDictionary *> *capturedBindings;
@property NSEventModifierFlags capturedModifiers;
@end
@implementation TSShortcutPaneController
- (instancetype)initWithShortcuts:(TSKeyboardShortcuts *)shortcuts {
    self = [super initWithNibName:nil bundle:nil];
    if (self == nil) { return nil; }
    _shortcuts = shortcuts;
    _store = shortcuts.store;
    _textQuery = @""; _searchMatches = @[]; _searchMessage = @"";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shortcutsChanged:) name:TSMacroShortcutsChangedNotification object:shortcuts];
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (NSWindow *)window { return self.viewIfLoaded.window; }
- (void)shortcutsChanged:(NSNotification *)notification { self.store = self.shortcuts.store; if (self.isViewLoaded) { [self reloadCommands]; } }
- (void)refreshMenuAndMacros { [self.shortcuts refreshMenuAndMacros]; }
- (NSButton *)button:(NSString *)title action:(SEL)action {
    return [NSButton buttonWithTitle:NSLocalizedString(title, @"") target:self action:action];
}
- (void)loadView {
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0,0,700,570)];
    self.view = content;
    self.search = [NSSearchField new];
    self.search.placeholderString = NSLocalizedString(@"Search commands", @"");
    self.search.delegate = self;
    self.searchMode = [NSSegmentedControl segmentedControlWithLabels:@[NSLocalizedString(@"Search by Function", @""), NSLocalizedString(@"Search by Key", @"")]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeSearchMode:)];
    self.searchMode.selectedSegment = TSShortcutSearchByFunction;
    [self.searchMode setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.searchMode setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.keySearchView = [TSShortcutKeySearchView new];
    self.keySearchView.hidden = YES;
    __weak TSShortcutPaneController *weakSelf = self;
    self.keySearchView.handleEvent = ^BOOL(NSEvent *event) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil) { return NO; }
        return [strongSelf handleKeySearchEvent:event];
    };
    NSTextField *hint = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Select a command to change its shortcut. Changes take effect immediately. Macros and text input key bindings use their own editors.", @"")];
    hint.textColor = NSColor.secondaryLabelColor; self.hint = hint;
    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES; scroll.hasHorizontalScroller = YES; scroll.borderType = NSBezelBorder;
    self.table = [NSTableView new];
    self.table.delegate = self; self.table.dataSource = self;
    self.table.rowHeight = 28; self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.doubleAction = @selector(editShortcut:); self.table.target = self;
    NSTableColumn *command = [[NSTableColumn alloc] initWithIdentifier:@"command"];
    command.title = NSLocalizedString(@"Command", @""); command.width = 560; command.minWidth = 240;
    NSTableColumn *shortcut = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    shortcut.title = NSLocalizedString(@"Shortcut", @""); shortcut.width = 160; shortcut.minWidth = 100;
    [self.table addTableColumn:command]; [self.table addTableColumn:shortcut];
    scroll.documentView = self.table;
    NSButton *edit = [self button:@"Change…" action:@selector(editShortcut:)];
    NSButton *clear = [self button:@"Remove Shortcut" action:@selector(removeShortcut:)];
    NSButton *restore = [self button:@"Restore Default" action:@selector(restoreShortcut:)];
    NSButton *all = [self button:@"Restore All…" action:@selector(restoreAll:)];
    self.selectionButtons = @[edit, clear, restore];
    self.macroButton = [self button:@"Show in Macro Editor" action:@selector(showSelectedMacro:)];
    self.macroButton.enabled = NO;
    NSStackView *primary = [NSStackView stackViewWithViews:@[edit,clear,restore]];
    primary.orientation = NSUserInterfaceLayoutOrientationHorizontal; primary.spacing = 8;
    NSStackView *secondary = [NSStackView stackViewWithViews:@[all,self.macroButton]];
    secondary.orientation = NSUserInterfaceLayoutOrientationHorizontal; secondary.spacing = 8;
    NSStackView *buttons = [NSStackView stackViewWithViews:@[primary,secondary]];
    buttons.orientation = NSUserInterfaceLayoutOrientationVertical; buttons.alignment = NSLayoutAttributeLeading; buttons.spacing = 8;
    for (NSView *view in @[self.searchMode,self.search,hint,scroll,buttons,self.keySearchView]) { view.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [self.searchMode.topAnchor constraintEqualToAnchor:content.topAnchor constant:16],
        [self.searchMode.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [self.searchMode.centerYAnchor constraintEqualToAnchor:self.search.centerYAnchor],
        [self.search.widthAnchor constraintGreaterThanOrEqualToConstant:160],
        [self.keySearchView.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor],
        [self.keySearchView.trailingAnchor constraintEqualToAnchor:self.search.trailingAnchor],
        [self.keySearchView.topAnchor constraintEqualToAnchor:self.search.topAnchor],
        [self.keySearchView.bottomAnchor constraintEqualToAnchor:self.search.bottomAnchor],
        [self.search.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [self.search.trailingAnchor constraintEqualToAnchor:self.searchMode.leadingAnchor constant:-8],
        [hint.topAnchor constraintEqualToAnchor:self.search.bottomAnchor constant:12],
        [hint.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor], [hint.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [scroll.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:16],
        [scroll.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [buttons.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:16],
        [buttons.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor],
        [buttons.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-20],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]
    ]];
    [self reloadCommands];
}
- (void)reloadFunctionCommands {
    self.hint.stringValue = NSLocalizedString(@"Select a command to change its shortcut. Changes take effect immediately. Macros and text input key bindings use their own editors.", @"");
    if (self.store.unavailableCommands.count)
        self.hint.stringValue = [self.hint.stringValue stringByAppendingFormat:@"\n%@: %@", NSLocalizedString(@"Shortcut Unavailable", @""), [self.store.unavailableCommands componentsJoinedByString:@", "]];
    NSString *query = self.search.stringValue ?: @"";
    NSMutableArray *visible = [NSMutableArray array];
    for (TSShortcutCommand *command in self.store.commands) {
        if (command.item.hidden && !command.item.allowsKeyEquivalentWhenHidden) continue;
        if (!query.length || [command.path localizedCaseInsensitiveContainsString:query]) [visible addObject:command];
    }
    self.visibleCommands = visible;
    [self.table reloadData];
    for (NSButton *button in self.selectionButtons) button.enabled = [self selectedCommand] != nil;
}
- (void)controlTextDidChange:(NSNotification *)notification { if (!self.searchingByKey) { [self reloadCommands]; } }
- (void)reloadCommands {
    if (self.searchingByKey) { [self updateKeyResults]; }
    else { [self reloadFunctionCommands]; self.macroButton.enabled = NO; }
}
- (void)changeSearchMode:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == TSShortcutSearchByFunction) { [self stopKeySearch]; return; }
    if (self.searchingByKey) { [self stopKeySearch]; return; }
    self.textQuery = self.search.stringValue;
    self.searchingByKey = YES;
    self.search.editable = NO;
    self.searchEvent = nil;
    self.keySearchView.hidden = NO;
    self.search.stringValue = @"";
    self.search.placeholderString = NSLocalizedString(@"Press a key", @"");
    [self updateKeyResults];
    NSWindow *window = self.window;
    if (window != nil) { [window makeFirstResponder:self.keySearchView]; }
}
- (void)stopKeySearch {
    if (!self.searchingByKey) { return; }
    self.searchingByKey = NO;
    self.searchMode.selectedSegment = TSShortcutSearchByFunction;
    self.searchEvent = nil; self.searchMatches = @[];
    self.keySearchView.hidden = YES;
    self.search.editable = YES;
    self.search.stringValue = self.textQuery;
    self.search.placeholderString = NSLocalizedString(@"Search commands", @"");
    [self reloadCommands];
}
- (BOOL)handleKeySearchEvent:(NSEvent *)event {
    if (!self.searchingByKey) { return NO; }
    if (event.type != NSEventTypeKeyDown) { return YES; }
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    if (flags == 0 && [event.charactersIgnoringModifiers isEqualToString:@"\033"]) {
        [self stopKeySearch];
        NSWindow *window = self.window;
        if (window != nil && window.isKeyWindow) { [window makeFirstResponder:self.search]; }
        return YES;
    }
    self.searchEvent = event;
    [self updateKeyResults];
    return YES;
}
- (void)updateKeyResults {
    TSShortcutStore *store = self.store;
    NSEvent *event = self.searchEvent;
    self.searchMatches = @[];
    self.searchMessage = NSLocalizedString(@"Press a key", @"");
    if (store != nil && event != nil) {
        NSDictionary *binding = TSRecordedBinding(event, [event charactersByApplyingModifiers:0]);
        NSString *key = binding[@"key"];
        NSEventModifierFlags flags = [binding[@"modifiers"] unsignedIntegerValue];
        self.search.stringValue = [TSShortcutStore displayKey:key modifiers:flags];
        NSArray<TSShortcutMacro *> *macros = self.shortcuts.macroProvider != nil ? self.shortcuts.macroProvider() : @[];
        self.searchMatches = [TSShortcutSearch matchesEvent:event store:store macros:macros];
        if (key.length == 0 || ![TSShortcutStore isAllowedKey:key modifiers:flags]) {
            self.searchMessage = self.searchMatches.count > 0
                ? NSLocalizedString(@"Existing assignments are shown. This key cannot be assigned to a new shortcut.", @"")
                : NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.", @"");
        } else {
            self.searchMessage = self.searchMatches.count == 0 ? NSLocalizedString(@"No command uses this key.", @"") : NSLocalizedString(@"Assignment priority is shown; whether a command can run depends on the document.", @"");
        }
    }
    self.hint.stringValue = [self.searchMessage stringByAppendingFormat:@"\n%@", NSLocalizedString(@"Keys used by the system cannot be detected. Press Escape to stop recording.", @"")];
    self.keySearchView.accessibilityValue = self.search.stringValue;
    [self.table reloadData];
    NSInteger first = self.searchMatches.count > 0 ? (self.searchMatches[0].macro != nil ? 1 : 0) : -1;
    if (first >= 0) { [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)first] byExtendingSelection:NO]; [self.table scrollRowToVisible:first]; }
    [self updateSelectionButtons];
}
- (NSInteger)macroHeaderRow {
    if (!self.searchingByKey) { return -1; }
    for (NSUInteger index = 0; index < self.searchMatches.count; index++) { if (self.searchMatches[index].macro != nil) { return (NSInteger)index; } }
    return -1;
}
- (TSShortcutMatch *)matchAtRow:(NSInteger)row {
    if (!self.searchingByKey || row < 0) { return nil; }
    NSInteger header = [self macroHeaderRow];
    if (row == header) { return nil; }
    if (header >= 0 && row > header) { row--; }
    return row < (NSInteger)self.searchMatches.count ? self.searchMatches[(NSUInteger)row] : nil;
}
- (void)showSelectedMacro:(id)sender {
    TSShortcutMacro *macro = [self matchAtRow:self.table.selectedRow].macro;
    if (macro == nil || self.shortcuts.showMacro == nil) { return; }
    [self stopKeySearch];
    self.shortcuts.showMacro(macro);
}
- (void)updateSelectionButtons {
    for (NSButton *button in self.selectionButtons) { button.enabled = [self selectedCommand] != nil; }
    self.macroButton.enabled = [self matchAtRow:self.table.selectedRow].macro != nil;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.searchingByKey ? (NSInteger)self.searchMatches.count + ([self macroHeaderRow] >= 0 ? 1 : 0) : (NSInteger)self.visibleCommands.count;
}
- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row { return self.searchingByKey && row == [self macroHeaderRow]; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return ![self tableView:tableView isGroupRow:row]; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (self.searchingByKey) {
        if (row == [self macroHeaderRow]) { return [NSTextField labelWithString:[column.identifier isEqualToString:@"command"] ? NSLocalizedString(@"Macros", @"") : @""]; }
        TSShortcutMatch *match = [self matchAtRow:row];
        if (match == nil) { return nil; }
        NSString *key = match.macro != nil ? match.macro.key : match.menuItem.keyEquivalent;
        NSEventModifierFlags flags = match.macro != nil ? match.macro.modifiers : match.menuItem.keyEquivalentModifierMask;
        NSString *status = match.winner ? NSLocalizedString(@"Assigned", @"") : NSLocalizedString(@"Inactive for this key", @"");
        NSString *text = [column.identifier isEqualToString:@"command"] ? [match.path stringByAppendingFormat:@" — %@", status] : [TSShortcutStore displayKey:key modifiers:flags];
        NSTextField *label = [NSTextField labelWithString:text]; label.lineBreakMode = NSLineBreakByTruncatingMiddle; label.toolTip = text;
        return label;
    }
    if (row < 0 || row >= (NSInteger)self.visibleCommands.count) { return nil; }
    TSShortcutCommand *command = self.visibleCommands[(NSUInteger)row];
    BOOL isCommand = [column.identifier isEqualToString:@"command"];
    NSTextField *label = [NSTextField labelWithString:isCommand ? command.path : [TSShortcutStore displayKey:command.item.keyEquivalent modifiers:command.item.keyEquivalentModifierMask]];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.toolTip = command.path;
    return label;
}
- (TSShortcutCommand *)selectedCommand {
    NSInteger row = self.table.selectedRow;
    if (self.searchingByKey) { return [self matchAtRow:row].command; }
    return row >= 0 && row < self.visibleCommands.count ? self.visibleCommands[row] : nil;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification { [self updateSelectionButtons]; }
- (void)showError:(NSString *)error {
    NSWindow *parent = self.capturePanel ?: self.window;
    if (error == nil || parent == nil || parent.attachedSheet != nil) { return; }
    NSAlert *alert = [NSAlert new]; alert.messageText = NSLocalizedString(@"Shortcut Unavailable", @""); alert.informativeText = error;
    [alert beginSheetModalForWindow:parent completionHandler:nil];
}
- (void)confirmMacrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags completion:(void (^)(BOOL))completion {
    NSArray *macros = [self.store macrosUsingKey:key modifiers:flags];
    if (!macros.count) { completion(YES); return; }
    NSWindow *parent = self.capturePanel ?: self.window;
    if (parent == nil || parent.attachedSheet != nil) { completion(NO); return; }
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Assign a shortcut used by macros?", @"");
    alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The following macros use this shortcut. Assigning it to the menu command will make their shortcuts inactive. Their files will not be changed.\n\n%@", @""), [macros componentsJoinedByString:@"\n"]];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Assign", @"")];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        BOOL unchanged = [[strongSelf.store macrosUsingKey:key modifiers:flags] isEqualToArray:macros];
        completion(response == NSAlertSecondButtonReturn && unchanged);
    }];
}
- (void)removeShortcut:(id)sender {
    TSShortcutCommand *command = self.selectedCommand; if (!command) return;
    [self showError:[self.store setKey:@"" modifiers:0 forCommand:command]];
    [self refreshMenuAndMacros];
}
- (void)restoreShortcut:(id)sender {
    TSShortcutCommand *command = self.selectedCommand; if (!command) return;
    NSString *error = [self.store conflictForRestoringCommand:command];
    if (error) { [self showError:[NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), error]]; return; }
    __weak typeof(self) weakSelf = self;
    [self confirmMacrosUsingKey:command.defaultKey modifiers:command.defaultModifiers completion:^(BOOL accepted) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil || !accepted) { return; }
        [strongSelf showError:[strongSelf.store restoreCommand:command]];
        [strongSelf refreshMenuAndMacros];
    }];
}
- (void)restoreAll:(id)sender {
    NSWindow *parent = self.window;
    if (parent == nil || parent.attachedSheet != nil) { return; }
    NSAlert *alert = [NSAlert new]; alert.messageText = NSLocalizedString(@"Restore all keyboard shortcuts?", @"");
    alert.informativeText = NSLocalizedString(@"Custom menu shortcuts will be removed. Existing KeyEquivalents.plist settings will be preserved.", @"");
    NSArray *macros = [self.store macrosAffectedByRestoringAll];
    if (macros.count) alert.informativeText = [alert.informativeText stringByAppendingFormat:@"\n\n%@\n%@",
        NSLocalizedString(@"These macro shortcuts will become inactive:", @""), [macros componentsJoinedByString:@"\n"]];
    [alert addButtonWithTitle:NSLocalizedString(@"Restore All", @"")]; [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil || response != NSAlertFirstButtonReturn) { return; }
        [strongSelf.store restoreAll]; [strongSelf refreshMenuAndMacros];
    }];
}
- (void)editShortcut:(id)sender {
    NSWindow *parent = self.window;
    TSShortcutCommand *command = self.selectedCommand;
    if (command == nil || parent == nil || parent.attachedSheet != nil) { return; }
    [self stopKeySearch];
    self.editingCommand = command; self.capturedKey = nil; self.capturedBindings = nil;
    TSShortcutCapturePanel *panel = [[TSShortcutCapturePanel alloc] initWithContentRect:NSMakeRect(0,0,640,240) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.capturePanel = panel;
    panel.title = NSLocalizedString(@"Change Shortcut", @"");
    TSShortcutRecorder *recorder = [[TSShortcutRecorder alloc] initWithFrame:panel.contentView.bounds];
    recorder.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    panel.contentView = recorder; panel.recorder = recorder;
    NSTextField *title = [NSTextField labelWithString:command.path]; title.frame = NSMakeRect(20,195,600,25); title.lineBreakMode = NSLineBreakByTruncatingMiddle; title.toolTip = command.path;
    self.captureDisplay = [NSTextField labelWithString:NSLocalizedString(@"Press the new shortcut (Escape to cancel).", @"")];
    self.captureDisplay.frame = NSMakeRect(20,145,600,40); self.captureDisplay.font = [NSFont systemFontOfSize:18]; self.captureDisplay.alignment = NSTextAlignmentCenter;
    self.captureError = [NSTextField wrappingLabelWithString:@""]; self.captureError.frame = NSMakeRect(20,65,600,70); self.captureError.textColor = NSColor.secondaryLabelColor;
    self.applyButton = [self button:@"Apply" action:@selector(applyCapturedShortcut:)]; self.applyButton.enabled = NO;
    NSButton *cancel = [self button:@"Cancel" action:@selector(cancelCapture:)];
    self.applyButton.keyEquivalent = @"\r"; cancel.keyEquivalent = @"\033";
    recorder.nextKeyView = self.applyButton; self.applyButton.nextKeyView = cancel; cancel.nextKeyView = recorder;
    [self.applyButton sizeToFit]; [cancel sizeToFit];
    self.applyButton.frame = NSMakeRect(620-NSWidth(self.applyButton.frame),18,NSWidth(self.applyButton.frame),32);
    cancel.frame = NSMakeRect(NSMinX(self.applyButton.frame)-NSWidth(cancel.frame)-12,18,NSWidth(cancel.frame),32);
    for (NSView *view in @[title,self.captureDisplay,self.captureError,self.applyButton,cancel]) [recorder addSubview:view];
    __weak typeof(self) weakSelf = self;
    recorder.record = ^(NSEvent *event) { TSShortcutPaneController *strongSelf = weakSelf; if (strongSelf != nil) { [strongSelf recordShortcutEvent:event]; } };
    recorder.accept = ^{ TSShortcutPaneController *strongSelf = weakSelf; if (strongSelf != nil) { [strongSelf applyCapturedShortcut:nil]; } };
    recorder.cancel = ^{ TSShortcutPaneController *strongSelf = weakSelf; if (strongSelf != nil) { [strongSelf cancelCapture:nil]; } };
    [parent beginSheet:panel completionHandler:^(NSModalResponse result) {
        panel.recorder.record = nil; panel.recorder.accept = nil; panel.recorder.cancel = nil;
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        strongSelf.capturePanel = nil; strongSelf.editingCommand = nil;
        [strongSelf reloadCommands];
    }];
    [panel makeFirstResponder:recorder];
    panel.initialFirstResponder = recorder;
}
- (void)recordShortcutEvent:(NSEvent *)event {
    NSString *key = TSShortcutCharacterForEvent(event);
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    self.captureError.stringValue = @"";
    self.applyButton.enabled = [TSShortcutStore isAllowedKey:key modifiers:flags] && key.length > 0;
    if (!self.applyButton.enabled) {
        self.capturedKey = nil; self.capturedBindings = nil;
        self.captureDisplay.stringValue = NSLocalizedString(@"Press the new shortcut (Escape to cancel).", @"");
        self.captureError.stringValue = NSLocalizedString(@"Use Command or Control with a key, or a function key (F1–F20).", @"");
    } else {
        self.capturedBindings = TSEventBindings(event, [event charactersByApplyingModifiers:0]);
        NSDictionary *binding = self.capturedBindings.firstObject;
        self.capturedKey = binding[@"key"]; self.capturedModifiers = [binding[@"modifiers"] unsignedIntegerValue];
        self.captureDisplay.stringValue = [TSShortcutStore displayKey:self.capturedKey modifiers:self.capturedModifiers];
    }
    self.capturePanel.recorder.accessibilityValue = self.captureDisplay.stringValue;
}
- (void)cancelCapture:(id)sender {
    NSWindow *parent = self.window;
    TSShortcutCapturePanel *panel = self.capturePanel;
    if (parent != nil && panel != nil && panel.attachedSheet == nil) { [parent endSheet:panel returnCode:NSModalResponseCancel]; }
}
- (NSString *)conflictForCapturedShortcut {
    NSArray *bindings = self.capturedBindings ?: @[TSBinding(self.capturedKey, self.capturedModifiers)];
    NSMutableOrderedSet *conflicts = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *binding in bindings) {
        NSString *path = [self.store conflictForKey:binding[@"key"] modifiers:[binding[@"modifiers"] unsignedIntegerValue]
            except:self.editingCommand.item restoring:nil];
        if (path) [conflicts addObject:path];
    }
    if (!conflicts.count) return nil;
    if (conflicts.count == 1)
        return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), conflicts.firstObject];
    return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by:\n%@", @""),
        [conflicts.array componentsJoinedByString:@"\n"]];
}
- (void)applyCapturedShortcut:(id)sender {
    NSString *key = self.capturedKey;
    TSShortcutCommand *command = self.editingCommand;
    NSEventModifierFlags flags = self.capturedModifiers;
    if (key == nil || command == nil || !self.applyButton.enabled) { return; }
    NSString *conflict = [self conflictForCapturedShortcut];
    if (conflict != nil) { self.captureError.stringValue = conflict; return; }
    __weak typeof(self) weakSelf = self;
    [self confirmMacrosUsingKey:key modifiers:flags completion:^(BOOL accepted) {
        TSShortcutPaneController *strongSelf = weakSelf;
        if (strongSelf == nil || !accepted || strongSelf.editingCommand != command ||
            ![strongSelf.capturedKey isEqualToString:key] || strongSelf.capturedModifiers != flags) { return; }
        NSString *error = [strongSelf conflictForCapturedShortcut];
        if (error == nil) { error = [strongSelf.store setKey:key modifiers:flags forCommand:command]; }
        [strongSelf refreshMenuAndMacros];
        TSShortcutCapturePanel *panel = strongSelf.capturePanel;
        if (error != nil) {
            strongSelf.captureError.stringValue = error;
            if (panel != nil) { [panel makeFirstResponder:panel.recorder]; }
            return;
        }
        NSWindow *parent = strongSelf.window;
        if (parent != nil && panel != nil) { [parent endSheet:panel returnCode:NSModalResponseOK]; }
    }];
}
@end
