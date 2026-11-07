// Production methods with memory-only defaults, temporary files and invisible UI doubles.
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "TSKeyboardShortcuts.m"
#import "TSMacroEditor.h"
#import "TSMacroMenuController.h"
#import "TSMacroOutlineController.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while (0)
#import <objc/runtime.h>
static NSEvent *(^eventMonitor)(NSEvent *);
static NSWindow *modalTestWindow;
static NSModalResponse modalAnswer;
static BOOL monitorRemoved;
static id AddMonitor(id self, SEL cmd, NSEventMask mask, NSEvent *(^handler)(NSEvent *)) { eventMonitor=[handler copy]; return @"test"; }
static void RemoveMonitor(id self, SEL cmd, id token) { monitorRemoved=YES; eventMonitor=nil; }
static NSWindow *ModalWindow(id self, SEL cmd) { return modalTestWindow; }
static void StopModal(id self, SEL cmd, NSModalResponse answer) { modalAnswer=answer; }
@interface InvisibleAlert : NSAlert
@end
@implementation InvisibleAlert
- (NSModalResponse)runModal {
    modalTestWindow=self.window;
    NSEvent *other=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"x" charactersIgnoringModifiers:@"x" isARepeat:NO keyCode:7];
    REQUIRE(eventMonitor(other)==other);
    NSEvent *escape=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"\e" charactersIgnoringModifiers:@"\e" isARepeat:NO keyCode:53];
    REQUIRE(!eventMonitor(escape) && modalAnswer==NSAlertFirstButtonReturn);
    return modalAnswer;
}
@end
static void CheckEscape(void) {
    Method methods[]={class_getClassMethod(NSEvent.class,@selector(addLocalMonitorForEventsMatchingMask:handler:)),class_getClassMethod(NSEvent.class,@selector(removeMonitor:)),class_getInstanceMethod(NSApplication.class,@selector(modalWindow)),class_getInstanceMethod(NSApplication.class,@selector(stopModalWithCode:))};
    IMP replacements[]={(IMP)AddMonitor,(IMP)RemoveMonitor,(IMP)ModalWindow,(IMP)StopModal}, originals[4];
    for(int i=0;i<4;i++) originals[i]=method_setImplementation(methods[i],replacements[i]);
    InvisibleAlert *alert=[InvisibleAlert new]; [alert addButtonWithTitle:@"Return to Editing"]; [alert addButtonWithTitle:@"Save Anyway"]; [alert addButtonWithTitle:@"Remove Keys"];
    REQUIRE([alert.buttons[0].keyEquivalent isEqual:@"\r"]);
    REQUIRE(TSRunShortcutAlert(alert)==NSAlertFirstButtonReturn && monitorRemoved);
    for(int i=0;i<4;i++) method_setImplementation(methods[i],originals[i]);
    modalTestWindow=nil;
    puts("PASS: Return is safe; Escape returns to editing and removes the temporary event monitor");
}
@interface MemoryDefaults : NSObject
@property NSMutableDictionary *values;
@end
@implementation MemoryDefaults
- (instancetype)init { if ((self=[super init])) _values=[NSMutableDictionary dictionary]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (void)setObject:(id)value forKey:(NSString *)key { self.values[key]=value; }
- (void)removeObjectForKey:(NSString *)key { [self.values removeObjectForKey:key]; }
@end
static int reloads, writeAlerts;

@implementation TSMacroMenuController
+ (id)sharedInstance { static id instance; if (!instance) instance=[self new]; return instance; }
- (void)reloadMacros:(id)sender { reloads++; [self setupMainMacroMenu]; }
- (void)doMacro:(id)sender {}

- (void)doNothing:(id)sender {}
#include "MacroMenuProduction.inc"
@end
#include "MacroKeyProduction.inc"
static NSString *MacrosPath;
static int g_macroType;
enum { TexEngine, LatexEngine, BibtexEngine, IndexEngine, MetapostEngine };
static NSInteger TestWriteAlert(NSString *title, NSString *format, ...) { writeAlerts++; return 0; }
static void (^sheetCompletion)(NSModalResponse);
static int sheetStarts, sheetDismissals;
@interface InvisibleSheetWindow : NSWindow @end
@implementation InvisibleSheetWindow
- (void)orderOut:(id)sender { sheetDismissals++; }
@end
static void CaptureSheet(id self, SEL cmd, NSWindow *window, void (^handler)(NSModalResponse)) { sheetStarts++; sheetCompletion=[handler copy]; }

@interface TestSheetAlert : NSAlert
@end
@implementation TestSheetAlert
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler { CaptureSheet(self,_cmd,window,handler); }
- (NSWindow *)window { static NSWindow *w; if (!w) w=[InvisibleSheetWindow new]; return w; }
@end
#define NSAlert TestSheetAlert
#define NSRunAlertPanel TestWriteAlert
@implementation TSMacroEditor
#include "MacroEditorProduction.inc"
@end
#undef NSRunAlertPanel
#undef NSAlert
@interface TestOutline : NSObject
@property TSMacroTreeNode *rootOfTree;
@property NSArray *selection;
@end
@implementation TestOutline
- (void)expandItem:(id)item {}
- (void)reloadData {}
- (NSInteger)numberOfRows { return 0; }
- (NSInteger)numberOfColumns { return 2; }
- (void)reloadDataForRowIndexes:(NSIndexSet *)rows columnIndexes:(NSIndexSet *)columns {}
- (void)selectItems:(NSArray *)items byExtendingSelection:(BOOL)extend { self.selection=items; }
@end
@interface TestWindow : NSObject
@property int closes;
@property BOOL rejectCommit;
@property NSWindow *attachedSheet;
@end
@implementation TestWindow
- (BOOL)makeFirstResponder:(id)item { return !self.rejectCommit; }
- (void)close { self.closes++; }

@end
@interface TestEditor : TSMacroEditor
@property NSModalResponse answer;
@property NSString *details;
@property int prompts;
@property TestWindow *testWindow;
@property TestOutline *testOutline;
@property BOOL failWrite;
- (void)rememberOriginalShortcutKeys;
- (BOOL)validateMacroShortcutsBeforeSaving;
- (void)updatePendingShortcutStatus;
- (BOOL)windowShouldClose:(id)sender;
@end
@implementation TestEditor
- (instancetype)init { if ((self=[super init])) {
    _testWindow=[TestWindow new]; window=_testWindow;
    _testOutline=[TestOutline new]; outlineController=_testOutline; outlineView=_testOutline;
    dataTouched=YES;
} return self; }
- (NSModalResponse)showShortcutConflicts:(NSString *)details { self.prompts++; self.details=details; return self.answer; }
- (void)reflectChangesInEditor:(BOOL)force {} // No live field editor in these save-path tests.
- (BOOL)saveNodes:(id)nodes toFile:(NSString *)path { return [super saveNodes:nodes toFile:self.failWrite ? [path stringByAppendingPathComponent:@"missing/file"] : path]; }
@end
@interface TestShortcuts : TSShortcutPaneController
@property TSShortcutCommand *selection;
@property BOOL consent;
@property int confirmations;
@property NSString *error;
@property int commandReloads;
@property BOOL pretendLoaded;
@end
@implementation TestShortcuts
- (TSShortcutCommand *)selectedCommand { return self.selection; }
- (void)confirmMacrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags completion:(void (^)(BOOL))completion {
    if (![self.store macrosUsingKey:key modifiers:flags].count) { completion(YES); return; }
    self.confirmations++; completion(self.consent);
}
- (void)showError:(NSString *)error { self.error=error; }
- (NSWindow *)window { static NSWindow *inert; if (!inert) inert=[NSWindow new]; return inert; }
- (BOOL)isViewLoaded { return self.pretendLoaded; }
- (void)reloadCommands { self.commandReloads++; }
@end
static NSDictionary *Candidate(NSString *path, NSString *key, NSUInteger flags) { return @{@"path":path,@"key":key,@"modifiers":@(flags)}; }
static NSMenuItem *Command(NSString *name, NSString *key) {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:name action:@selector(description) keyEquivalent:key];
    item.allowsAutomaticKeyEquivalentLocalization=NO;
    item.identifier=[@"TSShortcut." stringByAppendingString:name]; item.keyEquivalentModifierMask=NSEventModifierFlagCommand; return item;
}
static NSDictionary *Macro(NSString *name,NSString *key) { return @{@"name":name,@"content":@"KEEP",@"key":key}; }
static void Drain(void) {
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:.04];
    while([until timeIntervalSinceNow]>0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:until];
}
static NSMutableArray *assignments;
@interface TrackedItem : NSMenuItem @end
@implementation TrackedItem
- (void)setKeyEquivalent:(NSString *)key {
    if(assignments) [assignments addObject:@[self.title,key]];
    [super setKeyEquivalent:key];
}
@end
static void CheckAssignmentOrder(void) {
    NSMenu *menu=[NSMenu new];
    for(NSString *key in @[@"f",@"g"]) {
        NSMenuItem *item=[[TrackedItem alloc] initWithTitle:key action:@selector(description) keyEquivalent:key];
        item.identifier=[@"TSShortcut." stringByAppendingString:key]; [menu addItem:item];
    }
    TSShortcutStore *store=[[TSShortcutStore alloc] initWithMenu:menu defaults:(id)[MemoryDefaults new]];
    assignments=[NSMutableArray new]; [store applySavedOverrides];
    REQUIRE(assignments.count==4 && ![assignments[0][1] length] && ![assignments[1][1] length]);
    REQUIRE([assignments[2][1] length] && [assignments[3][1] length]); assignments=nil;
}
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    CheckEscape(); CheckAssignmentOrder();
    NSEvent *punctuation=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand|NSEventModifierFlagShift timestamp:0 windowNumber:0 context:nil characters:@"{" charactersIgnoringModifiers:@"{" isARepeat:NO keyCode:33];
    REQUIRE([TSRecordedBinding(punctuation,@"[") isEqual:TSBinding(@"{",NSEventModifierFlagCommand)]);
    REQUIRE([TSShortcutStore event:punctuation matchesItem:Command(@"Find punctuation",@"{")]);
    NSMenuItem *legacy=Command(@"Legacy Find",@"{"); legacy.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift;
    REQUIRE([TSShortcutStore event:punctuation matchesItem:legacy]);
    NSUInteger control=NSEventModifierFlagControl, shifted=NSEventModifierFlagShift;
    NSEvent *cyrillic=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:control|shifted timestamp:0 windowNumber:0 context:nil characters:@"Ж" charactersIgnoringModifiers:@"Ж" isARepeat:NO keyCode:41];
    REQUIRE([TSRecordedBinding(cyrillic,@"ж") isEqual:TSBinding(@"Ж",control|shifted)]);
    REQUIRE([TSRecordedBinding(punctuation,@"") isEqual:TSBinding(@"{",NSEventModifierFlagCommand)]);
    REQUIRE([TSRecordedBinding(punctuation,@"ab") isEqual:TSBinding(@"{",NSEventModifierFlagCommand)]);
    REQUIRE([TSEventBindings(punctuation,@"[") containsObject:TSBinding(@"{",NSEventModifierFlagCommand|shifted)]);
    MacrosPath=[NSString stringWithUTF8String:argv[1]]; g_macroType=LatexEngine;
    NSUInteger cmd=NSEventModifierFlagCommand, shift=NSEventModifierFlagShift;
    NSMenu *menu=[NSMenu new]; NSApp.mainMenu=menu;
    NSMenuItem *find=Command(@"Find",@"f"), *zoom=Command(@"Zoom",@"="); [menu addItem:find]; [menu addItem:zoom];
    NSMenuItem *macrosEntry=[[NSMenuItem alloc] initWithTitle:@"Macros" action:nil keyEquivalent:@""];
    NSMenu *macroMenu=[NSMenu new]; macrosEntry.submenu=macroMenu; [menu addItem:macrosEntry];
    [macroMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Editor" action:nil keyEquivalent:@""]];
    TSMacroMenuController *macros=[TSMacroMenuController sharedInstance]; [macros setValue:macroMenu forKey:@"macroMenu"];
    MemoryDefaults *defaults=[MemoryDefaults new];
    TSShortcutStore *store=[[TSShortcutStore alloc] initWithMenu:menu defaults:(id)defaults];
    TSShortcutCommand *findCommand=store.commands.firstObject;
    TSKeyboardShortcuts *coordinator=[TSKeyboardShortcuts sharedController]; coordinator.store=store;
    [[NSNotificationCenter defaultCenter] addObserverForName:TSRebuildMacrosNotification object:nil queue:nil usingBlock:^(NSNotification *n){ [macros setupMainMacroMenu]; }];
    REQUIRE(![store setKey:@"k" modifiers:cmd forCommand:findCommand]);
    macros.macroDict=@{@"submenu":@[Macro(@"Freed",@"F"),Macro(@"Blocked",@"K"),Macro(@"Root",@"-+ShiftKey"),Macro(@"Duplicate",@"F")]};
    [coordinator refreshMenuAndMacros];
    REQUIRE(macroMenu.numberOfItems==6);
    REQUIRE([find.keyEquivalent isEqual:@"k"] && store.unavailableCommands.count==0);
    REQUIRE([macroMenu.itemArray[2].keyEquivalent isEqual:@"f"]);
    REQUIRE(macroMenu.itemArray[3].keyEquivalent.length==0 && [macroMenu.itemArray[3].toolTip containsString:@"Find"]);
    REQUIRE([macroMenu.itemArray[4].keyEquivalent isEqual:@"-"] && macroMenu.itemArray[4].keyEquivalentModifierMask==(cmd|shift));
    REQUIRE(macroMenu.itemArray[5].keyEquivalent.length==0);
    REQUIRE([store conflictsForMacroShortcuts:@[Candidate(@"freed",@"f",cmd)]].count==0);
    REQUIRE([store macrosUsingKey:@"f" modifiers:cmd].count==1 && [store macrosAffectedByRestoringAll].count==1);
    TestShortcuts *ui=[[TestShortcuts alloc] initWithShortcuts:coordinator]; ui.store=store; ui.selection=findCommand;
    [ui restoreShortcut:nil]; REQUIRE(ui.confirmations==1 && [find.keyEquivalent isEqual:@"k"]);
    ui.consent=YES; [ui restoreShortcut:nil]; REQUIRE(ui.confirmations==2 && [find.keyEquivalent isEqual:@"f"] && macroMenu.itemArray[2].keyEquivalent.length==0);
    REQUIRE(![store setKey:@"k" modifiers:cmd forCommand:findCommand]); [coordinator refreshMenuAndMacros];
    ui.capturedKey=@"f";ui.capturedModifiers=cmd;ui.editingCommand=findCommand;ui.applyButton=[NSButton new];ui.applyButton.enabled=YES;ui.consent=NO;
    [ui applyCapturedShortcut:nil]; REQUIRE(ui.confirmations==3 && [find.keyEquivalent isEqual:@"k"]);
    ui.consent=YES;[ui applyCapturedShortcut:nil];REQUIRE(ui.confirmations==4 && [find.keyEquivalent isEqual:@"f"]);
    macros.macroDict=@{@"submenu":@[Macro(@"Engine switch",@"F"),Macro(@"Still free",@"Z")]};[coordinator refreshMenuAndMacros];
    REQUIRE([find.keyEquivalent isEqual:@"f"] && !macroMenu.itemArray[2].keyEquivalent.length && store.unavailableCommands.count==0);
    // Exercise the UI actions themselves, including the restore-all sheet callback.
    [ui removeShortcut:nil];
    REQUIRE(!find.keyEquivalent.length && [macroMenu.itemArray[2].keyEquivalent isEqual:@"f"]);
    Method sheetMethod=class_getInstanceMethod(NSAlert.class,@selector(beginSheetModalForWindow:completionHandler:));
    IMP originalSheet=method_setImplementation(sheetMethod,(IMP)CaptureSheet);
    [ui restoreAll:nil]; REQUIRE(sheetCompletion); sheetCompletion(NSAlertFirstButtonReturn);
    method_setImplementation(sheetMethod,originalSheet);
    REQUIRE([find.keyEquivalent isEqual:@"f"] && !macroMenu.itemArray[2].keyEquivalent.length && [macroMenu.itemArray[3].keyEquivalent isEqual:@"z"]);
    // An engine-only rebuild must reapply saved menu keys and refresh an open settings list.
    find.keyEquivalent=@"x"; [macros setupMainMacroMenu]; REQUIRE([find.keyEquivalent isEqual:@"f"]);
    ui.pretendLoaded=YES; [coordinator beginMenuRebuild]; [coordinator endMenuRebuild]; REQUIRE(ui.commandReloads>0); ui.pretendLoaded=NO;
    NSDictionary *validMacros=macros.macroDict;
    macros.macroDict=@{@"submenu":@[@42]};
    BOOL caught=NO; @try { [macros setupMainMacroMenu]; } @catch(NSException *e) { caught=YES; }
    REQUIRE(caught && !coordinator.rebuildingMacros);
    macros.macroDict=validMacros; [macros setupMainMacroMenu];
    NSEvent *upperEvent=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:cmd|shift timestamp:0 windowNumber:0 context:nil characters:@"T" charactersIgnoringModifiers:@"T" isARepeat:NO keyCode:17];
    REQUIRE([TSShortcutStore event:upperEvent matchesItem:Command(@"Upper",@"T")]);
    NSMenuItem *importItem=[[NSMenuItem alloc] initWithTitle:@"Import" action:@selector(readDictionaryToMacroEditor:) keyEquivalent:@""];
    [macroMenu insertItem:importItem atIndex:1]; [coordinator refreshMenuAndMacros]; REQUIRE([macroMenu.itemArray containsObject:importItem]);
    [macroMenu removeItem:importItem];
    NSMenuItem *upper=Command(@"Uppercase",@"T"); [menu addItem:upper];
    macros.macroDict=@{@"submenu":@[Macro(@"Letter collision",@"T+ShiftKey"),Macro(@"First",@"Y"),@{@"name":@"Nested",@"submenu":@[Macro(@"Later",@"Y")]}]};
    [coordinator refreshMenuAndMacros];
    REQUIRE(!macroMenu.itemArray[2].keyEquivalent.length && [macroMenu.itemArray[2].toolTip containsString:@"Uppercase"]);
    REQUIRE(!macroMenu.itemArray[4].submenu.itemArray[0].keyEquivalent.length && [macroMenu.itemArray[4].submenu.itemArray[0].toolTip containsString:@"First"]);
    [menu removeItem:upper];
    puts("PASS: effective menu precedence, freed defaults, takeover confirmation/cancel, restore, engine changes and inactive tooltip");
    NSMenu *services=[NSMenu new];NSApp.servicesMenu=services;NSMenuItem *serviceParent=[[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""];serviceParent.submenu=services;[menu addItem:serviceParent];
    [services addItem:Command(@"Service",@"z")];
    REQUIRE([store conflictsForMacroShortcuts:@[Candidate(@"z",@"z",cmd)]].count==0);
    NSMenuItem *dynamic=[[NSMenuItem alloc] initWithTitle:@"Show All Tabs" action:NSSelectorFromString(@"toggleTabOverview:") keyEquivalent:@"\\"];
    dynamic.keyEquivalentModifierMask=cmd|shift;[menu addItem:dynamic];[coordinator refreshMenuAndMacros];
    REQUIRE(![dynamic.identifier hasPrefix:@"TSShortcut."] && [store conflictsForMacroShortcuts:@[Candidate(@"abs",@"\\",cmd|shift)]].count==1);
    [menu removeItem:dynamic];[coordinator refreshMenuAndMacros];
    REQUIRE([store conflictsForMacroShortcuts:@[Candidate(@"abs",@"\\",cmd|shift)]].count==0);
    REQUIRE([store conflictsForMacroShortcuts:@[Candidate(@"one",@"T",cmd),Candidate(@"two",@"t",cmd|shift)]].count==1);
    puts("PASS: services excluded; dynamically present menu keys counted without making them editable; ASCII Shift comparison");

    // Observe real AppKit notifications; visual validation changes must not rebuild.
    __block int rebuilds=0;
    id counter=[[NSNotificationCenter defaultCenter] addObserverForName:TSRebuildMacrosNotification object:nil queue:nil usingBlock:^(NSNotification *n){ rebuilds++; }];
    [coordinator observeMenuChanges]; Drain(); int before=rebuilds;
    for(int i=0;i<10;i++) { find.enabled=!find.enabled; find.state=i%2; find.title=[NSString stringWithFormat:@"Title %d",i]; find.toolTip=@"changed"; [menu update]; Drain(); }
    REQUIRE(rebuilds==before);
    NSMenuItem *added=Command(@"Dynamic observed",@"v"); [menu addItem:added]; Drain(); REQUIRE(rebuilds==before+1);
    [menu removeItem:added]; Drain(); REQUIRE(rebuilds==before+2);
    NSMenuItem *replacement=Command(@"Dynamic observed",@"w"); [menu addItem:replacement]; Drain(); REQUIRE(rebuilds==before+3);
    for (NSString *guard in @[@"applyingMenus",@"rebuildingMacros"]) {
        [coordinator setValue:@YES forKey:guard];
        [menu removeItem:replacement];
        REQUIRE(!coordinator.menuRefreshPending);
        [menu addItem:replacement];
        [coordinator setValue:@NO forKey:guard];
    }
    Drain(); REQUIRE(rebuilds==before+3);
    [menu removeItem:replacement]; Drain(); REQUIRE(rebuilds==before+4);
    // Reinsert the same object with only its key or modifier changed.
    [menu addItem:replacement]; Drain(); before=rebuilds;
    [menu removeItem:replacement]; replacement.keyEquivalent=@"u"; [menu addItem:replacement];
    Drain(); REQUIRE(rebuilds==before+1); before=rebuilds;
    [menu removeItem:replacement]; replacement.keyEquivalentModifierMask=cmd|shift; [menu addItem:replacement];
    Drain(); REQUIRE(rebuilds==before+1);
    [menu removeItem:replacement]; Drain(); before=rebuilds;
    // AppKit can hide an anonymous item's key when an installed macro already uses it.
    NSDictionary *priorMacros=macros.macroDict;
    macros.macroDict=@{@"submenu":@[Macro(@"Late collision",@"C+ControlKey")]};
    [coordinator refreshMenuAndMacros]; Drain(); before=rebuilds;
    REQUIRE([macroMenu.itemArray[2].keyEquivalent isEqual:@"c"]);
    NSMenuItem *late=[[NSMenuItem alloc] initWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"c"];
    late.keyEquivalentModifierMask=cmd|control;
    [menu addItem:late]; Drain();
    REQUIRE(rebuilds==before+1 && [late.keyEquivalent isEqual:@"c"]);
    REQUIRE(!macroMenu.itemArray[2].keyEquivalent.length && [macroMenu.itemArray[2].toolTip containsString:@"Enter Full Screen"]);
    REQUIRE([store conflictsForMacroShortcuts:@[Candidate(@"Late collision",@"c",cmd|control)]].count==1);
    [menu removeItem:late]; Drain();
    REQUIRE([macroMenu.itemArray[2].keyEquivalent isEqual:@"c"]);
    macros.macroDict=priorMacros; [coordinator refreshMenuAndMacros]; Drain(); before=rebuilds;
    NSMenuItem *recent=[[NSMenuItem alloc] initWithTitle:@"Recent document" action:@selector(description) keyEquivalent:@""];
    // A burst of structural edits coalesces into one refresh when it leaves a different menu.
    for(int i=0;i<5;i++) { [menu addItem:recent]; [menu removeItem:recent]; }
    [menu addItem:recent]; Drain(); REQUIRE(rebuilds==before+1);
    [menu removeItem:recent]; Drain(); REQUIRE(rebuilds==before+2);
    [[NSNotificationCenter defaultCenter] removeObserver:counter];
    [[NSNotificationCenter defaultCenter] removeObserver:coordinator name:NSMenuDidAddItemNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:coordinator name:NSMenuDidRemoveItemNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:coordinator name:NSMenuDidChangeItemNotification object:nil];
    find.title=@"Find";
    puts("PASS: actual notifications ignore validation/title/state, track add/remove/replacement and reject reentry");
    TSMacroTreeNode *root=[TSMacroTreeNode submenuNodeWithName:@"ROOT"],*group=[TSMacroTreeNode submenuNodeWithName:@"Nested"];
    TSMacroTreeNode *old=[TSMacroTreeNode nodeWithName:@"Old collision" content:@"KEEP OLD" key:@"F"];
    TSMacroTreeNode *a=[TSMacroTreeNode nodeWithName:@"New collision" content:@"KEEP NEW" key:@"Y"];
    TSMacroTreeNode *b=[TSMacroTreeNode nodeWithName:@"Free" content:@"KEEP FREE" key:@"Z"];
    [root addChild:group];[group addChildren:@[old,a,b]];
    TestEditor *editor=[TestEditor new];editor.testOutline.rootOfTree=root;[editor rememberOriginalShortcutKeys];
    [editor refreshShortcutConflicts];REQUIRE([[editor shortcutConflictForNode:old] containsString:@"Find"]);
    NSTextField *field=[NSTextField new];field.stringValue=@"f";
    [editor setValue:field forKey:@"keyField"];
    for(NSString *name in @[@"shiftCheckBox",@"optionCheckBox",@"controlCheckBox"]) [editor setValue:[NSButton new] forKey:name];
    editor.shortcutStatus=[NSTextField wrappingLabelWithString:@""];editor.previousItem=a;
    [editor updatePendingShortcutStatus];
    REQUIRE([a.key isEqual:@"Y"] && [editor.shortcutStatus.stringValue containsString:@"Find"] && [editor.shortcutStatus.stringValue containsString:@"⌘F"]);
    field.stringValue=@"x";[editor updatePendingShortcutStatus];REQUIRE(editor.shortcutStatus.stringValue.length==0 && [a.key isEqual:@"Y"]);
    editor.previousItem=nil;
    NSString *file=[MacrosPath stringByAppendingPathComponent:@"Macros_Latex.plist"];
    [editor savePressed:nil];REQUIRE(editor.prompts==0 && editor.testWindow.closes==1 && reloads==1);
    a.key=@"F";editor.answer=NSAlertFirstButtonReturn;[editor savePressed:nil];
    REQUIRE(editor.prompts==1 && editor.testWindow.closes==1 && reloads==1 && [a.key isEqual:@"F"]);
    REQUIRE(editor.testOutline.selection.firstObject==a && ![editor.details containsString:@"Old collision"]);
    REQUIRE([editor.details componentsSeparatedByString:@"Find"].count==2); // one opponent, with its key
    editor.testWindow.rejectCommit=YES;[editor savePressed:nil];REQUIRE(editor.prompts==1);editor.testWindow.rejectCommit=NO;
    editor.answer=NSAlertSecondButtonReturn;[editor savePressed:nil];
    REQUIRE(editor.prompts==2 && editor.testWindow.closes==2 && reloads==2 && [a.key isEqual:@"F"]);
    NSDictionary *saved=[NSDictionary dictionaryWithContentsOfFile:file];REQUIRE([saved[@"submenu"][0][@"submenu"][1][@"key"] isEqual:@"F"]);
    editor.answer=NSAlertThirdButtonReturn;[editor savePressed:nil];
    REQUIRE(editor.prompts==3 && editor.testWindow.closes==3 && reloads==3 && [a.key isEqual:@""] && [old.key isEqual:@"F"]);
    REQUIRE([a.content isEqual:@"KEEP NEW"] && [b.key isEqual:@"Z"]);
    TSMacroTreeNode *imported=[TSMacroTreeNode nodeWithName:@"Imported" content:@"KEEP IMPORT" key:@"Z"];[group addChild:imported];
    editor.answer=NSAlertFirstButtonReturn;[editor savePressed:nil];REQUIRE(editor.prompts==4 && [editor.details containsString:@"Imported"] && [editor.details containsString:@"Free"]);
    imported.key=@""; editor.failWrite=YES;[editor savePressed:nil];REQUIRE(writeAlerts==1 && reloads==3 && editor.testWindow.closes==3);
    editor.failWrite=NO; a.key=@"F"; editor.answer=NSAlertFirstButtonReturn;
    int prompts=editor.prompts;
    int oldStarts=sheetStarts; editor.testWindow.attachedSheet=[InvisibleSheetWindow new];
    REQUIRE(![editor windowShouldClose:editor.testWindow] && sheetStarts==oldStarts);
    editor.testWindow.attachedSheet=nil;
    REQUIRE(![editor windowShouldClose:editor.testWindow] && sheetCompletion && sheetStarts==oldStarts+1);
    sheetCompletion(NSAlertFirstButtonReturn); REQUIRE(editor.prompts==prompts && sheetDismissals==1);
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:1];
    while(editor.prompts==prompts && [deadline timeIntervalSinceNow]>0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    REQUIRE(editor.prompts==prompts+1 && editor.testWindow.closes==3 && reloads==3);
    puts("PASS: close-sheet save defers conflict review until after sheet dismissal");
    TSMacroTreeNode *first=[TSMacroTreeNode nodeWithName:@"Changed first" content:@"KEEP" key:@"X"], *later=[TSMacroTreeNode nodeWithName:@"Existing later" content:@"KEEP" key:@"Z"];
    TSMacroTreeNode *secondRoot=[TSMacroTreeNode submenuNodeWithName:@"ROOT"];[secondRoot addChildren:@[first,later]];
    TestEditor *second=[TestEditor new];second.testOutline.rootOfTree=secondRoot;[second rememberOriginalShortcutKeys];first.key=@"Z";
    second.answer=NSAlertFirstButtonReturn;[second savePressed:nil];REQUIRE(second.prompts==1 && second.testWindow.closes==0 && [second.details containsString:@"Existing later"] && [second.details containsString:@"appears later"]);
    second.answer=NSAlertThirdButtonReturn;[second savePressed:nil];REQUIRE(!first.key.length && [later.key isEqual:@"Z"] && second.testWindow.closes==1);
    puts("PASS: changing an earlier macro warns before making a later macro inactive");
    puts("PASS: existing conflicts save without prompting; new/imported keys have three choices; cancellation and write errors preserve content");
} return 0; }
