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

#import <Cocoa/Cocoa.h>
#include <fcntl.h>

// Console output stays selectable while TeX runs, so that it can be copied.

static inline BOOL TSConsoleHasSelection(NSTextView *view)
{
    for (NSValue *value in view.selectedRanges)
        if (value.rangeValue.length > 0)
            return YES;
    return NO;
}

// Appends at the end, never in place of the selection, so new output cannot
// overwrite text being copied. While text is selected the selection is kept
// and the view does not scroll; otherwise the view follows the output.
// Call on the main thread.
static inline void TSAppendConsoleOutput(NSTextView *view, NSString *text, NSColor *color)
{
    if (text.length == 0)
        return;
    NSArray<NSValue *> *selection = view.selectedRanges;
    BOOL selecting = TSConsoleHasSelection(view);
    NSRange appended = NSMakeRange(view.string.length, text.length);
    [view replaceCharactersInRange:NSMakeRange(appended.location, 0) withString:text];
    if (color != nil)
        [view setTextColor:color range:appended];
    if (selecting)
        [view setSelectedRanges:selection];
    else {
        [view setSelectedRange:NSMakeRange(NSMaxRange(appended), 0)];
        [view scrollRangeToVisible:NSMakeRange(NSMaxRange(appended), 0)];
    }
}

// Writes console input to a process. A process that has quit, or closed its
// input, makes the write fail instead of stopping TeXShop with SIGPIPE.
static inline BOOL TSWriteConsoleInput(NSFileHandle *handle, NSData *data, NSError **error)
{
    if (handle == nil || data == nil)
        return NO;
    fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1);
    @try {
        return [handle writeData:data error:error];
    } @catch (NSException *exception) {
        return NO;
    }
}

// Moving the focus away from the input field, for example to select output,
// must not send TeX an empty line. Return and Enter still send the field,
// including an empty response.
static inline void TSConfigureConsoleInput(NSTextField *field)
{
    [(NSTextFieldCell *)field.cell setSendsActionOnEndEditing:NO];
}

// Return in the console output answers TeX as Return in an empty input field
// does, so that output can be clicked and read while TeX waits. An unmodified
// Return or Enter in the output text view sends an empty line when the console
// can send input, then moves the focus to the input field and keeps what has
// been typed there, unsent. Return with Shift, Control, Option or Command, and
// Return while the console cannot send, are left to AppKit. Make an instance the
// delegate of the output text view and keep a strong reference to it. The
// sendEmptyLine block reports its own failure, as the input field does.
@interface TSConsoleOutputReturn : NSObject <NSTextViewDelegate>
- (instancetype)initWithInputField:(NSTextField *)field
                           canSend:(BOOL (^)(void))canSend
                     sendEmptyLine:(BOOL (^)(void))sendEmptyLine;
@end
