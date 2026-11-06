#import "TSKeyboardShortcuts.h"
#import <Carbon/Carbon.h>

NSString * const TSMenuShortcutOverridesKey = @"TSMenuShortcutOverrides";
static const NSEventModifierFlags TSShortcutModifiers = NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift;

// AppKit represents shifted punctuation as the resulting character without Shift.
// Resolve older menu definitions such as Shift+"=" using the active keyboard layout.
static NSString *TSTranslateKey(CFDataRef data, UInt16 keyCode, BOOL shifted, UInt32 keyboardType) {
    if (!data) return nil;
    UniChar chars[8]; UniCharCount count = 0; UInt32 dead = 0;
    OSStatus result = UCKeyTranslate((const UCKeyboardLayout *)CFDataGetBytePtr(data), keyCode,
        kUCKeyActionDown, shifted ? (shiftKey >> 8) : 0, keyboardType,
        kUCKeyTranslateNoDeadKeysBit, &dead, 8, &count, chars);
    return result == noErr && count == 1 ? [NSString stringWithCharacters:chars length:count] : nil;
}
static NSDictionary *TSBindingWithLayout(NSString *key, NSEventModifierFlags flags, CFDataRef data, UInt32 keyboardType) {
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
static NSDictionary *TSBinding(NSString *key, NSEventModifierFlags flags) {
    TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
    CFDataRef data = source ? TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) : NULL;
    if (!data) {
        if (source) CFRelease(source);
        source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
        data = source ? TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) : NULL;
    }
    NSDictionary *binding = TSBindingWithLayout(key, flags, data, LMGetKbdType());
    if (source) CFRelease(source);
    return binding;
}
static void TSVisitMenu(NSMenu *menu, NSString *path, void (^visit)(NSMenuItem *, NSString *)) {
    for (NSMenuItem *item in menu.itemArray) {
        NSString *title = path.length ? [path stringByAppendingFormat:@" › %@", item.title] : item.title;
        visit(item, title);
        if (item.submenu && item.submenu != NSApp.servicesMenu) TSVisitMenu(item.submenu, title, visit);
    }
}
static NSString *TSFindCommandID(NSMenuItem *item) {
    NSDictionary *tags = @{@"showFindPanel:":@1, @"findNext:":@2, @"findPrevious:":@3,
        @"replaceAll:":@4, @"replace:":@5, @"replaceAndFind:":@6,
        @"useSelectionForFind:":@7, @"jumpToSelection:":@8};
    NSNumber *tag = tags[NSStringFromSelector(item.action) ?: @""];
    if (tag) return [NSString stringWithFormat:@"TSShortcut.performFindPanelAction:.%@", tag];
    return nil;
}
static void TSPrepareMenuIdentifiers(NSMenu *menu) {
    TSVisitMenu(menu, @"", ^(NSMenuItem *item, NSString *path) {
        if ([item.identifier hasPrefix:@"TSShortcut."] || !item.action || item.submenu) return;
        NSString *sharedID = TSFindCommandID(item);
        if (sharedID) item.identifier = sharedID;
        else if ([NSStringFromClass([item.target class]) hasPrefix:@"Ogre"])
            item.identifier = [NSString stringWithFormat:@"TSShortcut.Ogre.%@.%ld", NSStringFromSelector(item.action), (long)item.tag];
    });
}
@implementation TSShortcutCommand
@end

