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

// Moving the focus away from the input field, for example to select output,
// must not send TeX an empty line. Return and Enter still send the field,
// including an empty response.
static inline void TSConfigureConsoleInput(NSTextField *field)
{
    [(NSTextFieldCell *)field.cell setSendsActionOnEndEditing:NO];
}
