// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSShortcutInternal.h"
const NSEventModifierFlags TSShortcutModifiers = NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift;

@protocol TSMacroActionTarget
- (void)doMacro:(id)sender;
@end
SEL TSMacroAction(void) { return @selector(doMacro:); }

// Translate event input and restoration candidates; never use this for binding equality.
NSString *TSTranslateKey(CFDataRef data, UInt16 keyCode, BOOL shifted, UInt32 keyboardType) {
    if (!data) return nil;
    UniChar chars[8]; UniCharCount count = 0; UInt32 dead = 0;
    OSStatus result = UCKeyTranslate((const UCKeyboardLayout *)CFDataGetBytePtr(data), keyCode,
        kUCKeyActionDown, shifted ? (shiftKey >> 8) : 0, keyboardType,
        kUCKeyTranslateNoDeadKeysBit, &dead, 8, &count, chars);
    return result == noErr && count == 1 ? [NSString stringWithCharacters:chars length:count] : nil;
}
// Compare AppKit key equivalents without consulting a keyboard layout.
NSDictionary *TSBinding(NSString *key, NSEventModifierFlags flags) {
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
NSString *TSShortcutCharacterForEvent(NSEvent *event) {
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
NSDictionary *TSRecordedBinding(NSEvent *event, NSString *unshifted) {
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
NSArray<NSDictionary *> *TSEventBindings(NSEvent *event, NSString *unshifted) {
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
BOOL TSRestorationSymbol(NSString *key) {
    if (key.length != 1) return NO;
    unichar c = [key characterAtIndex:0];
    return [[NSCharacterSet punctuationCharacterSet] characterIsMember:c] ||
        [[NSCharacterSet symbolCharacterSet] characterIsMember:c];
}
NSString *TSRestorationCharacters(CFDataRef data, UInt16 code, NSEventModifierFlags flags, UInt32 keyboardType) {
    if (!data) return @"";
    UInt32 modifiers = ((flags & NSEventModifierFlagCommand) ? cmdKey : 0) |
        ((flags & NSEventModifierFlagShift) ? shiftKey : 0) |
        ((flags & NSEventModifierFlagOption) ? optionKey : 0) |
        ((flags & NSEventModifierFlagControl) ? controlKey : 0);
    UniChar chars[8]; UniCharCount count = 0; UInt32 dead = 0;
    OSStatus result = UCKeyTranslate((const UCKeyboardLayout *)CFDataGetBytePtr(data), code,
        kUCKeyActionDown, modifiers >> 8, keyboardType, kUCKeyTranslateNoDeadKeysBit, &dead, 8, &count, chars);
    return result == noErr ? [NSString stringWithCharacters:chars length:count] : @"";
}
NSArray<NSDictionary *> *TSRestorationBindings(NSString *key, NSEventModifierFlags flags, CFDataRef data, UInt32 keyboardType) {
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
            if ([TSShortcutStore isAllowedKey:recorded[@"key"] ?: @"" modifiers:[recorded[@"modifiers"] unsignedIntegerValue]] &&
                [spellings containsObject:original]) [bindings addObjectsFromArray:spellings];
        }
    }
    return bindings.array;
}
void TSVisitMenu(NSMenu *menu, NSString *path, void (^visit)(NSMenuItem *, NSString *)) {
    for (NSMenuItem *item in menu.itemArray) {
        NSString *title = path.length ? [path stringByAppendingFormat:@" › %@", item.title] : item.title;
        if (item.submenu == NSApp.servicesMenu && item.submenu) continue;
        visit(item, title);
        if (item.submenu && item.submenu != NSApp.servicesMenu) TSVisitMenu(item.submenu, title, visit);
    }
}
NSString *TSFindCommandID(NSMenuItem *item) {
    if (item.action == NSSelectorFromString(@"jumpToSelection:")) return @"TSShortcut.centerSelectionInVisibleArea:.0";
    NSDictionary *tags = @{@"showFindPanel:":@1, @"findNext:":@2, @"findPrevious:":@3,
        @"replaceAll:":@4, @"replace:":@5, @"replaceAndFind:":@6,
        @"useSelectionForFind:":@7};
    SEL action = item.action;
    NSNumber *tag = tags[action ? NSStringFromSelector(action) : @""];
    if (tag) return [NSString stringWithFormat:@"TSShortcut.performFindPanelAction:.%@", tag];
    return nil;
}
void TSPrepareMenuIdentifiers(NSMenu *menu) {
    TSVisitMenu(menu, @"", ^(NSMenuItem *item, NSString *path) {
        if ([item.identifier hasPrefix:@"TSShortcut."] || !item.action || item.submenu) return;
        SEL action = item.action; Class targetClass = [item.target class];
        NSString *sharedID = TSFindCommandID(item);
        if (sharedID) item.identifier = sharedID;
        else if (targetClass && [NSStringFromClass(targetClass) hasPrefix:@"Ogre"])
            item.identifier = [NSString stringWithFormat:@"TSShortcut.Ogre.%@.%ld", action ? NSStringFromSelector(action) : @"", (long)item.tag];
    });
}
