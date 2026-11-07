// Previous recording behavior, retained only as a regression comparison.
static NSDictionary *PreviousRecordingBinding(NSString *key, NSEventModifierFlags flags, CFDataRef data, UInt32 keyboardType) {
    flags &= TSShortcutModifiers;
    if (!key.length) return @{@"key":@"", @"modifiers":@0};
    if (![key isEqualToString:key.lowercaseString]) flags |= NSEventModifierFlagShift;
    key = key.lowercaseString;
    if ((flags & NSEventModifierFlagShift) && key.length == 1 &&
        ![[NSCharacterSet letterCharacterSet] characterIsMember:[key characterAtIndex:0]] &&
        [key characterAtIndex:0] < 0xf700) {
        // Prefer an already shifted character ("{"), then an unshifted definition ("=").
        BOOL found = NO;
        for (UInt16 code = 0; code < 128; code++) {
            NSString *base = TSTranslateKey(data, code, NO, keyboardType), *shifted = TSTranslateKey(data, code, YES, keyboardType);
            if ([shifted isEqual:key] && base.length == 1 && [base characterAtIndex:0] >= 0x20 && ![base isEqual:shifted]) { found = YES; break; }
        }
        if (!found) {
            for (UInt16 code = 0; code < 128; code++) {
                NSString *base = TSTranslateKey(data, code, NO, keyboardType), *shifted = TSTranslateKey(data, code, YES, keyboardType);
                if ([base isEqual:key] && shifted.length == 1 && [shifted characterAtIndex:0] >= 0x20 && ![base isEqual:shifted]) { key = shifted; found = YES; break; }
            }
        }
        if (found) flags &= ~NSEventModifierFlagShift;
    }
    return @{@"key":key, @"modifiers":@(flags)};
}
static NSString *PreviousCharacterForEvent(NSEvent *event) {
    NSString *key = event.charactersIgnoringModifiers ?: @"";
    if (!(event.modifierFlags & NSEventModifierFlagCommand)) return key;
    NSString *characters = event.characters;
    unichar c = characters.length == 1 ? [characters characterAtIndex:0] : 0;
    BOOL plainASCII = !(event.modifierFlags & (NSEventModifierFlagOption | NSEventModifierFlagControl)) && c >= 0x20 && c < 0x7f;
    if (plainASCII && ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')))
        // Shift comes from the event flags; Caps Lock must not add Shift.
        return characters.lowercaseString;
    // Command layers can suppress Shift for punctuation. Keep the normal layer
    // here so normalization cannot turn, for example, Swedish Command-colon into Command-period.
    if (key.length == 1 && ([key characterAtIndex:0] < 0x80 || [key characterAtIndex:0] >= 0xf700)) return key;
    if (plainASCII) return characters;
    if (key.length != 1) return key;
    TISInputSourceRef source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    CFDataRef data = source ? TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) : NULL;
    NSString *latin = TSTranslateKey(data, event.keyCode, (event.modifierFlags & NSEventModifierFlagShift) != 0, LMGetKbdType());
    if (source) CFRelease(source);
    return latin.length == 1 && [latin characterAtIndex:0] >= 0x20 && [latin characterAtIndex:0] < 0x7f ? latin : key;
}
