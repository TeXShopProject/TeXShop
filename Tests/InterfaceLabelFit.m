// Load every window, panel and view of the given compiled nibs offscreen, apply
// the layout and the text the application gives it after loading, and check it
// with the checks of LayoutChecks.inc. Resizable windows are checked again at
// their smallest size. Nothing is ordered on screen and AppKit defaults stay in
// memory.
// Usage: InterfaceLabelFit [--images DIR [--focus-rings]] <label>|<compiled nib>|<Localizable.strings> ...
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#include "LayoutChecks.inc"
#include "ProductionLayout.inc"
#import "TSMacroEditor.h"
#import "TSListBottomBar.h"
#import "TSMacroShortcutField.h"
#import "TSMacroMenuController.h"
#import "TSShortcutInternal.h"

// The macro editor adds its status line, list buttons and placeholder guide and
// lays out its buttons after loading; MacroEditorLayout.inc is that code, copied
// from its source.
@implementation TSMacroEditor
#include "MacroEditorLayout.inc"
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
// What the shortcut field asks of the rest of the editor, which these checks leave out.
- (void)updatePendingShortcutStatus {}
- (void)reflectChangesInEditor:(BOOL)force {}
@end
@interface TSMacroOutlineController : NSObject @end
@implementation TSMacroOutlineController
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item { return 0; }
@end
@interface TSMacroOutlineView : NSOutlineView @end
@implementation TSMacroOutlineView @end

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    InstallLocalizedStrings();
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--images") && i + 1 < argc) { imagesDirectory = @(argv[++i]); continue; }
        if (!strcmp(argv[i], "--focus-rings")) { imagesWithFocusRings = YES; continue; }
        [entries addObject:@(argv[i])];
    }
    NSUInteger roots = 0;
    for (int pass = 0; pass < 2; pass++) { automaticBezel = pass == 1;
    for (NSString *entry in entries) {
        NSArray<NSString *> *parts = [entry componentsSeparatedByString:@"|"];
        NSString *label = parts[0], *path = parts[1], *strings = parts.count > 2 ? parts[2] : nil;
        UseLocalizedStrings(strings);
        // The label is <language>.lproj/<interface>[/<compiled variant>].
        NSString *name = label.pathComponents.count > 1 ? label.pathComponents[1] : label.lastPathComponent;
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSArray *objects = nil;
        BOOL macroEditor = [name isEqual:@"MacroEditor.nib"];
        id owner = macroEditor ? [TSMacroEditor new] : ProductionOwner(name);
        // A compiled main menu becomes the application's menu; the guides that name
        // menu commands then fall back to the strings of this nib's language.
        NSApp.mainMenu = nil;
        if (![[[NSNib alloc] initWithNibData:data bundle:nil] instantiateWithOwner:owner topLevelObjects:&objects]) { printf("ERROR %s cannot load\n", label.UTF8String); return 2; }
        NSApp.mainMenu = nil;
        if (macroEditor) {
            TSMacroEditor *editor = owner;
            [editor installShortcutStatus]; [editor installListControls]; [editor installShortcutField]; [editor installPlaceholderNote]; [editor layoutDialogButtons];
        } else ApplyProductionLayout(name, owner, objects);
        for (id o in objects) {
            if ([o isKindOfClass:NSWindow.class]) {
                NSWindow *w = o;
                NSString *where = [NSString stringWithFormat:@"%@ [%@]", label, w.title.length ? w.title : @"untitled window"];
                CheckWindow(w, where); roots++;
            } else if ([o isKindOfClass:NSView.class]) {
                CheckRoot(o, [NSString stringWithFormat:@"%@ [view]", label]); roots++;
            }
        }
    }}
    if (problems) { printf("FAIL: %d problems\n", problems); return 1; }
    printf("PASS: text, controls and pop-up choices are whole, inside their windows and apart, input fields have room for their focus rings, and wrapping fields have even margins, in %lu windows and views of %lu localized interfaces (also with the automatic toolbar bezel)\n", (unsigned long)roots / 2, (unsigned long)entries.count);
} return 0; }