@interface TSShortcutStore ()
@property NSMenu *menu;
@property NSUserDefaults *defaults;
@property NSMutableDictionary *overrides;
@property (readwrite) NSArray<TSShortcutCommand *> *commands;
@property (readwrite) NSArray<NSString *> *unavailableCommands;
@end
@implementation TSShortcutStore
- (instancetype)initWithMenu:(NSMenu *)menu defaults:(NSUserDefaults *)defaults {
    if (!(self = [super init])) return nil;
    _menu = menu; _defaults = defaults;
    id saved = [defaults objectForKey:TSMenuShortcutOverridesKey];
    _overrides = [NSMutableDictionary dictionary];
    // Treat a malformed preference as absent, including invalid individual entries.
    if ([saved isKindOfClass:NSDictionary.class]) {
        [saved enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSDictionary.class]) return;
            id character = value[@"key"], modifiers = value[@"modifiers"];
            if ([character isKindOfClass:NSString.class] && [modifiers isKindOfClass:NSNumber.class] &&
                [TSShortcutStore isAllowedKey:character modifiers:[modifiers unsignedIntegerValue]])
                self.overrides[key] = TSBinding(character, [modifiers unsignedIntegerValue]);
        }];
    }
    [self refreshMenu];
    return self;
}
- (void)refreshMenu {
    TSPrepareMenuIdentifiers(self.menu);
    NSMapTable *previous = [NSMapTable strongToStrongObjectsMapTable];
    for (TSShortcutCommand *command in self.commands) [previous setObject:command forKey:command.item];
    NSMutableArray *commands = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (![item.identifier hasPrefix:@"TSShortcut."] || !item.action || item.submenu || [seen containsObject:item.identifier]) return;
        [seen addObject:item.identifier];
        TSShortcutCommand *command = [previous objectForKey:item];
        if (!command) {
            command = [TSShortcutCommand new];
            command.item = item; command.commandID = item.identifier;
            command.defaultKey = item.keyEquivalent; command.defaultModifiers = item.keyEquivalentModifierMask;
            command.defaultLocalization = item.allowsAutomaticKeyEquivalentLocalization;
        }
        command.path = path; [commands addObject:command];
    });
    self.commands = commands;
    [self applySavedOverrides];
}
- (void)suspendOverridesForMenuRebuild {
    // Let rebuilt macro items reserve their own keys before applying user overrides.
    for (TSShortcutCommand *command in self.commands) command.item.keyEquivalent = @"";
    for (TSShortcutCommand *command in self.commands) {
        command.item.allowsAutomaticKeyEquivalentLocalization = command.defaultLocalization;
        command.item.keyEquivalentModifierMask = command.defaultModifiers;
        command.item.keyEquivalent = command.defaultKey;
    }
}
- (void)applySavedOverrides {
    NSMutableSet *active = [NSMutableSet set];
    NSMutableOrderedSet *unavailable = [NSMutableOrderedSet orderedSet];
    for (TSShortcutCommand *command in self.commands)
        if (self.overrides[command.commandID]) [active addObject:command.commandID];
    NSMapTable *planned = [NSMapTable strongToStrongObjectsMapTable];
    BOOL changed;
    do {
        changed = NO;
        TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
            if (!item.submenu) [planned setObject:TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask) forKey:item];
        });
        for (TSShortcutCommand *command in self.commands) {
            NSDictionary *value = [active containsObject:command.commandID] ? self.overrides[command.commandID] : TSBinding(command.defaultKey, command.defaultModifiers);
            [planned setObject:value forKey:command.item];
        }
        NSMutableSet *rejected = [NSMutableSet set];
        for (TSShortcutCommand *command in self.commands) {
            if (![active containsObject:command.commandID]) continue;
            NSDictionary *value = [planned objectForKey:command.item];
            if (![value[@"key"] length]) continue;
            for (NSMenuItem *other in planned.keyEnumerator) {
                if (other != command.item && [[planned objectForKey:other] isEqual:value]) {
                    [rejected addObject:command.commandID]; [unavailable addObject:command.path]; break;
                }
            }
        }
        if (rejected.count) { [active minusSet:rejected]; changed = YES; }
    } while (changed);
    // Avoid transient duplicates when restoring defaults or swapping two saved bindings.
    for (TSShortcutCommand *command in self.commands) command.item.keyEquivalent = @"";
    for (TSShortcutCommand *command in self.commands) {
        if ([active containsObject:command.commandID]) [self apply:self.overrides[command.commandID] to:command];
        else {
            command.item.allowsAutomaticKeyEquivalentLocalization = command.defaultLocalization;
            command.item.keyEquivalentModifierMask = command.defaultModifiers;
            command.item.keyEquivalent = command.defaultKey;
        }
    }
    for (TSShortcutCommand *command in self.commands) {
        if ([active containsObject:command.commandID] &&
            ![TSBinding(command.item.keyEquivalent, command.item.keyEquivalentModifierMask) isEqual:[planned objectForKey:command.item]])
            [unavailable addObject:command.path];
    }
    self.unavailableCommands = unavailable.array;
}
+ (BOOL)isAllowedKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    if (key.length == 0) return YES;
    if (key.length != 1 || (flags & ~TSShortcutModifiers)) return NO;
    unichar c = [key characterAtIndex:0];
    if (c >= NSF1FunctionKey && c <= NSF20FunctionKey) return YES;
    // Avoid taking plain typing, navigation, or dead-key combinations away from editors.
    return (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) &&
        c >= 0x20 && c != 0x7f && !(c >= 0xd800 && c <= 0xdfff);
}
- (void)apply:(NSDictionary *)binding to:(TSShortcutCommand *)command {
    command.item.allowsAutomaticKeyEquivalentLocalization = NO;
    command.item.keyEquivalent = @"";
    command.item.keyEquivalentModifierMask = [binding[@"modifiers"] unsignedIntegerValue];
    command.item.keyEquivalent = binding[@"key"];
}
- (nullable NSString *)conflictForKey:(NSString *)key modifiers:(NSEventModifierFlags)flags except:(NSMenuItem *)excluded {
    if (!key.length) return nil;
    NSDictionary *binding = TSBinding(key, flags);
    __block NSString *conflict = nil;
    TSVisitMenu(self.menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (item == excluded || item.submenu || !item.keyEquivalent.length) return;
        if ([TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask) isEqual:binding]) conflict = path;
    });
    return conflict;
}
- (void)persist {
    if (self.overrides.count) [self.defaults setObject:self.overrides.copy forKey:TSMenuShortcutOverridesKey];
    else [self.defaults removeObjectForKey:TSMenuShortcutOverridesKey];
}
- (nullable NSString *)setKey:(NSString *)key modifiers:(NSEventModifierFlags)flags forCommand:(TSShortcutCommand *)command {
    if (![self.commands containsObject:command]) return NSLocalizedString(@"This command is no longer available.", @"");
    if (![TSShortcutStore isAllowedKey:key modifiers:flags]) return NSLocalizedString(@"Use Command or Control with a key, or a function key (F1–F20).", @"");
    NSString *conflict = [self conflictForKey:key modifiers:flags except:command.item];
    if (conflict) return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), conflict];
    NSDictionary *binding = TSBinding(key, flags);
    if ([binding isEqual:TSBinding(command.defaultKey, command.defaultModifiers)]) [self.overrides removeObjectForKey:command.commandID];
    else self.overrides[command.commandID] = binding;
    [self applySavedOverrides];
    [self persist];
    return [self.unavailableCommands containsObject:command.path] ? NSLocalizedString(@"Shortcut Unavailable", @"") : nil;
}
- (nullable NSString *)restoreCommand:(TSShortcutCommand *)command {
    if (![self.commands containsObject:command]) return NSLocalizedString(@"This command is no longer available.", @"");
    NSString *conflict = [self conflictForKey:command.defaultKey modifiers:command.defaultModifiers except:command.item];
    if (conflict) return [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.", @""), conflict];
    [self.overrides removeObjectForKey:command.commandID];
    [self applySavedOverrides]; [self persist];
    return nil;
}
- (void)restoreAll {
    [self.overrides removeAllObjects];
    [self applySavedOverrides]; [self persist];
}
+ (NSString *)displayKey:(NSString *)key modifiers:(NSEventModifierFlags)flags {
    if (!key.length) return @"—";
    NSDictionary *binding = TSBinding(key, flags); flags = [binding[@"modifiers"] unsignedIntegerValue]; key = binding[@"key"];
    NSMutableString *text = [NSMutableString string];
    if (flags & NSEventModifierFlagControl) [text appendString:@"⌃"];
    if (flags & NSEventModifierFlagOption) [text appendString:@"⌥"];
    if (flags & NSEventModifierFlagShift) [text appendString:@"⇧"];
    if (flags & NSEventModifierFlagCommand) [text appendString:@"⌘"];
    unichar c = [key characterAtIndex:0];
    NSDictionary *symbols = @{@(NSLeftArrowFunctionKey):@"←", @(NSRightArrowFunctionKey):@"→", @(NSUpArrowFunctionKey):@"↑", @(NSDownArrowFunctionKey):@"↓", @13:@"↩", @9:@"⇥", @27:@"⎋", @32:@"␣", @127:@"⌫", @(NSDeleteFunctionKey):@"⌦"};
    if (c >= NSF1FunctionKey && c <= NSF20FunctionKey) [text appendFormat:@"F%u", c - NSF1FunctionKey + 1];
    else [text appendString:symbols[@(c)] ?: key.uppercaseString];
    return text;
}
+ (BOOL)event:(NSEvent *)event matchesItem:(NSMenuItem *)item {
    if (!item.keyEquivalent.length) return NO;
    return [TSBinding(event.charactersIgnoringModifiers ?: @"", event.modifierFlags) isEqual:TSBinding(item.keyEquivalent, item.keyEquivalentModifierMask)];
}
@end

@interface TSShortcutRecorder : NSView
@property (copy) void (^record)(NSEvent *);
@property (copy) dispatch_block_t accept;
@property (copy) dispatch_block_t cancel;
@end
@implementation TSShortcutRecorder
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityTextFieldRole; }
- (NSString *)accessibilityLabel { return NSLocalizedString(@"Change Shortcut", @""); }
- (NSString *)accessibilityHelp { return NSLocalizedString(@"Press the new shortcut (Escape to cancel).", @""); }
- (void)keyDown:(NSEvent *)event { [self performKeyEquivalent:event]; }
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers;
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    if ([key isEqual:@"\r"] && !flags) { if (self.accept) self.accept(); return YES; }
    if ([key isEqual:@"\033"] && !flags) { if (self.cancel) self.cancel(); return YES; }
    if (([key isEqual:@"\t"] || [key isEqual:@"\031"]) && !(flags & ~NSEventModifierFlagShift)) {
        if ((flags & NSEventModifierFlagShift) || [key isEqual:@"\031"]) [self.window selectPreviousKeyView:self];
        else [self.window selectNextKeyView:self];
        return YES;
    }
    if (self.record) self.record(event);
    return YES;
}
@end
@interface TSShortcutCapturePanel : NSPanel
@property TSShortcutRecorder *recorder;
@end
@implementation TSShortcutCapturePanel
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers;
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    BOOL buttonNavigation = (([key isEqual:@"\t"] || [key isEqual:@"\031"]) && !(flags & ~NSEventModifierFlagShift)) ||
        (([key isEqual:@"\r"] || [key isEqual:@" "]) && !flags);
    if (self.firstResponder != self.recorder && buttonNavigation) return [super performKeyEquivalent:event];
    return [self.recorder performKeyEquivalent:event];
}
@end

