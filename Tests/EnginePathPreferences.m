#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSPreferenceProfile.h"

#import "MemoryDefaults.h"
#include "EngineProfileSheet.h"
@interface MemoryDefaults : TSMemoryDefaults @end
@implementation MemoryDefaults @end
static MemoryDefaults *defaults;
static NSModalResponse modalResponse = NSAlertSecondButtonReturn;
static NSUInteger modalCount;
// The alerts of the paths, and the engine profile windows, in the order shown.
static NSMutableArray *modals;
#define SUD defaults
static NSString *TetexBinPath = @"TetexBinPath", *GSBinPath = @"GSBinPath";
static NSDictionary *results;
static NSDictionary *applied;
static BOOL validPaths = YES;
static void check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } }
static void spin(void) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.2];
    while (until.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
@interface TSEnginePathDiscovery : NSObject @end
@implementation TSEnginePathDiscovery
+ (NSArray *)systemSearchPaths { return @[]; }
+ (NSDictionary *)candidatesForPaths:(NSArray *)p currentTeX:(NSString *)t currentGhostscript:(NSString *)g { return results; }
+ (BOOL)directory:(NSString *)path containsPrograms:(NSArray *)programs { return validPaths; }
@end

@interface TestAlert : NSAlert
@property (copy) void (^completion)(NSModalResponse);
@end
static TestAlert *shown;
@implementation TestAlert
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler {
    self.completion = handler; shown = self;
}
- (NSModalResponse)runModal { shown = self; modalCount++; [modals addObject:self]; return modalResponse; }
@end
// The engine profile step is a window of its own: shown as a sheet or modally, it answers as the alerts do here.
static TSEngineProfileSheet *shownSheet;
static void (^sheetCompletion)(NSModalResponse);
static NSModalResponse SheetResponse(NSModalResponse alertResponse) { return alertResponse == NSAlertFirstButtonReturn ? NSModalResponseOK : NSModalResponseCancel; }
@implementation TSEngineProfileSheet (Test)
- (NSModalResponse)testRunModal { shownSheet = self; shown = nil; modalCount++; [modals addObject:self]; return SheetResponse(modalResponse); }
- (void)testBeginSheetForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler { shownSheet = self; shown = nil; sheetCompletion = handler; }
@end
@interface TestWindow : NSWindow
@property BOOL testVisible;
@property NSUInteger frontCount;
@end
@implementation TestWindow
- (BOOL)isVisible { return self.testVisible; }
- (void)makeKeyAndOrderFront:(id)sender { self.frontCount++; self.testVisible = YES; }
@end
@interface PreferencesProbe : NSObject {
@public
    NSWindow *_prefsWindow;
    NSTextField *_tetexBinPathField, *_gsBinPathField;

}
@property BOOL initialEnginePathSearchPending;
@property NSUInteger enginePathSearchGeneration;
@property (weak) NSButton *enginePathSearchButton;
@end
@implementation PreferencesProbe
- (BOOL)finishPreferenceEditing:(BOOL)showError { return YES; }
// The first-launch choice is written as one group of values.
- (void)applyEngineProfileValues:(NSDictionary *)values { applied = values; [values enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) { [defaults setObject:value forKey:key]; }]; }
#define NSAlert TestAlert
#include "PreferencesMethods.h"
#undef NSAlert
@end

