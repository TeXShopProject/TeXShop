// SPDX-License-Identifier: GPL-2.0-or-later
// Completion and mark keys (TeXShop-audit spec, 2026-11-19): the yielding F5 of
// Edit › Complete Label or Citation Key, the menu item and its target, Escape and Tab
// during composition, and Escape in the Experiment panel. Windows are never shown.
#import "TSKeyboardShortcuts.m"
#import "TestAppKitIsolation.h"
#import "TSMarkMenu.h"
#import "TSCompletionKeys.h"
static int checks = 0, failures = 0;
static void check(BOOL ok, NSString *what) { checks++; if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", what.UTF8String); } }
static NSString *F5(void) { unichar c = NSF5FunctionKey; return [NSString stringWithCharacters:&c length:1]; }
static NSString *F6(void) { unichar c = NSF6FunctionKey; return [NSString stringWithCharacters:&c length:1]; }

// ---- the yielding default ----
static NSMenuItem *Item(NSMenu *menu, NSString *title, SEL action, NSString *key, NSString *identifier) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.keyEquivalentModifierMask = 0; item.identifier = identifier; item.allowsAutomaticKeyEquivalentLocalization = NO;
    [menu addItem:item]; return item;
}
static NSUInteger F5Owners(NSMenu *menu) {
    NSUInteger n = 0;
    for (NSMenuItem *item in menu.itemArray) if ([item.keyEquivalent isEqual:F5()] && (item.keyEquivalentModifierMask & TSShortcutModifiers) == 0) n++;
    return n;
}
static void CheckYielding(void) {
    NSString *newID = @"TSShortcut.completeLabelOrCitationKey:.0";
    // 1. Nobody else: the new item takes F5.
    { NSMenu *menu = [NSMenu new]; NSMenuItem *mine = Item(menu, @"Complete", @selector(completeLabelOrCitationKey:), F5(), newID);
      Item(menu, @"Other", @selector(copy:), @"c", @"TSShortcut.copy:.0");
      TSMemoryDefaults *d = [TSMemoryDefaults new]; TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:menu defaults:d];
      check([mine.keyEquivalent isEqual:F5()], @"with F5 free, the new item takes F5"); (void)store; }
    // 2. Another item's default is F5: it keeps it, the new item is empty.
    { NSMenu *menu = [NSMenu new]; NSMenuItem *other = Item(menu, @"Other", @selector(copy:), F5(), @"TSShortcut.copy:.0");
      NSMenuItem *mine = Item(menu, @"Complete", @selector(completeLabelOrCitationKey:), F5(), newID);
      TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:menu defaults:[TSMemoryDefaults new]];
      check([other.keyEquivalent isEqual:F5()] && mine.keyEquivalent.length == 0 && store.unavailableCommands.count == 0,
            @"another item's default F5 wins, and nothing is unavailable"); }
    // 3. Another item saved F5.
    { NSMenu *menu = [NSMenu new]; NSMenuItem *other = Item(menu, @"Other", @selector(copy:), @"c", @"TSShortcut.copy:.0");
      NSMenuItem *mine = Item(menu, @"Complete", @selector(completeLabelOrCitationKey:), F5(), newID);
      TSMemoryDefaults *d = [TSMemoryDefaults new];
      [d setObject:@{@"TSShortcut.copy:.0": @{@"key": F5(), @"modifiers": @0}} forKey:TSMenuShortcutOverridesKey];
      TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:menu defaults:d];
      check([other.keyEquivalent isEqual:F5()] && mine.keyEquivalent.length == 0 && store.unavailableCommands.count == 0,
            @"another item's saved F5 wins"); }
    // 4. A saved key is rejected and its item falls back to the default F5 (A: default F5, saved F6; B: default F6).
    { NSMenu *menu = [NSMenu new]; NSMenuItem *a = Item(menu, @"A", @selector(copy:), F5(), @"TSShortcut.copy:.0");
      NSMenuItem *b = Item(menu, @"B", @selector(paste:), F6(), @"TSShortcut.paste:.0");
      NSMenuItem *mine = Item(menu, @"Complete", @selector(completeLabelOrCitationKey:), F5(), newID);
      TSMemoryDefaults *d = [TSMemoryDefaults new];
      [d setObject:@{@"TSShortcut.copy:.0": @{@"key": F6(), @"modifiers": @0}} forKey:TSMenuShortcutOverridesKey];
      TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:menu defaults:d];
      check([a.keyEquivalent isEqual:F5()] && [b.keyEquivalent isEqual:F6()] && mine.keyEquivalent.length == 0 && F5Owners(menu) == 1,
            @"an item that falls back to F5 keeps it, and F5 has one owner"); (void)store; }
    // 4b. The new item's own saved F6 is rejected (B's default is F6) while A has F5: the new item stays empty.
    { NSMenu *menu = [NSMenu new]; NSMenuItem *a = Item(menu, @"A", @selector(copy:), F5(), @"TSShortcut.copy:.0");
      Item(menu, @"B", @selector(paste:), F6(), @"TSShortcut.paste:.0");
      NSMenuItem *mine = Item(menu, @"Complete", @selector(completeLabelOrCitationKey:), F5(), newID);
      TSMemoryDefaults *d = [TSMemoryDefaults new];
      [d setObject:@{newID: @{@"key": F6(), @"modifiers": @0}} forKey:TSMenuShortcutOverridesKey];
      TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:menu defaults:d];
      check([a.keyEquivalent isEqual:F5()] && mine.keyEquivalent.length == 0 && F5Owners(menu) == 1,
            @"the new item's rejected key falls back to a yielding F5");
      TSShortcutMacro *macro = [[TSShortcutMacro alloc] initWithName:@"M" path:@"Macros/M" indexPath:[NSIndexPath indexPathWithIndex:0] serializedKey:@"F5" key:F5() modifiers:0];
      a.keyEquivalent = @"c";
      [menu removeItem:a];
      store.macroProvider = ^{ return @[macro]; }; [store refreshMenu];
      check(mine.keyEquivalent.length == 0 && [store conflictsForMacroShortcuts:@[@{@"path":@"Macros/M", @"key":F5(), @"modifiers":@0}]].count == 0,
            @"with its saved key rejected, the new item still leaves F5 to a macro");
      store.macroProvider = nil; [store refreshMenu];
      check([mine.keyEquivalent isEqual:F5()], @"once nothing else has F5, the new item takes it while its saved F6 stays rejected"); }
    // 4c. A macro has F5 and the new item has a saved F6: recording F5 is refused and F6 stays.
    { NSMenu *menu = [NSMenu new]; NSMenuItem *mine = Item(menu, @"Complete", @selector(completeLabelOrCitationKey:), F5(), newID);
      TSMemoryDefaults *d = [TSMemoryDefaults new];
      [d setObject:@{newID: @{@"key": F6(), @"modifiers": @0}} forKey:TSMenuShortcutOverridesKey];
      TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:menu defaults:d];
      TSShortcutMacro *macro = [[TSShortcutMacro alloc] initWithName:@"M" path:@"Macros/M" indexPath:[NSIndexPath indexPathWithIndex:0] serializedKey:@"F5" key:F5() modifiers:0];
      store.macroProvider = ^{ return @[macro]; }; [store refreshMenu];
      TSShortcutCommand *command = nil; for (TSShortcutCommand *c in store.commands) if ([c.commandID isEqual:newID]) command = c;
      NSString *message = [store setKey:F5() modifiers:0 forCommand:command];
      check(message.length > 0 && [mine.keyEquivalent isEqual:F6()], @"recording F5 that a macro has is refused, and the saved F6 stays");
      // Restoring the item forgets F6 and leaves F5 to the macro without an error.
      check([store restoreCommand:command] == nil && mine.keyEquivalent.length == 0 &&
            [store conflictsForMacroShortcuts:@[@{@"path":@"Macros/M", @"key":F5(), @"modifiers":@0}]].count == 0,
            @"restoring the item gives F5 to the macro, which stays active"); }
    // 4d. The new item has F6 and another item F5: restoring the item clears F6 without an error.
    { NSMenu *menu = [NSMenu new]; NSMenuItem *other = Item(menu, @"Other", @selector(copy:), F5(), @"TSShortcut.copy:.0");
      NSMenuItem *mine = Item(menu, @"Complete", @selector(completeLabelOrCitationKey:), F5(), newID);
      TSMemoryDefaults *d = [TSMemoryDefaults new];
      [d setObject:@{newID: @{@"key": F6(), @"modifiers": @0}} forKey:TSMenuShortcutOverridesKey];
      TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:menu defaults:d];
      TSShortcutCommand *command = nil; for (TSShortcutCommand *c in store.commands) if ([c.commandID isEqual:newID]) command = c;
      check([mine.keyEquivalent isEqual:F6()], @"the saved F6 applies");
      check([store restoreCommand:command] == nil && mine.keyEquivalent.length == 0 && [other.keyEquivalent isEqual:F5()],
            @"restoring the item forgets F6 and leaves F5 to the other item"); }
    // 5. A macro names F5.
    { NSMenu *menu = [NSMenu new]; NSMenuItem *mine = Item(menu, @"Complete", @selector(completeLabelOrCitationKey:), F5(), newID);
      TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:menu defaults:[TSMemoryDefaults new]];
      TSShortcutMacro *macro = [[TSShortcutMacro alloc] initWithName:@"M" path:@"Macros/M" indexPath:[NSIndexPath indexPathWithIndex:0] serializedKey:@"F5" key:F5() modifiers:0];
      store.macroProvider = ^{ return @[macro]; };
      [store refreshMenu];
      check(mine.keyEquivalent.length == 0, @"a macro that names F5 keeps it");
      NSArray *conflicts = [store conflictsForMacroShortcuts:@[@{@"path":@"Macros/M", @"key":F5(), @"modifiers":@0}]];
      check(conflicts.count == 0, @"the macro's F5 is not inactive");
      check([store macrosAffectedByRestoringAll].count == 0, @"restoring all warns of no macro for the yielding item");
      store.macroProvider = nil; [store refreshMenu];
      check([mine.keyEquivalent isEqual:F5()], @"without the macro, F5 comes back"); }
    // 6. Recording F5 while another item has it is refused; restoring the item keeps it empty.
    { NSMenu *menu = [NSMenu new]; Item(menu, @"Other", @selector(copy:), F5(), @"TSShortcut.copy:.0");
      NSMenuItem *mine = Item(menu, @"Complete", @selector(completeLabelOrCitationKey:), F5(), newID);
      TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:menu defaults:[TSMemoryDefaults new]];
      TSShortcutCommand *command = nil; for (TSShortcutCommand *c in store.commands) if ([c.commandID isEqual:newID]) command = c;
      NSString *message = [store setKey:F5() modifiers:0 forCommand:command];
      check(message.length > 0 && mine.keyEquivalent.length == 0, @"recording F5 that another item has is refused");
      [store restoreCommand:command];
      check(mine.keyEquivalent.length == 0 && F5Owners(menu) == 1, @"restoring the yielding item leaves F5 to the other item");
      [store restoreAll];
      check(mine.keyEquivalent.length == 0 && F5Owners(menu) == 1, @"restoring all leaves one F5 owner"); }
}

