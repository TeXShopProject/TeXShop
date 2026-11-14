// SPDX-License-Identifier: GPL-2.0-or-later
// The commands of the Advanced Find panel in the Find submenu (TSAdvancedFindMenu), in the shipped MainMenu nibs: the
// items, their order, titles and keys while the find method is the Advanced Find panel, the menu left exactly as it
// was with the other methods and after switching back, no key used twice in the menu bar or by the bundled macros,
// Settings › Keyboard (the shortcut store) listing them and keeping a changed key across a switch, and the commands
// acting on a text view through the menu with the panel never shown. Built by Tests/run-advanced-find-menu.py; no
// window is shown and the defaults stay in memory.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "TSKeyboardShortcuts.m"
#pragma clang diagnostic pop
#include "MacroKeyProduction.inc"
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "AdvancedFindTaskWait.h"
#import "TSAdvancedFindMenu.h"
#import "TSAdvancedFindTextView.h"
#import "TSAdvancedFindHighlights.h"
#import "TSAdvancedFindPanelController.h"
#import "TSMultipleReplaceMenu.h"

static int failures;
static void Check(BOOL ok, NSString *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what.UTF8String);
        failures++;
    }
}

static TSAdvancedFindController *TestShared;
static NSUInteger beeps;
static id SharedForTests(id self, SEL _cmd) { return TestShared; }
static void IgnoreOutlet(id self, SEL cmd, id value, NSString *key) {}

@interface MenuMemoryDefaults : NSObject
@property NSMutableDictionary *values;
@end
@implementation MenuMemoryDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (void)setObject:(id)value forKey:(NSString *)key { self.values[key] = value; }
- (void)removeObjectForKey:(NSString *)key { [self.values removeObjectForKey:key]; }
@end

static void CollectMacros(NSArray *array, NSString *path, NSMutableArray *candidates)
{
    for (NSDictionary *entry in array) {
        NSString *name = [path stringByAppendingFormat:@" › %@", entry[@"name"]];
        if (entry[@"submenu"])
            CollectMacros(entry[@"submenu"], name, candidates);
        else if (![entry[@"name"] isEqual:@"Separator"])
            [candidates addObject:@{@"path": name, @"key": getKeyEquivalentFromString(entry[@"key"]),
                                    @"modifiers": @(getKeyModifierMaskFromString(entry[@"key"]))}];
    }
}

/// Every item of the menu bar, as text: the whole menu, so any change shows.
static NSArray<NSString *> *Snapshot(NSMenu *menu)
{
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    TSVisitMenu(menu, @"", ^(NSMenuItem *item, NSString *path) {
        [lines addObject:[NSString stringWithFormat:@"%@|%@|%ld|%@|%lu|%@|%d", path, item.action ? NSStringFromSelector(item.action) : @"-",
                          (long)item.tag, item.keyEquivalent, (unsigned long)item.keyEquivalentModifierMask, item.identifier ?: @"-", item.separatorItem]];
    });
    return lines;
}

static NSMenu *AppKitFindMenu(NSMenu *menu)
{
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action == @selector(performFindPanelAction:) && item.tag == NSFindPanelActionShowFindPanel)
            return menu;
        NSMenu *found = item.submenu ? AppKitFindMenu(item.submenu) : nil;
        if (found)
            return found;
    }
    return nil;
}

static NSMenuItem *ItemWithIdentifier(NSMenu *menu, NSString *identifier)
{
    __block NSMenuItem *found = nil;
    TSVisitMenu(menu, @"", ^(NSMenuItem *item, NSString *path) {
        if (!found && [item.identifier isEqualToString:identifier])
            found = item;
    });
    return found;
}

static NSString *ID(NSInteger tag) { return [NSString stringWithFormat:@"TSShortcut.performFindPanelAction:.%ld", (long)tag]; }

