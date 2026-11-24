// SPDX-License-Identifier: GPL-2.0-or-later
// Window › Enter Full Screen has Globe-F and Control-Command-F is Next Mark's alone, in a compiled main menu after the
// launch step. No visible windows, user defaults or key events posted to the system.
#import "TestAppKitIsolation.h"
#import "TSShortcutInternal.h"
#import <objc/message.h>
static void Check(BOOL condition, NSString *reason) { if (!condition) { fprintf(stderr, "FAIL: %s\n", reason.UTF8String); exit(1); } }
static const NSEventModifierFlags C = NSEventModifierFlagCommand, K = NSEventModifierFlagControl;
static const NSEventModifierFlags Every = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption |
    NSEventModifierFlagShift | NSEventModifierFlagFunction;
// Every item of the menu, hidden ones and AppKit's own included.
static void Visit(NSMenu *menu, void (^visit)(NSMenuItem *)) {
    for (NSMenuItem *item in menu.itemArray) { visit(item); if (item.submenu) Visit(item.submenu, visit); }
}
static NSArray<NSMenuItem *> *Items(NSMenu *menu, SEL action) {
    NSMutableArray *items = [NSMutableArray array];
    Visit(menu, ^(NSMenuItem *item) { if (item.action == action) [items addObject:item]; });
    return items;
}
// The key an item was given. AppKit shows no key for an item whose key an earlier item shows, so the key is read with
// the adaptation to the keyboard layout off for a moment, as TSGivenBinding does.
static NSString *GivenKey(NSMenuItem *item) {
    BOOL localized = item.allowsAutomaticKeyEquivalentLocalization;
    item.allowsAutomaticKeyEquivalentLocalization = NO;
    NSString *key = [item.keyEquivalent copy];
    item.allowsAutomaticKeyEquivalentLocalization = localized;
    return key;
}
// The items whose key is Control-Command-F, as given or as shown: f (F would add Shift) with exactly these modifiers.
static NSArray<NSMenuItem *> *ControlCommandF(NSMenu *menu) {
    NSMutableArray *items = [NSMutableArray array];
    Visit(menu, ^(NSMenuItem *item) {
        if (([item.keyEquivalent isEqual:@"f"] || [GivenKey(item) isEqual:@"f"]) && (item.keyEquivalentModifierMask & Every) == (C | K))
            [items addObject:item];
    });
    return items;
}
// What AppKit does with a main menu when it is set at launch: adds the items it provides, and a hidden copy of Enter
// Full Screen for a key it moves to Globe-F. Private, so only when this AppKit has it.
static BOOL Customize(void) {
    SEL customize = NSSelectorFromString(@"_customizeMainMenu");
    if (![NSApp respondsToSelector:customize]) return NO;
    ((void (*)(id, SEL))objc_msgSend)(NSApp, customize);
    return YES;
}
static NSEvent *ControlCommandFEvent(void) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:C | K timestamp:0 windowNumber:0
                             context:nil characters:@"\x06" charactersIgnoringModifiers:@"f" isARepeat:NO keyCode:3];
}
int main(int argc, const char **argv) { @autoreleasepool {
    Check(argc >= 2, @"a compiled MainMenu nib is given");
    BOOL runtimeOnly = argc > 2 && !strcmp(argv[2], "--runtime-only");
    TSInstallAppKitIsolation(); [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[1])] bundle:nil]; NSArray *objects = nil;
    Check(nib != nil && [nib instantiateWithOwner:NSApp topLevelObjects:&objects], @"the compiled menu loads");
    NSMenu *main = nil; for (id object in objects) if ([object isKindOfClass:NSMenu.class] && [object numberOfItems] > 5) main = object;
    Check(main != nil, @"the main menu is found");
    NSArray<NSMenuItem *> *full = Items(main, @selector(toggleFullScreen:)), *next = Items(main, @selector(doNextBullet:));
    Check(full.count == 1 && next.count == 1, @"one Enter Full Screen and one Next Mark");
    NSMenuItem *fullScreen = full[0], *nextMark = next[0];
    // A nib key for it that another item has already is dropped by ibtool, which keeps its modifiers.
    if (!runtimeOnly) Check(GivenKey(fullScreen).length == 0 && fullScreen.keyEquivalentModifierMask == C, @"Enter Full Screen has no key or modifiers in the nib");
    // --runtime-only: the item as a nib key would leave it where no other item has the key (as when Next Mark had
    // Control-Command-]): Control-Command-F at launch.
    if (runtimeOnly) { fullScreen.keyEquivalentModifierMask = C | K; fullScreen.keyEquivalent = @"f"; nextMark.keyEquivalent = @"]"; }
    // Launch: AppKit customizes the menu it is given; then TeXShop's step and the shortcuts, which read the default keys.
    NSApp.mainMenu = main;
    BOOL customized = Customize();
    if (runtimeOnly) nextMark.keyEquivalent = @"f";
    Check([ControlCommandF(main) isEqual:@[nextMark]], @"AppKit adds no hidden Control-Command-F copy of Enter Full Screen");
    TSKeyboardShortcuts *shortcuts = [TSKeyboardShortcuts new];
    [shortcuts startObservingMenu];
    Check(shortcuts.store != nil, @"the shortcuts read the menu");
    // AppKit customizes the menu again whenever it is set; Globe-F stays, and no hidden copy comes.
    Customize();
    full = Items(main, @selector(toggleFullScreen:));
    Check(full.count == 1 && full[0] == fullScreen && !fullScreen.hidden && [fullScreen.keyEquivalent isEqual:@"f"] &&
          fullScreen.keyEquivalentModifierMask == NSEventModifierFlagFunction, @"Enter Full Screen has f with the Globe key only");
    Check([nextMark.keyEquivalent isEqual:@"f"] && (nextMark.keyEquivalentModifierMask & Every) == (C | K), @"Next Mark has Control-Command-F");
    Check([ControlCommandF(main) isEqual:@[nextMark]], @"no other item, hidden ones included, has Control-Command-F");
    // AppKit's own matching: Control-Command-F is taken while Next Mark has it, and by nothing once it has not.
    Check([main performKeyEquivalent:ControlCommandFEvent()], @"Control-Command-F reaches the menu");
    nextMark.keyEquivalent = @"";
    Check(![main performKeyEquivalent:ControlCommandFEvent()], @"nothing but Next Mark answers Control-Command-F");
    nextMark.keyEquivalent = @"f";
    // Settings › Keyboard: the default is Globe-F, macOS keeps it, and the row shows it as AppKit 27 does.
    TSShortcutCommand *command = nil;
    for (TSShortcutCommand *candidate in shortcuts.store.commands) if (candidate.item == fullScreen) command = candidate;
    Check(command != nil && command.managedBySystem && [command.defaultKey isEqual:@"f"] && command.defaultModifiers == NSEventModifierFlagFunction,
          @"the shortcuts take Globe-F as the default of Enter Full Screen, which macOS keeps");
    Check([[shortcuts.store displayKeyForCommand:command] isEqual:@"\U0001F310︎F"] &&
          [[shortcuts.store displayDefaultKeyForCommand:command] isEqual:@"\U0001F310︎F"], @"Settings shows 🌐︎F");
    printf("PASS: %s: Enter Full Screen f + Globe only, Next Mark Control-Command-F alone (AppKit customization %s)\n",
           [[@(argv[1]) stringByDeletingLastPathComponent] lastPathComponent].UTF8String, customized ? "run" : "not available");
}
return 0; }
