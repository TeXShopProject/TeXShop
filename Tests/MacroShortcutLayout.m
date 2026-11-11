// Instantiate existing localized nibs offscreen and run the production status-band layout.
#import "TSMacroEditor.h"
#import "TSDialogButtonLayout.h"
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
// Bounding box, in points from the top left, of pixels that differ between two renderings.
static NSRect Drawn(NSView *host, NSView *control) {
    NSBitmapImageRep *a=[host bitmapImageRepForCachingDisplayInRect:host.bounds];[host cacheDisplayInRect:host.bounds toBitmapImageRep:a];
    control.hidden=YES; NSBitmapImageRep *b=[host bitmapImageRepForCachingDisplayInRect:host.bounds];[host cacheDisplayInRect:host.bounds toBitmapImageRep:b]; control.hidden=NO;
    CGFloat scale=a.pixelsWide/NSWidth(host.bounds); NSInteger w=a.pixelsWide,h=a.pixelsHigh,bpr=a.bytesPerRow,spp=a.bitsPerPixel/8,minx=w,maxx=-1,miny=h,maxy=-1;
    // Only the neighbourhood of the control: hiding a default button can repaint unrelated views.
    NSRect near=NSInsetRect([control convertRect:control.bounds toView:host],-10,-10); if(!host.isFlipped) near.origin.y=NSHeight(host.bounds)-NSMaxY(near);
    NSInteger x0=MAX(0,(NSInteger)(NSMinX(near)*scale)),x1=MIN(w,(NSInteger)(NSMaxX(near)*scale)),y0=MAX(0,(NSInteger)(NSMinY(near)*scale)),y1=MIN(h,(NSInteger)(NSMaxY(near)*scale));
    for(NSInteger y=y0;y<y1;y++){unsigned char *r1=a.bitmapData+y*bpr,*r2=b.bitmapData+y*bpr;
        for(NSInteger x=x0;x<x1;x++){int d=0;for(int k=0;k<spp;k++)d=MAX(d,abs(r1[x*spp+k]-r2[x*spp+k]));if(d>8){minx=MIN(minx,x);maxx=MAX(maxx,x);miny=MIN(miny,y);maxy=MAX(maxy,y);}}}
    return maxx<0?NSZeroRect:NSMakeRect(minx/scale,miny/scale,(maxx-minx+1)/scale,(maxy-miny+1)/scale);
}
static NSTextView *contentsOf(TSMacroEditor *owner){return [owner valueForKey:@"contentTextView"];}
// The list bar, the placeholder note and the dismissal row follow the Human Interface Guidelines.
static void CheckEditor(TSMacroEditor *owner, NSWindow *window) {
    NSView *host=window.contentView; [host layoutSubtreeIfNeeded];
    if(getenv("TS_DUMP")) for(NSView *v in host.subviews) fprintf(stderr,"SUB %s %s hidden=%d %s\n",NSStringFromClass(v.class).UTF8String,NSStringFromRect(v.frame).UTF8String,v.hidden,[v isKindOfClass:NSTextField.class]?((NSTextField*)v).stringValue.UTF8String:"");
    NSScrollView *list=[[owner valueForKey:@"outlineView"] enclosingScrollView];
    NSButton *save=[owner valueForKey:@"saveButton"],*cancel=[owner valueForKey:@"cancelButton"],*test=[owner valueForKey:@"testButton"];
    REQUIRE(owner.listButtons && owner.listActions && owner.placeholderNote && owner.listButtons.segmentCount==3 && [owner.listButtons menuForSegment:2]==owner.listActions);
    for(NSString *key in @[@"newItemButton",@"submenuButton",@"separatorButton",@"deleteButton",@"duplicateButton"]) REQUIRE([[owner valueForKey:key] isHidden]);
    REQUIRE(owner.listActions.numberOfItems==3);
    REQUIRE(fabs(NSMinY(list.frame)-(NSMaxY(owner.listButtons.frame)-1))<.5 && fabs(NSMinX(list.frame)-NSMinX(owner.listButtons.frame))<.5);
    REQUIRE(fabs(NSMaxX(save.frame)-(NSWidth(host.bounds)-20))<.5 && fabs(NSMinX(save.frame)-12-NSMaxX(cancel.frame))<.5 && NSWidth(save.frame)==NSWidth(cancel.frame));
    REQUIRE(fabs(NSMinX(test.frame)-20)<.5 && NSMaxX(test.frame)+12<=NSMinX(cancel.frame));
    for(NSButton *b in @[save,cancel,test]) REQUIRE(b.fittingSize.width<=NSWidth(b.frame)+.5);
    NSRect s=Drawn(host,save),c=Drawn(host,cancel); REQUIRE(NSMinX(s)-NSMaxX(c)>=11);
    NSTextField *note=owner.placeholderNote;
    REQUIRE([note.stringValue containsString:@"#SEL#"] && [note.stringValue containsString:@"#INS#"] && [note.stringValue containsString:@"#PASTE#"]);
    REQUIRE([note.cell cellSizeForBounds:NSMakeRect(0,0,NSWidth(note.bounds),CGFLOAT_MAX)].height<=NSHeight(note.bounds)+.5);
    NSArray *attached=@[list,owner.listButtons];
    // What this layout adds or moves must not overlap anything; older labels in the
    // nibs may run into their fields by a few points.
    NSArray *placed=@[list,owner.listButtons,owner.placeholderNote,save,cancel,test];
    for(NSView *a in placed) {
        REQUIRE(NSContainsRect(NSInsetRect(host.bounds,-.5,-.5),a.frame));
        for(NSView *b in host.subviews) if(a!=b && !b.hidden && !([attached containsObject:a]&&[attached containsObject:b])) {
            if(NSIntersectsRect(NSInsetRect(a.frame,.5,.5),NSInsetRect(b.frame,.5,.5))) fprintf(stderr,"OVERLAP %s %s / %s %s\n",NSStringFromClass(a.class).UTF8String,NSStringFromRect(a.frame).UTF8String,NSStringFromClass(b.class).UTF8String,NSStringFromRect(b.frame).UTF8String);
            REQUIRE(!NSIntersectsRect(NSInsetRect(a.frame,.5,.5),NSInsetRect(b.frame,.5,.5)));
        }
    }
}
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
    [owner installListControls];[owner installPlaceholderNote];[owner layoutDialogButtons];
    CheckEditor(owner,window);
    if(getenv("TS_RENDER_DIR") && round==0) for (NSAppearanceName mode in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        NSView *view=window.contentView; view.appearance=[NSAppearance appearanceNamed:mode]; owner.shortcutStatus.stringValue=@"このキーは“タイプセット › MetaPost”（⇧⌘M）と重なっているため無効です。";
        NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [NSGraphicsContext saveGraphicsState];[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        [view.effectiveAppearance performAsCurrentDrawingAppearance:^{[NSColor.windowBackgroundColor setFill];NSRectFill(view.bounds);}];
        [NSGraphicsContext restoreGraphicsState];[view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
        NSString *name=[NSString stringWithFormat:@"%s/%@-%@.png",getenv("TS_RENDER_DIR"),[[@(argv[1]) stringByDeletingLastPathComponent].stringByDeletingLastPathComponent.lastPathComponent stringByDeletingPathExtension],[mode isEqual:NSAppearanceNameAqua]?@"light":@"dark"];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:name atomically:YES];
    }
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
    CheckEditor(owner,window);
    { NSRect narrow=window.frame; narrow.size.width=window.minSize.width; [window setFrame:narrow display:NO]; CheckEditor(owner,window); }
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