/// The Find submenu as tokens: the command identifier, or "-" and the identifier for a separator, "▸" for a submenu.
static NSArray<NSString *> *FindTokens(NSMenu *find)
{
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSMenuItem *item in find.itemArray)
        [tokens addObject:item.separatorItem ? [@"-" stringByAppendingString:item.identifier ?: @""]
                          : item.submenu ? @"▸" : item.identifier ?: @"?"];
    return tokens;
}

static TSShortcutCommand *Command(TSShortcutStore *store, NSString *identifier)
{
    for (TSShortcutCommand *command in store.commands)
        if ([command.commandID isEqualToString:identifier])
            return command;
    return nil;
}

static void TestNib(NSString *nibPath, NSString *macrosPath, NSDictionary<NSString *, NSString *> *titles)
{
    NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:nibPath] bundle:nil];
    NSArray *objects;
    if (![nib instantiateWithOwner:NSApp topLevelObjects:&objects] || !NSApp.mainMenu) {
        Check(NO, @"the nib makes the main menu");
        return;
    }
    NSMenu *main = NSApp.mainMenu, *find = AppKitFindMenu(main);
    Check(find != nil, @"AppKit's Find submenu");
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [TSMultipleReplaceMenu installInMainMenu:main directory:directory];
    NSArray<NSString *> *before = Snapshot(main);
    BOOL findAndReplace = [find indexOfItemWithTag:12] >= 0;

    for (NSNumber *method in @[@0, @1, @2]) {
        [TSAdvancedFindMenu updateMainMenu:main findMethod:method.integerValue];
        Check([Snapshot(main) isEqual:before], [NSString stringWithFormat:@"find method %@: the menu is as it was", method]);
    }

    [TSAdvancedFindMenu updateMainMenu:main findMethod:3];
    NSMutableArray *expected = [@[ID(1), @"TSShortcut.performTextFinderAction:.12", ID(2), ID(3), ID(106), ID(9), @"-TSAdvancedFindMenu.separator.find",
                                  ID(7), ID(101), @"TSShortcut.centerSelectionInVisibleArea:.0", @"-", ID(5), ID(6), ID(4),
                                  @"TSShortcut.showMultipleReplace:.0", @"▸", @"-TSAdvancedFindMenu.separator.highlight", ID(102), ID(103)] mutableCopy];
    if (!findAndReplace)
        [expected removeObject:@"TSShortcut.performTextFinderAction:.12"];
    NSArray *tokens = FindTokens(find);
    Check([tokens isEqual:expected], [NSString stringWithFormat:@"the order of the Find submenu: %@", [tokens componentsJoinedByString:@" "]]);
    NSArray<NSString *> *withCommands = Snapshot(main);

    struct { NSInteger tag; NSString *key; NSEventModifierFlags flags; NSString *name; } commands[] = {
        {106, @"F", NSEventModifierFlagCommand | NSEventModifierFlagShift, @"FindAll"},
        {9, @"", 0, @"SelectAll"},
        {101, @"E", NSEventModifierFlagCommand | NSEventModifierFlagShift, @"SetReplaceString"},
        {5, @"", 0, @"Replace"},
        {6, @"g", NSEventModifierFlagCommand | NSEventModifierFlagOption, @"ReplaceAndFind"},
        {4, @"", 0, @"ReplaceAll"},
        {102, @"H", NSEventModifierFlagCommand | NSEventModifierFlagShift, @"Highlight"},
        {103, @"H", NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagControl, @"Unhighlight"},
    };
    for (size_t i = 0; i < sizeof(commands) / sizeof(commands[0]); i++) {
        NSMenuItem *item = ItemWithIdentifier(main, ID(commands[i].tag));
        Check(item.action == @selector(performFindPanelAction:) && item.tag == commands[i].tag && item.target == nil,
              [NSString stringWithFormat:@"%@ goes to the first responder with its tag", commands[i].name]);
        Check([item.keyEquivalent isEqualToString:commands[i].key] && (item.keyEquivalentModifierMask & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl)) == (commands[i].key.length ? commands[i].flags : 0),
              [NSString stringWithFormat:@"%@ has its key", commands[i].name]);
        Check([item.title isEqualToString:titles[commands[i].name]],
              [NSString stringWithFormat:@"%@ is titled %@, not %@", commands[i].name, titles[commands[i].name], item.title]);
    }

    // No key twice in the menu bar, and none of the bundled macros' keys
    NSMutableDictionary<NSString *, NSNumber *> *count = [NSMutableDictionary dictionary];
    for (NSDictionary *binding in [TSShortcutStore menuBindings:main]) {
        TSShortcutBinding *normalized = [TSShortcutStore normalizedKey:binding[@"key"] modifiers:[binding[@"modifiers"] unsignedIntegerValue]];
        NSString *text = [NSString stringWithFormat:@"%@ %lu", normalized.key, (unsigned long)normalized.modifiers];
        count[text] = @(count[text].integerValue + 1);
    }
    for (NSString *text in count)
        Check(count[text].integerValue == 1, [NSString stringWithFormat:@"the key %@ is used once in the menu bar", text]);
    TSShortcutStore *store = [[TSShortcutStore alloc] initWithMenu:main defaults:(id)[MenuMemoryDefaults new]];
    NSDictionary *macros = [NSDictionary dictionaryWithContentsOfFile:macrosPath];
    NSMutableArray *candidates = [NSMutableArray array];
    CollectMacros(macros[@"submenu"], @"Macros", candidates);
    Check(candidates.count > 100 && [store conflictsForMacroShortcuts:candidates].count == 0, @"no bundled macro uses a key of the menu");
    Check(store.unavailableCommands.count == 0, @"no command lost its key");

    // Settings › Keyboard lists the commands with their keys
    for (size_t i = 0; i < sizeof(commands) / sizeof(commands[0]); i++) {
        TSShortcutCommand *command = Command(store, ID(commands[i].tag));
        Check(command && [command.defaultKey isEqualToString:commands[i].key] && [command.path hasSuffix:titles[commands[i].name]] && !command.item.hidden,
              [NSString stringWithFormat:@"Settings › Keyboard lists %@ with its key", commands[i].name]);
    }
    Check([store.settingsSearchCommandNames containsObject:Command(store, ID(106)).path], @"and the settings search finds them");

    // Idempotent; switching away restores the menu exactly; a changed key survives the switch
    [TSAdvancedFindMenu updateMainMenu:main findMethod:3];
    Check([Snapshot(main) isEqual:withCommands], @"updating again changes nothing");
    MenuMemoryDefaults *saved = [MenuMemoryDefaults new];
    store = [[TSShortcutStore alloc] initWithMenu:main defaults:(id)saved];
    const NSEventModifierFlags other = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption;
    NSString *conflict = [store setKey:@"k" modifiers:other forCommand:Command(store, ID(106))];
    Check(conflict == nil, [NSString stringWithFormat:@"Find All takes another key (%@)", conflict]);
    [TSAdvancedFindMenu updateMainMenu:main findMethod:1];
    [store refreshMenu];
    Check([Snapshot(main) isEqual:before] && !Command(store, ID(106)), @"back to the find bar: the menu is as it was, without the commands");
    [TSAdvancedFindMenu updateMainMenu:main findMethod:3];
    [store refreshMenu];
    NSMenuItem *findAll = ItemWithIdentifier(main, ID(106));
    Check([findAll.keyEquivalent isEqualToString:@"k"] && findAll.keyEquivalentModifierMask == other,
          @"the changed key of Find All is back with the Advanced Find panel");
    Check([store restoreCommand:Command(store, ID(106))] == nil && [findAll.keyEquivalent isEqualToString:@"F"], @"and its default can be restored");
    [TSAdvancedFindMenu updateMainMenu:main findMethod:0];
    Check([Snapshot(main) isEqual:before], @"back to the Apple panel: the menu is as it was");
    NSApp.mainMenu = nil;
}

