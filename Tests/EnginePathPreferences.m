#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSPreferenceProfile.h"

@interface MemoryDefaults : NSObject
@property NSMutableDictionary *values;
- (NSString *)stringForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;
@end
@implementation MemoryDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (NSString *)stringForKey:(NSString *)key { return self.values[key]; }
- (void)setObject:(id)value forKey:(NSString *)key { self.values[key] = value; }
@end
static MemoryDefaults *defaults;
static NSModalResponse modalResponse = NSAlertSecondButtonReturn;
static NSUInteger modalCount;
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
- (NSModalResponse)runModal { shown = self; modalCount++; return modalResponse; }
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
    void (^completion)(NSModalResponse) = shown.completion;
    shown.completion = nil;
    completion(response);
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
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
    [p discoverEnginePaths:button]; spin();
    check(shown.buttons.count == 2 && [shown.buttons[1].title isEqual:@"Cancel"], @"candidate dialog offers Cancel");
    check(shown != nil && button.enabled, @"asynchronous results presented");
    check(matrices().count == 2 && matrices()[0].selectedRow == 0 && matrices()[1].selectedRow == 0, @"newest preselected for both lists");
    check(matrices()[0].numberOfRows == 3 && matrices()[1].numberOfRows == 3, @"all alternatives selectable");
    check([[[matrices()[0] cellAtRow:2 column:0] title] isEqual:@"Version unavailable\n/unknown/tex"] &&
          [[[matrices()[1] cellAtRow:2 column:0] title] isEqual:@"Version unavailable\n/unknown/gs"], @"unknown version displayed explicitly with path in both lists");
    [matrices()[0] selectCellAtRow:1 column:0];
    finish(NSAlertFirstButtonReturn);
    check([[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"] && [[defaults stringForKey:GSBinPath] isEqual:@"/new/gs"], @"user can choose older TeX with newer Ghostscript");
    check([p->_gsBinPathField.stringValue isEqual:@"/new/gs"], @"fields reflect chosen paths");

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
    [p discoverInitialEnginePaths]; spin();
    check(shown != nil && modalCount == 1 && [[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"], @"initial modal Cancel is non-destructive");

    check(applied == nil, @"initial Cancel applies no profile");
    // The first-launch setup: the engine profiles but the one under Other, chosen by language, and latexmk.
    NSPopUpButton *profiles = nil; NSButton *latexmk = nil;
    for (NSView *v in shown.accessoryView.subviews) {
        if ([v.identifier isEqual:@"settings.first-launch-profile"]) profiles = (NSPopUpButton *)v;
        if ([v.identifier isEqual:@"settings.engine-profile-latexmk"]) latexmk = (NSButton *)v;
    }
    NSMutableArray *tags = [NSMutableArray array];
    for (NSMenuItem *item in profiles.itemArray) if (!item.isSeparatorItem) [tags addObject:@(item.tag)];
    check([tags isEqual:@[@1, @2, @3, @4, @5, @6, @7]], [NSString stringWithFormat:@"first launch offers seven profiles, without dvips: %@", tags]);
    check(profiles.selectedTag == TSEngineProfileForLanguages(NSLocale.preferredLanguages) && latexmk.state == NSControlStateValueOff, @"the profile for the preferred language is chosen, without latexmk");
    check([shown.messageText isEqual:@"Set Up Typesetting"] && shown.buttons.count == 2, @"first launch: one setup dialog with OK and Cancel");

    modalResponse = NSAlertFirstButtonReturn;
    [p discoverInitialEnginePaths]; spin();
    check(modalCount == 2 && [[defaults stringForKey:TetexBinPath] isEqual:@"/new/tex"] &&
          [[defaults stringForKey:GSBinPath] isEqual:@"/new/gs"],
          @"initial modal confirmation applies without Settings undo group");
    NSDictionary *chosen = TSEngineProfileValues(TSEngineProfileForLanguages(NSLocale.preferredLanguages), NO);
    for (NSString *key in chosen) check([applied[key] isEqual:chosen[key]], [NSString stringWithFormat:@"initial confirmation applies the chosen profile: %@", key]);
    check(applied.count == chosen.count + 2, @"the profile and the two paths, nothing else");
    [defaults setObject:@"/old/tex" forKey:TetexBinPath];
    [defaults setObject:@"/old/gs" forKey:GSBinPath];

    shown = nil;
    [p discoverInitialEnginePaths];
    NSUInteger generation = p.enginePathSearchGeneration;
    [p showPreferences:nil];
    check(p.initialEnginePathSearchPending && p.enginePathSearchGeneration == generation, @"opening Settings preserves initial discovery");
    spin();
    check(shown.completion != nil && modalCount == 2, @"initial result becomes sheet when Settings opens");
    finish(NSAlertFirstButtonReturn);
    check([p->_tetexBinPathField.stringValue isEqual:@"/new/tex"], @"initial result refreshes open Settings");

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
    check(matrices().count == 0 && shown.buttons.count == 1, @"nothing found gives informational dialog");
    finish(NSAlertFirstButtonReturn);
    NSLog(@"PASS: candidate selection, local Cancel, immediate saving, stale results, initial setup, removed and missing tools, TeX or Ghostscript alone");
} return 0; }
