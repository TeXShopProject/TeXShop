// SPDX-License-Identifier: GPL-2.0-or-later
//
// The keys of command completion and its mark moves in the source window and the
// Experiment source panel: Escape and Tab, alone or with Shift, Option or Control.
//
// While text is being composed (an input method has marked text), these keys belong
// to the input method: Escape cancels the conversion, Tab picks a candidate. TeXShop
// then does no completion and no mark move, and lets the input method handle the key.
// A command the input method leaves (cancelOperation:, insertTabIgnoringFieldEditor:,
// selectNextKeyView:, ...) is dropped while that key is delivered, so the text, the
// composition and the focus stay as the input method left them, and the Experiment
// panel does not close. Whether the text was being composed is decided once, when the
// key goes down, not after the input method has run.

#pragma once
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

static inline BOOL TSIsCompletionFamilyKey(NSEvent *event)
{
    if (event.type != NSEventTypeKeyDown) return NO;
    if (event.keyCode == kVK_Escape || event.keyCode == kVK_Tab) return YES;
    NSString *characters = event.charactersIgnoringModifiers;
    if (characters.length != 1) return NO;
    unichar c = [characters characterAtIndex:0];
    return c == 0x1b || c == 0x09 || c == 0x19;
}

// Set while such a key, pressed during composition, is delivered to the input method.
// Each file that includes this header has its own flag; one text view class per file.
static BOOL TSCompletionKeyInComposition = NO;

// Delivers the key to the input method and drops the commands it leaves.
static inline void TSDeliverCompletionKeyToInputMethod(void (NS_NOESCAPE ^deliver)(void))
{
    BOOL was = TSCompletionKeyInComposition;
    TSCompletionKeyInComposition = YES;
    deliver();
    TSCompletionKeyInComposition = was;
}

// The Escape key alone or with Shift (the trigger and the reverse candidate), as
// opposed to Option or Control with it.
static inline BOOL TSIsPlainOrShiftedEscape(NSEvent *event)
{
    NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagCommand);
    return event.keyCode == kVK_Escape && flags == 0;
}