@interface TSKeyboardShortcuts () <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property TSShortcutStore *store;
@property BOOL menuRefreshPending;
@property NSTextField *hint;
@property NSTableView *table;
@property NSSearchField *search;
@property NSArray<TSShortcutCommand *> *visibleCommands;
@property NSArray<NSButton *> *selectionButtons;
@property TSShortcutCapturePanel *capturePanel;
@property TSShortcutCommand *editingCommand;
@property NSTextField *captureDisplay;
@property NSTextField *captureError;
@property NSButton *applyButton;
@property NSString *capturedKey;
@property NSEventModifierFlags capturedModifiers;
@end
@implementation TSKeyboardShortcuts
+ (instancetype)sharedController {
    static TSKeyboardShortcuts *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[self alloc] initWithWindow:nil]; });
    return controller;
}
- (void)installInMainMenu {
    if (self.store) { [self.store refreshMenu]; return; }
    NSMenu *appMenu = NSApp.mainMenu.itemArray.firstObject.submenu;
    for (NSMenuItem *item in appMenu.itemArray) {
        if (item.action != NSSelectorFromString(@"showPreferences:")) continue;
        NSMenuItem *entry = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Keyboard Shortcuts…", @"") action:@selector(showKeyboardShortcuts:) keyEquivalent:@""];
        entry.target = self;
        entry.identifier = @"TSShortcut.showKeyboardShortcuts:.0";
        [appMenu insertItem:entry atIndex:[appMenu indexOfItem:item] + 1];
        break;
    }
    self.store = [[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:NSUserDefaults.standardUserDefaults];
    for (NSNotificationName name in @[NSMenuDidAddItemNotification, NSMenuDidRemoveItemNotification])
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuStructureChanged:) name:name object:nil];
}
- (void)beginMenuRebuild {
    [self.store suspendOverridesForMenuRebuild];
}
- (void)endMenuRebuild {
    [self.store refreshMenu];
    if (self.isWindowLoaded) [self reloadCommands];
}
- (void)menuStructureChanged:(NSNotification *)notification {
    NSMenu *menu = notification.object;
    while (menu.supermenu) menu = menu.supermenu;
    if (menu != NSApp.mainMenu || self.menuRefreshPending) return;
    self.menuRefreshPending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.menuRefreshPending = NO;
        [self.store refreshMenu];
        if (self.isWindowLoaded) [self reloadCommands];
    });
}
+ (BOOL)event:(NSEvent *)event matchesAction:(SEL)action tag:(NSInteger)tag {
    __block BOOL matches = NO, found = NO;
    NSString *commandID = [NSString stringWithFormat:@"TSShortcut.%@.%ld", NSStringFromSelector(action), (long)tag];
    TSVisitMenu(NSApp.mainMenu, @"", ^(NSMenuItem *item, NSString *path) {
        if ((item.action == action && item.tag == tag) || [item.identifier isEqual:commandID] || [TSFindCommandID(item) isEqual:commandID]) {
            found = YES;
            if ([TSShortcutStore event:event matchesItem:item]) matches = YES;
        }
    });
    // Preserve PDF search if a custom menu entirely omits the standard Find commands.
    if (!found && action == @selector(performFindPanelAction:) && (tag == 1 || tag == 2)) {
        NSDictionary *key = TSBinding(event.charactersIgnoringModifiers ?: @"", event.modifierFlags);
        return [key isEqual:TSBinding(tag == 1 ? @"f" : @"g", NSEventModifierFlagCommand)];
    }
    return matches;
}
- (NSButton *)button:(NSString *)title action:(SEL)action {
    return [NSButton buttonWithTitle:NSLocalizedString(title, @"") target:self action:action];
}
- (void)loadWindow {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 570)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    window.title = NSLocalizedString(@"Keyboard Shortcuts", @"");
    window.contentMinSize = NSMakeSize(760, 480);
    window.releasedWhenClosed = NO;
    self.window = window;
    NSView *content = window.contentView;
    self.search = [NSSearchField new];
    self.search.placeholderString = NSLocalizedString(@"Search commands", @"");
    self.search.delegate = self;
    NSTextField *hint = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Select a command to change its shortcut. Changes take effect immediately. Macros and text input key bindings use their own editors.", @"")];
    hint.textColor = NSColor.secondaryLabelColor; self.hint = hint;
    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;
    self.table = [NSTableView new];
    self.table.delegate = self; self.table.dataSource = self;
    self.table.rowHeight = 28; self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.doubleAction = @selector(editShortcut:); self.table.target = self;
    NSTableColumn *command = [[NSTableColumn alloc] initWithIdentifier:@"command"];
    command.title = NSLocalizedString(@"Command", @""); command.width = 560; command.minWidth = 390;
    NSTableColumn *shortcut = [[NSTableColumn alloc] initWithIdentifier:@"shortcut"];
    shortcut.title = NSLocalizedString(@"Shortcut", @""); shortcut.width = 160; shortcut.minWidth = 130;
    [self.table addTableColumn:command]; [self.table addTableColumn:shortcut];
    scroll.documentView = self.table;
    NSButton *edit = [self button:@"Change…" action:@selector(editShortcut:)];
    NSButton *clear = [self button:@"Remove Shortcut" action:@selector(removeShortcut:)];
    NSButton *restore = [self button:@"Restore Default" action:@selector(restoreShortcut:)];
    NSButton *all = [self button:@"Restore All…" action:@selector(restoreAll:)];
    self.selectionButtons = @[edit, clear, restore];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[edit,clear,restore,all]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal; buttons.spacing = 12;
    for (NSView *view in @[self.search,hint,scroll,buttons]) { view.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [self.search.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [self.search.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [self.search.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [hint.topAnchor constraintEqualToAnchor:self.search.bottomAnchor constant:12],
        [hint.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor], [hint.trailingAnchor constraintEqualToAnchor:self.search.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:16],
        [scroll.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:self.search.trailingAnchor],
        [buttons.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:16],
        [buttons.leadingAnchor constraintEqualToAnchor:self.search.leadingAnchor],
        [buttons.trailingAnchor constraintLessThanOrEqualToAnchor:self.search.trailingAnchor],
        [buttons.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]
    ]];
    [window center];
    [self reloadCommands];
}
- (void)showKeyboardShortcuts:(id)sender {
    [self installInMainMenu];
    [self showWindow:sender];
    [self reloadCommands];
    [self.window makeKeyAndOrderFront:sender];
}
- (void)reloadCommands {
    self.hint.stringValue = NSLocalizedString(@"Select a command to change its shortcut. Changes take effect immediately. Macros and text input key bindings use their own editors.", @"");
    if (self.store.unavailableCommands.count)
        self.hint.stringValue = [self.hint.stringValue stringByAppendingFormat:@"\n%@: %@", NSLocalizedString(@"Shortcut Unavailable", @""), [self.store.unavailableCommands componentsJoinedByString:@", "]];
    NSString *query = self.search.stringValue ?: @"";
    NSMutableArray *visible = [NSMutableArray array];
    for (TSShortcutCommand *command in self.store.commands) {
        if (command.item.hidden && !command.item.allowsKeyEquivalentWhenHidden) continue;
        if (!query.length || [command.path localizedCaseInsensitiveContainsString:query]) [visible addObject:command];
    }
    self.visibleCommands = visible;
    [self.table reloadData];
    for (NSButton *button in self.selectionButtons) button.enabled = [self selectedCommand] != nil;
}
- (void)controlTextDidChange:(NSNotification *)notification { [self reloadCommands]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.visibleCommands.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    TSShortcutCommand *command = self.visibleCommands[row];
    BOOL isCommand = [column.identifier isEqualToString:@"command"];
    NSTextField *label = [NSTextField labelWithString:isCommand ? command.path : [TSShortcutStore displayKey:command.item.keyEquivalent modifiers:command.item.keyEquivalentModifierMask]];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.toolTip = command.path;
    return label;
}
- (TSShortcutCommand *)selectedCommand {
    NSInteger row = self.table.selectedRow;
    return row >= 0 && row < self.visibleCommands.count ? self.visibleCommands[row] : nil;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    for (NSButton *button in self.selectionButtons) button.enabled = [self selectedCommand] != nil;
}
- (void)showError:(NSString *)error {
    if (!error) return;
    NSAlert *alert = [NSAlert new]; alert.messageText = NSLocalizedString(@"Shortcut Unavailable", @""); alert.informativeText = error;
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (void)removeShortcut:(id)sender {
    TSShortcutCommand *command = self.selectedCommand; if (!command) return;
    [self showError:[self.store setKey:@"" modifiers:0 forCommand:command]];
    [self reloadCommands];
}
- (void)restoreShortcut:(id)sender {
    TSShortcutCommand *command = self.selectedCommand; if (!command) return;
    [self showError:[self.store restoreCommand:command]];
    [self reloadCommands];
}
- (void)restoreAll:(id)sender {
    NSAlert *alert = [NSAlert new]; alert.messageText = NSLocalizedString(@"Restore all keyboard shortcuts?", @"");
    alert.informativeText = NSLocalizedString(@"Your changes in this window will be removed. Existing KeyEquivalents.plist settings will be preserved.", @"");
    [alert addButtonWithTitle:NSLocalizedString(@"Restore All", @"")]; [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        [self.store restoreAll]; [self reloadCommands];
    }];
}
- (void)editShortcut:(id)sender {
    TSShortcutCommand *command = self.selectedCommand; if (!command || self.window.attachedSheet) return;
    self.editingCommand = command; self.capturedKey = nil;
    TSShortcutCapturePanel *panel = [[TSShortcutCapturePanel alloc] initWithContentRect:NSMakeRect(0,0,640,240) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.capturePanel = panel;
    panel.title = NSLocalizedString(@"Change Shortcut", @"");
    TSShortcutRecorder *recorder = [[TSShortcutRecorder alloc] initWithFrame:panel.contentView.bounds];
    recorder.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    panel.contentView = recorder; panel.recorder = recorder;
    NSTextField *title = [NSTextField labelWithString:command.path]; title.frame = NSMakeRect(20,195,600,25); title.lineBreakMode = NSLineBreakByTruncatingMiddle; title.toolTip = command.path;
    self.captureDisplay = [NSTextField labelWithString:NSLocalizedString(@"Press the new shortcut (Escape to cancel).", @"")];
    self.captureDisplay.frame = NSMakeRect(20,145,600,40); self.captureDisplay.font = [NSFont systemFontOfSize:18]; self.captureDisplay.alignment = NSTextAlignmentCenter;
    self.captureError = [NSTextField wrappingLabelWithString:@""]; self.captureError.frame = NSMakeRect(20,65,600,70); self.captureError.textColor = NSColor.secondaryLabelColor;
    self.applyButton = [self button:@"Apply" action:@selector(applyCapturedShortcut:)]; self.applyButton.enabled = NO;
    NSButton *cancel = [self button:@"Cancel" action:@selector(cancelCapture:)];
    self.applyButton.keyEquivalent = @"\r"; cancel.keyEquivalent = @"\033";
    recorder.nextKeyView = self.applyButton; self.applyButton.nextKeyView = cancel; cancel.nextKeyView = recorder;
    [self.applyButton sizeToFit]; [cancel sizeToFit];
    self.applyButton.frame = NSMakeRect(620-NSWidth(self.applyButton.frame),18,NSWidth(self.applyButton.frame),32);
    cancel.frame = NSMakeRect(NSMinX(self.applyButton.frame)-NSWidth(cancel.frame)-12,18,NSWidth(cancel.frame),32);
    for (NSView *view in @[title,self.captureDisplay,self.captureError,self.applyButton,cancel]) [recorder addSubview:view];
    __weak typeof(self) weakSelf = self;
    recorder.record = ^(NSEvent *event) { [weakSelf recordShortcutEvent:event]; };
    recorder.accept = ^{ [weakSelf applyCapturedShortcut:nil]; };
    recorder.cancel = ^{ [weakSelf cancelCapture:nil]; };
    [self.window beginSheet:panel completionHandler:^(NSModalResponse result) {
        panel.recorder.record = nil; panel.recorder.accept = nil; panel.recorder.cancel = nil;
        weakSelf.capturePanel = nil; weakSelf.editingCommand = nil;
        [weakSelf reloadCommands];
    }];
    [panel makeFirstResponder:recorder];
    panel.initialFirstResponder = recorder;
}
- (void)recordShortcutEvent:(NSEvent *)event {
    NSString *key = event.charactersIgnoringModifiers ?: @"";
    NSEventModifierFlags flags = event.modifierFlags & TSShortcutModifiers;
    self.captureError.stringValue = @"";
    self.applyButton.enabled = [TSShortcutStore isAllowedKey:key modifiers:flags] && key.length > 0;
    if (!self.applyButton.enabled) {
        self.capturedKey = nil;
        self.captureDisplay.stringValue = NSLocalizedString(@"Press the new shortcut (Escape to cancel).", @"");
        self.captureError.stringValue = NSLocalizedString(@"Use Command or Control with a key, or a function key (F1–F20).", @"");
    } else {
        self.capturedKey = key; self.capturedModifiers = flags;
        self.captureDisplay.stringValue = [TSShortcutStore displayKey:key modifiers:flags];
    }
    self.capturePanel.recorder.accessibilityValue = self.captureDisplay.stringValue;
}
- (void)cancelCapture:(id)sender { [self.window endSheet:self.capturePanel returnCode:NSModalResponseCancel]; }
- (void)applyCapturedShortcut:(id)sender {
    if (!self.capturedKey || !self.applyButton.enabled) return;
    NSString *error = [self.store setKey:self.capturedKey modifiers:self.capturedModifiers forCommand:self.editingCommand];
    if (error) { self.captureError.stringValue = error; [self.capturePanel makeFirstResponder:self.capturePanel.recorder]; return; }
    [self.window endSheet:self.capturePanel returnCode:NSModalResponseOK];
}
@end