static NSArray<NSMatrix *> *matrices(void) {
    NSMutableArray *array = [NSMutableArray array];
    for (NSView *v in shown.accessoryView.subviews)
        if ([v isKindOfClass:NSScrollView.class]) [array addObject:((NSScrollView *)v).documentView];
    return array;
}
static NSDictionary *candidate(NSString *path, NSString *version) { return @{@"path":path,@"version":version}; }
static void finish(NSModalResponse response) {
    if (shown == nil && sheetCompletion != nil) {
        void (^completion)(NSModalResponse) = sheetCompletion;
        sheetCompletion = nil;
        completion(SheetResponse(response));
        return;
    }
    void (^completion)(NSModalResponse) = shown.completion;
    shown.completion = nil;
    completion(response);
}
static NSView *FindIn(NSView *root, NSString *identifier) {
    if ([root.identifier isEqual:identifier]) return root;
    for (NSView *view in root.subviews) { NSView *found = FindIn(view, identifier); if (found) return found; }
    return nil;
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    method_exchangeImplementations(class_getInstanceMethod(TSEngineProfileSheet.class, @selector(runModal)),
                                   class_getInstanceMethod(TSEngineProfileSheet.class, @selector(testRunModal)));
    method_exchangeImplementations(class_getInstanceMethod(TSEngineProfileSheet.class, @selector(beginSheetForWindow:completionHandler:)),
                                   class_getInstanceMethod(TSEngineProfileSheet.class, @selector(testBeginSheetForWindow:completionHandler:)));
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    defaults = [MemoryDefaults new];
    [defaults setObject:@"/old/tex" forKey:TetexBinPath];
    [defaults setObject:@"/old/gs" forKey:GSBinPath];
    results = @{@"TeX":@[candidate(@"/new/tex",@"TeX Live 2026"),candidate(@"/old/tex",@"TeX Live 2025"),candidate(@"/unknown/tex",@"")],
                @"Ghostscript":@[candidate(@"/new/gs",@"10.10.0"),candidate(@"/old/gs",@"10.9.0"),candidate(@"/unknown/gs",@"")]};
    PreferencesProbe *p = [PreferencesProbe new];
    p->_prefsWindow = [[TestWindow alloc] initWithContentRect:NSMakeRect(0,0,800,800) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    ((TestWindow *)p->_prefsWindow).testVisible = YES;
    p->_tetexBinPathField = [NSTextField new]; p->_tetexBinPathField.stringValue = @"/old/tex";
    p->_gsBinPathField = [NSTextField new]; p->_gsBinPathField.stringValue = @"/old/gs";


    NSButton *button = [NSButton new];
    modals = [NSMutableArray array];
    BOOL (^hasPopup)(NSAlert *) = ^BOOL(NSAlert *alert) {
        for (NSView *v in alert.accessoryView.subviews) if ([v isKindOfClass:NSPopUpButton.class]) return YES;
        return NO;
    };
    [p discoverEnginePaths:button]; spin();
    check(shown.buttons.count == 2 && [shown.buttons[0].title isEqual:@"OK"] && [shown.buttons[1].title isEqual:@"Cancel"], @"candidate dialog offers OK and Cancel");
    check([shown.messageText isEqual:@"Detect Paths"] && shown.informativeText.length == 0 && !hasPopup(shown), @"Detect Paths shows only the installations, without explanation or profile");
    check(shown != nil && button.enabled, @"asynchronous results presented");
    check(matrices().count == 2 && matrices()[0].selectedRow == 0 && matrices()[1].selectedRow == 0, @"newest preselected for both lists");
    check(matrices()[0].numberOfRows == 3 && matrices()[1].numberOfRows == 3, @"all alternatives selectable");
    check([[[matrices()[0] cellAtRow:2 column:0] title] isEqual:@"Version unavailable\n/unknown/tex"] &&
          [[[matrices()[1] cellAtRow:2 column:0] title] isEqual:@"Version unavailable\n/unknown/gs"], @"unknown version displayed explicitly with path in both lists");
    NSSize longest = NSZeroSize;
    for (NSInteger row = 0; row < 3; row++) longest.width = MAX(longest.width, [[matrices()[0] cellAtRow:row column:0] cellSize].width);
    check(NSWidth(matrices()[0].frame) >= longest.width && NSWidth(matrices()[0].frame) <= ceil(longest.width) + 1, @"the list is as wide as its longest installation");
    [matrices()[0] selectCellAtRow:1 column:0];
    finish(NSAlertFirstButtonReturn);
    check([[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"] && [[defaults stringForKey:GSBinPath] isEqual:@"/new/gs"], @"user can choose older TeX with newer Ghostscript");
    check([p->_gsBinPathField.stringValue isEqual:@"/new/gs"], @"fields reflect chosen paths");
    check(applied == nil, @"Detect Paths sets no engine profile");

    check([[defaults stringForKey:GSBinPath] isEqual:@"/new/gs"], @"selected paths save immediately");
    p->_gsBinPathField.stringValue = [defaults stringForKey:GSBinPath];
    [p discoverEnginePaths:button]; spin(); finish(NSAlertSecondButtonReturn);
    check([[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"], @"dialog Cancel leaves settings unchanged");
    [p discoverEnginePaths:button]; spin();
    p->_tetexBinPathField.stringValue = @"/edited/tex";
    finish(NSAlertFirstButtonReturn);
    check([[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"], @"pending field edit is never overwritten");
    p->_tetexBinPathField.stringValue = @"/old/tex";
    shown = nil; [p discoverEnginePaths:button]; [p cancelEnginePathDiscovery]; spin();
    check(shown == nil && button.enabled, @"closing Settings discards pending discovery");
    ((TestWindow *)p->_prefsWindow).testVisible = NO;

    // First launch: the paths, then the engine profile, each with its own Cancel.
    [modals removeAllObjects];
    [p discoverInitialEnginePaths]; spin();
    check(modals.count == 2 && modalCount == 2 && [[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"] && applied == nil, @"initial modal Cancel is non-destructive, in both steps");
    check([modals[0] isKindOfClass:NSAlert.class] && [[modals[0] messageText] isEqual:@"Detect Paths"] && !hasPopup(modals[0]) &&
          [modals[1] isKindOfClass:TSEngineProfileSheet.class] && [[modals[1] window].title isEqual:@"Choose an Engine Profile"], @"first launch: the paths first, then the engine profile");
    TSEngineProfileSheet *profileWindow = modals[1];
    NSPopUpButton *profiles = (NSPopUpButton *)FindIn(profileWindow.window.contentView, @"settings.choose-profile");
    NSSegmentedControl *latexmk = (NSSegmentedControl *)FindIn(profileWindow.window.contentView, @"settings.engine-profile-latexmk");
    NSMutableArray *tags = [NSMutableArray array];
    for (NSMenuItem *item in profiles.itemArray) if (!item.isSeparatorItem) [tags addObject:@(item.tag)];
    check([tags isEqual:@[@1, @2, @3, @4, @5, @7, @6]], [NSString stringWithFormat:@"first launch offers seven profiles, without dvips, the Japanese ones LuaLaTeX, upLaTeX, then pLaTeX: %@", tags]);
    check(profiles == profileWindow.profileMenu && latexmk == profileWindow.latexmkChoice && profiles.selectedTag == TSEngineProfileForLanguages(NSLocale.preferredLanguages) && latexmk.selectedSegment == 0,
          @"the profile for the preferred language is chosen, without latexmk");
    check([profileWindow.okButton.keyEquivalent isEqual:@"\r"] && [profileWindow.cancelButton.keyEquivalent isEqual:@"\e"] && NSMinX(profiles.frame) <= 20, @"the profile window has OK and Cancel, its menu at the left");
    // Another profile and latexmk chosen in the window are what OK applies.
    [profiles selectItemWithTag:TSEngineProfileLuaLaTeX]; [profiles sendAction:profiles.action to:profiles.target];
    latexmk.selectedSegment = 1; [latexmk sendAction:latexmk.action to:latexmk.target];
    check([profileWindow.valuesToApply isEqual:TSEngineProfileValues(TSEngineProfileLuaLaTeX, YES)], @"the window applies the profile and the latexmk form chosen in it");

    modalResponse = NSAlertFirstButtonReturn;
    [modals removeAllObjects];
    [p discoverInitialEnginePaths]; spin();
    check(modals.count == 2 && [[defaults stringForKey:TetexBinPath] isEqual:@"/new/tex"] &&
          [[defaults stringForKey:GSBinPath] isEqual:@"/new/gs"],
          @"initial modal confirmation applies without Settings undo group");
    NSDictionary *chosen = TSEngineProfileValues(TSEngineProfileForLanguages(NSLocale.preferredLanguages), NO);
    for (NSString *key in chosen) check([applied[key] isEqual:chosen[key]], [NSString stringWithFormat:@"initial confirmation applies the chosen profile: %@", key]);
    check(applied.count == chosen.count, @"the profile step writes the profile, nothing else");
    [defaults setObject:@"/old/tex" forKey:TetexBinPath];
    [defaults setObject:@"/old/gs" forKey:GSBinPath];

    shown = nil; applied = nil;
    NSUInteger modalsBefore = modalCount;
    [p discoverInitialEnginePaths];
    NSUInteger generation = p.enginePathSearchGeneration;
    [p showPreferences:nil];
    check(p.initialEnginePathSearchPending && p.enginePathSearchGeneration == generation, @"opening Settings preserves initial discovery");
    spin();
    check(shown.completion != nil && modalCount == modalsBefore, @"initial result becomes sheet when Settings opens");
    shownSheet = nil;
    finish(NSAlertFirstButtonReturn);
    check([p->_tetexBinPathField.stringValue isEqual:@"/new/tex"], @"initial result refreshes open Settings");
    check([shownSheet.window.title isEqual:@"Choose an Engine Profile"] && sheetCompletion != nil && modalCount == modalsBefore, @"the profile step follows as a sheet too");
    finish(NSAlertFirstButtonReturn);
    check(applied[@"DefaultScript"] != nil, @"the profile chosen in the sheet is applied");

    check([[defaults stringForKey:TetexBinPath] isEqual:@"/new/tex"] && [[defaults stringForKey:GSBinPath] isEqual:@"/new/gs"], @"initial result in sheet remains saved");
    [defaults setObject:@"/old/tex" forKey:TetexBinPath];
    p->_tetexBinPathField.stringValue = @"/old/tex";
    p->_gsBinPathField.stringValue = [defaults stringForKey:GSBinPath];
    shown = nil; [p discoverEnginePaths:button];
    generation = p.enginePathSearchGeneration;
    [p showPreferences:nil];
    check(p.enginePathSearchGeneration == generation && !button.enabled, @"reselecting open Settings does not cancel discovery");
    spin(); check(shown != nil, @"discovery survives reselecting Settings");
    finish(NSAlertSecondButtonReturn);
    [p discoverEnginePaths:button]; spin(); validPaths = NO; finish(NSAlertFirstButtonReturn);
    check([[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"], @"removed installation not applied");
    validPaths = YES;
    // Only one of the two found: the other keeps its path, and the dialog says only Not found.
    for (NSString *missing in @[@"Ghostscript", @"TeX"]) {
        NSString *found = [missing isEqual:@"TeX"] ? @"Ghostscript" : @"TeX";
        [defaults setObject:@"/old/tex" forKey:TetexBinPath]; [defaults setObject:@"/old/gs" forKey:GSBinPath];
        p->_tetexBinPathField.stringValue = @"/old/tex"; p->_gsBinPathField.stringValue = @"/old/gs";
        results = @{found:@[candidate([found isEqual:@"TeX"] ? @"/new/tex" : @"/new/gs", @"1")], missing:@[]};
        shown = nil; [p discoverEnginePaths:button]; spin();
        NSMutableArray<NSString *> *labels = [NSMutableArray array];
        NSMutableArray<NSView *> *pending = [NSMutableArray arrayWithObject:shown.accessoryView];
        while (pending.count) {
            NSView *view = pending.lastObject; [pending removeLastObject];
            if ([view isKindOfClass:NSTextField.class]) [labels addObject:((NSTextField *)view).stringValue];
            [pending addObjectsFromArray:view.subviews];
            if ([view isKindOfClass:NSScrollView.class] && ((NSScrollView *)view).documentView) [pending addObject:((NSScrollView *)view).documentView];
        }
        check(matrices().count == 1 && shown.buttons.count == 2, [NSString stringWithFormat:@"%@ only: one list and both buttons", found]);
        check([labels containsObject:@"Not found"] && ![[labels componentsJoinedByString:@"\n"] containsString:@"current setting"], [NSString stringWithFormat:@"missing %@ is shown as Not found only", missing]);
        finish(NSAlertFirstButtonReturn);
        BOOL texFound = [found isEqual:@"TeX"];
        check([[defaults stringForKey:TetexBinPath] isEqual:texFound ? @"/new/tex" : @"/old/tex"] &&
              [[defaults stringForKey:GSBinPath] isEqual:texFound ? @"/old/gs" : @"/new/gs"] &&
              [p->_gsBinPathField.stringValue isEqual:texFound ? @"/old/gs" : @"/new/gs"] &&
              [p->_tetexBinPathField.stringValue isEqual:texFound ? @"/new/tex" : @"/old/tex"],
              [NSString stringWithFormat:@"%@ only: the found path is applied and the missing one is kept", found]);
    }
    [defaults setObject:@"/old/tex" forKey:TetexBinPath]; [defaults setObject:@"/old/gs" forKey:GSBinPath];
    p->_tetexBinPathField.stringValue = @"/old/tex"; p->_gsBinPathField.stringValue = @"/old/gs";
    results = @{@"TeX":@[],@"Ghostscript":@[]};
    [p discoverEnginePaths:button]; spin();
    check(matrices().count == 0 && shown.buttons.count == 1 && [shown.informativeText containsString:@"Install TeX Live or MacTeX"] && [shown.informativeText containsString:@"Detect Paths"], @"nothing found gives informational dialog");
    finish(NSAlertFirstButtonReturn);
    NSLog(@"PASS: candidate selection, minimal width, local Cancel, immediate saving, stale results, two-step initial setup, removed and missing tools, TeX or Ghostscript alone");
} return 0; }
