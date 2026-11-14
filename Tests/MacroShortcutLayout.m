// Instantiate existing localized nibs offscreen and run the production status-band layout.
#import "TSMacroEditor.h"
#import "TSDialogButtonLayout.h"
#import "TSMarkMenu.h"
#import "TSListBottomBar.h"
#import "TSMacroShortcutField.h"
#import "TSMacroTreeNode.h"
#import "TSMacroMenuController.h"
#import "TSShortcutInternal.h"
#import <objc/runtime.h>
#import "MemoryDefaults.h"
static TSMemoryDefaults *memoryDefaults;
static id StandardDefaults(id self, SEL cmd) { return memoryDefaults; }
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
static int reflections, pendingUpdates;
@implementation TSMacroEditor
#include "MacroStatusLayout.inc"
// The rest of the editor: what the shortcut field asks of it.
- (void)updatePendingShortcutStatus { pendingUpdates++; }
- (void)reflectChangesInEditor:(BOOL)force { reflections++; [self syncShortcutField]; }
@end
@interface TSMacroOutlineController : NSObject @end
@implementation TSMacroOutlineController
- (void)setValue:(id)v forUndefinedKey:(NSString *)key {}
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item { return 0; }
@end
@interface TSMacroOutlineView : NSOutlineView @end
@implementation TSMacroOutlineView @end
static void NoOrder(id self, SEL cmd, NSWindowOrderingMode mode, NSInteger relative) {}
// With TS_STRINGS (a Localizable.strings), NSLocalizedString gives that language's text, as the application does.
static NSDictionary *TestStrings; static IMP OriginalLocalizedString;
static NSString *TestLocalizedString(id self, SEL cmd, NSString *key, NSString *value, NSString *table) {
    if ((!table.length || [table isEqual:@"Localizable"]) && TestStrings[key]) return TestStrings[key];
    return ((NSString *(*)(id, SEL, NSString *, NSString *, NSString *))OriginalLocalizedString)(self, cmd, key, value, table);
}
static void UseTestStrings(void) {
    if (!getenv("TS_STRINGS")) return;
    TestStrings=[[NSString stringWithContentsOfFile:@(getenv("TS_STRINGS")) encoding:NSUTF8StringEncoding error:nil] propertyListFromStringsFileFormat];
    REQUIRE(TestStrings.count>0);
    OriginalLocalizedString=method_setImplementation(class_getInstanceMethod(NSBundle.class,@selector(localizedStringForKey:value:table:)),(IMP)TestLocalizedString);
}
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
// Records the actions that the old buttons send.
@interface ActionRecorder : NSObject
@property NSMutableArray<NSString *> *log;
@end
@implementation ActionRecorder
- (void)hit:(NSButton *)sender { [self.log addObject:sender.title]; }
@end
// The bar under the list is the Multiple Replace window's: a line on top, ＋ and − without
// borders at the leading edge, ⊙… at the trailing edge, the list's width, at the bottom
// of the list's frame. Its buttons do what the old buttons do, when they can.
// A control's alignment rectangle (what Auto Layout places) in another view.
static NSRect Aligned(NSView *view, NSView *to) { return [view.superview convertRect:[view alignmentRectForFrame:view.frame] toView:to]; }
static void CheckListBar(TSMacroEditor *owner, NSScrollView *list) {
    NSBox *box=owner.listBox; TSListBottomBar *bar=owner.listBar; NSView *inside=box.contentView;
    REQUIRE([bar isKindOfClass:TSListBottomBar.class] && bar.superview==inside && list.superview==inside && box.superview==[[owner valueForKey:@"window"] contentView]);
    REQUIRE(box.boxType==NSBoxCustom && box.borderWidth==1 && [box.borderColor isEqual:NSColor.separatorColor] && [box.fillColor isEqual:NSColor.textBackgroundColor]);
    REQUIRE(list.borderType==NSNoBorder && [[[owner valueForKey:@"outlineView"] backgroundColor] isEqual:NSColor.textBackgroundColor]);
    [box layoutSubtreeIfNeeded];
    // Inside the frame: the bar takes the whole width at the bottom, the list the rest.
    REQUIRE(NSContainsRect(NSInsetRect(box.bounds,.5,.5),[inside convertRect:inside.bounds toView:box]));
    REQUIRE(NSMinY(bar.frame)==0 && NSMinX(bar.frame)==0 && fabs(NSWidth(bar.frame)-NSWidth(inside.bounds))<.5);
    REQUIRE(fabs(NSMinY(list.frame)-NSMaxY(bar.frame))<.5 && NSMinX(list.frame)==0 && fabs(NSWidth(list.frame)-NSWidth(inside.bounds))<.5 && fabs(NSMaxY(list.frame)-NSHeight(inside.bounds))<.5);
    REQUIRE(NSHeight(bar.frame)>=36 && NSHeight(bar.frame)<=40 && NSHeight(list.frame)>=64);
    [bar layoutSubtreeIfNeeded];
    NSRect line=[bar.separator alignmentRectForFrame:bar.separator.frame]; // the line itself, not the box around it
    REQUIRE(bar.separator.boxType==NSBoxSeparator && fabs(NSMaxY(line)-NSHeight(bar.bounds))<.5 && NSMinX(line)==0 && fabs(NSWidth(line)-NSWidth(bar.bounds))<.5);
    NSRect add=Aligned(bar.addButton,bar),remove=Aligned(bar.removeButton,bar),more=Aligned(bar.actionsButton,bar);
    REQUIRE(fabs(NSMinX(add)-12)<.5 && NSMinX(remove)>NSMaxX(add) && NSMinX(remove)-NSMaxX(add)<=4.5 && fabs(NSMaxX(more)-(NSWidth(bar.bounds)-12))<.5 && NSMinX(more)>NSMaxX(remove));
    REQUIRE(fabs(NSMinY(add)-8)<.5 && fabs(NSMidY(add)-NSMidY(remove))<.5 && fabs(NSMidY(add)-NSMidY(more))<.5);
    // The symbols only, read out by VoiceOver as the old buttons' titles.
    for(NSButton *b in @[bar.addButton,bar.removeButton]) REQUIRE(!b.bordered && b.image && b.imagePosition==NSImageOnly && [b.accessibilityLabel isEqual:b.toolTip]);
    REQUIRE(!bar.actionsButton.bordered && bar.actionsButton.pullsDown && [bar.actionsButton.itemArray.firstObject.image.accessibilityDescription isEqual:bar.actionsButton.toolTip]);
    NSButton *newItem=[owner valueForKey:@"newItemButton"],*submenu=[owner valueForKey:@"submenuButton"],*separator=[owner valueForKey:@"separatorButton"],*delete=[owner valueForKey:@"deleteButton"],*duplicate=[owner valueForKey:@"duplicateButton"];
    REQUIRE([bar.addButton.toolTip isEqual:newItem.title] && [bar.addButton.image.accessibilityDescription isEqual:newItem.title]);
    REQUIRE([bar.removeButton.toolTip isEqual:delete.title] && [bar.removeButton.image.accessibilityDescription isEqual:delete.title]);
    REQUIRE([bar.actionsButton.toolTip containsString:submenu.title] && [bar.actionsButton.toolTip containsString:separator.title] && [bar.actionsButton.toolTip containsString:duplicate.title]);
    NSArray<NSMenuItem *> *items=bar.actionItems; NSArray *sources=@[submenu,separator,duplicate];
    REQUIRE(items.count==3);
    for(NSUInteger i=0;i<3;i++) REQUIRE([items[i].title isEqual:[sources[i] title]] && items[i].representedObject==sources[i] && items[i].target==owner);
    // The buttons send the old buttons' actions, and only while those are enabled.
    ActionRecorder *recorder=[ActionRecorder new]; recorder.log=[NSMutableArray new];
    NSArray<NSButton *> *all=@[newItem,submenu,separator,delete,duplicate]; NSMutableArray *targets=[NSMutableArray new],*actions=[NSMutableArray new];
    for(NSButton *b in all) { [targets addObject:b.target?:NSNull.null]; [actions addObject:NSStringFromSelector(b.action)?:@""]; b.target=recorder; b.action=@selector(hit:); }
    BOOL states[]={YES,NO};
    for(int k=0;k<2;k++) {
        for(NSButton *b in all) b.enabled=states[k];
        [owner syncListControls];
        REQUIRE(bar.addButton.enabled==states[k] && bar.removeButton.enabled==states[k]);
        for(NSMenuItem *item in items) REQUIRE(item.enabled==states[k]);
        REQUIRE(bar.actionsButton.itemArray.firstObject.enabled);
        [recorder.log removeAllObjects];
        [NSApp sendAction:bar.addButton.action to:bar.addButton.target from:bar.addButton];
        [NSApp sendAction:bar.removeButton.action to:bar.removeButton.target from:bar.removeButton];
        for(NSMenuItem *item in items) [NSApp sendAction:item.action to:item.target from:item];
        if(states[k]) REQUIRE([recorder.log isEqual:(@[newItem.title,delete.title,submenu.title,separator.title,duplicate.title])]);
        else REQUIRE(recorder.log.count==0);
    }
    // The selection: ＋ stays, − and Duplicate follow it.
    newItem.enabled=YES; delete.enabled=NO; duplicate.enabled=NO; submenu.enabled=YES; separator.enabled=YES;
    [owner syncListControls];
    REQUIRE(bar.addButton.enabled && !bar.removeButton.enabled && items[0].enabled && items[1].enabled && !items[2].enabled);
    for(NSUInteger i=0;i<all.count;i++) { all[i].target=targets[i]==NSNull.null?nil:targets[i]; all[i].action=NSSelectorFromString(actions[i]); all[i].enabled=YES; }
    [owner syncListControls];
}
static NSEvent *Key(NSString *characters, NSString *ignoring, unsigned short code, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil
        characters:characters charactersIgnoringModifiers:ignoring isARepeat:NO keyCode:code];
}
// The shortcut is set as in Settings > Keyboard: a field takes the rows of the nib's key field and
// Shift/Option/Control boxes, records the keys pressed and removes them with ⊗.
static void CheckShortcutField(TSMacroEditor *owner) {
    NSWindow *window=[owner valueForKey:@"window"]; NSView *host=window.contentView;
    TSMacroShortcutField *field=owner.shortcutField; NSTextField *label=owner.shortcutLabel;
    NSTextField *nameField=[owner valueForKey:@"nameField"],*keyField=[owner valueForKey:@"keyField"];
    REQUIRE(field && label && field.superview==host && label.superview==host && !field.hidden && !label.hidden);
    NSArray *old=@[keyField,[owner valueForKey:@"shiftCheckBox"],[owner valueForKey:@"optionCheckBox"],[owner valueForKey:@"controlCheckBox"]];
    for(NSView *v in old) REQUIRE(v.hidden);
    // No label of the old rows is left: only the new label and field in the field's row of the right column.
    for(NSView *v in host.subviews) if(!v.hidden && v!=field && v!=label && NSMinX(v.frame)>=NSMinX(nameField.frame)-12)
        { if(NSMinY(v.frame)<NSMaxY(field.frame) && NSMaxY(v.frame)>NSMinY(field.frame)) fprintf(stderr,"ROW %s %s %s\n",NSStringFromClass(v.class).UTF8String,NSStringFromRect(v.frame).UTF8String,[v isKindOfClass:NSTextField.class]?((NSTextField*)v).stringValue.UTF8String:"");
          REQUIRE(!(NSMinY(v.frame)<NSMaxY(field.frame) && NSMaxY(v.frame)>NSMinY(field.frame))); }
    REQUIRE([label.stringValue hasPrefix:NSLocalizedString(@"Shortcut",@"")] && label.stringValue.length>NSLocalizedString(@"Shortcut",@"").length);
    REQUIRE([label.cell cellSize].width<=NSWidth(label.frame)+.5 && fabs(NSMidY(label.frame)-NSMidY(field.frame))<=1);
    REQUIRE(fabs(NSMinX(field.frame)-NSMaxX(label.frame)-8)<.5 && NSMaxX(field.frame)<=NSMaxX(nameField.frame)+.5);
    REQUIRE(NSWidth(field.frame)>=field.minimumWidth-.5 || fabs(NSMaxX(field.frame)-NSMaxX(nameField.frame))<.5);
    REQUIRE(NSHeight(field.frame)==NSHeight(keyField.frame) && field.display.bezelStyle==keyField.bezelStyle);
    NSRect cross=field.clearButton.frame;
    REQUIRE(NSMaxX(cross)<=NSWidth(field.bounds)-3.5 && fabs(NSMidY(cross)-NSMidY(field.bounds))<=1);
    REQUIRE([field.clearButton.toolTip isEqual:NSLocalizedString(@"Remove Shortcut",@"")] && [field.clearButton.image.accessibilityDescription isEqual:field.clearButton.toolTip]);
    REQUIRE([field.accessibilityLabel isEqual:NSLocalizedString(@"Shortcut",@"")] && field.isAccessibilityElement && [field.accessibilityRole isEqual:NSAccessibilityButtonRole]);
    // In the key view loop where the key field was.
    BOOL reached=NO; NSMutableArray *pending=[host.subviews mutableCopy];
    while(pending.count){ NSView *v=pending.lastObject; [pending removeLastObject]; [pending addObjectsFromArray:v.subviews]; if(v.nextKeyView==field) reached=YES; REQUIRE(v.nextKeyView!=keyField || v.hidden); }
    REQUIRE(reached && ![old containsObject:field.nextKeyView]);
}
// What the field does: records Command or Control with a key, or F1–F20, as Settings does;
// Escape and Return keep the shortcut; Delete and ⊗ remove it; only a macro has one.
static void CheckShortcutBehavior(TSMacroEditor *owner) {
    NSWindow *window=[owner valueForKey:@"window"]; TSMacroShortcutField *field=owner.shortcutField;
    owner.previousItem=nil; owner.pendingShortcutKey=@""; [owner syncShortcutField];
    REQUIRE(!field.enabled && field.clearButton.hidden && ![field acceptsFirstResponder] && ![owner recordShortcutEvent:Key(@"j",@"j",38,NSEventModifierFlagCommand)]);
    TSMacroTreeNode *macro=[TSMacroTreeNode nodeWithName:@"Macro" content:@"x" key:@"M+ShiftKey"], *group=[TSMacroTreeNode submenuNodeWithName:@"Group"];
    owner.previousItem=group; [owner syncShortcutField]; REQUIRE(!field.enabled);
    owner.previousItem=macro; owner.pendingShortcutKey=macro.key; [owner syncShortcutField];
    REQUIRE(field.enabled && [field.shortcut isEqual:@"⇧⌘M"] && [field.display.stringValue isEqual:@"⇧⌘M"] && !field.clearButton.hidden);
    struct { NSString *chars, *ignoring; unsigned short code; NSEventModifierFlags flags; NSString *saved, *shown; } cases[]={
        {@"K",@"K",40,NSEventModifierFlagCommand|NSEventModifierFlagShift,@"K+ShiftKey",@"⇧⌘K"},
        {@"\x0b",@"k",40,NSEventModifierFlagControl,@"K+ControlKey+NoCommandKey",@"⌃K"},
        {@"",@"",96,0,@"+NoCommandKey",@"F5"},
        {@"",@"",96,NSEventModifierFlagCommand|NSEventModifierFlagOption,@"+OptionKey",@"⌥⌘F5"},
        {@"k",@"k",40,NSEventModifierFlagCommand,@"K",@"⌘K"},
    };
    for(size_t i=0;i<sizeof cases/sizeof *cases;i++) {
        int before=reflections; [owner setValue:@NO forKey:@"keyTouched"];
        REQUIRE([owner recordShortcutEvent:Key(cases[i].chars,cases[i].ignoring,cases[i].code,cases[i].flags)]);
        if(![owner.pendingShortcutKey isEqual:cases[i].saved]) fprintf(stderr,"saved %s for case %zu\n",owner.pendingShortcutKey.UTF8String,i);
        REQUIRE([owner.pendingShortcutKey isEqual:cases[i].saved] && [field.shortcut isEqual:cases[i].shown]);
        REQUIRE(reflections==before+1 && [[owner valueForKey:@"keyTouched"] boolValue]);
    }
    // Typing keys stay typing keys: not plain, Shift or Option alone, not Return or Tab with Command.
    NSString *kept=owner.pendingShortcutKey;
    NSEvent *refused[]={Key(@"k",@"k",40,0),Key(@"K",@"K",40,NSEventModifierFlagShift),Key(@"˚",@"k",40,NSEventModifierFlagOption),Key(@"\r",@"\r",36,NSEventModifierFlagCommand),Key(@"\t",@"\t",48,NSEventModifierFlagCommand)};
    for(size_t i=0;i<5;i++) REQUIRE(![owner recordShortcutEvent:refused[i]] && [owner.pendingShortcutKey isEqual:kept]);
    owner.previousItem=group; REQUIRE(![owner recordShortcutEvent:Key(@"j",@"j",38,NSEventModifierFlagCommand)]); owner.previousItem=macro; [owner syncShortcutField];
    // The field itself: a click starts, the key pressed ends; Escape and Return keep, Delete and ⊗ remove.
    [field beginRecording];
    REQUIRE(window.firstResponder==field && field.recording && [field.display.placeholderString isEqual:NSLocalizedString(@"Press a key",@"")] && field.display.stringValue.length==0 && [field valueForKey:@"keyMonitor"]);
    [field keyDown:Key(@"\x1b",@"\x1b",53,0)]; REQUIRE(!field.recording && window.firstResponder!=field && [owner.pendingShortcutKey isEqual:kept] && ![field valueForKey:@"keyMonitor"]);
    [field beginRecording]; [field keyDown:Key(@"\r",@"\r",36,0)]; REQUIRE(!field.recording && [owner.pendingShortcutKey isEqual:kept]);
    [field beginRecording]; REQUIRE([field performKeyEquivalent:Key(@"j",@"j",38,NSEventModifierFlagCommand)]);
    REQUIRE(!field.recording && [owner.pendingShortcutKey isEqual:@"J"] && [field.display.stringValue isEqual:@"⌘J"]);
    REQUIRE(![field performKeyEquivalent:Key(@"s",@"s",1,NSEventModifierFlagCommand)] && [owner.pendingShortcutKey isEqual:@"J"]); // not waiting: the menus get it
    [field beginRecording]; [field keyDown:Key(@"k",@"k",40,0)]; REQUIRE(field.recording && [owner.pendingShortcutKey isEqual:@"J"]); // refused: still waiting
    [field keyDown:Key(@"\x7f",@"\x7f",51,0)]; REQUIRE(!field.recording && [owner.pendingShortcutKey isEqual:@""] && field.clearButton.hidden && field.display.stringValue.length==0);
    owner.pendingShortcutKey=@"J"; [owner syncShortcutField]; REQUIRE(!field.clearButton.hidden);
    REQUIRE([field hitTest:[field convertPoint:NSMakePoint(NSMidX(field.clearButton.frame),NSMidY(field.clearButton.frame)) toView:field.superview]]==field.clearButton);
    REQUIRE([field hitTest:[field convertPoint:NSMakePoint(10,NSMidY(field.bounds)) toView:field.superview]]==field);
    [field.clearButton performClick:nil]; REQUIRE([owner.pendingShortcutKey isEqual:@""]);
    owner.pendingShortcutKey=macro.key; [owner syncShortcutField];
    [field beginRecording]; owner.previousItem=nil; [owner syncShortcutField]; REQUIRE(!field.recording && !field.enabled);
    owner.previousItem=macro; [owner syncShortcutField];
}
// The list bar, the placeholder note and the dismissal row follow the Human Interface Guidelines.
static void CheckEditor(TSMacroEditor *owner, NSWindow *window) {
    NSView *host=window.contentView; [host layoutSubtreeIfNeeded];
    if(getenv("TS_DUMP")) for(NSView *v in host.subviews) fprintf(stderr,"SUB %s %s hidden=%d %s\n",NSStringFromClass(v.class).UTF8String,NSStringFromRect(v.frame).UTF8String,v.hidden,[v isKindOfClass:NSTextField.class]?((NSTextField*)v).stringValue.UTF8String:"");
    NSScrollView *list=[[owner valueForKey:@"outlineView"] enclosingScrollView];
    NSButton *save=[owner valueForKey:@"saveButton"],*cancel=[owner valueForKey:@"cancelButton"],*test=[owner valueForKey:@"testButton"];
    REQUIRE(owner.listBox && owner.listBar && owner.placeholderNote);
    for(NSString *key in @[@"newItemButton",@"submenuButton",@"separatorButton",@"deleteButton",@"duplicateButton"]) REQUIRE([[owner valueForKey:key] isHidden]);
    CheckListBar(owner,list);
    CheckShortcutField(owner);
    REQUIRE(fabs(NSMaxX(save.frame)-(NSWidth(host.bounds)-20))<.5 && fabs(NSMinX(save.frame)-12-NSMaxX(cancel.frame))<.5 && NSWidth(save.frame)==NSWidth(cancel.frame));
    REQUIRE(fabs(NSMinX(test.frame)-20)<.5 && NSMaxX(test.frame)+12<=NSMinX(cancel.frame));
    for(NSButton *b in @[save,cancel,test]) REQUIRE(b.fittingSize.width<=NSWidth(b.frame)+.5);
    NSRect s=Drawn(host,save),c=Drawn(host,cancel); REQUIRE(NSMinX(s)-NSMaxX(c)>=11);
    NSTextField *note=owner.placeholderNote;
    REQUIRE([note.stringValue containsString:@"#SEL#"] && [note.stringValue containsString:@"#INS#"] && [note.stringValue containsString:@"#PASTE#"]);
    REQUIRE([note.cell cellSizeForBounds:NSMakeRect(0,0,NSWidth(note.bounds),CGFLOAT_MAX)].height<=NSHeight(note.bounds)+.5);
    NSArray *attached=@[owner.listBox];
    // What this layout adds or moves must not overlap anything; older labels in the
    // nibs may run into their fields by a few points.
    NSArray *placed=@[owner.listBox,owner.placeholderNote,owner.shortcutLabel,owner.shortcutField,save,cancel,test];
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
    UseTestStrings();
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
    CGFloat minimumBefore=window.minSize.height;
    [owner installShortcutStatus];
    REQUIRE(fabs(NSMaxY(window.frame)-originalTop)<.1);
    // The smallest window keeps the room it had for the editors and adds the status band.
    REQUIRE(window.minSize.height+.1 >= minimumBefore+NSHeight(owner.shortcutStatus.frame));
    REQUIRE(window.frame.size.height==MAX(originalHeight,window.minSize.height));
    if(round) REQUIRE(originalHeight==savedHeight);
    NSTableViewStyle styleBefore=((NSOutlineView*)[owner valueForKey:@"outlineView"]).effectiveStyle;
    [owner installListControls];
    if(getenv("TS_DUMP")) fprintf(stderr,"BEFORE key %s shift %s contents %s\n",NSStringFromRect([[owner valueForKey:@"keyField"] frame]).UTF8String,NSStringFromRect([[owner valueForKey:@"shiftCheckBox"] frame]).UTF8String,NSStringFromRect([[[owner valueForKey:@"contentTextView"] enclosingScrollView] frame]).UTF8String);
    [owner installShortcutField];[owner installPlaceholderNote];
    // In its frame the list keeps the style it had in its own border.
    REQUIRE(styleBefore==NSTableViewStyleFullWidth && ((NSOutlineView*)[owner valueForKey:@"outlineView"]).effectiveStyle==styleBefore);
    [owner layoutDialogButtons];
    CheckEditor(owner,window);
    if(round==0) CheckShortcutBehavior(owner);
    // Images with a macro selected (its shortcut and ⊗), and, as -recording, while the field waits for keys.
    TSMacroTreeNode *shown=[TSMacroTreeNode nodeWithName:@"Macro" content:@"x" key:@"M+ShiftKey"];
    if(getenv("TS_RENDER_DIR") && round==0) { owner.previousItem=shown; owner.pendingShortcutKey=shown.key; [owner syncShortcutField]; }
    if(getenv("TS_RENDER_DIR") && round==0) for (NSString *state in @[@"",@"-recording"]) for (NSAppearanceName mode in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        if(state.length) [owner.shortcutField beginRecording]; else [owner.shortcutField endRecording];
        NSView *view=window.contentView; view.appearance=[NSAppearance appearanceNamed:mode]; owner.shortcutStatus.stringValue=@"このキーは“タイプセット › MetaPost”（⇧⌘M）と重なっているため無効です。";
        NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [NSGraphicsContext saveGraphicsState];[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        [view.effectiveAppearance performAsCurrentDrawingAppearance:^{[NSColor.windowBackgroundColor setFill];NSRectFill(view.bounds);}];
        [NSGraphicsContext restoreGraphicsState];[view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
        // Buttons in a window that is never shown draw as in an inactive window; their cells are drawn
        // again as the Multiple Replace window's images draw them (Tests/MultipleReplace.m), so the two compare.
        [NSGraphicsContext saveGraphicsState];[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        [view.effectiveAppearance performAsCurrentDrawingAppearance:^{ for(NSView *v in @[owner.listBar.addButton,owner.listBar.removeButton,owner.listBar.actionsButton,owner.shortcutField.clearButton]) { if(v.isHiddenOrHasHiddenAncestor) continue;
            NSRect frame=[v convertRect:v.bounds toView:view]; [NSGraphicsContext saveGraphicsState];
            NSAffineTransform *t=[NSAffineTransform transform]; [t translateXBy:frame.origin.x yBy:frame.origin.y];
            if(v.isFlipped){[t translateXBy:0 yBy:frame.size.height];[t scaleXBy:1 yBy:-1];} [t concat];
            [[(NSControl *)v cell] drawWithFrame:v.bounds inView:v]; [NSGraphicsContext restoreGraphicsState]; } }];
        [NSGraphicsContext restoreGraphicsState];
        NSString *name=[NSString stringWithFormat:@"%s/%@-%@%@.png",getenv("TS_RENDER_DIR"),[[@(argv[1]) stringByDeletingLastPathComponent].stringByDeletingLastPathComponent.lastPathComponent stringByDeletingPathExtension],[mode isEqual:NSAppearanceNameAqua]?@"light":@"dark",state];
        [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:name atomically:YES];
    }
    if(getenv("TS_RENDER_DIR") && round==0) { [owner.shortcutField endRecording]; owner.previousItem=nil; owner.pendingShortcutKey=@""; [owner syncShortcutField]; }
    NSTextField *label=owner.shortcutStatus; NSView *host=window.contentView;
    for (NSString *text in @[@"This shortcut is inactive because it conflicts with “Typeset › plain TeX” (⇧⌘T).",@"このキーは“タイプセット › plain TeX”（⇧⌘T）と重なっているため無効です。"])
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
    // The list is in its frame with the bar now: the frame keeps the list's minimum.
    NSScrollView *listScroll=[[owner valueForKey:@"outlineView"] enclosingScrollView];
    REQUIRE(originalMinimumHeights[[NSValue valueWithNonretainedObject:listScroll]] && NSHeight(owner.listBox.frame)+.1 >= [originalMinimumHeights[[NSValue valueWithNonretainedObject:listScroll]] doubleValue]);
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
