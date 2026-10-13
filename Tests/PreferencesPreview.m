// Terada: Test rendering without initializing TeXShop or writing user preferences.
#import <Cocoa/Cocoa.h>
@interface TSPreferences : NSObject
- (void)nextLanguage:(id)sender;
@end
@implementation TSPreferences
- (void)nextLanguage:(id)sender { [NSApp stop:nil]; }
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
@end
@interface TSPreferenceWindow : NSWindow
- (void)nextLanguage:(id)sender;
@end
@implementation TSPreferenceWindow
- (void)nextLanguage:(id)sender { [NSApp stop:nil]; }
@end
static NSTabView *Tabs(NSView *v) {
    if ([v isKindOfClass:NSTabView.class]) return (NSTabView *)v;
    for (NSView *c in v.subviews) { NSTabView *t=Tabs(c); if(t) return t; }
    return nil;
}
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    TSPreferences *owner=[TSPreferences new];
    for(int a=1;a<argc;a++) {
        NSString *path=@(argv[a]);
        NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"keyedobjects.nib"]] bundle:nil];
        NSArray *objects;
        if(![nib instantiateWithOwner:owner topLevelObjects:&objects]) return 1;
        NSString *lang=path.stringByDeletingLastPathComponent.lastPathComponent;
        for(id o in objects) {
            if(![o isKindOfClass:NSWindow.class]) continue;
            NSWindow *w=o; NSTabView *tabs=Tabs(w.contentView);
            if(tabs.numberOfTabViewItems!=9) continue;
            w.appearance=[NSAppearance appearanceNamed:NSAppearanceNameAqua];
                w.title=lang;
                NSButton *next=[NSButton buttonWithTitle:@"Next language" target:owner action:@selector(nextLanguage:)];
                next.frame=NSMakeRect(260,18,135,28); [w.contentView addSubview:next];
                [tabs selectTabViewItemAtIndex:0];
                [w center]; [w makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; [NSApp run];
            [w orderOut:nil];
        }
    }
} return 0; }
