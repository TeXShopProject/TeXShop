// Runs against production code with in-memory preferences and no visible windows.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "TSKeyboardShortcuts.m"
#pragma clang diagnostic pop
#include "MacroKeyProduction.inc"
static void CollectMacros(NSArray *array, NSString *path, NSMutableArray *candidates) {
    for (NSDictionary *entry in array) {
        NSString *name=[path stringByAppendingFormat:@" › %@", entry[@"name"]];
        if (entry[@"submenu"]) CollectMacros(entry[@"submenu"], name, candidates);
        else if (![entry[@"name"] isEqual:@"Separator"])
            [candidates addObject:@{@"path":name, @"key":getKeyEquivalentFromString(entry[@"key"]), @"modifiers":@(getKeyModifierMaskFromString(entry[@"key"]))}];
    }
}
#import <objc/runtime.h>
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); exit(1); } } while (0)
@interface ShortcutMemoryDefaults : NSObject
@property NSMutableDictionary *values;
@end
@implementation ShortcutMemoryDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (void)setObject:(id)value forKey:(NSString *)key { self.values[key] = value; }
- (void)removeObjectForKey:(NSString *)key { [self.values removeObjectForKey:key]; }
@end
@interface ShortcutActionTarget : NSObject
@property NSMenuItem *lastItem;
- (void)run:(NSMenuItem *)sender;
@end
@implementation ShortcutActionTarget
- (void)run:(NSMenuItem *)sender { self.lastItem = sender; }
@end
static NSMenuItem *Item(NSString *ident, NSString *key, NSEventModifierFlags flags) {
    static NSUInteger serial = 0;
    SEL action = NSSelectorFromString([NSString stringWithFormat:@"fixtureAction%lu:", (unsigned long)++serial]);
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:ident ?: @"Dynamic" action:action keyEquivalent:@""];
    item.identifier = ident; item.keyEquivalentModifierMask = flags; item.keyEquivalent = key; return item;
}
static TSShortcutCommand *Command(TSShortcutStore *store, NSString *ident) {
    for (TSShortcutCommand *command in store.commands) if ([command.commandID isEqual:ident]) return command;
    return nil;
}
static NSDictionary *Saved(NSString *key) { return @{@"key":key, @"modifiers":@(NSEventModifierFlagCommand)}; }
static NSEvent *Event(NSString *key, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
        windowNumber:0 context:nil characters:key charactersIgnoringModifiers:key isARepeat:NO keyCode:0];
}
static NSEvent *LayoutEvent(NSString *characters, NSString *ignoring, unsigned short code, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
        windowNumber:0 context:nil characters:characters charactersIgnoringModifiers:ignoring isARepeat:NO keyCode:code];
}
static NSString *fixtureUnshifted;
static IMP originalUnshifted;
static id UnshiftedForFixture(id self, SEL cmd, NSEventModifierFlags flags) {
    return fixtureUnshifted ?: ((id (*)(id,SEL,NSEventModifierFlags))originalUnshifted)(self,cmd,flags);
}
static void CheckRecordedMenuConflicts(TSShortcutStore *store) {
    const NSUInteger cmd=NSEventModifierFlagCommand, shift=NSEventModifierFlagShift;
    TSKeyboardShortcuts *ui=[[TSKeyboardShortcuts alloc] initWithWindow:nil];
    ui.store=store; ui.editingCommand=Command(store,@"TSShortcut.doTypeset:.-1");
    ui.captureError=[NSTextField new]; ui.captureDisplay=[NSTextField new]; ui.applyButton=[NSButton new];
    NSString *original=ui.editingCommand.item.keyEquivalent;
    NSArray *cases=@[@[@"+",@"=",@24,@"zoomIn:"],@[@"_",@"-",@27,@"zoomOut:"]];
    if ([Command(store,@"TSShortcut.zoomOut:.0").item.keyEquivalent isEqual:@"_"])
        cases=[cases arrayByAddingObjectsFromArray:@[@[@"+",@";",@41,@"zoomIn:"],@[@"_",@"\\",@94,@"zoomOut:"]]];
    Method method=class_getInstanceMethod(NSEvent.class,@selector(charactersByApplyingModifiers:));
    originalUnshifted=method_setImplementation(method,(IMP)UnshiftedForFixture);
    for (NSArray *c in cases) {
        fixtureUnshifted=c[1];
        [ui recordShortcutEvent:LayoutEvent(c[0],c[0],[c[2] unsignedShortValue],cmd|shift)];
        TSShortcutCommand *zoom=Command(store,[@"TSShortcut." stringByAppendingFormat:@"%@.0",c[3]]);
        REQUIRE(zoom);
        REQUIRE([[ui conflictForCapturedShortcut] containsString:zoom.path]);
        [ui applyCapturedShortcut:nil];
        REQUIRE([ui.captureError.stringValue containsString:zoom.path]);
        REQUIRE([ui.editingCommand.item.keyEquivalent isEqual:original]);
    }
    // A German unshifted plus must not acquire the shifted Zoom In alias.
    TSShortcutCommand *zoom=Command(store,@"TSShortcut.zoomIn:.0");
    if ([zoom.item.keyEquivalent isEqual:@"+"] && zoom.item.keyEquivalentModifierMask==(cmd|shift)) {
        fixtureUnshifted=@"+"; [ui recordShortcutEvent:LayoutEvent(@"+",@"+",30,cmd)];
        REQUIRE(ui.capturedBindings.count==1);
        REQUIRE(![[ui conflictForCapturedShortcut] containsString:zoom.path]);
    }
    method_setImplementation(method,originalUnshifted); fixtureUnshifted=nil;
}
static NSMenu *MainMenu(void) {
    NSMenu *root = [NSMenu new], *menu = [NSMenu new];
    NSMenuItem *parent = [[NSMenuItem alloc] initWithTitle:@"Fixture" action:nil keyEquivalent:@""];
    parent.submenu = menu; [root addItem:parent]; NSApp.mainMenu = root; return menu;
}
static void IgnoreShortcutOutlet(id self, SEL cmd, id value, NSString *key) {}
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    if (argc > 1) {
        for (NSString *name in @[@"HelpDocuments",@"TSAppDelegate",@"TSAutoCompletionListEditor",@"TSDocumentController",@"TSMacroEditor",@"TSMacroMenuController",@"TSMovie",@"TSPreferences",@"TSSparkleController",@"TSStationery",@"TextFinder"]) {
            Class c = objc_allocateClassPair(NSObject.class,name.UTF8String,0);
            class_addMethod(c,@selector(setValue:forUndefinedKey:),(IMP)IgnoreShortcutOutlet,"v@:@@");
            objc_registerClassPair(c);
        }
        NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[1])] bundle:nil];
        NSArray *objects; REQUIRE([nib instantiateWithOwner:NSApp topLevelObjects:&objects]);
        NSMutableDictionary *original = [NSMutableDictionary new];
        TSVisitMenu(NSApp.mainMenu, @"", ^(NSMenuItem *item, NSString *path) {
            if (item.identifier) original[item.identifier] = @[item.keyEquivalent, @(item.keyEquivalentModifierMask)];
        });
        TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)[ShortcutMemoryDefaults new]];
        TSVisitMenu(NSApp.mainMenu, @"", ^(NSMenuItem *item, NSString *path) {
            if (original[item.identifier]) REQUIRE([original[item.identifier] isEqual:@[item.keyEquivalent, @(item.keyEquivalentModifierMask)]]);
        });
        TSShortcutCommand *typeset = Command(store,@"TSShortcut.doTypeset:.-1");
        REQUIRE(typeset);
        NSString *key = typeset.defaultKey; NSEventModifierFlags flags = typeset.defaultModifiers;
        REQUIRE(![store setKey:@"\uf717" modifiers:NSEventModifierFlagControl forCommand:typeset]);
        [store refreshMenu];
        REQUIRE(![store restoreCommand:Command(store,typeset.commandID)]);
        REQUIRE([typeset.item.keyEquivalent isEqual:key] && typeset.item.keyEquivalentModifierMask == flags);
        for (NSString *ident in @[@"TSShortcut.doTypeset:.-1",@"TSShortcut.doTypeset:.-2",@"TSShortcut.doAlternateTypeset:.-2",
            @"TSShortcut.splitWindow:.0",@"TSShortcut.splitWindow:.vertical",@"TSShortcut.doNextBulletAndDelete:.0",
            @"TSShortcut.doPreviousBulletAndDelete:.0",@"TSShortcut.placeComment:.0"])
            REQUIRE(Command(store,ident));
        if (argc > 2) {
            NSDictionary *macros=[NSDictionary dictionaryWithContentsOfFile:@(argv[2])]; REQUIRE(macros);
            NSMutableArray *candidates=[NSMutableArray array]; CollectMacros(macros[@"submenu"], @"Macros", candidates);
            NSArray *conflicts=[store conflictsForMacroShortcuts:candidates];
            if (conflicts.count) fprintf(stderr,"Conflicts: %s\n",conflicts.description.UTF8String);
            REQUIRE(candidates.count>100 && conflicts.count==0);
        }
        CheckRecordedMenuConflicts(store);
        return 0;
    }
    const NSEventModifierFlags cmd = NSEventModifierFlagCommand, shift = NSEventModifierFlagShift;
    ShortcutMemoryDefaults *defaults = [ShortcutMemoryDefaults new];
    NSMenu *menu = MainMenu();
    NSMenuItem *a = Item(@"TSShortcut.a", @"a", cmd), *b = Item(@"TSShortcut.b", @"b", cmd);
    [menu addItem:a]; [menu addItem:b];
    TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)defaults];
    REQUIRE([store setKey:@"b" modifiers:cmd forCommand:Command(store, a.identifier)] != nil);
    REQUIRE([a.keyEquivalent isEqual:@"a"] && defaults.values.count == 0);
    REQUIRE([store setKey:@"x" modifiers:cmd forCommand:Command(store, a.identifier)] == nil);
    REQUIRE([a.keyEquivalent isEqual:@"x"]);
    REQUIRE([store setKey:@"" modifiers:0 forCommand:Command(store, b.identifier)] == nil);
    REQUIRE(b.keyEquivalent.length == 0);
    [store restoreAll]; REQUIRE([a.keyEquivalent isEqual:@"a"] && [b.keyEquivalent isEqual:@"b"]);
    REQUIRE(defaults.values.count == 0);
    REQUIRE(![store setKey:@"x" modifiers:cmd forCommand:Command(store,a.identifier)]);
    [store refreshMenu]; [store refreshMenu];
    REQUIRE(![store restoreCommand:Command(store,a.identifier)]);
    REQUIRE([a.keyEquivalent isEqual:@"a"]);
    puts("PASS: conflict rejection, change, removal, refresh preserving baseline and restoration");
    REQUIRE(![store setKey:@"x" modifiers:cmd forCommand:Command(store,a.identifier)]);
    REQUIRE(![store setKey:@"a" modifiers:cmd forCommand:Command(store,b.identifier)]);
    REQUIRE([store setKey:@"a" modifiers:cmd forCommand:Command(store,a.identifier)] != nil);
    REQUIRE([store restoreCommand:Command(store,a.identifier)] != nil);
    REQUIRE([a.keyEquivalent isEqual:@"x"] && [b.keyEquivalent isEqual:@"a"]);
    REQUIRE(store.unavailableCommands.count == 0);
    [store restoreAll];
    puts("PASS: recording the original shortcut rejects a conflicting custom assignment without displacing it");

    // Swapped saved bindings must not be lost to AppKit's duplicate-key suppression.
    defaults.values[TSMenuShortcutOverridesKey] = @{a.identifier:Saved(@"b"), b.identifier:Saved(@"a")};
    store = [[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)defaults];
    REQUIRE([a.keyEquivalent isEqual:@"b"] && [b.keyEquivalent isEqual:@"a"]);
    [store restoreAll]; REQUIRE([a.keyEquivalent isEqual:@"a"] && [b.keyEquivalent isEqual:@"b"]);
    defaults.values[TSMenuShortcutOverridesKey] = @{a.identifier:Saved(@"b")};
    store = [[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)defaults];
    REQUIRE([a.keyEquivalent isEqual:@"a"] && [b.keyEquivalent isEqual:@"b"]);
    REQUIRE(store.unavailableCommands.count == 1);
    REQUIRE(defaults.values[TSMenuShortcutOverridesKey][a.identifier]);
    [store restoreAll];
    puts("PASS: launch-time conflicts remain saved but are not applied; atomic swap/reset");

    // Missing IDs survive edits; malformed values do not become bindings.
    defaults.values[TSMenuShortcutOverridesKey] = @{a.identifier:@{@"key":@4,@"modifiers":@0}, @"TSShortcut.absent":Saved(@"q")};
    store = [[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)defaults];
    REQUIRE([a.keyEquivalent isEqual:@"a"]);
    REQUIRE([store setKey:@"x" modifiers:cmd forCommand:Command(store,a.identifier)] == nil);
    REQUIRE(defaults.values[TSMenuShortcutOverridesKey][@"TSShortcut.absent"]);
    NSMenu *translated = MainMenu(); NSMenuItem *renamed = Item(a.identifier,@"a",cmd); renamed.title = @"別の言語";
    [translated addItem:renamed];
    TSShortcutStore *translatedStore = [[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)defaults];
    REQUIRE([renamed.keyEquivalent isEqual:@"x"]);
    [translatedStore restoreAll]; REQUIRE([renamed.keyEquivalent isEqual:@"a"]);
    puts("PASS: malformed preferences, absent IDs and language-independent persistence");

    // OgreKit replaces the whole Find menu after the launch notification.
    menu = MainMenu(); NSMenu *find = [NSMenu new];
    NSMenuItem *parent = [[NSMenuItem alloc] initWithTitle:@"Find" action:nil keyEquivalent:@""]; parent.submenu=find; [menu addItem:parent];
    NSMenuItem *oldFind=Item(@"TSShortcut.performFindPanelAction:.1",@"f",cmd);
    oldFind.action=@selector(performFindPanelAction:); oldFind.tag=1; [find addItem:oldFind];
    store=[[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)defaults];
    REQUIRE([store setKey:@"j" modifiers:cmd forCommand:Command(store,oldFind.identifier)] == nil);
    NSMenu *ogre=[NSMenu new];
    NSMenuItem *newFind=Item(nil,@"f",cmd); newFind.action=NSSelectorFromString(@"showFindPanel:");
    NSMenuItem *next=Item(nil,@"g",cmd); next.action=NSSelectorFromString(@"findNext:");
    [ogre addItem:newFind]; [ogre addItem:next]; parent.submenu=ogre;
    [store refreshMenu];
    REQUIRE(Command(store,oldFind.identifier).item == newFind);
    REQUIRE([newFind.keyEquivalent isEqual:@"j"]);
    REQUIRE([TSKeyboardShortcuts event:Event(@"j",cmd) matchesAction:@selector(performFindPanelAction:) tag:1]);
    REQUIRE(![TSKeyboardShortcuts event:Event(@"f",cmd) matchesAction:@selector(performFindPanelAction:) tag:1]);
    REQUIRE([TSKeyboardShortcuts event:Event(@"g",cmd) matchesAction:@selector(performFindPanelAction:) tag:2]);
    REQUIRE([store setKey:@"" modifiers:0 forCommand:Command(store,newFind.identifier)] == nil);
    REQUIRE(![TSKeyboardShortcuts event:Event(@"f",cmd) matchesAction:@selector(performFindPanelAction:) tag:1]);
    [store restoreAll]; REQUIRE([newFind.keyEquivalent isEqual:@"f"]);
    REQUIRE([TSKeyboardShortcuts event:Event(@"f",cmd) matchesAction:@selector(performFindPanelAction:) tag:1]);
    puts("PASS: Ogre replacement, shared IDs, customized PDF search, explicit removal and reset");
    NSMenuItem *jump=Item(@"TSShortcut.centerSelectionInVisibleArea:.0",@"j",cmd);
    jump.action=@selector(centerSelectionInVisibleArea:); [ogre addItem:jump]; [store refreshMenu];
    REQUIRE(![store setKey:@"k" modifiers:cmd forCommand:Command(store,jump.identifier)]);
    [ogre removeItem:jump];
    NSMenuItem *ogreJump=Item(nil,@"j",cmd); ogreJump.action=NSSelectorFromString(@"jumpToSelection:");
    [ogre addItem:ogreJump]; [store refreshMenu];
    REQUIRE([ogreJump.identifier isEqual:jump.identifier] && [ogreJump.keyEquivalent isEqual:@"k"]);
    [ogre removeItem:ogreJump];
    jump=Item(@"TSShortcut.centerSelectionInVisibleArea:.0",@"j",cmd); jump.action=@selector(centerSelectionInVisibleArea:);
    [ogre addItem:jump]; [store refreshMenu];
    REQUIRE([jump.keyEquivalent isEqual:@"k"]);
    [store restoreAll];
    puts("PASS: Jump to Selection override survives both standard/Ogre menu replacements");

    // Adding a macro later must not silently remove either command's shortcut.
    REQUIRE([store setKey:@"x" modifiers:cmd forCommand:Command(store,newFind.identifier)] == nil);
    [store refreshMenu];
    NSMenuItem *macro=Item(nil,@"x",cmd); macro.action=NSSelectorFromString(@"doMacro:"); [menu addItem:macro]; [store refreshMenu];
    REQUIRE([newFind.keyEquivalent isEqual:@"x"]);
    REQUIRE(store.unavailableCommands.count == 0); [store restoreAll];
    puts("PASS: macros never suspend a menu override");

    menu = MainMenu(); menu.autoenablesItems = NO;
    NSMenuItem *normal = Item(@"TSShortcut.normal",@"t",cmd);
    NSMenuItem *alternate = Item(@"TSShortcut.alternate",@"t",cmd|NSEventModifierFlagOption);
    ShortcutActionTarget *target = [ShortcutActionTarget new];
    normal.target = target; normal.action = @selector(run:);
    alternate.target = target; alternate.action = @selector(run:); alternate.alternate = YES;
    [menu addItem:normal]; [menu addItem:alternate];
    store = [[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)[ShortcutMemoryDefaults new]];
    REQUIRE(Command(store,normal.identifier) && Command(store,alternate.identifier));
    REQUIRE([store setKey:@"y" modifiers:cmd forCommand:Command(store,alternate.identifier)] == nil);
    REQUIRE([NSApp.mainMenu performKeyEquivalent:Event(@"y",cmd)] && target.lastItem == alternate);
    [store restoreAll];
    REQUIRE([normal.keyEquivalent isEqual:@"t"] && [alternate.keyEquivalent isEqual:@"t"]);
    REQUIRE(alternate.keyEquivalentModifierMask == (cmd|NSEventModifierFlagOption));
    puts("PASS: alternate commands remain selectable and dispatch after removing Option from their shortcut");

    menu=MainMenu(); menu.autoenablesItems=NO;
    NSMenuItem *minus=Item(nil,@"-",cmd|shift), *equals=Item(nil,@"=",cmd);
    for(NSMenuItem *item in @[minus,equals]) { item.action=@selector(run:);item.target=target;item.enabled=YES;item.allowsAutomaticKeyEquivalentLocalization=NO;[menu addItem:item]; }
    target.lastItem=nil; REQUIRE([menu performKeyEquivalent:LayoutEvent(@"-",@"-",kVK_ANSI_Minus,cmd|shift)] && target.lastItem==minus);
    target.lastItem=nil; REQUIRE([menu performKeyEquivalent:LayoutEvent(@"=",@"=",kVK_ANSI_Minus,cmd)] && target.lastItem==equals);
    puts("PASS: public AppKit dispatch distinguishes raw Shift-minus and equals");
    // Key comparison is independent of the active keyboard layout and hardware.
    REQUIRE(![TSBinding(@"-",cmd|shift) isEqual:TSBinding(@"=",cmd)]);
    REQUIRE(![TSBinding(@"=",cmd|shift) isEqual:TSBinding(@"+",cmd|shift)]);
    REQUIRE([TSBinding(@"G",cmd) isEqual:TSBinding(@"g",cmd|shift)]);
    REQUIRE([[TSShortcutStore displayKey:@"-" modifiers:cmd|shift] isEqual:@"⇧⌘-"]);
    menu=MainMenu();
    NSMenuItem *left=Item(@"TSShortcut.left",@"G",cmd), *right=Item(@"TSShortcut.right",@"g",cmd|shift);
    [menu addItem:left]; [menu addItem:right];
    store=[[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)[ShortcutMemoryDefaults new]];
    // Restoring a default must not create a collision, even with another default.
    TSShortcutCommand *lc=Command(store,left.identifier), *rc=Command(store,right.identifier);
    lc.defaultKey=@"G"; lc.defaultModifiers=cmd; rc.defaultKey=@"g"; rc.defaultModifiers=cmd|shift;
    right.keyEquivalentModifierMask=cmd|shift; right.keyEquivalent=@"g";
    REQUIRE(![store setKey:@"z" modifiers:cmd forCommand:lc]);
    REQUIRE([store restoreCommand:lc] != nil);
    REQUIRE([left.keyEquivalent isEqual:@"z"]);
    // A new custom collision must still prevent individual restoration.
    [store setKey:@"z" modifiers:cmd forCommand:lc];
    [menu removeItem:right];
    NSMenuItem *custom=Item(nil,@"G",cmd); [menu addItem:custom];
    REQUIRE([store restoreCommand:lc] != nil);
    puts("PASS: JIS comparison, distinct raw display, baseline overlap restoration and custom conflict rejection");
    REQUIRE(![TSShortcutStore isAllowedKey:@"a" modifiers:0]);
    REQUIRE([TSShortcutStore isAllowedKey:@"\uf704" modifiers:0]);
    REQUIRE(![TSShortcutStore isAllowedKey:@"ab" modifiers:cmd]);
    puts("PASS: Shift punctuation, shifted letters, function keys and invalid input");

    TSShortcutRecorder *recorder=[TSShortcutRecorder new];
    __block int recorded=0, accepted=0, cancelled=0;
    recorder.record=^(NSEvent *event){recorded++;}; recorder.accept=^{accepted++;}; recorder.cancel=^{cancelled++;};
    REQUIRE([recorder performKeyEquivalent:Event(@"x",cmd)] && recorded==1);
    REQUIRE([recorder performKeyEquivalent:Event(@"\r",0)] && accepted==1 && recorded==1);
    REQUIRE([recorder performKeyEquivalent:Event(@"\033",0)] && cancelled==1 && recorded==1);
    REQUIRE([recorder performKeyEquivalent:Event(@"\t",0)] && recorded==1);
    REQUIRE([recorder performKeyEquivalent:Event(@"\031",shift)] && recorded==1);
    REQUIRE(recorder.accessibilityLabel.length && [recorder.accessibilityRole isEqual:NSAccessibilityTextFieldRole]);
    puts("PASS: capture consumes commands, Return accepts, Escape cancels, accessibility metadata");
    TSKeyboardShortcuts *controller = [[TSKeyboardShortcuts alloc] initWithWindow:nil];
    controller.captureDisplay = [NSTextField labelWithString:@""];
    controller.captureError = [NSTextField labelWithString:@""];
    controller.applyButton = [NSButton new];
    [controller recordShortcutEvent:Event(@"q",cmd)];
    REQUIRE(controller.applyButton.enabled && [controller.capturedKey isEqual:@"q"]);
    NSString *validDisplay = controller.captureDisplay.stringValue;
    [controller recordShortcutEvent:Event(@"a",0)];
    REQUIRE(!controller.applyButton.enabled && !controller.capturedKey);
    REQUIRE(![controller.captureDisplay.stringValue isEqual:validDisplay] && controller.captureError.stringValue.length);
    puts("PASS: invalid input clears the previous valid capture and disables Apply");
    menu=MainMenu(); NSMenuItem *latinFind=Item(@"TSShortcut.performFindPanelAction:.1",@"f",cmd);
    latinFind.action=@selector(performFindPanelAction:); latinFind.tag=1; [menu addItem:latinFind];
    NSMenuItem *latinNext=Item(@"TSShortcut.performFindPanelAction:.2",@"g",cmd);
    latinNext.action=@selector(performFindPanelAction:); latinNext.tag=2; [menu addItem:latinNext];
    NSMenuItem *other=Item(@"TSShortcut.other",@"o",cmd); [menu addItem:other];
    store=[[TSShortcutStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)[ShortcutMemoryDefaults new]];
    for (NSString *nonLatin in @[@"а",@"φ",@"כ"]) {
        NSEvent *event=LayoutEvent(@"f",nonLatin,kVK_ANSI_F,cmd);
        REQUIRE([TSKeyboardShortcuts event:event matchesAction:@selector(performFindPanelAction:) tag:1]);
        [controller recordShortcutEvent:event];
        REQUIRE([controller.capturedKey isEqual:@"f"]);
        REQUIRE([store setKey:controller.capturedKey modifiers:controller.capturedModifiers forCommand:Command(store,other.identifier)] != nil);
    }
    REQUIRE([TSKeyboardShortcuts event:LayoutEvent(@"g",@"п",kVK_ANSI_G,cmd) matchesAction:@selector(performFindPanelAction:) tag:2]);
    for (NSArray *entry in @[@[@"f",@"u",@(kVK_ANSI_F),@1], @[@"g",@"i",@(kVK_ANSI_G),@2]]) {
        NSEvent *event=LayoutEvent(entry[0],entry[1],[entry[2] unsignedShortValue],cmd);
        REQUIRE([TSKeyboardShortcuts event:event matchesAction:@selector(performFindPanelAction:) tag:[entry[3] integerValue]]);
        [controller recordShortcutEvent:event];
        REQUIRE([controller.capturedKey isEqual:entry[0]] && controller.capturedModifiers==cmd);
        REQUIRE([store setKey:controller.capturedKey modifiers:controller.capturedModifiers forCommand:Command(store,other.identifier)] != nil);
    }
    [controller recordShortcutEvent:LayoutEvent(@"F",@"",kVK_ANSI_F,cmd|shift)];
    REQUIRE([controller.capturedKey isEqual:@"f"] && controller.capturedModifiers==(cmd|shift));
    [controller recordShortcutEvent:LayoutEvent(@"F",@"f",kVK_ANSI_F,cmd|NSEventModifierFlagCapsLock)];
    REQUIRE([controller.capturedKey isEqual:@"f"] && controller.capturedModifiers==cmd);
    REQUIRE([TSKeyboardShortcuts event:LayoutEvent(@"F",@"f",kVK_ANSI_F,cmd|NSEventModifierFlagCapsLock) matchesAction:@selector(performFindPanelAction:) tag:1]);
    puts("PASS: Dvorak–QWERTY Command, empty unmodified characters and Caps Lock");
    [controller recordShortcutEvent:LayoutEvent(@"F",@"φ",kVK_ANSI_F,cmd)];
    REQUIRE([controller.capturedKey isEqual:@"f"] && controller.capturedModifiers==cmd);
    NSEvent *swedishColon = LayoutEvent(@".",@":",kVK_ANSI_Period,cmd|shift);
    REQUIRE([TSShortcutCharacterForEvent(swedishColon) isEqual:@":"]);
    [controller recordShortcutEvent:swedishColon];
    NSDictionary *expectedColon = TSBinding(@":",cmd);
    REQUIRE([controller.capturedKey isEqual:expectedColon[@"key"]]);
    REQUIRE(controller.capturedModifiers==[expectedColon[@"modifiers"] unsignedIntegerValue]);
    REQUIRE(![controller.capturedKey isEqual:@"."]);
    REQUIRE([TSShortcutCharacterForEvent(LayoutEvent(@"/",@"?",kVK_ANSI_Minus,cmd|shift)) isEqual:@"?"]);
    REQUIRE([TSShortcutCharacterForEvent(LayoutEvent(@",",@";",kVK_ANSI_Comma,cmd|shift)) isEqual:@";"]);
    [controller recordShortcutEvent:LayoutEvent(@"[",@"[",kVK_ANSI_LeftBracket,cmd|shift)];
    NSDictionary *expectedBracket = TSRecordedBinding(LayoutEvent(@"[",@"[",kVK_ANSI_LeftBracket,cmd|shift), [LayoutEvent(@"[",@"[",kVK_ANSI_LeftBracket,cmd|shift) charactersByApplyingModifiers:0]);
    REQUIRE([TSRecordedBinding(LayoutEvent(@"[",@"[",kVK_ANSI_LeftBracket,cmd|shift), @"[") isEqual:TSBinding(@"[",cmd|shift)]);
    REQUIRE([controller.capturedKey isEqual:expectedBracket[@"key"]]);
    REQUIRE(controller.capturedModifiers==[expectedBracket[@"modifiers"] unsignedIntegerValue]);
    for (NSString *symbol in @[@"{",@"}",@"?",@":",@"+"]) {
        NSDictionary *binding=TSRecordedBinding(LayoutEvent(symbol,symbol,kVK_ANSI_LeftBracket,cmd|shift),@"[");
        REQUIRE([binding isEqual:TSBinding(symbol,cmd)]);
        NSMenu *collisionMenu=[NSMenu new];
        NSMenuItem *existing=Item(@"TSShortcut.existing",symbol,cmd);
        [collisionMenu addItem:existing];
        TSShortcutStore *collisionStore=[[TSShortcutStore alloc] initWithMenu:collisionMenu defaults:(id)[ShortcutMemoryDefaults new]];
        REQUIRE([collisionStore conflictForKey:binding[@"key"] modifiers:[binding[@"modifiers"] unsignedIntegerValue] except:nil restoring:nil]);
    }
    puts("PASS: Command letters normalize case and shifted punctuation keeps the normal keyboard layer");
    REQUIRE([TSShortcutCharacterForEvent(LayoutEvent(@"=",@"",kVK_ANSI_Equal,cmd)) isEqual:@"="]);
    puts("PASS: Command punctuation is retained when the normal keyboard layer is empty");

    NSEvent *optionG=LayoutEvent(@"©",@"g",kVK_ANSI_G,cmd|NSEventModifierFlagOption);
    REQUIRE([TSShortcutCharacterForEvent(optionG) isEqual:@"g"]);
    [controller recordShortcutEvent:optionG];
    REQUIRE([controller.capturedKey isEqual:@"g"] && controller.capturedModifiers==(cmd|NSEventModifierFlagOption));
    REQUIRE(![TSKeyboardShortcuts event:optionG matchesAction:@selector(performFindPanelAction:) tag:2]);
    TISInputSourceRef asciiSource=TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    CFDataRef asciiData=TISGetInputSourceProperty(asciiSource,kTISPropertyUnicodeKeyLayoutData);
    NSString *asciiG=TSTranslateKey(asciiData,kVK_ANSI_G,NO,LMGetKbdType());
    REQUIRE([TSShortcutCharacterForEvent(LayoutEvent(@"©",@"п",kVK_ANSI_G,cmd|NSEventModifierFlagOption)) isEqual:asciiG]);
    REQUIRE([TSShortcutCharacterForEvent(LayoutEvent(@"\007",@"п",kVK_ANSI_G,cmd|NSEventModifierFlagControl)) isEqual:asciiG]);
    CFRelease(asciiSource);
    [controller recordShortcutEvent:LayoutEvent(@"F",@"А",kVK_ANSI_F,cmd|shift)];
    REQUIRE([controller.capturedKey isEqual:@"f"] && controller.capturedModifiers==(cmd|shift));
    MainMenu();
    REQUIRE([TSKeyboardShortcuts event:Event(@"f",cmd) matchesAction:@selector(performFindPanelAction:) tag:1]);
    REQUIRE([TSKeyboardShortcuts event:LayoutEvent(@"g",@"п",kVK_ANSI_G,cmd) matchesAction:@selector(performFindPanelAction:) tag:2]);
    REQUIRE(![TSKeyboardShortcuts event:Event(@"f",cmd|shift) matchesAction:@selector(performFindPanelAction:) tag:1]);
    puts("PASS: non-Latin PDF search and capture, conflict detection, Option character preservation, absent-menu fallback");
} return 0; }
