// added by Terada: Isolated native preference and Dock plug-in checks.
#import <Cocoa/Cocoa.h>
#import "../Sources/TSDockIconController.h"
#import "../Sources/TSDockIcon.h"
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
- (void)accept:(id)sender { [self.controller acceptEditing]; [NSApp terminate:nil]; }
- (void)cancel:(id)sender { [self.controller cancelEditing]; [NSApp terminate:nil]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
@end
int main(int argc,char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *domain = NSBundle.mainBundle.bundleIdentifier;
    Require([domain hasPrefix:@"org.texshop.DockLab"], @"Use the isolated test bundle");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL snapshot = argc > 2 && [@(argv[2]) isEqualToString:@"--snapshot"];
    BOOL preview = snapshot || (argc > 2 && [@(argv[2]) isEqualToString:@"--preview"]);
    if (!preview) [defaults removePersistentDomainForName:domain];
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
    NSView *themeView = tabs.tabViewItems.lastObject.view;
    NSBox *iconGroup;
    for (NSView *view in themeView.subviews) if ([view.identifier isEqual:@"DockIconChoices"]) iconGroup = (id)view;
    Require(iconGroup != nil, @"Direct icon choices on Themes");
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
    [controller beginEditing];
    if (!preview) {
        Require(buttons[4].state == NSControlStateValueOn, @"Default current icon");
        for (NSInteger i = 0; i < 5; i++) {
            [buttons[i] performClick:nil];
            Require((NSApp.dockTile.contentView != nil) == (i != 4), @"Native custom drawing and reset");
            [controller acceptEditing];
            Require([[defaults stringForKey:TSDockIconKey] isEqual:TSDockIconNames()[i]], @"Persist choice");
            TSDockIconController *fresh = [[TSDockIconController alloc] initWithBundle:bundle defaults:[NSUserDefaults standardUserDefaults]];
            [fresh restoreSavedIcon];
            Require([[fresh valueForKey:@"selection"] isEqual:TSDockIconNames()[i]], @"Restore across controller instances");
            [controller beginEditing];
        }
        [buttons[0] performClick:nil]; [controller cancelEditing];
        Require([[defaults stringForKey:TSDockIconKey] isEqual:@"current"] && NSApp.dockTile.contentView == nil, @"Cancel preserves saved icon");
        // Match Preferences' undo-before-cancel order after restoring defaults.
        [defaults setObject:@"round" forKey:TSDockIconKey];
        [controller beginEditing];
        [defaults removeObjectForKey:TSDockIconKey];
        [controller restoreSavedIcon];
        Require(NSApp.dockTile.contentView == nil, @"Reset previews the default");
        [defaults setObject:@"round" forKey:TSDockIconKey]; // Preferences undo
        [controller cancelEditing];
        Require([[controller valueForKey:@"selection"] isEqual:@"round"] && NSApp.dockTile.contentView != nil, @"Cancel restores the undone saved preference");
        [defaults setObject:@"current" forKey:TSDockIconKey];
        [controller beginEditing]; [buttons[2] performClick:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowWillCloseNotification object:window];
        Require(NSApp.dockTile.contentView == nil, @"Window-close cancels preview");
        [defaults setObject:@"invalid-style" forKey:TSDockIconKey]; [controller restoreSavedIcon];
        Require(NSApp.dockTile.contentView == nil, @"Unknown preference falls back");
        NSBundle *plugin = [NSBundle bundleWithPath:[bundle.builtInPlugInsPath stringByAppendingPathComponent:@"TeXShopDockIcon.docktileplugin"]];
        id<NSDockTilePlugIn> instance = [[plugin.principalClass alloc] init];
        Require(instance != nil, @"Load real compiled plug-in");
        DockProbe *probe = [DockProbe new]; probe.size = NSMakeSize(128,128); probe.badgeLabel = @"7";
        for (NSString *name in TSDockIconNames()) {
            [defaults setObject:name forKey:TSDockIconKey]; [defaults synchronize];
            [instance setDockTile:(id)probe];
            Require((probe.contentView != nil) == ![name isEqual:@"current"], @"Plug-in reads application domain, not Dock defaults");
            [instance setDockTile:nil];
        }
        [defaults setObject:@"round" forKey:TSDockIconKey]; [defaults synchronize];
        [instance setDockTile:(id)probe];
        [defaults setObject:@"current" forKey:TSDockIconKey]; [defaults synchronize];
        [[NSDistributedNotificationCenter defaultCenter] postNotificationName:TSDockIconChanged object:domain userInfo:nil deliverImmediately:YES];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (probe.contentView && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        Require(probe.contentView == nil, @"Plug-in receives saved selection notification");
        // Simulate Sparkle removing the original installation after loading.
        [defaults setObject:@"round" forKey:TSDockIconKey]; [defaults synchronize];
        NSString *images=[bundle.resourcePath stringByAppendingPathComponent:@"DockIcons"];
        NSString *moved=[images stringByAppendingString:@".moved"];
        Require([[NSFileManager defaultManager] moveItemAtPath:images toPath:moved error:NULL], @"Temporarily remove icon source");
        [instance performSelector:@selector(refresh:) withObject:nil];
        Require(probe.contentView != nil, @"Cached image survives removed original bundle resources");
        Require([[NSFileManager defaultManager] moveItemAtPath:moved toPath:images error:NULL], @"Restore test resources");
        [instance setDockTile:nil];
        [defaults removePersistentDomainForName:domain];
        puts("PASS: nib, five assets, preview, save, restore, cancel, close, fallback, plug-in lifecycle and shared preference domain");
        return 0;
    }
    if (snapshot) {
        window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        [window.contentView layoutSubtreeIfNeeded];
        NSView *view = tabs.tabViewItems.lastObject.view;
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
    [tabs selectLastTabViewItem:nil]; [nested selectLastTabViewItem:nil];
    // Disable the original unrelated controls; keep this harness from changing TeXShop preferences.
    for (NSView *v in window.contentView.subviews) if ([v isKindOfClass:NSButton.class]) {
        NSButton *b = (id)v; b.enabled = NO;
    }
    for (NSUInteger i = 0; i < 2; i++) {
        NSButton *b = [NSButton buttonWithTitle:i ? @"OK" : @"Cancel" target:delegate action:i ? @selector(accept:) : @selector(cancel:)];
        b.frame = NSMakeRect(420+i*90,12,80,28); [window.contentView addSubview:b];
    }
    window.title = @"TeXShop Dock Icon Experiment";
    [window center]; [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    [NSApp run];
} return 0; }
