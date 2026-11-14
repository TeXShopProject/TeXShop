// Instantiate existing localized nibs offscreen and run the production status-band layout.
#import "TSMacroEditor.h"
#import "TSDialogButtonLayout.h"
#import "TSMarkMenu.h"
#import "TSListBottomBar.h"
#import "TSMacroShortcutField.h"
#import "TSMacroTreeNode.h"
#import "TSMacroMenuController.h"
#import "TSShortcutInternal.h"
#import "TSPlaceholderToken.h"
#import "TSMacroContentKind.h"
#import "TSSyntaxMacroContentScanner.h"
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
// The list shows the items of SampleRoot (none unless set), as the editor's outline controller does.
static TSMacroTreeNode *SampleRoot;
@interface TSMacroOutlineController : NSObject @end
@implementation TSMacroOutlineController
- (void)setValue:(id)v forUndefinedKey:(NSString *)key {}
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item { return [(item ?: SampleRoot) numberOfChildren]; }
- (id)outlineView:(NSOutlineView *)view child:(NSInteger)index ofItem:(id)item { return [(item ?: SampleRoot) childAtIndex:index]; }
- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item { return [item isExpandable]; }
- (id)outlineView:(NSOutlineView *)view objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item {
    return [column.identifier isEqual:@"Key"] ? getMenuItemString([item key]) : [item name];
}
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
// The sidebar is the Multiple Replace window's: the list from the top edge, under the title
// bar, to the bar at the bottom edge (a line on top, ＋ and − without borders at the leading
// edge, ⊙… at the trailing edge), the window's whole height, without margins. Its buttons do
// what the old buttons do, when they can. The rest of the window is beside it.
// A control's alignment rectangle (what Auto Layout places) in another view.
static NSRect Aligned(NSView *view, NSView *to) { return [view.superview convertRect:[view alignmentRectForFrame:view.frame] toView:to]; }
static NSSplitViewController *SplitOf(NSWindow *window) { return (NSSplitViewController *)window.contentViewController; }
// The list as it fits now: the rows as wide as the visible list, the names taking what the
// shortcuts leave, nothing beyond the visible width, no sideways offset or scrolling.
static void CheckListFits(TSMacroEditor *owner) {
    NSOutlineView *rows=[owner valueForKey:@"outlineView"]; NSScrollView *list=rows.enclosingScrollView; NSClipView *clip=list.contentView;
    [list layoutSubtreeIfNeeded];
    CGFloat visible=NSWidth(clip.bounds), margin=NSMinX([rows rectOfColumn:0]), end=NSMaxX([rows rectOfColumn:rows.numberOfColumns-1]);
    // The same margin at both ends of the rows; the names take what the shortcuts leave.
    if(fabs(NSWidth(rows.frame)-visible)>.5 || fabs(end-(visible-margin))>.5) fprintf(stderr,"LIST rows %.1f visible %.1f columns end %.1f margin %.1f\n",NSWidth(rows.frame),visible,end,margin);
    REQUIRE(fabs(NSWidth(rows.frame)-visible)<=.5 && fabs(end-(visible-margin))<=.5 && margin>=0 && margin<=12);
    REQUIRE(NSMinX(clip.bounds)==0 && !list.hasHorizontalScroller && list.horizontalScrollElasticity==NSScrollElasticityNone);
    for(NSInteger row=0;row<rows.numberOfRows;row++) REQUIRE(NSMaxX([rows rectOfRow:row])<=visible+.5 && NSMaxX([rows frameOfCellAtColumn:1 row:row])<=visible-margin+.5);
}
// How far below the title bar the first row of the Multiple Replace window's sets is: a
// source list of one row in the same sidebar (TSListSidebarView, TSInstallListSidebar) of a panel
// made as that window's.
@interface OneRow : NSObject <NSTableViewDataSource, NSTableViewDelegate> @end
@implementation OneRow
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return 1; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return [NSTextField labelWithString:@"Set"]; }
@end
static CGFloat SetListFirstRowGap(void) {
    static CGFloat gap=-1; if(gap>=0) return gap;
    NSPanel *panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,980,440) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:YES];
    NSTableView *table=[[NSTableView alloc] initWithFrame:NSMakeRect(0,0,240,300)]; [table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"name"]];
    table.headerView=nil; table.style=NSTableViewStyleSourceList; static OneRow *source; source=[OneRow new]; table.dataSource=source; table.delegate=source;
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,200,200)]; scroll.documentView=table; scroll.hasVerticalScroller=YES;
    TSListBottomBar *bar=[[TSListBottomBar alloc] initWithTarget:nil addAction:NULL addToolTip:@"+" removeAction:NULL removeToolTip:@"-" actionsToolTip:@"..."];
    NSViewController *side=[NSViewController new],*main=[NSViewController new]; side.view=TSListSidebarView(scroll,bar); main.view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,640,400)];
    TSInstallListSidebar(panel,side,main,240,480,@"");
    [panel.contentView layoutSubtreeIfNeeded]; [table reloadData]; [panel.contentView layoutSubtreeIfNeeded];
    NSView *content=panel.contentView;
    gap=NSMaxY([content convertRect:panel.contentLayoutRect fromView:nil])-NSMaxY([table convertRect:[table rectOfRow:0] toView:content]);
    panel.releasedWhenClosed=NO; [panel close];
    return gap;
}
static void CheckSidebar(TSMacroEditor *owner, NSScrollView *list) {
    NSWindow *window=[owner valueForKey:@"window"]; NSVisualEffectView *sidebar=owner.sidebar; TSListBottomBar *bar=owner.listBar; NSView *main=owner.editorView;
    NSView *content=window.contentView; [content layoutSubtreeIfNeeded];
    // The window's contents run under its title bar, as the Multiple Replace window's.
    REQUIRE(window.styleMask & NSWindowStyleMaskFullSizeContentView);
    NSSplitViewController *split=SplitOf(window);
    REQUIRE([split isKindOfClass:NSSplitViewController.class] && split.splitViewItems.count==2 && content==split.view);
    NSSplitViewItem *side=split.splitViewItems[0],*rest=split.splitViewItems[1];
    REQUIRE(side.viewController.view==sidebar && !side.canCollapse && side.minimumThickness==160 && side.maximumThickness==320 && side.titlebarSeparatorStyle==NSTitlebarSeparatorStyleNone);
    REQUIRE(side.behavior==NSSplitViewItemBehaviorDefault && side.holdingPriority>rest.holdingPriority && rest.titlebarSeparatorStyle==NSTitlebarSeparatorStyleNone);
    REQUIRE(main.superview==rest.viewController.view && rest.minimumThickness>=TSDialogButtonsWidth(@[[owner valueForKey:@"saveButton"],[owner valueForKey:@"cancelButton"]],@[[owner valueForKey:@"testButton"]]));
    REQUIRE([sidebar isKindOfClass:NSVisualEffectView.class] && sidebar.material==NSVisualEffectMaterialSidebar && sidebar.blendingMode==NSVisualEffectBlendingModeBehindWindow);
    // From the top edge to the bottom edge at the leading edge: no margin above, below or beside it.
    NSRect side_=[sidebar convertRect:sidebar.bounds toView:content];
    REQUIRE(NSMinX(side_)==0 && NSMinY(side_)==0 && fabs(NSMaxY(side_)-NSHeight(content.bounds))<.5 && fabs(NSHeight(content.bounds)-NSHeight(window.frame))<.5);
    REQUIRE(NSWidth(side_)>=160-.5 && NSWidth(side_)<=320+.5);
    // The bar at the very bottom, the sidebar's width; the list from below the title bar down to the bar.
    REQUIRE(bar.superview==sidebar && list.superview==sidebar && [bar isKindOfClass:TSListBottomBar.class]);
    REQUIRE(NSMinY(bar.frame)==0 && NSMinX(bar.frame)==0 && fabs(NSWidth(bar.frame)-NSWidth(sidebar.bounds))<.5);
    CGFloat top=NSMaxY([content convertRect:window.contentLayoutRect fromView:nil]);
    REQUIRE(fabs(NSMaxY([list convertRect:list.bounds toView:content])-top)<.5 && top<NSHeight(content.bounds)-10);
    REQUIRE(fabs(NSMinY(list.frame)-NSMaxY(bar.frame))<.5 && NSMinX(list.frame)==0 && fabs(NSWidth(list.frame)-NSWidth(sidebar.bounds))<.5);
    REQUIRE(NSHeight(bar.frame)>=36 && NSHeight(bar.frame)<=40 && NSHeight(list.frame)>=64);
    // The first row as far below the title bar as the first set, at the same distance as the sets.
    NSOutlineView *outline=[owner valueForKey:@"outlineView"];
    if(outline.numberOfRows>0 && NSMinY(list.contentView.bounds)<=-list.contentInsets.top+.5) {
        CGFloat gap=top-NSMaxY([outline convertRect:[outline rectOfRow:0] toView:content]);
        if(fabs(gap-SetListFirstRowGap())>.5) fprintf(stderr,"FIRST ROW %.1f below the title bar, the sets' %.1f\n",gap,SetListFirstRowGap());
        REQUIRE(fabs(gap-SetListFirstRowGap())<=.5 && fabs(NSHeight([outline rectOfRow:0])-24)<.5);
    }
    REQUIRE(list.borderType==NSNoBorder && !list.drawsBackground && !list.hasHorizontalScroller && !list.automaticallyAdjustsContentInsets);
    // A source list without headings; the shortcuts at the trailing edge, wide enough for four modifiers.
    NSOutlineView *rows=[owner valueForKey:@"outlineView"];
    NSTableColumn *key=[rows tableColumnWithIdentifier:@"Key"],*name=[rows tableColumnWithIdentifier:@"Name"];
    REQUIRE(rows.headerView==nil && rows.style==NSTableViewStyleInset && [rows.backgroundColor isEqual:NSColor.clearColor] && rows.numberOfColumns==2 && key && name && !key.hidden && !name.hidden);
    REQUIRE(((NSCell *)key.dataCell).alignment==NSTextAlignmentRight && key.resizingMask==NSTableColumnNoResizing && (name.resizingMask&NSTableColumnAutoresizingMask));
    REQUIRE(key.width>=[@"⌃⌥⇧⌘W" sizeWithAttributes:@{NSFontAttributeName:((NSCell *)key.dataCell).font}].width+4);
    CheckListFits(owner);
    // Beside the sidebar, the rest of the window: from below the title bar to the bottom edge, to the trailing edge.
    NSRect m=[main convertRect:main.bounds toView:content];
    REQUIRE(NSMinX(m)>=NSMaxX(side_)-.5 && NSMinX(m)<=NSMaxX(side_)+split.splitView.dividerThickness+.5 && fabs(NSMaxX(m)-NSWidth(content.bounds))<.5);
    REQUIRE(NSMinY(m)==0 && fabs(NSMaxY(m)-top)<.5);
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
    for(NSButton *b in all) { REQUIRE(b.hidden); [targets addObject:b.target?:NSNull.null]; [actions addObject:NSStringFromSelector(b.action)?:@""]; b.target=recorder; b.action=@selector(hit:); }
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
// The list fits its sidebar at the narrowest, the first and the widest width of the sidebar
// that the window leaves beside the rest.
static void CheckListFitsSidebarWidths(TSMacroEditor *owner) {
    NSWindow *window=[owner valueForKey:@"window"]; NSSplitViewController *split=SplitOf(window); NSSplitView *splitView=split.splitView;
    CGFloat first=NSWidth(splitView.arrangedSubviews.firstObject.frame), room=NSWidth(window.frame)-splitView.dividerThickness-split.splitViewItems[1].minimumThickness;
    for(NSNumber *wanted in @[@160,@(first),@320]) {
        [splitView setPosition:wanted.doubleValue ofDividerAtIndex:0]; [window.contentView layoutSubtreeIfNeeded];
        REQUIRE(fabs(NSWidth(owner.sidebar.frame)-MIN(wanted.doubleValue,room))<.5);
        CheckListFits(owner);
    }
    [splitView setPosition:first ofDividerAtIndex:0]; [window.contentView layoutSubtreeIfNeeded];
    REQUIRE(fabs(NSWidth(owner.sidebar.frame)-first)<.5);
}
static NSEvent *Key(NSString *characters, NSString *ignoring, unsigned short code, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil
        characters:characters charactersIgnoringModifiers:ignoring isARepeat:NO keyCode:code];
}
// The shortcut is set as in Settings > Keyboard: a field takes the rows of the nib's key field and
// Shift/Option/Control boxes, records the keys pressed and removes them with ⊗.
static void CheckShortcutField(TSMacroEditor *owner) {
    NSView *host=owner.editorView;
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
    // As tall as a text field made now, and drawn as the nib's key field.
    REQUIRE(NSHeight(field.frame)==MAX(NSHeight(keyField.frame),[NSTextField textFieldWithString:@""].fittingSize.height) && field.display.bezelStyle==keyField.bezelStyle);
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
// Below the contents, as in the key binding list: Insert at the leading edge and the help
// button at the trailing edge, in one row between the contents and the shortcut.
static void CheckPlaceholderRow(TSMacroEditor *owner) {
    NSView *host=owner.editorView;
    NSPopUpButton *insert=owner.insertPlaceholderButton; NSButton *help=owner.placeholdersButton;
    NSScrollView *contents=[[owner valueForKey:@"contentTextView"] enclosingScrollView];
    REQUIRE(insert && help && insert.superview==host && help.superview==host && !insert.hidden && !help.hidden);
    REQUIRE(insert.pullsDown && [insert.itemArray.firstObject.title isEqual:NSLocalizedString(@"Insert",@"")] && help.bezelStyle==NSBezelStyleHelpButton);
    REQUIRE([help.accessibilityLabel isEqual:NSLocalizedString(@"Symbols",@"")] && [help.toolTip isEqual:help.accessibilityLabel]);
    REQUIRE(fabs(NSMinX(insert.frame)-NSMinX(contents.frame))<.5 && fabs(NSMaxX(help.frame)-NSMaxX(contents.frame))<.5);
    REQUIRE(NSMaxX(insert.frame)+12<=NSMinX(help.frame) && fabs(NSMidY(insert.frame)-NSMidY(help.frame))<=1);
    REQUIRE(NSMaxY(insert.frame)<=NSMinY(contents.frame)-5.5 && NSMaxY(help.frame)<=NSMinY(contents.frame)-5.5);
    REQUIRE(insert.fittingSize.width<=NSWidth(insert.frame)+.5 && NSHeight(contents.frame)>=64);
}
// What Insert offers and does, and what the help button lists: the placeholders of a TeX macro
// and those of an AppleScript macro, each kind enabled for its own macros only.
static void CheckPlaceholderControls(TSMacroEditor *owner) {
    NSWindow *window=[owner valueForKey:@"window"]; NSPopUpButton *insert=owner.insertPlaceholderButton;
    NSArray<NSString *> *teX=@[@"#SEL#",@"#INS#",@"#PASTE#",@"•",@"•‹›"], *appleScript=TSSyntaxMacroContentScanner.appleScriptPlaceholders;
    REQUIRE(appleScript.count==13);
    NSMutableArray *symbols=[NSMutableArray array], *headers=[NSMutableArray array];
    for(NSMenuItem *item in insert.menu.itemArray) {
        if(item.isSectionHeader) [headers addObject:item.title];
        if([item.representedObject isKindOfClass:NSString.class]) {
            [symbols addObject:item.representedObject];
            REQUIRE(item.target==owner && item.action==@selector(insertPlaceholder:));
            NSString *title=[item.representedObject isEqual:@"•‹›"]?NSLocalizedString(@"Mark with Note",@""):TSPlaceholderTokenTitle(item.representedObject);
            REQUIRE([item.title isEqual:title] && item.title.length>0);
        }
    }
    REQUIRE([headers isEqual:(@[@"TeX",@"AppleScript"])] && [symbols isEqual:[teX arrayByAddingObjectsFromArray:appleScript]]);
    for(NSString *symbol in appleScript) REQUIRE(![TSPlaceholderTokenTitle(symbol) isEqual:TSPlaceholderTokenTitle(@"•")]);
    NSTextView *contents=[owner valueForKey:@"contentTextView"];
    TSMacroTreeNode *macro=[TSMacroTreeNode nodeWithName:@"Macro" content:@"" key:@""];
    owner.previousItem=nil; contents.editable=NO; [owner syncPlaceholderControls]; REQUIRE(!insert.enabled);
    owner.previousItem=macro; contents.editable=YES; [owner syncPlaceholderControls]; REQUIRE(insert.enabled);
    for(NSString *text in @[@"\\begin{x}",@"--applescript direct\ntell application \"TeXShop\""]) {
        contents.string=text; BOOL isTeX=![text hasPrefix:@"--"];
        [owner menuNeedsUpdate:insert.menu];
        for(NSMenuItem *item in insert.menu.itemArray) if([item.representedObject isKindOfClass:NSString.class])
            REQUIRE(item.enabled==([appleScript containsObject:item.representedObject]?!isTeX:isTeX));
    }
    // Insert puts the placeholder as it is written at the selection; a mark with a note leaves the insertion point in the note.
    contents.string=@"\\begin{}"; contents.selectedRange=NSMakeRange(7,0);
    NSMenuItem *sel=[insert.menu itemAtIndex:[insert.menu indexOfItemWithRepresentedObject:@"#SEL#"]];
    [owner insertPlaceholder:sel];
    REQUIRE([contents.string isEqual:@"\\begin{#SEL#}"] && NSEqualRanges(contents.selectedRange,NSMakeRange(12,0)) && window.firstResponder==contents);
    [owner insertPlaceholder:[insert.menu itemAtIndex:[insert.menu indexOfItemWithRepresentedObject:@"•‹›"]]];
    REQUIRE([contents.string isEqual:@"\\begin{#SEL#•‹›}"] && NSEqualRanges(contents.selectedRange,NSMakeRange(14,0)));
    contents.editable=NO; [owner insertPlaceholder:sel]; REQUIRE([contents.string isEqual:@"\\begin{#SEL#•‹›}"]);
    contents.editable=YES; contents.string=@""; owner.previousItem=nil; [owner syncPlaceholderControls];
    // The help: a token and how it is written, for each placeholder of each kind, and how to use marks.
    NSView *list=[owner makePlaceholderListView]; [list setFrameSize:list.fittingSize]; [list layoutSubtreeIfNeeded];
    NSMutableArray<NSString *> *tokens=[NSMutableArray array], *written=[NSMutableArray array]; NSMutableArray *pending=[list.subviews mutableCopy]; BOOL marks=NO;
    while(pending.count){ NSView *v=pending.firstObject; [pending removeObjectAtIndex:0]; [pending addObjectsFromArray:v.subviews];
        if([v isKindOfClass:NSImageView.class]) [tokens addObject:((NSImageView *)v).image.accessibilityDescription?:@""];
        if([v isKindOfClass:NSTextField.class] && ((NSTextField *)v).isSelectable) [written addObject:((NSTextField *)v).stringValue];
        if([v isKindOfClass:NSButton.class] && ((NSButton *)v).action==@selector(showMarkHelp:)) marks=YES;
        if([v isKindOfClass:NSTextField.class]) REQUIRE([((NSTextField *)v).cell cellSize].width<=NSWidth(v.frame)+.5); }
    NSString *note=NSLocalizedString(@"note",@"");
    NSArray *expected=[@[@"#SEL#",@"#INS#",@"#PASTE#",@"•",[NSString stringWithFormat:@"•‹%@›",note]] arrayByAddingObjectsFromArray:appleScript];
    REQUIRE(marks && [[NSSet setWithArray:written] isEqual:[NSSet setWithArray:expected]] && written.count==expected.count && tokens.count==expected.count);
    for(NSString *symbol in appleScript) REQUIRE([tokens containsObject:TSPlaceholderTokenTitle(symbol)]);
    REQUIRE(NSWidth(list.frame)<1200 && NSHeight(list.frame)<700);
}
// The sidebar, the insert row and the dismissal row follow the Human Interface Guidelines.
static void CheckEditor(TSMacroEditor *owner, NSWindow *window) {
    [window.contentView layoutSubtreeIfNeeded];
    NSView *host=owner.editorView;
    if(getenv("TS_DUMP")) for(NSView *v in host.subviews) fprintf(stderr,"SUB %s %s hidden=%d %s\n",NSStringFromClass(v.class).UTF8String,NSStringFromRect(v.frame).UTF8String,v.hidden,[v isKindOfClass:NSTextField.class]?((NSTextField*)v).stringValue.UTF8String:"");
    NSScrollView *list=[[owner valueForKey:@"outlineView"] enclosingScrollView];
    NSButton *save=[owner valueForKey:@"saveButton"],*cancel=[owner valueForKey:@"cancelButton"],*test=[owner valueForKey:@"testButton"];
    REQUIRE(owner.sidebar && owner.listBar && host && owner.insertPlaceholderButton);
    CheckSidebar(owner,list);
    CheckShortcutField(owner);
    // The fields 20 points from the sidebar and from the window's trailing edge, as the rules of the Multiple Replace window.
    NSTextField *nameField=[owner valueForKey:@"nameField"]; NSScrollView *contents=[[owner valueForKey:@"contentTextView"] enclosingScrollView];
    for(NSView *v in @[nameField,contents]) REQUIRE(v.superview==host && fabs(NSMinX(v.frame)-20)<.5 && fabs(NSMaxX(v.frame)-(NSWidth(host.bounds)-20))<.5);
    // The name field as tall as a text field made now (as the shortcut field).
    REQUIRE(NSHeight(nameField.frame)>=[NSTextField textFieldWithString:@""].fittingSize.height-.5 && fabs(NSHeight(nameField.frame)-NSHeight(owner.shortcutField.frame))<.5);
    // The labels of the name and the contents stand above their fields, whole, and the shortcut's at their leading edge.
    NSTextField *nameLabel=nil;
    for(NSView *v in host.subviews) if([v isKindOfClass:NSTextField.class] && !((NSTextField *)v).isEditable && !v.hidden && v!=owner.shortcutStatus && v!=owner.shortcutLabel)
        for(NSView *f in @[nameField,contents]) if(NSMaxX(v.frame)>NSMinX(f.frame) && NSMinX(v.frame)<NSMaxX(f.frame) && NSMaxY(v.frame)>NSMaxY(f.frame) && NSMinY(v.frame)<NSMaxY(f.frame)+12) {
            if(NSMinY(v.frame)<NSMaxY(f.frame)-.5) fprintf(stderr,"LABEL %s %s into %s\n",((NSTextField *)v).stringValue.UTF8String,NSStringFromRect(v.frame).UTF8String,NSStringFromRect(f.frame).UTF8String);
            // Its text (some nibs end it with a line break) within its height.
            NSString *text=[((NSTextField *)v).stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if([text sizeWithAttributes:@{NSFontAttributeName:((NSTextField *)v).font}].height>NSHeight(v.frame)+.5) fprintf(stderr,"LABEL [%s] %s needs %.1f\n",text.UTF8String,NSStringFromRect(v.frame).UTF8String,[text sizeWithAttributes:@{NSFontAttributeName:((NSTextField *)v).font}].height);
            REQUIRE(NSMinY(v.frame)>=NSMaxY(f.frame)-.5 && [text sizeWithAttributes:@{NSFontAttributeName:((NSTextField *)v).font}].height<=NSHeight(v.frame)+.5);
            if(f==nameField) nameLabel=(NSTextField *)v;
        }
    REQUIRE(nameLabel && fabs(NSMinX(owner.shortcutLabel.frame)-NSMinX(nameLabel.frame))<.5);
    // Nothing of the column runs into the name field.
    for(NSView *v in host.subviews) if(v!=nameField && !v.hidden) {
        if(NSIntersectsRect(NSInsetRect(v.frame,.5,.5),nameField.frame)) fprintf(stderr,"INTO NAME %s %s\n",NSStringFromClass(v.class).UTF8String,NSStringFromRect(v.frame).UTF8String);
        REQUIRE(!NSIntersectsRect(NSInsetRect(v.frame,.5,.5),nameField.frame));
    }
    REQUIRE(owner.shortcutStatus.superview==host && fabs(NSMinX(owner.shortcutStatus.frame)-20)<.5 && fabs(NSMaxX(owner.shortcutStatus.frame)-(NSWidth(host.bounds)-20))<.5);
    REQUIRE(fabs(NSMaxX(save.frame)-(NSWidth(host.bounds)-20))<.5 && fabs(NSMinX(save.frame)-12-NSMaxX(cancel.frame))<.5 && NSWidth(save.frame)==NSWidth(cancel.frame));
    REQUIRE(fabs(NSMinX(test.frame)-20)<.5 && NSMaxX(test.frame)+12<=NSMinX(cancel.frame));
    for(NSButton *b in @[save,cancel,test]) REQUIRE(b.superview==host && b.fittingSize.width<=NSWidth(b.frame)+.5);
    // As the Multiple Replace window's buttons: AppKit's own style and height, 20 points above the bottom edge.
    for(NSButton *b in @[save,cancel,test]) REQUIRE(b.bezelStyle==NSBezelStyleAutomatic && fabs(NSHeight(b.frame)-b.fittingSize.height)<.5 && fabs(NSMinY(b.frame)-20)<.5);
    // Save is the preferred one (macOS 26); Return stays with the fields.
    if (@available(macOS 26.0, *)) REQUIRE(save.tintProminence==NSTintProminencePrimary && cancel.tintProminence!=NSTintProminencePrimary && test.tintProminence!=NSTintProminencePrimary);
    REQUIRE(save.keyEquivalent.length==0 && cancel.keyEquivalent.length==0 && test.keyEquivalent.length==0 && window.defaultButtonCell==nil);
    NSRect s=Drawn(host,save),c=Drawn(host,cancel); REQUIRE(NSMinX(s)-NSMaxX(c)>=11);
    CheckPlaceholderRow(owner);
    // What this layout adds or moves must not overlap anything; older labels in the
    // nibs may run into their fields by a few points.
    NSArray *placed=@[owner.insertPlaceholderButton,owner.placeholdersButton,owner.shortcutLabel,owner.shortcutField,save,cancel,test];
    for(NSView *a in placed) {
        REQUIRE(NSContainsRect(NSInsetRect(host.bounds,-.5,-.5),a.frame));
        for(NSView *b in host.subviews) if(a!=b && !b.hidden) {
            if(NSIntersectsRect(NSInsetRect(a.frame,.5,.5),NSInsetRect(b.frame,.5,.5))) fprintf(stderr,"OVERLAP %s %s / %s %s\n",NSStringFromClass(a.class).UTF8String,NSStringFromRect(a.frame).UTF8String,NSStringFromClass(b.class).UTF8String,NSStringFromRect(b.frame).UTF8String);
            REQUIRE(!NSIntersectsRect(NSInsetRect(a.frame,.5,.5),NSInsetRect(b.frame,.5,.5)));
        }
    }
}
// Return in the contents starts a new line and does not save, also when the window looks for a
// key equivalent first, as the application does: no button takes Return.
static void CheckReturnKey(TSMacroEditor *owner) {
    NSWindow *window=[owner valueForKey:@"window"]; NSButton *save=[owner valueForKey:@"saveButton"];
    NSTextView *contents=contentsOf(owner);
    id target=save.target; SEL action=save.action; ActionRecorder *recorder=[ActionRecorder new]; recorder.log=[NSMutableArray new];
    save.target=recorder; save.action=@selector(hit:);
    NSEvent *ret=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:window.windowNumber context:nil characters:@"\r" charactersIgnoringModifiers:@"\r" isARepeat:NO keyCode:36];
    BOOL editable=contents.editable; contents.editable=YES; contents.string=@"ab"; contents.selectedRange=NSMakeRange(1,0);
    REQUIRE([window makeFirstResponder:contents]);
    if(![window performKeyEquivalent:ret]) [window sendEvent:ret];
    if(![contents.string isEqual:@"a\nb"] || recorder.log.count) fprintf(stderr,"RETURN contents %s saves %lu\n",contents.string.UTF8String,(unsigned long)recorder.log.count);
    REQUIRE([contents.string isEqual:@"a\nb"] && recorder.log.count==0);
    contents.editable=editable; contents.string=@""; [window makeFirstResponder:window];
    save.target=target; save.action=action;
}
// The frames in the main part, to compare after the window has been resized and back.
static NSArray<NSValue *> *MainFrames(TSMacroEditor *owner) {
    NSMutableArray *frames=[NSMutableArray array];
    for(NSView *v in owner.editorView.subviews) [frames addObject:[NSValue valueWithRect:v.frame]];
    return frames;
}
// Windows that are never shown do not draw their buttons as in a key window, and a sidebar's
// material blends with what is behind the window, which an offscreen image does not have: the
// images are drawn as the Multiple Replace window's are (Tests/MultipleReplace.m), so the two
// compare. The selection of a source list is drawn as in a window that is not key.
static void DrawMaterialsWithinWindow(NSView *view) {
    NSMutableArray<NSView *> *pending=[view.subviews mutableCopy];
    while(pending.count) { NSView *v=pending.lastObject; [pending removeLastObject]; [pending addObjectsFromArray:v.subviews];
        if([v isKindOfClass:NSVisualEffectView.class]) ((NSVisualEffectView *)v).blendingMode=NSVisualEffectBlendingModeWithinWindow; }
}
static void WritePNG(NSView *view, NSAppearance *appearance, NSString *path) {
    [appearance performAsCurrentDrawingAppearance:^{
        view.appearance=appearance;
        DrawMaterialsWithinWindow(view); [view layoutSubtreeIfNeeded]; [view displayIfNeeded];
        NSBitmapImageRep *raw=[view bitmapImageRepForCachingDisplayInRect:view.bounds]; [view cacheDisplayInRect:view.bounds toBitmapImageRep:raw];
        NSImage *image=[[NSImage alloc] initWithSize:view.bounds.size]; [image lockFocus];
        [NSColor.windowBackgroundColor setFill]; NSRectFill(view.bounds);
        NSImage *cached=[[NSImage alloc] initWithSize:view.bounds.size]; [cached addRepresentation:raw];
        [cached drawInRect:view.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        NSMutableArray<NSView *> *pending=[view.subviews mutableCopy];
        while(pending.count) { NSView *v=pending.lastObject; [pending removeLastObject]; [pending addObjectsFromArray:v.subviews];
            if(!([v isKindOfClass:NSButton.class]||[v isKindOfClass:NSSegmentedControl.class]) || v.isHiddenOrHasHiddenAncestor) continue;
            NSRect frame=[v convertRect:v.bounds toView:view], visible=[v convertRect:v.visibleRect toView:view];
            if(NSIsEmptyRect(visible)) continue;
            [NSGraphicsContext saveGraphicsState];
            NSRectClip(NSMakeRect(NSMinX(visible),view.isFlipped?NSHeight(view.bounds)-NSMaxY(visible):NSMinY(visible),NSWidth(visible),NSHeight(visible)));
            NSAffineTransform *transform=[NSAffineTransform transform];
            [transform translateXBy:frame.origin.x yBy:view.isFlipped?NSHeight(view.bounds)-NSMaxY(frame):frame.origin.y];
            if(v.isFlipped){[transform translateXBy:0 yBy:frame.size.height];[transform scaleXBy:1 yBy:-1];}
            [transform concat]; [[(NSControl *)v cell] drawWithFrame:v.bounds inView:v]; [NSGraphicsContext restoreGraphicsState];
        }
        [image unlockFocus];
        NSBitmapImageRep *painted=[[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
        REQUIRE([[painted representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
    }];
}
// Items to show in the images and to fit in the list: a submenu with macros, macros with and
// without shortcuts, one with a long name.
static TSMacroTreeNode *MakeSampleRoot(TSMacroTreeNode **selected) {
    TSMacroTreeNode *root=[TSMacroTreeNode submenuNodeWithName:@"root"], *group=[TSMacroTreeNode submenuNodeWithName:@"Begin/End"];
    [group addChild:[TSMacroTreeNode nodeWithName:@"equation" content:@"\\begin{equation}\n#SEL##INS#\n\\end{equation}" key:@"E+ControlKey"]];
    [group addChild:[TSMacroTreeNode nodeWithName:@"align" content:@"\\begin{align}\n#SEL##INS#\n\\end{align}" key:@""]];
    [root addChild:group];
    *selected=[TSMacroTreeNode nodeWithName:@"MetaPost" content:@"\\begin{mplibcode}\n#SEL##INS#\n\\end{mplibcode}" key:@"M+ShiftKey"];
    [root addChild:*selected];
    [root addChild:[TSMacroTreeNode nodeWithName:@"\\ref{•‹label›}" content:@"\\ref{•‹label›}" key:@"R+ControlKey+OptionKey"]];
    [root addChild:[TSMacroTreeNode nodeWithName:@"A macro with a name longer than the sidebar is wide" content:@"x" key:@"W+ShiftKey+OptionKey+ControlKey"]];
    [root addChild:[TSMacroTreeNode nodeWithName:@"Insert Reference" content:@"x" key:@""]];
    return root;
}
// TS_CONTROLS: the kind of each control beside the sidebar and of those AppKit makes in code (as the Multiple Replace window's).
static void DumpControl(NSString *what, NSView *v) {
    NSMutableString *s=[NSMutableString stringWithFormat:@"CTRL %@ %@ frame %@ fit %@",what,NSStringFromClass(v.class),NSStringFromRect(v.frame),NSStringFromSize(v.fittingSize)];
    if([v isKindOfClass:NSControl.class]) { NSControl *c=(NSControl *)v; [s appendFormat:@" size %ld font %@ %.1f",(long)c.controlSize,c.font.fontName,c.font.pointSize]; }
    if([v isKindOfClass:NSButton.class]) { NSButton *b=(NSButton *)v; [s appendFormat:@" bezel %ld bordered %d key '%@' cell %@ bezelColor %@",(long)b.bezelStyle,b.bordered,[b.keyEquivalent stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"],NSStringFromClass(b.cell.class),b.bezelColor]; }
    if([v isKindOfClass:NSTextField.class]) { NSTextField *f=(NSTextField *)v; [s appendFormat:@" bezeled %d bezelStyle %ld bg %d %@ border %d",f.bezeled,(long)f.bezelStyle,f.drawsBackground,f.backgroundColor,f.bordered]; }
    if([v isKindOfClass:NSScrollView.class]) { NSScrollView *f=(NSScrollView *)v; [s appendFormat:@" borderType %ld bg %d",(long)f.borderType,f.drawsBackground]; }
    fprintf(stderr,"%s\n",s.UTF8String);
}
static void DumpControls(TSMacroEditor *owner) {
    NSWindow *w=[owner valueForKey:@"window"];
    fprintf(stderr,"WINDOW class %s style %lu toolbar %p tbstyle %ld transparent %d\n",NSStringFromClass(w.class).UTF8String,(unsigned long)w.styleMask,w.toolbar,(long)w.toolbarStyle,w.titlebarAppearsTransparent);
    for(NSView *v in owner.editorView.subviews) if(!v.hidden) DumpControl(@"macro",v);
    DumpControl(@"code-push",[NSButton buttonWithTitle:@"Replace All" target:nil action:NULL]);
    DumpControl(@"code-field",[NSTextField textFieldWithString:@"x"]);
    DumpControl(@"code-label",[NSTextField labelWithString:@"x"]);
    NSButton *help=[NSButton buttonWithTitle:@"" target:nil action:NULL]; help.bezelStyle=NSBezelStyleHelpButton; DumpControl(@"code-help",help);
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
    if(getenv("TS_DUMP")) fprintf(stderr,"BEFORE key %s shift %s contents %s\n",NSStringFromRect([[owner valueForKey:@"keyField"] frame]).UTF8String,NSStringFromRect([[owner valueForKey:@"shiftCheckBox"] frame]).UTF8String,NSStringFromRect([[[owner valueForKey:@"contentTextView"] enclosingScrollView] frame]).UTF8String);
    [owner installShortcutField];[owner installPlaceholderControls];
    [owner layoutDialogButtons];
    TSMacroTreeNode *shown=nil; SampleRoot=nil;
    NSOutlineView *rows=[owner valueForKey:@"outlineView"];
    CGFloat heightBefore=NSHeight(window.frame), minimumHeightBefore=window.minSize.height;
    [owner installSidebar];
    // The window keeps its top edge and height; it is at least as wide as both parts need.
    REQUIRE(fabs(NSMaxY(window.frame)-originalTop)<.1 && NSHeight(window.frame)==heightBefore && window.minSize.height==minimumHeightBefore);
    NSSplitViewController *split=SplitOf(window);
    REQUIRE(fabs(window.minSize.width-(160+split.splitView.dividerThickness+split.splitViewItems[1].minimumThickness))<.5 && NSWidth(window.frame)>=window.minSize.width);
    REQUIRE(fabs(NSWidth(owner.sidebar.frame)-240)<.5 || NSWidth(window.frame)<240+split.splitView.dividerThickness+split.splitViewItems[1].minimumThickness+.5);
    // The items come after the window is laid out, as openMacroEditor: gives the list its tree.
    if(round==0) { SampleRoot=MakeSampleRoot(&shown); [rows reloadData]; [rows expandItem:nil expandChildren:YES]; }
    { NSVisualEffectView *sidebar=owner.sidebar; NSView *main=owner.editorView; [owner installSidebar]; REQUIRE(owner.sidebar==sidebar && owner.editorView==main && SplitOf(window)==split); }
    CheckEditor(owner,window);
    if(getenv("TS_CONTROLS") && round==0) DumpControls(owner);
    CheckListFitsSidebarWidths(owner);
    if(round==0) { CheckShortcutBehavior(owner); CheckPlaceholderControls(owner); CheckReturnKey(owner); }
    NSArray<NSValue *> *openedFrames=MainFrames(owner);
    NSTextField *label=owner.shortcutStatus; NSView *host=owner.editorView;
    // The messages, as long as they come, wrap within the band, at this width and at the narrowest.
    NSMutableArray<NSString *> *messages=[NSMutableArray arrayWithObjects:@"This shortcut is inactive because it conflicts with “Typeset › plain TeX” (⇧⌘T).",@"このキーは“タイプセット › plain TeX”（⇧⌘T）と重なっているため無効です。",nil];
    for(NSString *format in @[@"This shortcut is inactive because macro “%@” (%@) uses it first.",@"This shortcut is inactive because it conflicts with “%@” (%@).",@"This shortcut conflicts with macro “%@” (%@), whose shortcut will be inactive because it appears later."])
        [messages addObject:[NSString stringWithFormat:NSLocalizedString(format,@""),[NSString stringWithFormat:@"%@ › Begin/End › equation*",NSLocalizedString(@"Macros",@"")],@"⌃⌥⇧⌘W"]];
    NSRect frame=window.frame;
    for(int narrow=0;narrow<2;narrow++) {
      if(narrow) { NSRect n=window.frame; n.size.width=window.minSize.width; [window setFrame:n display:NO]; [window.contentView layoutSubtreeIfNeeded]; }
      for (NSString *text in messages)
      for (NSAppearanceName mode in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        host.appearance=[NSAppearance appearanceNamed:mode];label.stringValue=text;
        REQUIRE(NSContainsRect(host.bounds,label.frame));
        CGFloat needed=[label.cell cellSizeForBounds:NSMakeRect(0,0,label.bounds.size.width,CGFLOAT_MAX)].height;
        if(needed>label.bounds.size.height) fprintf(stderr,"MESSAGE %.0f > %.0f at width %.0f: %s\n",needed,label.bounds.size.height,label.bounds.size.width,text.UTF8String);
        REQUIRE(needed<=label.bounds.size.height);
        for (NSView *v in host.subviews) if(v!=label && !v.hidden) { if([v isKindOfClass:NSScrollView.class]) REQUIRE(NSContainsRect(host.bounds,v.frame)); if(NSIntersectsRect(label.frame,v.frame)) fprintf(stderr,"OVERLAP %s %s label %s\n",NSStringFromClass(v.class).UTF8String,NSStringFromRect(v.frame).UTF8String,NSStringFromRect(label.frame).UTF8String); REQUIRE(!NSIntersectsRect(label.frame,v.frame)); }
        NSBitmapImageRep *rep=[window.contentView bitmapImageRepForCachingDisplayInRect:[window.contentView bounds]];[window.contentView cacheDisplayInRect:[window.contentView bounds] toBitmapImageRep:rep];
        REQUIRE(rep.pixelsWide>400 && rep.pixelsHigh>300 && !window.visible);
      }
    }
    label.stringValue=@""; host.appearance=nil;
    [window setFrame:frame display:NO]; [window.contentView layoutSubtreeIfNeeded];
    { NSRect again=window.frame; [owner installShortcutStatus]; REQUIRE(NSEqualRects(again,window.frame)); }
    smallest=window.frame; smallest.size.height=window.minSize.height; [window setFrame:smallest display:NO];
    CheckEditor(owner,window);
    { NSRect narrow=window.frame; narrow.size.width=window.minSize.width; [window setFrame:narrow display:NO]; CheckEditor(owner,window);
      // At the narrowest, the sidebar at its narrowest and the rest as narrow as it can be.
      REQUIRE(fabs(NSWidth(owner.sidebar.frame)-160)<.5 && fabs(NSWidth(host.frame)-split.splitViewItems[1].minimumThickness)<.5); }
    for (NSView *v in host.subviews) if([v isKindOfClass:NSScrollView.class]) {
        REQUIRE(NSContainsRect(host.bounds,v.frame));
        REQUIRE(NSHeight(v.frame)+.1 >= [originalMinimumHeights[[NSValue valueWithNonretainedObject:v]] doubleValue]);
    }
    // The list keeps its minimum height in the sidebar, above the bar.
    NSScrollView *listScroll=[[owner valueForKey:@"outlineView"] enclosingScrollView];
    REQUIRE(originalMinimumHeights[[NSValue valueWithNonretainedObject:listScroll]] && NSHeight(listScroll.frame)+.1 >= [originalMinimumHeights[[NSValue valueWithNonretainedObject:listScroll]] doubleValue]);
    if(round==0) {
        printf("minimum window %.0f × %.0f; editor heights",window.minSize.width,window.minSize.height);
        for (NSView *v in host.subviews) if([v isKindOfClass:NSScrollView.class]) printf(" %.0f",NSHeight(v.frame));
        printf(" list %.0f\n",NSHeight(listScroll.frame));
    }
    // Larger, then back: the fields follow the window and come back where they were.
    { NSRect large=frame; large.size.width+=260; large.size.height+=160; large.origin.y-=160; [window setFrame:large display:NO]; CheckEditor(owner,window); }
    [window setFrame:frame display:NO]; [window.contentView layoutSubtreeIfNeeded];
    NSArray<NSValue *> *backFrames=MainFrames(owner);
    for(NSUInteger i=0;i<openedFrames.count;i++) { if(!NSEqualRects(openedFrames[i].rectValue,backFrames[i].rectValue)) fprintf(stderr,"MOVED %s -> %s\n",NSStringFromRect(openedFrames[i].rectValue).UTF8String,NSStringFromRect(backFrames[i].rectValue).UTF8String); REQUIRE(NSEqualRects(openedFrames[i].rectValue,backFrames[i].rectValue)); }
    // Images: the window as it opens with a macro selected (its name, contents, shortcut and ⊗, and a
    // conflict), while the field waits for keys, larger and at its smallest, light and dark.
    if(getenv("TS_RENDER_DIR") && round==0) {
        NSString *nibPath=@(argv[1]);
        NSString *name=[[nibPath stringByDeletingLastPathComponent].stringByDeletingLastPathComponent.lastPathComponent stringByDeletingPathExtension];
        if([nibPath.lastPathComponent containsString:@"101300"]) name=[name stringByAppendingString:@"-10.13"];
        NSInteger row=[rows rowForItem:shown]; REQUIRE(row>=0);
        [rows expandItem:nil expandChildren:YES];
        row=[rows rowForItem:shown]; [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        owner.previousItem=shown; owner.pendingShortcutKey=shown.key; [owner syncShortcutField];
        [[owner valueForKey:@"nameField"] setStringValue:shown.name]; [contentsOf(owner) setString:shown.content];
        label.stringValue=[NSString stringWithFormat:NSLocalizedString(@"This shortcut is inactive because it conflicts with “%@” (%@).",@""),@"MetaPost",@"⇧⌘M"];
        struct { NSString *tag; CGFloat dw, dh; BOOL recording, smallest; } states[]={{@"opened",0,0,NO,NO},{@"recording",0,0,YES,NO},{@"resized",260,160,NO,NO},{@"smallest",0,0,NO,YES}};
        for(size_t i=0;i<sizeof states/sizeof *states;i++) for (NSAppearanceName mode in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
            NSRect f=frame; f.size.width+=states[i].dw; f.size.height+=states[i].dh; f.origin.y-=states[i].dh;
            if(states[i].smallest) f.size=window.minSize;
            [window setFrame:f display:NO]; [window.contentView layoutSubtreeIfNeeded];
            if(states[i].recording) [owner.shortcutField beginRecording]; else [owner.shortcutField endRecording];
            WritePNG(window.contentView,[NSAppearance appearanceNamed:mode],[NSString stringWithFormat:@"%s/%@-%@-%@.png",getenv("TS_RENDER_DIR"),name,states[i].tag,[mode isEqual:NSAppearanceNameAqua]?@"light":@"dark"]);
            // As it opens, also with its title bar (the window's frame view): the title and the window's buttons.
            if(i==0) { WritePNG(window.contentView.superview,[NSAppearance appearanceNamed:mode],[NSString stringWithFormat:@"%s/%@-window-%@.png",getenv("TS_RENDER_DIR"),name,[mode isEqual:NSAppearanceNameAqua]?@"light":@"dark"]); window.contentView.superview.appearance=nil; }
        }
        [owner.shortcutField endRecording]; window.contentView.appearance=nil;
        [window setFrame:frame display:NO]; owner.previousItem=nil; owner.pendingShortcutKey=@""; [owner syncShortcutField]; label.stringValue=@"";
    }
    [window setFrame:frame display:NO];
    if(round==1) { NSRect resized=window.frame; resized.size.height+=80; [window setFrame:resized display:NO]; }
    savedHeight=window.frame.size.height;
    [window saveFrameUsingName:@"Macro Editor"];
    REQUIRE([[memoryDefaults stringForKey:@"NSWindow Frame Macro Editor"] length]>0);
    window.releasedWhenClosed=NO; [window close];
    }
    printf("PASS: %s sidebar, status band: bounds, wrapping, control separation, resizing, idempotence, offscreen light/dark rendering\n",argv[1]);
} return 0; }
