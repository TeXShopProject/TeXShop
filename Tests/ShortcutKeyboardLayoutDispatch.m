// Menu shortcuts on French and German keyboard layouts, matched by AppKit itself.
// This switches the keyboard layout of the Mac it runs on, so it refuses to run unless
// TEXSHOP_ALLOW_LAYOUT_SWITCH=1; run-shortcut-keyboard-layout-dispatch.py runs it in a VM.
// The menu holds the commands of TeXShop's MainMenu.nib with the keys the nib gives them.
#import "TSShortcutInternal.h"
#import <Carbon/Carbon.h>
#define REQUIRE(c, ...) do { if (!(c)) { fprintf(stderr, "FAIL: %s\n", [[NSString stringWithFormat:__VA_ARGS__] UTF8String]); Restore(); exit(1); } } while (0)

static NSString * const ABC = @"com.apple.keylayout.ABC", * const French = @"com.apple.keylayout.French", * const German = @"com.apple.keylayout.German";
static TISInputSourceRef Source(NSString *identifier) {
    NSArray *list = CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)@{(__bridge id)kTISPropertyInputSourceID: identifier}, true));
    return list.count ? (__bridge TISInputSourceRef)list[0] : NULL;
}
static NSMutableSet *enabledHere;
static void Restore(void) {
    TISSelectInputSource(Source(ABC));
    for (NSString *identifier in enabledHere) TISDisableInputSource(Source(identifier));
}
static void Spin(NSTimeInterval seconds) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static void Select(NSString *identifier) {
    TISInputSourceRef source = Source(identifier);
    if (!source) { fprintf(stderr, "FAIL: no input source %s\n", identifier.UTF8String); Restore(); exit(1); }
    NSNumber *enabled = (__bridge NSNumber *)TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled);
    if (!enabled.boolValue) { TISEnableInputSource(source); [enabledHere addObject:identifier]; }
    TISSelectInputSource(source);
    Spin(1.0);
    REQUIRE([TSKeyboardLayoutID() isEqual:identifier], @"layout %@ selected, %@ current", identifier, TSKeyboardLayoutID());
}

