// Isolated native preference and running-app Dock checks.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "MemoryDefaults.h"
#import "../Sources/TSDockIconController.h"
#import "../Sources/TSDockIcon.h"
#define SUD NSUserDefaults.standardUserDefaults
@interface TSSpellSupport : NSObject
+ (void)preferencesDidChange;
@end
@implementation TSSpellSupport
+ (void)preferencesDidChange {}
@end
@interface TSPreferences : NSObject @end
@implementation TSPreferences
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
@end
@interface TSPreferenceWindow : NSWindow @end
@implementation TSPreferenceWindow @end
@interface DockProbe : NSObject
@property NSSize size;
@property (strong) NSView *contentView;
@property (copy) NSString *badgeLabel;
@property NSUInteger displays;
@end
@implementation DockProbe
- (void)display { self.displays++; }
@end
static NSTabView *Tabs(NSView *view) {
    if ([view isKindOfClass:NSTabView.class]) return (id)view;
    for (NSView *child in view.subviews) { NSTabView *tabs = Tabs(child); if (tabs) return tabs; }
    return nil;
}
static void Require(BOOL condition, NSString *message) { if (!condition) { NSLog(@"FAIL: %@",message); exit(1); } }
@interface PreviewDelegate : NSObject <NSApplicationDelegate>
@property (strong) TSDockIconController *controller;
- (void)accept:(id)sender; - (void)cancel:(id)sender;
@end
@implementation PreviewDelegate
- (void)accept:(id)sender { [NSApp terminate:nil]; }
- (void)cancel:(id)sender { [NSApp terminate:nil]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
@end

static TSMemoryDefaults *memoryDefaults;
static id InMemoryStandardDefaults(id self, SEL cmd) { return memoryDefaults; }
static void PreventOrdering(id self, SEL cmd, NSWindowOrderingMode mode, NSInteger relative) {}
int main(int argc,char **argv) { @autoreleasepool {
    memoryDefaults = [TSMemoryDefaults new];
    for (int i = 1; i + 1 < argc; i++) if ([@(argv[i]) isEqual:@"-AppleLanguages"]) {
        NSString *language = [@(argv[i+1]) stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"()"]];
        [memoryDefaults registerDefaults:@{@"AppleLanguages":@[language]}];
    }
    method_setImplementation(class_getClassMethod(NSUserDefaults.class,@selector(standardUserDefaults)),(IMP)InMemoryStandardDefaults);
    // Check before creating AppKit objects, so a broken isolation fixture cannot write preferences.
    Require([NSUserDefaults standardUserDefaults] == memoryDefaults, @"All standard defaults must remain in memory");
    BOOL snapshot = argc > 2 && [@(argv[2]) isEqualToString:@"--snapshot"];
    BOOL preview = snapshot || (argc > 2 && [@(argv[2]) isEqualToString:@"--preview"]);
    if (!preview) method_setImplementation(class_getInstanceMethod(NSWindow.class,@selector(orderWindow:relativeTo:)),(IMP)PreventOrdering);
    [NSApplication sharedApplication];
    if (!preview) [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSString *domain = NSBundle.mainBundle.bundleIdentifier;
    Require([domain hasPrefix:@"org.texshop.DockLab"], @"Use the isolated test bundle");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSBundle *bundle = NSBundle.mainBundle;
    TSDockIconController *controller = [[TSDockIconController alloc] initWithBundle:bundle defaults:defaults];
    TSPreferences *owner = [TSPreferences new];
    NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:[@(argv[1]) stringByAppendingPathComponent:@"keyedobjects.nib"]] bundle:nil];
    NSArray *objects; Require([nib instantiateWithOwner:owner topLevelObjects:&objects], @"Load actual preferences nib");
    NSWindow *window; NSTabView *tabs;
    for (id object in objects) if ([object isKindOfClass:NSWindow.class]) {
        NSTabView *candidate = Tabs([object contentView]);
        if (candidate.numberOfTabViewItems == 9) { window = object; tabs = candidate; break; }
    }
    Require(tabs != nil, @"Nine main preference tabs");
    [controller installInPreferences:tabs];
    NSTabView *nested = Tabs(tabs.tabViewItems.lastObject.view);
    Require(nested.numberOfTabViewItems == 2, @"No extra preference sub-tab");
    [tabs selectLastTabViewItem:nil]; [nested selectLastTabViewItem:nil];
    NSView *themeView = tabs.tabViewItems[tabs.numberOfTabViewItems - 2].view;
    NSBox *iconGroup;
    for (NSView *view in themeView.subviews) if ([view.identifier isEqual:@"DockIconChoices"]) iconGroup = (id)view;
    Require(iconGroup != nil, @"Direct icon choices on Misc2");
    if (snapshot) {
        BOOL japanese = [[@(argv[1]) stringByDeletingLastPathComponent].lastPathComponent isEqual:@"ja.lproj"];
        Require([iconGroup.title isEqual:japanese ? @"起動中のDockアイコン" : @"Dock Icon While Running"], @"Snapshot title matches requested language");
    }
    for (NSView *view in themeView.subviews)
        if (view != iconGroup) Require(!NSIntersectsRect(iconGroup.frame, view.frame), [NSString stringWithFormat:@"No overlap with existing controls: %@ vs %@", NSStringFromRect(iconGroup.frame), NSStringFromRect(view.frame)]);
    for (NSView *view in iconGroup.contentView.subviews)
        Require(NSContainsRect(iconGroup.contentView.bounds, view.frame), @"Choices fit the group");
    NSArray<NSButton *> *buttons = [controller valueForKey:@"buttons"];
    Require(buttons.count == 5, @"Five choices");
    for (NSString *name in TSDockIconNames()) {
        NSImage *image = TSDockIconImage(bundle,name);
        Require(image != nil, @"Artwork present");
        NSInteger pixels = 0; for (NSImageRep *rep in image.representations) pixels = MAX(pixels,rep.pixelsWide);
        Require(pixels >= 1024, @"High resolution artwork");
    }
    [controller restoreSavedIcon];
    if (!preview) {
        Require(buttons[4].state == NSControlStateValueOn, @"Default current icon");
        for (NSInteger i = 0; i < 5; i++) {
            [buttons[i] performClick:nil];
            Require((NSApp.dockTile.contentView != nil) == (i != 4), @"Native custom drawing and reset");

            Require([[defaults stringForKey:TSDockIconKey] isEqual:TSDockIconNames()[i]], @"Save choice in memory");
            TSDockIconController *fresh = [[TSDockIconController alloc] initWithBundle:bundle defaults:[NSUserDefaults standardUserDefaults]];
            [fresh restoreSavedIcon];
            Require([[fresh valueForKey:@"selection"] isEqual:TSDockIconNames()[i]], @"Restore across controller instances");
            [controller restoreSavedIcon];
        }
        [buttons[0] performClick:nil];
        Require([[defaults stringForKey:TSDockIconKey] isEqual:TSDockIconNames()[0]] && NSApp.dockTile.contentView != nil, @"click immediately saves custom icon");
        [defaults setObject:@"current" forKey:TSDockIconKey];
        [controller restoreSavedIcon]; [buttons[2] performClick:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowWillCloseNotification object:window];
        Require(NSApp.dockTile.contentView != nil && [[defaults stringForKey:TSDockIconKey] isEqual:TSDockIconNames()[2]], @"Window-close retains the saved selection");
        [defaults setObject:@"invalid-style" forKey:TSDockIconKey]; [controller restoreSavedIcon];
        Require(NSApp.dockTile.contentView == nil, @"Unknown preference falls back");
        Require([bundle objectForInfoDictionaryKey:@"NSDockTilePlugIn"] == nil, @"No resident Dock plug-in");
        DockProbe *probe = [DockProbe new]; probe.size = NSMakeSize(128,128); probe.badgeLabel = @"7";
        TSApplyDockIcon((id)probe,bundle,@"round");
        Require(probe.contentView != nil && [probe.badgeLabel isEqual:@"7"], @"Custom drawing does not alter badges");
        TSApplyDockIcon((id)probe,bundle,@"current");
        Require(probe.contentView == nil && [probe.badgeLabel isEqual:@"7"], @"Reset does not alter badges");


        puts("PASS: nib, five assets, immediate save, restore, close persistence, fallback and badge property");
        return 0;
    }
    if (snapshot) {
        window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        [window.contentView layoutSubtreeIfNeeded];
        [window display];
        [tabs selectTabViewItemAtIndex:tabs.numberOfTabViewItems - 2]; [window display];
        NSView *view = tabs.tabViewItems[tabs.numberOfTabViewItems - 2].view;
        for (NSView *child in view.subviews) if ([child.identifier isEqual:@"DockIconChoices"]) {
            [child layoutSubtreeIfNeeded];
            NSBitmapImageRep *rep = [child bitmapImageRepForCachingDisplayInRect:child.bounds];
            [child cacheDisplayInRect:child.bounds toBitmapImageRep:rep];
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[3]) atomically:YES];
        }
        return 0;
    }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    PreviewDelegate *delegate = [PreviewDelegate new]; delegate.controller = controller; NSApp.delegate = delegate;
    [tabs selectTabViewItemAtIndex:tabs.numberOfTabViewItems - 2];
    // Disable the original unrelated controls; keep this harness from changing TeXShop preferences.
    for (NSView *v in window.contentView.subviews) if ([v isKindOfClass:NSButton.class]) {
        NSButton *b = (id)v; b.enabled = NO;
    }
    for (NSUInteger i = 0; i < 2; i++) {
        NSButton *b = [NSButton buttonWithTitle:@"Close" target:delegate action:i ? @selector(accept:) : @selector(cancel:)];
        b.frame = NSMakeRect(420+i*90,12,80,28); [window.contentView addSubview:b];
    }
    window.title = @"TeXShop Dock Icon Experiment";
    [window center]; [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
} return 0; }
