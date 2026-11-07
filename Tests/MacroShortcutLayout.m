// Instantiate existing localized nibs offscreen and run the production status-band layout.
#import "TSMacroEditor.h"
#import <objc/runtime.h>
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
@implementation TSMacroEditor
#include "MacroStatusLayout.inc"
@end
@interface TSMacroOutlineController : NSObject @end
@implementation TSMacroOutlineController
- (void)setValue:(id)v forUndefinedKey:(NSString *)key {}
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item { return 0; }
@end
@interface TSMacroOutlineView : NSOutlineView @end
@implementation TSMacroOutlineView @end
static void NoOrder(id self, SEL cmd, NSWindowOrderingMode mode, NSInteger relative) {}
int main(int argc,char **argv) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    // Make even an accidentally-visible nib incapable of ordering a window onscreen.
    method_setImplementation(class_getInstanceMethod(NSWindow.class,@selector(orderWindow:relativeTo:)),(IMP)NoOrder);
    TSMacroEditor *owner=[TSMacroEditor new];
    NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[1])] bundle:nil];
    NSArray *objects; REQUIRE([nib instantiateWithOwner:owner topLevelObjects:&objects]);
    NSWindow *window=[owner valueForKey:@"window"]; REQUIRE(window && !window.visible);
    [owner installShortcutStatus];
    NSTextField *label=owner.shortcutStatus; NSView *host=window.contentView;
    for (NSString *text in @[@"This shortcut is inactive because it conflicts with “Typeset › Plain TeX” (⇧⌘T).",@"このキーは“タイプセット › Plain TeX”（⇧⌘T）と重なっているため無効です。"])
      for (NSAppearanceName mode in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        host.appearance=[NSAppearance appearanceNamed:mode];label.stringValue=text;
        REQUIRE(NSContainsRect(host.bounds,label.frame));
        REQUIRE([label.cell cellSizeForBounds:NSMakeRect(0,0,label.bounds.size.width,CGFLOAT_MAX)].height<=label.bounds.size.height);
        for (NSView *v in host.subviews) if(v!=label) { if(NSIntersectsRect(label.frame,v.frame)) fprintf(stderr,"OVERLAP %s %s label %s\n",NSStringFromClass(v.class).UTF8String,NSStringFromRect(v.frame).UTF8String,NSStringFromRect(label.frame).UTF8String); REQUIRE(!NSIntersectsRect(label.frame,v.frame)); }
        NSBitmapImageRep *rep=[host bitmapImageRepForCachingDisplayInRect:host.bounds];[host cacheDisplayInRect:host.bounds toBitmapImageRep:rep];
        REQUIRE(rep.pixelsWide>400 && rep.pixelsHigh>300 && !window.visible);
        if(argc>2) [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[2]) atomically:YES];
      }
    NSRect frame=window.frame; [owner installShortcutStatus]; REQUIRE(NSEqualRects(frame,window.frame));
    printf("PASS: %s status band: bounds, wrapping, control separation, idempotence, offscreen light/dark rendering\n",argv[1]);
} return 0; }
