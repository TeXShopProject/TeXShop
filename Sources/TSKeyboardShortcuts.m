#import "TSKeyboardShortcuts.h"
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
static NSArray<NSDictionary *> *TSRestorationBindings(NSString *key, NSEventModifierFlags flags, CFDataRef data, UInt32 keyboardType) {
    NSMutableOrderedSet *bindings = [NSMutableOrderedSet orderedSetWithObject:TSBinding(key, flags)];
    if (!TSRestorationSymbol(key)) return bindings.array;
    BOOL encodesShift = NO;
    for (UInt16 code = 0; data && code < 128; code++) {
        NSString *plain = TSTranslateKey(data, code, NO, keyboardType);
        NSString *shifted = TSTranslateKey(data, code, YES, keyboardType);
        if ([plain isEqual:shifted]) continue;
        if ((flags & NSEventModifierFlagShift) && [plain isEqual:key] && TSRestorationSymbol(shifted)) {
            [bindings addObject:TSBinding(shifted, flags & ~NSEventModifierFlagShift)];
            [bindings addObject:TSBinding(shifted, flags)];
        }
        if ([shifted isEqual:key] && TSRestorationSymbol(plain)) {
            encodesShift = YES;
            [bindings addObject:TSBinding(plain, flags | NSEventModifierFlagShift)];
        }
    }
    if (encodesShift) [bindings addObject:TSBinding(key, flags ^ NSEventModifierFlagShift)];
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
- (nullable NSString *)conflictForKey:(NSString *)key modifiers:(NSEventModifierFlags)flags except:(NSMenuItem *)excluded restoring:(nullable TSShortcutCommand *)restoring {
    if (!key.length) return nil;
    NSDictionary *binding = TSBinding(key, flags);
    __block NSString *conflict = nil;
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item == excluded || item.submenu || item.action == NSSelectorFromString(@"doMacro:") || !item.keyEquivalent.length) return;
        if (![TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask) isEqual:binding]) return;
        conflict = path;
    });
    return conflict;
}
- (NSArray<NSDictionary *> *)restorationBindingsForCommand:(TSShortcutCommand *)command {
    TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
    CFDataRef data = source ? TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) : NULL;
    NSArray *bindings = TSRestorationBindings(command.defaultKey, command.defaultModifiers, data, LMGetKbdType());
    if (source) CFRelease(source);
    return bindings;
}
- (nullable NSString *)conflictForRestoringCommand:(TSShortcutCommand *)command {
    for (NSDictionary *binding in [self restorationBindingsForCommand:command]) {
        NSString *conflict = [self conflictForKey:binding[@"key"] modifiers:[binding[@"modifiers"] unsignedIntegerValue]
            except:command.item restoring:command];
        if (conflict) return conflict;
    }
    return nil;
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

@interface TSKeyboardShortcuts () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property TSShortcutStore *store;
@property BOOL menuRefreshPending;
@property NSArray *observedMenuBindings;
@property BOOL rebuildingMacros;
@property BOOL applyingMenus;
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
@implementation TSKeyboardShortcuts
+ (instancetype)sharedController {
    static TSKeyboardShortcuts *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[self alloc] initWithWindow:nil]; });
    return controller;
}
- (void)installInMainMenu {
    if (self.store) { [self refreshMenuAndMacros]; return; }
    NSMenu *appMenu = NSApp.mainMenu.itemArray.firstObject.submenu;
    for (NSMenuItem *item in appMenu.itemArray) {
        if (item.action != NSSelectorFromString(@"showPreferences:")) continue;
        NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Keyboard Shortcuts…", @"") action:@selector(showKeyboardShortcuts:) keyEquivalent:@""];
        entry.target = self;
        entry.identifier = @"TSShortcut.showKeyboardShortcuts:.0";
        [appMenu insertItem:entry atIndex:[appMenu indexOfItem:item] + 1];
        break;
    }
    self.store = [[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:NSUserDefaults.standardUserDefaults];
    [self observeMenuChanges];
    [self refreshMenuAndMacros];
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
    if (self.isWindowLoaded) [self reloadCommands];
    [[NSNotificationCenter defaultCenter] postNotificationName:TSMacroShortcutsChangedNotification object:self];
}
- (void)refreshMenuAndMacros {
    if (self.applyingMenus || self.rebuildingMacros) return;
    self.applyingMenus = YES;
    @try {
        [self.store refreshMenu];
        [[NSNotificationCenter defaultCenter] postNotificationName:TSRebuildMacrosNotification object:self];
        if (self.isWindowLoaded) [self reloadCommands];
    } @finally {
        self.observedMenuBindings = [self menuBindingSnapshot];
        self.applyingMenus = NO;
    }
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
- (NSButton *)button:(NSString *)title action:(SEL)action {
    return [NSButton buttonWithTitle:NSLocalizedString(title, @"") target:self action:action];
}
- (void)loadWindow {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 570)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    window.title = NSLocalizedString(@"Keyboard Shortcuts", @"");
    window.contentMinSize = NSMakeSize(760, 480);
    window.releasedWhenClosed = NO;
    self.window = window;
    NSView *content = window.contentView;
    self.search = [NSSearchField new];
    self.search.placeholderString = NSLocalizedString(@"Search commands", @"");
    self.search.delegate = self;
    NSTextField *hint = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Select a command to change its shortcut. Changes take effect immediately. Macros and text input key bindings use their own editors.", @"")];
    hint.textColor = NSColor.secondaryLabelColor; self.hint = hint;
    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;
    self.table = [NSTableView new];
    self.table.delegate = self; self.table.dataSource = self;
    self.table.rowHeight = 28; self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.doubleAction = @selector(editShortcut:); self.table.target = self;
    NSTableColumn *command = [[NSTableColumn alloc] initWithIdentifier:@"command"];
    command.title = NSLocalizedString(@"Command", @""); command.width = 560; command.minWidth = 390;
    NSTableColumn *shortcut = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    shortcut.title = NSLocalizedString(@"Shortcut", @""); shortcut.width = 160; shortcut.minWidth = 130;
    [self.table addTableColumn:command]; [self.table addTableColumn:shortcut];
    scroll.documentView = self.table;
    NSButton *edit = [self button:@"Change…" action:@selector(editShortcut:)];
    NSButton *clear = [self button:@"Remove Shortcut" action:@selector(removeShortcut:)];
    NSButton *restore = [self button:@"Restore Default" action:@selector(restoreShortcut:)];
    NSButton *all = [self button:@"Restore All…" action:@selector(restoreAll:)];
    self.selectionButtons = @[edit, clear, restore];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[edit,clear,restore,all]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal; buttons.spacing = 12;
    for (NSView *view in @[self.search,hint,scroll,buttons]) { view.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [self.search.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [self.search.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [self.search.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [hint.topAnchor constraintEqualToAnchor:self.search.bottomAnchor constant:12],
        [hint.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor], [hint.trailingAnchor constraintEqualToAnchor:self.search.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:16],
        [scroll.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.search.trailingAnchor],
        [buttons.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:16],
        [buttons.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor],
        [buttons.trailingAnchor constraintLessThanOrEqualToAnchor:self.search.trailingAnchor],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]
    ]];
    [window center];
    [self reloadCommands];
}
- (void)showKeyboardShortcuts:(id)sender {
    [self installInMainMenu];
    [self showWindow:sender];
    [self reloadCommands];
    [self.window makeKeyAndOrderFront:sender];
}
- (void)reloadCommands {
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
- (void)controlTextDidChange:(NSNotification *)notification { [self reloadCommands]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.visibleCommands.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    TSShortcutCommand *command = self.visibleCommands[row];
    BOOL isCommand = [column.identifier isEqualToString:@"command"];
    NSTextField *label = [NSTextField labelWithString:isCommand ? command.path : [TSShortcutStore displayKey:command.item.keyEquivalent modifiers:command.item.keyEquivalentModifierMask]];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.toolTip = command.path;
    return label;
}
- (TSShortcutCommand *)selectedCommand {
    NSInteger row = self.table.selectedRow;
    return row >= 0 && row < self.visibleCommands.count ? self.visibleCommands[row] : nil;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    for (NSButton *button in self.selectionButtons) button.enabled = [self selectedCommand] != nil;
}
- (void)showError:(NSString *)error {
    if (!error) return;
    NSAlert *alert = [NSAlert new]; alert.messageText = NSLocalizedString(@"Shortcut Unavailable", @""); alert.informativeText = error;
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (BOOL)confirmMacrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    NSArray *macros = [self.store macrosUsingKey:key modifiers:flags];
    if (!macros.count) return YES;
    NSAlert *alert = [NSAlert new];
    alert.messageText = NSLocalizedString(@"Assign a shortcut used by macros?", @"");
    alert.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The following macros use this shortcut. Assigning it to the menu command will make their shortcuts inactive. Their files will not be changed.\n\n%@", @""), [macros componentsJoinedByString:@"\n"]];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    [alert addButtonWithTitle:NSLocalizedString(@"Assign", @"")];
    return TSRunShortcutAlert(alert) == NSAlertSecondButtonReturn;
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
    if (![self confirmMacrosUsingKey:command.defaultKey modifiers:command.defaultModifiers]) return;
    [self showError:[self.store restoreCommand:command]];
    [self refreshMenuAndMacros];
}
- (void)restoreAll:(id)sender {
    NSAlert *alert = [NSAlert new]; alert.messageText = NSLocalizedString(@"Restore all keyboard shortcuts?", @"");
    alert.informativeText = NSLocalizedString(@"Your changes in this window will be removed. Existing KeyEquivalents.plist settings will be preserved.", @"");
    NSArray *macros = [self.store macrosAffectedByRestoringAll];
    if (macros.count) alert.informativeText = [alert.informativeText stringByAppendingFormat:@"\n\n%@\n%@",
        NSLocalizedString(@"These macro shortcuts will become inactive:", @""), [macros componentsJoinedByString:@"\n"]];
    [alert addButtonWithTitle:NSLocalizedString(@"Restore All", @"")]; [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        [self.store restoreAll]; [self refreshMenuAndMacros];
    }];
}
- (void)editShortcut:(id)sender {
    TSShortcutCommand *command = self.selectedCommand; if (!command || self.window.attachedSheet) return;
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
    recorder.record = ^(NSEvent *event) { [weakSelf recordShortcutEvent:event]; };
    recorder.accept = ^{ [weakSelf applyCapturedShortcut:nil]; };
    recorder.cancel = ^{ [weakSelf cancelCapture:nil]; };
    [self.window beginSheet:panel completionHandler:^(NSModalResponse result) {
        panel.recorder.record = nil; panel.recorder.accept = nil; panel.recorder.cancel = nil;
        weakSelf.capturePanel = nil; weakSelf.editingCommand = nil;
        [weakSelf reloadCommands];
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
- (void)cancelCapture:(id)sender { [self.window endSheet:self.capturePanel returnCode:NSModalResponseCancel]; }
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
    if (!self.capturedKey || !self.applyButton.enabled) return;
    NSString *conflict = [self conflictForCapturedShortcut];
    if (conflict) { self.captureError.stringValue = conflict; return; }
    if (![self confirmMacrosUsingKey:self.capturedKey modifiers:self.capturedModifiers]) return;
    NSString *error = [self.store setKey:self.capturedKey modifiers:self.capturedModifiers forCommand:self.editingCommand];
    [self refreshMenuAndMacros];
    if (error) { self.captureError.stringValue = error; [self.capturePanel makeFirstResponder:self.capturePanel.recorder]; return; }
    [self.window endSheet:self.capturePanel returnCode:NSModalResponseOK];
}
@end
