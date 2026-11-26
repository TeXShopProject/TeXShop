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

// The text view to which such a key, pressed during composition, is being delivered.
// Only that view drops the commands the input method leaves; another text view that
// gets a command meanwhile handles it as usual. The previous view is put back after a
// nested delivery.
static __weak NSView *TSCompletionKeyComposingView = nil;

// Delivers the key to the input method of the view and drops the commands it leaves.
static inline void TSDeliverCompletionKeyToInputMethod(NSView *view, void (NS_NOESCAPE ^deliver)(void))
{
    NSView *was = TSCompletionKeyComposingView;
    TSCompletionKeyComposingView = view;
    deliver();
    TSCompletionKeyComposingView = was;
}

// A key that does not start during composition is handled by the view as usual, even
// while an outer key is still being delivered to that view's input method: its commands
// are not dropped. The outer delivery is put back afterwards.
static inline void TSHandleKeyOutsideComposition(NSView *view, void (NS_NOESCAPE ^handle)(void))
{
    NSView *was = TSCompletionKeyComposingView;
    if (was == view) TSCompletionKeyComposingView = nil;
    handle();
    TSCompletionKeyComposingView = was;
}

// The key as completion compares it. Only the physical Escape and Tab keys are the
// trigger: Control-[ also arrives as Escape (U+001B), Control-I as Tab and Control-Y as
// Backtab (U+0019), and those stay ordinary keys for AppKit (noop:, yank:). Shift-Tab
// arrives as Backtab, which is the Tab trigger with Shift, so it goes back through the
// candidates as Shift-Escape does.
static inline NSString *TSCompletionTypedKey(NSEvent *event)
{
    NSString *characters = event.characters;
    if (characters.length != 1) return characters;
    unichar c = [characters characterAtIndex:0];
    if (c == 0x1b) return event.keyCode == kVK_Escape ? characters : @"";
    if (c == 0x09 || c == 0x19) return event.keyCode == kVK_Tab ? @"\t" : @"";
    return characters;
}

// Whether the event is the trigger key (alone or with modifiers). The trigger is nil
// when command completion is off, and then no key is the trigger. An empty string is
// never a trigger: TSCompletionTypedKey gives it for Control-[ and the like.
static inline BOOL TSIsCompletionTrigger(NSEvent *event, NSString *trigger)
{
    if (trigger.length == 0) return NO;
    return [TSCompletionTypedKey(event) isEqualToString:trigger];
}

// The Escape key alone or with Shift (the trigger and the reverse candidate), as
// opposed to Option or Control with it.
static inline BOOL TSIsPlainOrShiftedEscape(NSEvent *event)
{
    NSEventModifierFlags flags = event.modifierFlags & (NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagCommand);
    return event.keyCode == kVK_Escape && flags == 0;
}