@interface DispatchMemoryDefaults : NSObject
@property NSMutableDictionary *values;
@end
@implementation DispatchMemoryDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (void)setObject:(id)value forKey:(NSString *)key { self.values[key] = value; }
- (void)removeObjectForKey:(NSString *)key { [self.values removeObjectForKey:key]; }
@end
@interface DispatchTarget : NSObject
@property (weak) NSMenuItem *lastItem;
@end
@implementation DispatchTarget
- (BOOL)respondsToSelector:(SEL)selector { return [NSStringFromSelector(selector) hasPrefix:@"fixture"] || [super respondsToSelector:selector]; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [NSStringFromSelector(selector) hasPrefix:@"fixture"] ? [NSMethodSignature signatureWithObjCTypes:"v@:@"] : [super methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation { __unsafe_unretained id sender; [invocation getArgument:&sender atIndex:2]; self.lastItem = sender; }
- (BOOL)validateMenuItem:(NSMenuItem *)item { return YES; }
@end

static DispatchTarget *target;
static NSWindow *window;
static NSArray<NSDictionary *> *nibItems;
// Builds TeXShop's menu commands with the keys MainMenu.nib gives them.
static NSMenu *BuildMenu(void) {
    NSMenu *main = [NSMenu new];
    [main addItemWithTitle:@"App" action:nil keyEquivalent:@""].submenu = [NSMenu new];
    NSMenuItem *top = [main addItemWithTitle:@"Commands" action:nil keyEquivalent:@""];
    top.submenu = [[NSMenu alloc] initWithTitle:@"Commands"];
    NSUInteger serial = 0;
    for (NSDictionary *entry in nibItems) {
        SEL action = NSSelectorFromString([NSString stringWithFormat:@"fixture%lu:", (unsigned long)++serial]);
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entry[@"identifier"] action:action keyEquivalent:@""];
        item.identifier = entry[@"identifier"]; item.target = target;
        item.keyEquivalentModifierMask = [entry[@"modifiers"] unsignedIntegerValue];
        item.keyEquivalent = entry[@"key"];
        [top.submenu addItem:item];
    }
    return main;
}
static NSMenuItem *ItemNamed(NSMenu *main, NSString *identifier) {
    for (NSMenuItem *item in main.itemArray[1].submenu.itemArray) if ([item.identifier isEqual:identifier]) return item;
    return nil;
}
static TSShortcutCommand *Command(TSShortcutStore *store, NSString *identifier) {
    for (TSShortcutCommand *command in store.commands) if ([command.commandID isEqual:identifier]) return command;
    return nil;
}
// A key press as the current layout types the character with these modifiers, or nil.
static NSEvent *KeyPress(NSString *character, NSEventModifierFlags flags) {
    TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
    CFDataRef data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
    NSEvent *event = nil;
    for (UInt16 code = 0; code < 128 && !event; code++) {
        for (int shift = 0; shift < 2 && !event; shift++) {
            NSString *plain = TSRestorationCharacters(data, code, shift ? NSEventModifierFlagShift : 0, LMGetKbdType());
            if (![plain isEqual:character]) continue;
            NSEventModifierFlags modifiers = flags | (shift ? NSEventModifierFlagShift : 0);
            NSString *characters = TSRestorationCharacters(data, code, modifiers, LMGetKbdType());
            event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:modifiers
                timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
                characters:characters charactersIgnoringModifiers:plain isARepeat:NO keyCode:code];
        }
    }
    CFRelease(source);
    return event;
}
// The item AppKit runs for the key press that types this key on the current layout.
static NSMenuItem *Dispatch(TSShortcutBinding *binding) {
    NSString *key = binding.key;
    NSEventModifierFlags flags = binding.modifiers;
    // A capital letter or a shifted symbol in a key equivalent is typed with Shift.
    NSEvent *event = KeyPress(key, flags & ~NSEventModifierFlagShift);
    if (event && (flags & NSEventModifierFlagShift) && !(event.modifierFlags & NSEventModifierFlagShift)) event = nil;
    if (!event) event = KeyPress(key, flags);
    if (!event) return nil;
    target.lastItem = nil;
    [NSApp sendEvent:event];
    Spin(0.05);
    return target.lastItem;
}
// Keys AppKit shows for the nib's menu on this layout with no shortcut store, and whether
// pressing each key runs its command (a few keys cannot be typed as shown on a layout).
static NSDictionary<NSString *, TSShortcutBinding *> *ReferenceKeys(NSMutableSet *runs) {
    NSMenu *main = BuildMenu();
    NSApp.mainMenu = main; Spin(0.3);
    NSMutableDictionary *keys = [NSMutableDictionary dictionary];
    for (NSMenuItem *item in main.itemArray[1].submenu.itemArray) {
        TSShortcutBinding *shown = TSShownBinding(item);
        keys[item.identifier] = shown;
        if (shown.key.length && [shown.key characterAtIndex:0] < 0xf700 && Dispatch(shown) == item) [runs addObject:item.identifier];
    }
    return keys;
}
static NSUInteger checkedKeys;
static NSMutableDictionary<NSString *, NSSet *> *runsByLayout;
static void CheckLikeReference(NSMenu *main, NSDictionary<NSString *, TSShortcutBinding *> *reference, NSString *stage, NSSet *except) {
    NSString *layout = TSKeyboardLayoutID();
    NSSet *runs = runsByLayout[layout];
    for (NSMenuItem *item in main.itemArray[1].submenu.itemArray) {
        if ([except containsObject:item.identifier]) continue;
        TSShortcutBinding *expected = reference[item.identifier], *shown = TSShownBinding(item);
        REQUIRE([shown isEqual:expected], @"%@ on %@: %@ shows %@ %lx, AppKit shows %@ %lx for the nib's key",
            stage, layout, item.identifier, shown.key, (unsigned long)shown.modifiers, expected.key, (unsigned long)expected.modifiers);
        if (![runs containsObject:item.identifier]) continue;
        NSMenuItem *ran = Dispatch(expected);
        REQUIRE(ran == item, @"%@ on %@: the key %@ %lx shown for %@ runs %@", stage, layout, expected.key,
            (unsigned long)expected.modifiers, item.identifier, ran.identifier ?: @"nothing");
        checkedKeys++;
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.environment[@"TEXSHOP_ALLOW_LAYOUT_SWITCH"] isEqual:@"1"]) {
            fprintf(stderr, "Refusing to switch keyboard layouts here; run this in a VM with TEXSHOP_ALLOW_LAYOUT_SWITCH=1.\n");
            return 2;
        }
        enabledHere = [NSMutableSet set];
        nibItems = [NSArray arrayWithContentsOfFile:@(argv[1])];
        REQUIRE(nibItems.count > 20, @"menu fixture has %lu items", (unsigned long)nibItems.count);
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        target = [DispatchTarget new];
        window = [[NSWindow alloc] initWithContentRect:NSMakeRect(80, 80, 240, 120) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        Spin(0.5);
        NSString *const sourcePreview = @"TSShortcut.associatedWindow:.0", *const console = @"TSShortcut.displayConsole:.0";
        NSMutableDictionary *references = [NSMutableDictionary dictionary];
        runsByLayout = [NSMutableDictionary dictionary];
        for (NSString *layout in @[ABC, French, German]) {
            Select(layout);
            NSMutableSet *runs = [NSMutableSet set];
            references[layout] = ReferenceKeys(runs);
            runsByLayout[layout] = runs;
            REQUIRE(runs.count > nibItems.count / 2, @"%lu of %lu keys run their command on %@ without a store", (unsigned long)runs.count, (unsigned long)nibItems.count, layout);
        }
        TSShortcutBinding *french1 = references[French][sourcePreview];
        REQUIRE([french1 isEqual:TSBinding(@"&", NSEventModifierFlagCommand)], @"AppKit shows %@ for the nib's Command-1 on French", french1.key);
        REQUIRE([runsByLayout[French] containsObject:sourcePreview], @"Command-& runs Source ⇔ Preview on French without a store");

        for (NSString *layout in @[French, German, ABC]) {
            Select(layout);
            NSDictionary *reference = references[layout];
            // As at launch: the menu is in place and AppKit has adapted its keys before the store starts.
            NSMenu *main = BuildMenu();
            NSApp.mainMenu = main; Spin(0.3);
            DispatchMemoryDefaults *defaults = [DispatchMemoryDefaults new];
            TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:main defaults:(NSUserDefaults *)defaults];
            Spin(0.3);
            CheckLikeReference(main, reference, @"store started", nil);
            // The key 6.00 beta 6 gave Source ⇔ Preview on French: AppKit adapted the & it read back once more.
            if ([layout isEqual:French])
                REQUIRE(Dispatch(TSBinding(@"7", NSEventModifierFlagCommand | NSEventModifierFlagShift)) != ItemNamed(main, sourcePreview), @"Shift-Command-7 runs Source ⇔ Preview on French");
            // A refresh (macros rebuilt, a menu changed) keeps every default.
            [store refreshMenu]; Spin(0.3);
            CheckLikeReference(main, reference, @"menu refreshed", nil);
            TSShortcutCommand *associated = Command(store, sourcePreview), *consoleCommand = Command(store, console);
            REQUIRE(associated && consoleCommand, @"fixture commands are in the store");
            REQUIRE([associated.defaultKey isEqual:@"1"] && associated.defaultModifiers == NSEventModifierFlagCommand,
                @"Source ⇔ Preview default on %@ is %@ %lx, the nib gives Command-1", layout, associated.defaultKey, (unsigned long)associated.defaultModifiers);
            TSShortcutBinding *shownDefault = reference[sourcePreview];
            REQUIRE([[store shownDefaultForCommand:associated] isEqual:shownDefault], @"default shown on %@", layout);

            // Assigning another key to Console and restoring it leaves the other defaults as they were.
            NSString *error = [store setKey:@"j" modifiers:NSEventModifierFlagCommand | NSEventModifierFlagControl forCommand:consoleCommand];
            REQUIRE(error == nil, @"assigning Control-Command-J: %@", error);
            Spin(0.3);
            CheckLikeReference(main, reference, @"other command assigned", [NSSet setWithObject:console]);
            REQUIRE(Dispatch(TSBinding(@"j", NSEventModifierFlagCommand | NSEventModifierFlagControl)) == consoleCommand.item, @"assigned key runs Console");
            REQUIRE([store restoreCommand:consoleCommand] == nil, @"restoring Console");
            Spin(0.3);
            CheckLikeReference(main, reference, @"command restored", nil);

            // Source ⇔ Preview gets another key, and comes back as AppKit shows the nib's key.
            REQUIRE([store setKey:@"k" modifiers:NSEventModifierFlagCommand | NSEventModifierFlagControl forCommand:associated] == nil, @"assigning to Source ⇔ Preview");
            Spin(0.3);
            REQUIRE([[store shownDefaultForCommand:associated] isEqual:shownDefault], @"default shown on %@ while another key is assigned", layout);
            // The key the layout shows for the default is the default: recording it restores the command.
            REQUIRE([store setKey:shownDefault.key modifiers:shownDefault.modifiers forCommand:associated] == nil, @"recording the shown default");
            REQUIRE(defaults.values[TSMenuShortcutOverridesKey] == nil, @"recording %@ on %@ saved %@ instead of restoring the default",
                shownDefault.key, layout, defaults.values[TSMenuShortcutOverridesKey]);
            Spin(0.3);
            CheckLikeReference(main, reference, @"default recorded again", nil);

            // The key a layout shows for a default is in use: another command cannot take it.
            NSString *conflict = [store conflictForKey:shownDefault.key modifiers:shownDefault.modifiers except:consoleCommand.item restoring:nil];
            REQUIRE([conflict hasSuffix:sourcePreview], @"%@ %@ on %@ is used by %@", shownDefault.key, sourcePreview, layout, conflict);
            // So is the key the menu gives it, which it shows again on another layout.
            conflict = [store conflictForKey:@"1" modifiers:NSEventModifierFlagCommand except:consoleCommand.item restoring:nil];
            REQUIRE([conflict hasSuffix:sourcePreview], @"Command-1 on %@ is used by %@", layout, conflict);
            // A saved key equal to the shown default of another command is not applied.
            defaults.values[TSMenuShortcutOverridesKey] = @{console: @{@"key": shownDefault.key, @"modifiers": @(shownDefault.modifiers)}};
            TSShortcutStore *saved = [[TSShortcutStore alloc] initWithMenu:main defaults:(NSUserDefaults *)defaults];
            Spin(0.3);
            REQUIRE([saved.unavailableCommands containsObject:Command(saved, console).path], @"saved %@ for Console on %@ is reported unavailable", shownDefault.key, layout);
            CheckLikeReference(main, reference, @"conflicting saved key", nil);
            fprintf(stdout, "PASS: %s keeps the keys AppKit shows for the menu, and they run their commands\n", layout.UTF8String);
            store = nil; saved = nil;
        }

        // While TeXShop runs, the user switches layouts: defaults follow, as the menu's own keys do.
        Select(French);
        NSMenu *main = BuildMenu();
        NSApp.mainMenu = main; Spin(0.3);
        DispatchMemoryDefaults *defaults = [DispatchMemoryDefaults new];
        defaults.values[TSMenuShortcutOverridesKey] = @{console: @{@"key": @"é", @"modifiers": @(NSEventModifierFlagCommand | NSEventModifierFlagControl)}};
        TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:main defaults:(NSUserDefaults *)defaults];
        Spin(0.3);
        REQUIRE(Dispatch(TSBinding(@"é", NSEventModifierFlagCommand | NSEventModifierFlagControl)) == Command(store, console).item, @"a key recorded on French runs its command");
        for (NSString *layout in @[German, ABC, French]) {
            Select(layout);
            [store refreshMenu]; Spin(0.3);
            CheckLikeReference(main, references[layout], @"layout switched", [NSSet setWithObject:console]);
            REQUIRE([TSShownBinding(Command(store, console).item) isEqual:TSBinding(@"é", NSEventModifierFlagCommand | NSEventModifierFlagControl)], @"a recorded key stays as recorded on %@", layout);
        }
        fprintf(stdout, "PASS: defaults follow a layout switch, recorded keys stay as recorded\n");
        fprintf(stdout, "PASS: %lu key presses ran the expected command\n", (unsigned long)checkedKeys);
        Restore();
        Spin(0.3);
        REQUIRE([TSKeyboardLayoutID() isEqual:ABC], @"ABC restored");
    }
    return 0;
}
