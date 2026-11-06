#import <Cocoa/Cocoa.h>

static NSUserDefaults *defaults;
#define SUD defaults
static NSString *TetexBinPath = @"TetexBinPath", *GSBinPath = @"GSBinPath";
static NSDictionary *results;
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
- (NSModalResponse)runModal { shown = self; return NSAlertSecondButtonReturn; }
@end
@interface TestWindow : NSWindow @end
@implementation TestWindow
- (BOOL)isVisible { return YES; }
@end
@interface PreferencesProbe : NSObject {
@public
    NSWindow *_prefsWindow;
    NSTextField *_tetexBinPathField, *_gsBinPathField;
    NSUndoManager *_undoManager;
}
@property NSUInteger enginePathSearchGeneration;
@property (weak) NSButton *enginePathSearchButton;
@end
@implementation PreferencesProbe
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
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSString *suite = [@"org.texshop.tests.discovery." stringByAppendingString:NSUUID.UUID.UUIDString];
    defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults setObject:@"/old/tex" forKey:TetexBinPath];
    [defaults setObject:@"/old/gs" forKey:GSBinPath];
    results = @{@"TeX":@[candidate(@"/new/tex",@"TeX Live 2026"),candidate(@"/old/tex",@"TeX Live 2025")],
                @"Ghostscript":@[candidate(@"/new/gs",@"10.10.0"),candidate(@"/old/gs",@"10.9.0")]};
    PreferencesProbe *p = [PreferencesProbe new];
    p->_prefsWindow = [[TestWindow alloc] initWithContentRect:NSMakeRect(0,0,800,800) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    p->_tetexBinPathField = [NSTextField new]; p->_tetexBinPathField.stringValue = @"/old/tex";
    p->_gsBinPathField = [NSTextField new]; p->_gsBinPathField.stringValue = @"/old/gs";
    p->_undoManager = [NSUndoManager new]; p->_undoManager.groupsByEvent = NO;
    [p->_undoManager beginUndoGrouping];
    NSButton *button = [NSButton new];
    [p discoverEnginePaths:button]; spin();
    check(shown != nil && button.enabled, @"asynchronous results presented");
    check(matrices().count == 2 && matrices()[0].selectedRow == 0 && matrices()[1].selectedRow == 0, @"newest preselected for both lists");
    check(matrices()[0].numberOfRows == 2 && matrices()[1].numberOfRows == 2, @"all alternatives selectable");
    [matrices()[0] selectCellAtRow:1 column:0];
    finish(NSAlertFirstButtonReturn);
    check([[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"] && [[defaults stringForKey:GSBinPath] isEqual:@"/new/gs"], @"user can choose older TeX with newer Ghostscript");
    check([p->_gsBinPathField.stringValue isEqual:@"/new/gs"], @"fields reflect chosen paths");
    [p->_undoManager endUndoGrouping]; [p->_undoManager undo];
    check([[defaults stringForKey:GSBinPath] isEqual:@"/old/gs"], @"Settings Cancel undo restores prior paths");
    p->_gsBinPathField.stringValue = @"/old/gs";
    [p discoverEnginePaths:button]; spin(); finish(NSAlertSecondButtonReturn);
    check([[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"], @"dialog Cancel leaves settings unchanged");
    [p discoverEnginePaths:button]; spin();
    p->_tetexBinPathField.stringValue = @"/edited/tex";
    finish(NSAlertFirstButtonReturn);
    check([[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"], @"pending field edit is never overwritten");
    p->_tetexBinPathField.stringValue = @"/old/tex";
    shown = nil; [p discoverEnginePaths:button]; [p cancelEnginePathDiscovery]; spin();
    check(shown == nil && button.enabled, @"closing Settings discards pending discovery");
    [p discoverInitialEnginePaths]; spin();
    check(shown != nil && [[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"], @"initial setup Cancel is non-destructive");
    [p discoverEnginePaths:button]; spin(); validPaths = NO; finish(NSAlertFirstButtonReturn);
    check([[defaults stringForKey:TetexBinPath] isEqual:@"/old/tex"], @"removed installation not applied");
    validPaths = YES;
    results = @{@"TeX":@[],@"Ghostscript":@[]};
    [p discoverEnginePaths:button]; spin();
    check(matrices().count == 0 && shown.buttons.count == 1, @"nothing found gives informational dialog");
    finish(NSAlertFirstButtonReturn);
    [defaults removePersistentDomainForName:suite];
    NSLog(@"PASS: candidate selection, Cancel/undo, stale results, initial setup, removed and missing tools");
} return 0; }
