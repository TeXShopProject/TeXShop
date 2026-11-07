// Instantiate existing localized nibs offscreen and run the production status-band layout.
#import "TSMacroEditor.h"
#import <objc/runtime.h>
#import "MemoryDefaults.h"
static TSMemoryDefaults *memoryDefaults;
static id StandardDefaults(id self, SEL cmd) { return memoryDefaults; }
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
    memoryDefaults=[TSMemoryDefaults new];
    method_setImplementation(class_getClassMethod(NSUserDefaults.class,@selector(standardUserDefaults)),(IMP)StandardDefaults);
    REQUIRE(NSUserDefaults.standardUserDefaults==memoryDefaults);
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    // Make even an accidentally-visible nib incapable of ordering a window onscreen.
    method_setImplementation(class_getInstanceMethod(NSWindow.class,@selector(orderWindow:relativeTo:)),(IMP)NoOrder);
    [memoryDefaults setObject:@"414 289 585 100 0 0 1920 1080 " forKey:@"NSWindow Frame Macro Editor"];
    CGFloat savedHeight=0;
    for(int round=0;round<4;round++) {
    TSMacroEditor *owner=[TSMacroEditor new];
    NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[1])] bundle:nil];
    NSArray *objects; REQUIRE([nib instantiateWithOwner:owner topLevelObjects:&objects]);
    NSWindow *window=[owner valueForKey:@"window"]; REQUIRE(window && !window.visible);
    [window setFrameUsingName:@"Macro Editor"];
    REQUIRE(window.minSize.height>=272);
    REQUIRE(window.frame.size.height>=window.minSize.height);
    CGFloat originalHeight=window.frame.size.height;
    NSMutableDictionary *originalMinimumHeights=[NSMutableDictionary new];
    NSRect smallest;
    for (NSView *v in window.contentView.subviews) if([v isKindOfClass:NSScrollView.class])
        originalMinimumHeights[[NSValue valueWithNonretainedObject:v]]=@(MAX(64,NSHeight(v.frame) - (originalHeight-window.minSize.height)));
    if(round==0 && window.minSize.height>=272) {
        NSRect previousMinimum=window.frame; previousMinimum.size.height=window.minSize.height;
        [window setFrame:previousMinimum display:NO]; originalHeight=window.frame.size.height;
    }
    CGFloat originalTop=NSMaxY(window.frame);
    [owner installShortcutStatus];
    REQUIRE(fabs(NSMaxY(window.frame)-originalTop)<.1);
    REQUIRE(window.frame.size.height==MAX(originalHeight,window.minSize.height));
    if(round) REQUIRE(originalHeight==savedHeight);
    NSTextField *label=owner.shortcutStatus; NSView *host=window.contentView;
    for (NSString *text in @[@"This shortcut is inactive because it conflicts with “Typeset › Plain TeX” (⇧⌘T).",@"このキーは“タイプセット › Plain TeX”（⇧⌘T）と重なっているため無効です。"])
      for (NSAppearanceName mode in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        host.appearance=[NSAppearance appearanceNamed:mode];label.stringValue=text;
        REQUIRE(NSContainsRect(host.bounds,label.frame));
        REQUIRE([label.cell cellSizeForBounds:NSMakeRect(0,0,label.bounds.size.width,CGFLOAT_MAX)].height<=label.bounds.size.height);
        for (NSView *v in host.subviews) if(v!=label) { if([v isKindOfClass:NSScrollView.class]) REQUIRE(NSContainsRect(host.bounds,v.frame)); if(NSIntersectsRect(label.frame,v.frame)) fprintf(stderr,"OVERLAP %s %s label %s\n",NSStringFromClass(v.class).UTF8String,NSStringFromRect(v.frame).UTF8String,NSStringFromRect(label.frame).UTF8String); REQUIRE(!NSIntersectsRect(label.frame,v.frame)); }
        NSBitmapImageRep *rep=[host bitmapImageRepForCachingDisplayInRect:host.bounds];[host cacheDisplayInRect:host.bounds toBitmapImageRep:rep];
        REQUIRE(rep.pixelsWide>400 && rep.pixelsHigh>300 && !window.visible);
        if(argc>2) [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[2]) atomically:YES];
      }
    NSRect frame=window.frame; [owner installShortcutStatus]; REQUIRE(NSEqualRects(frame,window.frame));
    smallest=window.frame; smallest.size.height=window.minSize.height; [window setFrame:smallest display:NO];
    for (NSView *v in host.subviews) if([v isKindOfClass:NSScrollView.class]) {
        REQUIRE(NSContainsRect(host.bounds,v.frame));
        REQUIRE(NSHeight(v.frame)+.1 >= [originalMinimumHeights[[NSValue valueWithNonretainedObject:v]] doubleValue]);
    }
    if(round==0) {
        printf("minimum window height %.0f; editor heights",window.minSize.height);
        for (NSView *v in host.subviews) if([v isKindOfClass:NSScrollView.class]) printf(" %.0f",NSHeight(v.frame));
        printf("\n");
        if(argc>2) {
            NSBitmapImageRep *minimumRep=[host bitmapImageRepForCachingDisplayInRect:host.bounds];
            [host cacheDisplayInRect:host.bounds toBitmapImageRep:minimumRep];
            [[minimumRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[@(argv[2]) stringByAppendingString:@"-minimum.png"] atomically:YES];
        }
    }
    [window setFrame:frame display:NO];
    if(round==1) { NSRect resized=window.frame; resized.size.height+=80; [window setFrame:resized display:NO]; }
    savedHeight=window.frame.size.height;
    [window saveFrameUsingName:@"Macro Editor"];
    REQUIRE([[memoryDefaults stringForKey:@"NSWindow Frame Macro Editor"] length]>0);
    window.releasedWhenClosed=NO; [window close];
    }
    printf("PASS: %s status band: bounds, wrapping, control separation, idempotence, offscreen light/dark rendering\n",argv[1]);
} return 0; }