/// OgreKit's Find submenu (FindMethod 2 at launch) never gets the commands.
static void TestOgreKitMenu(void)
{
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *editItem = [main addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"], *find = [[NSMenu alloc] initWithTitle:@"Find"];
    editItem.submenu = edit;
    [edit addItemWithTitle:@"Find" action:NULL keyEquivalent:@""].submenu = find;
    [find addItemWithTitle:@"Find…" action:NSSelectorFromString(@"showFindPanel:") keyEquivalent:@"f"];
    [find addItemWithTitle:@"Find All" action:NSSelectorFromString(@"findAll:") keyEquivalent:@"F"].tag = 4;
    NSArray *before = Snapshot(main);
    [TSAdvancedFindMenu updateMainMenu:main findMethod:3];
    Check([Snapshot(main) isEqual:before], @"OgreKit's Find submenu is left alone");
}

static TSAdvancedFindTextView *MakeView(NSString *text)
{
    TSAdvancedFindTextView *view = [[TSAdvancedFindTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
    view.string = text;
    view.allowsUndo = YES;
    return view;
}

/// The commands act through the menu on a text view, with the panel never shown, and are gray where they may not.
static void TestBehavior(void)
{
    [NSUserDefaults.standardUserDefaults setInteger:3 forKey:@"FindMethod"];
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *editItem = [main addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"Edit"], *find = [[NSMenu alloc] initWithTitle:@"Find"];
    editItem.submenu = edit;
    [edit addItemWithTitle:@"Find" action:NULL keyEquivalent:@""].submenu = find;
    for (NSNumber *tag in @[@1, @2, @3, @7]) {
        NSMenuItem *base = [find addItemWithTitle:tag.stringValue action:@selector(performFindPanelAction:) keyEquivalent:@""];
        base.tag = tag.integerValue;
        base.identifier = ID(tag.integerValue);
    }
    [TSAdvancedFindMenu updateMainMenu:main findMethod:3];
    NSMenuItem *(^item)(NSInteger) = ^NSMenuItem *(NSInteger tag) { return ItemWithIdentifier(main, ID(tag)); };

    TSAdvancedFindTextView *view = MakeView(@"cat cat dog");
    TSAdvancedFindController.testTargetTextView = view;
    Check(view.findController == TestShared, @"with the Advanced Find panel, the text view goes to the shared controller");
    __block NSUInteger listed = 0;
    void (^showResults)(TSAdvancedFindResults *, NSTextView *) = TestShared.findAllHandler;
    Check(showResults != nil, @"the panel's controller, made by the routing, lists Find All without being shown");
    TestShared.findAllHandler = ^(TSAdvancedFindResults *results, NSTextView *textView) { listed = results.items.count; };
    TestShared.settings.findString = @"cat";
    TestShared.settings.replaceString = @"cow";
    TestShared.settings.options = TSRegexFindDefaultOptions;
    TestShared.settings.inSelection = NO;

    view.selectedRange = NSMakeRange(0, 3);
    for (NSNumber *tag in @[@106, @9, @101, @5, @6, @4, @102, @103])
        Check([view validateMenuItem:item(tag.integerValue)], [NSString stringWithFormat:@"command %@ is enabled in an editable text with a selection", tag]);
    view.selectedRange = NSMakeRange(0, 0);
    Check(![view validateMenuItem:item(101)], @"Use Selection for Replace is gray without a selection");

    [view performFindPanelAction:item(106)];
    TSTestWaitForTask(TestShared, 60);
    Check(listed == 2, @"Find All lists both matches");
    [view performFindPanelAction:item(9)];
    Check(view.selectedRanges.count == 2 && NSEqualRanges(view.selectedRanges[1].rangeValue, NSMakeRange(4, 3)), @"Select All Matches selects both");
    [view performFindPanelAction:item(102)];
    Check([TSAdvancedFindHighlights existingHighlightsForTextStorage:(NSTextStorage *_Nonnull)view.textStorage].ranges.count == 2, @"Highlight All marks both");
    [view performFindPanelAction:item(103)];
    Check([TSAdvancedFindHighlights existingHighlightsForTextStorage:(NSTextStorage *_Nonnull)view.textStorage].ranges.count == 0, @"Remove Highlights removes them");
    view.selectedRange = NSMakeRange(8, 3);
    [view performFindPanelAction:item(101)];
    Check([TestShared.settings.replaceString isEqualToString:@"dog"], @"Use Selection for Replace takes the selection as the replacement");
    TestShared.settings.replaceString = @"cow";
    view.selectedRange = NSMakeRange(0, 3);
    [view performFindPanelAction:item(5)];
    Check([view.string isEqualToString:@"cow cat dog"], @"Replace replaces the selected match");
    view.selectedRange = NSMakeRange(0, 0);
    [view performFindPanelAction:item(2)];
    [view performFindPanelAction:item(6)];
    Check([view.string isEqualToString:@"cow cow dog"], @"Replace and Find replaces the found match");
    view.string = @"cat cat dog";
    [view performFindPanelAction:item(4)];
    TSTestWaitForTask(TestShared, 60);
    Check([view.string isEqualToString:@"cow cow dog"], @"Replace All replaces both");

    TSAdvancedFindTextView *console = MakeView(@"cat cat");
    console.refusesReplacing = YES;
    TSAdvancedFindController.testTargetTextView = console;
    for (NSNumber *tag in @[@5, @6, @4])
        Check(![console validateMenuItem:item(tag.integerValue)], [NSString stringWithFormat:@"command %@ is gray where replacing is refused", tag]);
    for (NSNumber *tag in @[@106, @9, @102, @103])
        Check([console validateMenuItem:item(tag.integerValue)], [NSString stringWithFormat:@"command %@ still finds where replacing is refused", tag]);
    TSAdvancedFindController.testTargetTextView = nil;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:[TSMemoryDefaults new] findPasteboard:[NSPasteboard pasteboardWithUniqueName]];
        TestShared = [[TSAdvancedFindController alloc] initWithSettings:settings];
        TestShared.beepHandler = ^{ beeps++; };
        TestShared.sheetDelay = 600;
        method_setImplementation(class_getClassMethod(TSAdvancedFindController.class, @selector(sharedController)), (IMP)SharedForTests);
        NSString *mode = argc > 1 ? @(argv[1]) : @"";
        if ([mode isEqualToString:@"nib"] && argc > 4) {
            for (NSString *name in @[@"HelpDocuments", @"TSAppDelegate", @"TSDocumentController", @"TSMacroEditor", @"TSMacroMenuController", @"TSMovie",
                                     @"TSPreferences", @"TSSparkleController", @"TSStationery", @"TextFinder"]) {
                Class c = objc_allocateClassPair(NSObject.class, name.UTF8String, 0);
                class_addMethod(c, @selector(setValue:forUndefinedKey:), (IMP)IgnoreOutlet, "v@:@@");
                objc_registerClassPair(c);
            }
            NSDictionary *titles = [NSJSONSerialization JSONObjectWithData:[@(argv[4]) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
            TestNib(@(argv[2]), @(argv[3]), titles);
        } else if ([mode isEqualToString:@"behavior"]) {
            TestOgreKitMenu();
            TestBehavior();
        } else {
            Check(NO, @"usage: probe nib <nib> <macros> <titles json> | behavior");
        }
        if (failures)
            return 1;
        puts([mode isEqualToString:@"nib"] ? "PASS" : "PASS: the commands act through the menu, gray where replacing is refused; OgreKit's menu is left alone");
    }
    return 0;
}
