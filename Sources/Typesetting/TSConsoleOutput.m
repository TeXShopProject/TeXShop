/*
 * TeXShop - TeX editor for Mac OS
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#import "TSConsoleOutput.h"

// Return and keypad Enter, typed in this window without Shift, Control, Option or
// Command. Caps Lock and the flags that keypad keys carry do not count as modifiers.
static BOOL TSConsoleEventIsPlainReturn(NSEvent *event, NSWindow *window)
{
    if (event.type != NSEventTypeKeyDown || window == nil || event.window != window)
        return NO;
    NSEventModifierFlags modifiers = NSEventModifierFlagShift | NSEventModifierFlagControl |
        NSEventModifierFlagOption | NSEventModifierFlagCommand;
    if (event.modifierFlags & modifiers)
        return NO;
    NSString *key = event.charactersIgnoringModifiers;
    return [key isEqualToString:@"\r"] || [key isEqualToString:@"\003"];
}

@implementation TSConsoleOutputReturn {
    __weak NSTextField *_field;
    BOOL (^_canSend)(void);
    BOOL (^_sendEmptyLine)(void);
}

- (instancetype)initWithInputField:(NSTextField *)field
                           canSend:(BOOL (^)(void))canSend
                     sendEmptyLine:(BOOL (^)(void))sendEmptyLine
{
    self = [super init];
    if (self) {
        _field = field;
        _canSend = [canSend copy];
        _sendEmptyLine = [sendEmptyLine copy];
    }
    return self;
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)selector
{
    if (selector != @selector(insertNewline:) || textView.hasMarkedText)
        return NO;
    NSWindow *window = textView.window;
    NSTextField *field = _field;
    if (!TSConsoleEventIsPlainReturn(NSApp.currentEvent, window) || field.window != window ||
        !field.enabled || !_canSend || !_canSend())
        return NO;
    // The console reports a failure to send, so the focus then stays here.
    if (!_sendEmptyLine || !_sendEmptyLine())
        return YES;
    // The field does not send on losing or gaining the focus, so this sends nothing more.
    // Put the insertion point after any typed text instead of selecting it.
    if ([window makeFirstResponder:field]) {
        NSText *editor = field.currentEditor;
        editor.selectedRange = NSMakeRange(editor.string.length, 0);
    }
    return YES;
}

@end