// ---- the menu item and its target ----
static NSWindow *TSTestKeyWindow;
static id KeyWindow(id app, SEL sel) { return TSTestKeyWindow; }
@interface CountingTextView : NSTextView
@property int completes;
@end
@implementation CountingTextView
- (void)complete:(id)sender { self.completes++; }
@end
static void CheckMenuItem(void) {
    NSMenu *main = [NSMenu new];
    NSMenuItem *editItem = [main addItemWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"]; editItem.submenu = edit;
    [edit addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *markItem = [edit addItemWithTitle:@"Marks" action:nil keyEquivalent:@""];
    NSMenu *marks = [[NSMenu alloc] initWithTitle:@"Marks"]; markItem.submenu = marks;
    [marks addItemWithTitle:@"Next Mark" action:@selector(doNextBullet:) keyEquivalent:@""];
    [TSMarkMenu installInMenu:main];
    [TSMarkMenu installInMenu:main];
    NSInteger index = [edit indexOfItemWithTarget:[TSMarkMenu sharedInstance] andAction:@selector(completeLabelOrCitationKey:)];
    check(index >= 0 && index == [edit indexOfItem:markItem] + 1, @"the item comes just after the Mark submenu, once");
    NSMenuItem *item = index >= 0 ? [edit itemAtIndex:index] : nil;
    check([item.identifier isEqual:@"TSShortcut.completeLabelOrCitationKey:.0"] && [item.keyEquivalent isEqual:F5()] &&
          (item.keyEquivalentModifierMask & TSShortcutModifiers) == 0, @"the item has its identifier and F5 alone");
    TSReplaceTestMethod(class_getInstanceMethod(NSApplication.class, @selector(keyWindow)), (IMP)KeyWindow);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    CountingTextView *text = [[CountingTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    window.contentView = text; TSTestKeyWindow = window; [window makeFirstResponder:text];
    TSMarkMenu *target = [TSMarkMenu sharedInstance];
    check([target validateMenuItem:item], @"an editable text view enables the item");
    [target completeLabelOrCitationKey:item];
    check(text.completes == 1, @"the item sends complete: to that text view");
    text.editable = NO;
    check(![target validateMenuItem:item], @"a read-only text view dims the item");
    [target completeLabelOrCitationKey:item];
    check(text.completes == 1, @"nothing is sent to a read-only text view");
    text.editable = YES; text.fieldEditor = YES;
    check(![target validateMenuItem:item], @"a field editor dims the item");
    text.fieldEditor = NO;
    NSView *plain = [[NSView alloc] initWithFrame:NSZeroRect]; window.contentView = plain; [window makeFirstResponder:plain];
    check(![target validateMenuItem:item], @"no text view dims the item");
    TSTestKeyWindow = nil;
    check(![target validateMenuItem:item], @"no key window dims the item");
}

// ---- Escape and Tab during composition; Escape in the Experiment panel ----
NSString *g_commandCompletionChar;
@interface CountingPanel : NSPanel
@property int cancels;
@end
@implementation CountingPanel
- (void)cancelOperation:(id)sender { self.cancels++; }
@end
@interface SourceTextView : NSTextView
@property int completions;
@end
@implementation SourceTextView
@@DOCOMMAND_SOURCE@@
@@KEYDOWN_SOURCE@@
// Stands for the production handleKeyDown: (completion, marks, brackets): Escape and Tab
// count as completions, "d" deletes backward through a command, other keys go to AppKit.
- (void)handleKeyDown:(NSEvent *)theEvent
{
    if ([theEvent.charactersIgnoringModifiers isEqual:@"\033"] || [theEvent.charactersIgnoringModifiers isEqual:@"\t"]) { self.completions++; return; }
    if ([theEvent.charactersIgnoringModifiers isEqual:@"d"]) { [self doCommandBySelector:@selector(deleteBackward:)]; return; }
    [super keyDown: theEvent];
}
@end
@interface ScrapTextView : NSTextView
@end
@implementation ScrapTextView
@@PASS_SCRAP@@
- (void)keyDown:(NSEvent *)theEvent { [self passKeyDown: theEvent]; }
@end
static NSEvent *Key(NSWindow *window, unsigned short code, NSString *chars, NSString *ignoring, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:window.windowNumber context:nil characters:chars charactersIgnoringModifiers:ignoring isARepeat:NO keyCode:code];
}
static void CheckComposition(void) {
    CountingPanel *panel = [[CountingPanel alloc] initWithContentRect:NSMakeRect(-8000, -8000, 300, 200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)]; panel.contentView = content;
    SourceTextView *text = [[SourceTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
    NSTextField *other = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 120, 300, 24)];
    [content addSubview:text]; [content addSubview:other];
    text.nextKeyView = other; other.nextKeyView = text;
    struct { unsigned short code; NSString *chars, *ignoring; NSEventModifierFlags flags; const char *name; } keys[] = {
        {53, @"\033", @"\033", 0, "Escape"}, {53, @"\033", @"\033", NSEventModifierFlagShift, "Shift-Escape"},
        {53, @"\033", @"\033", NSEventModifierFlagOption, "Option-Escape"}, {53, @"\033", @"\033", NSEventModifierFlagControl, "Control-Escape"},
        {48, @"\t", @"\t", 0, "Tab"}, {48, @"\031", @"\031", NSEventModifierFlagShift, "Shift-Tab"},
        {48, @"\t", @"\t", NSEventModifierFlagOption, "Option-Tab"}, {48, @"\t", @"\t", NSEventModifierFlagControl, "Control-Tab"}};
    for (unsigned i = 0; i < sizeof keys / sizeof keys[0]; i++) {
        text.string = @"x"; [panel makeFirstResponder:text]; text.selectedRange = NSMakeRange(1, 0);
        [text setMarkedText:@"かな" selectedRange:NSMakeRange(2, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        text.completions = 0; panel.cancels = 0;
        NSEvent *event = Key(panel, keys[i].code, keys[i].chars, keys[i].ignoring, keys[i].flags);
        [text keyDown:event];
        NSString *name = @(keys[i].name);
        check(text.completions == 0, [name stringByAppendingString:@" during composition: no completion or mark move"]);
        check(panel.cancels == 0, [name stringByAppendingString:@" during composition: the panel stays"]);
        check(panel.firstResponder == text, [name stringByAppendingString:@" during composition: the focus stays"]);
        check([text.string isEqual:@"xかな"] && text.hasMarkedText && NSEqualRanges(text.markedRange, NSMakeRange(1, 2)),
              [name stringByAppendingString:@" during composition: the text and the composition stay"]);
        [text unmarkText];
    }
    // Shift-Tab arrives as Backtab and is the Tab trigger with Shift.
    check([TSCompletionTypedKey(Key(panel, 48, @"\031", @"\031", NSEventModifierFlagShift)) isEqual:@"\t"] &&
          [TSCompletionTypedKey(Key(panel, 48, @"\t", @"\t", 0)) isEqual:@"\t"] &&
          [TSCompletionTypedKey(Key(panel, 53, @"\033", @"\033", NSEventModifierFlagShift)) isEqual:@"\033"],
          @"Shift-Tab is compared as Tab with Shift");
    // Control-Y also arrives as U+0019: it is not Shift-Tab.
    check([TSCompletionTypedKey(Key(panel, 16, @"\031", @"y", NSEventModifierFlagControl)) isEqual:@"\031"], @"Control-Y stays itself");
    // A new key that does not start during composition keeps its commands, even while an outer
    // key is still being delivered to the same view.
    text.string = @"ab"; text.selectedRange = NSMakeRange(2, 0);
    TSDeliverCompletionKeyToInputMethod(text, ^{ [text keyDown:Key(panel, 2, @"d", @"d", 0)]; });
    check([text.string isEqual:@"a"], @"a nested key outside composition is handled by the same view");
    // Only the view being delivered to drops commands; another text view handles them.
    SourceTextView *second = [[SourceTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
    [content addSubview:second];
    second.string = @"ab"; second.selectedRange = NSMakeRange(2, 0);
    [second doCommandBySelector:@selector(deleteBackward:)];
    check([second.string isEqual:@"a"], @"a text view handles a command on its own");
    second.string = @"ab"; second.selectedRange = NSMakeRange(2, 0);
    TSDeliverCompletionKeyToInputMethod(text, ^{ [second doCommandBySelector:@selector(deleteBackward:)]; });
    check([second.string isEqual:@"a"], @"another text view handles a command while a key is delivered to the composing view");
    text.string = @"ab"; text.selectedRange = NSMakeRange(2, 0);
    TSDeliverCompletionKeyToInputMethod(text, ^{ [text doCommandBySelector:@selector(deleteBackward:)]; });
    check([text.string isEqual:@"ab"], @"the composing view drops it");
    // Not composing: the source view's own handling runs.
    text.string = @"x"; text.completions = 0;
    [text keyDown:Key(panel, 53, @"\033", @"\033", 0)];
    check(text.completions == 1, @"without composition, Escape goes to completion");

    // The Experiment panel: with Escape as the trigger, Escape never reaches the panel.
    ScrapTextView *scrap = [[ScrapTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
    [content addSubview:scrap]; [panel makeFirstResponder:scrap];
    unichar escape = 0x1b, tab = 0x09;
    g_commandCompletionChar = [NSString stringWithCharacters:&escape length:1];
    panel.cancels = 0;
    [scrap keyDown:Key(panel, 53, @"\033", @"\033", 0)];
    [scrap keyDown:Key(panel, 53, @"\033", @"\033", NSEventModifierFlagShift)];
    check(panel.cancels == 0, @"Escape trigger: Escape and Shift-Escape do not close the Experiment panel");
    g_commandCompletionChar = [NSString stringWithCharacters:&tab length:1];
    [scrap keyDown:Key(panel, 53, @"\033", @"\033", 0)];
    check(panel.cancels == 1, @"Tab trigger: Escape closes the Experiment panel as before");
}

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    CheckYielding();
    CheckMenuItem();
    CheckComposition();
    if (failures) { fprintf(stderr, "FAIL: %d of %d completion and mark key checks\n", failures, checks); return 1; }
    printf("PASS: %d completion and mark key checks\n", checks);
} return 0; }
