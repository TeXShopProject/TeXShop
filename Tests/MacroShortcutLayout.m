// Instantiate existing localized nibs offscreen and run the production layout of the macro editor: the sidebar,
// the contents, the status band, the shortcut field and the placeholder row; the keys, and renaming in the list.
#import "TSMacroEditor.h"
#import "TSMacroOutlineController.h"
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
#import <objc/message.h>
#import "MemoryDefaults.h"
#define COLUMNID_NAME @"Name"
#define COLUMNID_KEY @"Key"
static TSMemoryDefaults *memoryDefaults;
static id StandardDefaults(id self, SEL cmd) { return memoryDefaults; }
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
static int reflections, pendingUpdates;
// The editor of the window being checked (the outline controller asks the shared editor).
static TSMacroEditor *Editor;
@implementation TSMacroEditor
#include "MacroStatusLayout.inc"
// The rest of the editor: what the shortcut field and the list ask of it.
+ (id)sharedInstance { return Editor; }
- (void)updatePendingShortcutStatus { pendingUpdates++; }
- (void)reflectChangesInEditor:(BOOL)force { reflections++; [self syncShortcutField]; }
- (void)outlineViewItemsChanged:(NSNotification *)note { [self setValue:@YES forKey:@"dataTouched"]; }
- (NSString *)shortcutConflictForNode:(TSMacroTreeNode *)node { return nil; }
@end
// The list shows the items of SampleRoot (none unless set), as the editor's outline controller does, and takes a
// name typed in it with the controller's own code (MacroOutlineEditing.inc); the list and its cells are the
// application's (MacroOutlineView.inc).
static TSMacroTreeNode *SampleRoot;
@implementation TSMacroOutlineController
- (void)setValue:(id)v forUndefinedKey:(NSString *)key {}
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item { return [(item ?: SampleRoot) numberOfChildren]; }
- (id)outlineView:(NSOutlineView *)view child:(NSInteger)index ofItem:(id)item { return [(item ?: SampleRoot) childAtIndex:index]; }
- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item { return [item isExpandable]; }
- (id)outlineView:(NSOutlineView *)view objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item {
    if ([item isSeparator]) return @"";
    return [column.identifier isEqual:@"Key"] ? getMenuItemString([item key]) : [item name];
}
- (void)outlineView:(NSOutlineView *)view willDisplayCell:(NSCell *)cell forTableColumn:(NSTableColumn *)column item:(id)item {
    if ([column.identifier isEqual:@"Name"] && [cell isKindOfClass:ImageAndTextCell.class]) ((ImageAndTextCell *)cell).image1=[item isSeparator]?TSMacroSeparatorImage(column.width-8):nil;
}
#include "MacroOutlineEditing.inc"
@end
#include "MacroOutlineView.inc"
// The names in cells that can be edited, as the outline controller's awakeFromNib makes them.
static void UseNameCells(TSMacroEditor *owner) {
    NSTableColumn *name=[[owner valueForKey:@"outlineView"] tableColumnWithIdentifier:@"Name"];
    ImageAndTextCell *cell=[ImageAndTextCell new]; cell.editable=YES; name.dataCell=cell;
}
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
// The line under the contents.
static NSBox *ContentsLine(TSMacroEditor *owner) {
    for(NSView *v in owner.editorView.subviews) if([v.identifier isEqual:@"macro.contents.line"]) return (NSBox *)v;
    return nil;
}
// Below the contents and their line, as in the key binding list: Insert at the leading edge and the help
// button at the trailing edge, 20 points from the edges, in one row between the line and the shortcut.
static void CheckPlaceholderRow(TSMacroEditor *owner) {
    NSView *host=owner.editorView;
    NSPopUpButton *insert=owner.insertPlaceholderButton; NSButton *help=owner.placeholdersButton;
    NSScrollView *contents=[contentsOf(owner) enclosingScrollView]; NSBox *line=ContentsLine(owner);
    NSRect drawn=[line alignmentRectForFrame:line.frame];
    REQUIRE(insert && help && insert.superview==host && help.superview==host && !insert.hidden && !help.hidden);
    REQUIRE(insert.pullsDown && [insert.itemArray.firstObject.title isEqual:NSLocalizedString(@"Insert",@"")] && help.bezelStyle==NSBezelStyleHelpButton);
    REQUIRE([help.accessibilityLabel isEqual:NSLocalizedString(@"Symbols",@"")] && [help.toolTip isEqual:help.accessibilityLabel]);
    REQUIRE(fabs(NSMinX(insert.frame)-20)<.5 && fabs(NSMaxX(help.frame)-(NSWidth(host.bounds)-20))<.5);
    REQUIRE(NSMaxX(insert.frame)+12<=NSMinX(help.frame) && fabs(NSMidY(insert.frame)-NSMidY(help.frame))<=1);
    REQUIRE(fabs(NSMinY(drawn)-MAX(NSMaxY(insert.frame),NSMaxY(help.frame))-10)<.5);
    REQUIRE(insert.fittingSize.width<=NSWidth(insert.frame)+.5 && NSHeight(contents.frame)>=64);
}
// The contents without the name field and the labels: from the title bar, the sidebar and the window's
// trailing edge, without a border, down to a line the width of the part beside the sidebar; the text a
// little inside; named for VoiceOver by the label they had.
static void CheckContents(TSMacroEditor *owner, NSWindow *window) {
    NSView *main=owner.editorView, *content=window.contentView; NSTextView *text=contentsOf(owner); NSScrollView *scroll=text.enclosingScrollView;
    NSRect c=[scroll convertRect:scroll.bounds toView:content], m=[main convertRect:main.bounds toView:content];
    CGFloat top=NSMaxY([content convertRect:window.contentLayoutRect fromView:nil]);
    if(fabs(NSMaxY(c)-top)>=.5 || fabs(NSMinX(c)-NSMinX(m))>=.5 || fabs(NSMaxX(c)-NSWidth(content.bounds))>=.5) fprintf(stderr,"CONTENTS %s in %s, top %.1f\n",NSStringFromRect(c).UTF8String,NSStringFromRect(m).UTF8String,top);
    REQUIRE(scroll.superview==main && fabs(NSMaxY(c)-top)<.5 && fabs(NSMinX(c)-NSMinX(m))<.5 && fabs(NSMaxX(c)-NSWidth(content.bounds))<.5);
    REQUIRE(scroll.borderType==NSNoBorder && !scroll.drawsBackground && (scroll.autoresizingMask&NSViewWidthSizable) && (scroll.autoresizingMask&NSViewHeightSizable));
    REQUIRE(NSEqualSizes(text.textContainerInset,NSMakeSize(8,8)) && text.accessibilityLabel.length>0 && ![text.accessibilityLabel hasSuffix:@":"] && ![text.accessibilityLabel hasSuffix:@"："]);
    NSBox *line=ContentsLine(owner); NSRect drawn=[line alignmentRectForFrame:line.frame];
    REQUIRE(line && line.boxType==NSBoxSeparator && fabs(NSMaxY(drawn)-NSMinY(scroll.frame))<.5 && NSMinX(drawn)==0 && fabs(NSWidth(drawn)-NSWidth(main.bounds))<.5);
    REQUIRE([[owner valueForKey:@"nameField"] isHidden]);
    // No label is left but the shortcut's and the message; nothing runs into the contents.
    for(NSView *v in main.subviews) if(!v.hidden && v!=scroll && v!=line) {
        if([v isKindOfClass:NSTextField.class] && v!=owner.shortcutStatus && v!=owner.shortcutLabel) { fprintf(stderr,"LABEL LEFT %s\n",((NSTextField *)v).stringValue.UTF8String); REQUIRE(NO); }
        REQUIRE(!NSIntersectsRect(NSInsetRect(v.frame,.5,.5),scroll.frame));
    }
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
    CheckContents(owner,window);
    NSScrollView *scroll=[contentsOf(owner) enclosingScrollView];
    // The shortcut's label 20 points from the sidebar, as Insert and the message.
    REQUIRE(fabs(NSMinX(owner.shortcutLabel.frame)-20)<3.5);
    REQUIRE(owner.shortcutStatus.superview==host && fabs(NSMinX(owner.shortcutStatus.frame)-20)<.5 && fabs(NSMaxX(owner.shortcutStatus.frame)-(NSWidth(host.bounds)-20))<.5);
    REQUIRE(fabs(NSMaxX(save.frame)-(NSWidth(host.bounds)-20))<.5 && fabs(NSMinX(save.frame)-12-NSMaxX(cancel.frame))<.5 && NSWidth(save.frame)==NSWidth(cancel.frame));
    REQUIRE(fabs(NSMinX(test.frame)-20)<.5 && NSMaxX(test.frame)+12<=NSMinX(cancel.frame));
    for(NSButton *b in @[save,cancel,test]) REQUIRE(b.superview==host && b.fittingSize.width<=NSWidth(b.frame)+.5);
    // As the Multiple Replace window's buttons: AppKit's own style and height, 20 points above the bottom edge.
    for(NSButton *b in @[save,cancel,test]) REQUIRE(b.bezelStyle==NSBezelStyleAutomatic && fabs(NSHeight(b.frame)-b.fittingSize.height)<.5 && fabs(NSMinY(b.frame)-20)<.5);
    // Save is the default button, blue as Replace All of the Multiple Replace window.
    REQUIRE([save.keyEquivalent isEqual:@"\r"] && [cancel.keyEquivalent isEqual:@"\033"] && test.keyEquivalent.length==0 && window.defaultButtonCell==save.cell && owner.contentsKeyMonitor);
    // Interface text in the system font (the Chinese nibs name STHeiti), the hidden controls too.
    NSMutableArray<NSView *> *all=[NSMutableArray arrayWithObject:window.contentView];
    while(all.count){ NSView *v=all.lastObject; [all removeLastObject]; [all addObjectsFromArray:v.subviews];
        if([v isKindOfClass:NSControl.class] && ((NSControl *)v).font) { if(![((NSControl *)v).font.fontName hasPrefix:@"."]) fprintf(stderr,"FONT %s %s\n",NSStringFromClass(v.class).UTF8String,((NSControl *)v).font.fontName.UTF8String); REQUIRE([((NSControl *)v).font.fontName hasPrefix:@"."]); } }
    NSRect s=Drawn(host,save),c=Drawn(host,cancel); REQUIRE(NSMinX(s)-NSMaxX(c)>=11);
    CheckPlaceholderRow(owner);
    // What this layout adds or moves must not overlap anything; older labels in the
    // nibs may run into their fields by a few points.
    NSArray *placed=@[scroll,owner.insertPlaceholderButton,owner.placeholdersButton,owner.shortcutLabel,owner.shortcutField,save,cancel,test];
    for(NSView *a in placed) {
        REQUIRE(NSContainsRect(NSInsetRect(host.bounds,-.5,-.5),a.frame));
        for(NSView *b in host.subviews) if(a!=b && !b.hidden && b!=ContentsLine(owner)) {
            if(NSIntersectsRect(NSInsetRect(a.frame,.5,.5),NSInsetRect(b.frame,.5,.5))) fprintf(stderr,"OVERLAP %s %s / %s %s\n",NSStringFromClass(a.class).UTF8String,NSStringFromRect(a.frame).UTF8String,NSStringFromClass(b.class).UTF8String,NSStringFromRect(b.frame).UTF8String);
            REQUIRE(!NSIntersectsRect(NSInsetRect(a.frame,.5,.5),NSInsetRect(b.frame,.5,.5)));
        }
    }
}
// Keys as the application sends them: the local monitors first (the editor's keyForContents:),
// then the window's key equivalents (the buttons), then the first responder.
static void SendKey(TSMacroEditor *owner, NSWindow *window, NSEvent *event) {
    NSEvent *passed=[owner keyForContents:event];
    if(passed && ![window performKeyEquivalent:passed]) [window sendEvent:passed];
}
// The field editor while an item of the list is renamed, or nil.
static NSTextView *Renaming(NSWindow *window, NSOutlineView *rows) {
    NSTextView *editor=(NSTextView *)window.firstResponder;
    return [editor isKindOfClass:NSTextView.class] && editor.isFieldEditor && editor.delegate==rows ? editor : nil;
}
static NSEvent *KeyIn(NSWindow *window, NSString *c, unsigned short code, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:window.windowNumber context:nil characters:c charactersIgnoringModifiers:c isARepeat:NO keyCode:code];
}
static TSMacroTreeNode *MakeSampleRoot(TSMacroTreeNode **selected, TSMacroTreeNode **separator);
// The keys, where the keyboard focus is:
// - the list: Return and Enter rename the selected item (not a separator, nor several items), Escape does nothing;
// - an item renamed: Return and Enter keep the new name (an empty one keeps the old), Escape the old one, a focus
//   change the new one; none closes the window;
// - the contents: Return and Enter start a new line, Escape does not cancel;
// - elsewhere (the shortcut field when it does not wait for keys): Return saves, Escape cancels.
// A double click never edits a name; the field of the name is as wide as the name and grows with it.
static void CheckKeys(TSMacroEditor *owner) {
    NSWindow *window=[owner valueForKey:@"window"]; NSOutlineView *rows=[owner valueForKey:@"outlineView"];
    NSButton *save=[owner valueForKey:@"saveButton"],*cancel=[owner valueForKey:@"cancelButton"];
    NSTextView *contents=contentsOf(owner);
    TSMacroTreeNode *kept=SampleRoot,*macro=nil,*separator=nil; SampleRoot=MakeSampleRoot(&macro,&separator);
    [rows reloadData]; [rows expandItem:nil expandChildren:YES]; [window.contentView layoutSubtreeIfNeeded];
    id targets[]={save.target,cancel.target}; SEL actions[]={save.action,cancel.action};
    ActionRecorder *recorder=[ActionRecorder new]; recorder.log=[NSMutableArray new];
    for(NSButton *b in @[save,cancel]) { b.target=recorder; b.action=@selector(hit:); }
    [owner setValue:@NO forKey:@"dataTouched"];
    NSInteger row=[rows rowForItem:macro]; [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    REQUIRE([window makeFirstResponder:rows]); SendKey(owner,window,KeyIn(window,@"\r",36,0));
    NSTextView *editor=Renaming(window,rows);
    REQUIRE(editor && rows.editedRow==row && rows.editedColumn==[rows columnWithIdentifier:@"Name"] && [editor.string isEqual:@"MetaPost"] && NSEqualRanges(editor.selectedRange,NSMakeRange(0,8)) && recorder.log.count==0);
    // The field: the name's width, growing with what is typed up to the name's column, at least a few letters wide.
    NSFont *font=editor.font; NSView *clip=editor.superview; NSRect cell=[rows frameOfCellAtColumn:rows.editedColumn row:row];
    CGFloat wanted=ceil([@"MetaPost" sizeWithAttributes:@{NSFontAttributeName:font}].width)+10;
    if(fabs(NSWidth(clip.frame)-wanted)>1) fprintf(stderr,"RENAME FIELD %.1f wide, the name needs %.1f (column %.1f)\n",NSWidth(clip.frame),wanted,NSWidth(cell));
    REQUIRE(fabs(NSWidth(clip.frame)-wanted)<=1 && NSMaxX(clip.frame)<=NSMaxX(cell)+.5);
    [editor insertText:@"MetaPost with a longer name" replacementRange:NSMakeRange(0,editor.string.length)];
    CGFloat longer=MIN(NSMaxX(cell)-NSMinX(clip.frame),ceil([@"MetaPost with a longer name" sizeWithAttributes:@{NSFontAttributeName:font}].width)+10);
    REQUIRE(fabs(NSWidth(clip.frame)-longer)<=1 && NSWidth(clip.frame)>wanted);
    [editor insertText:@"A name much longer than the list is wide, and longer again than that" replacementRange:NSMakeRange(0,editor.string.length)];
    REQUIRE(fabs(NSMaxX(clip.frame)-NSMaxX(cell))<=.5);
    [editor insertText:@"M" replacementRange:NSMakeRange(0,editor.string.length)];
    REQUIRE(fabs(NSWidth(clip.frame)-48)<=.5);
    // Escape: the old name, the list focused, the window open, nothing to save.
    SendKey(owner,window,KeyIn(window,@"\x1b",53,0));
    REQUIRE(!Renaming(window,rows) && window.firstResponder==rows && [macro.name isEqual:@"MetaPost"] && recorder.log.count==0 && ![[owner valueForKey:@"dataTouched"] boolValue]);
    // Return: the new name kept, the list focused, not saved.
    SendKey(owner,window,KeyIn(window,@"\r",36,0)); editor=Renaming(window,rows); REQUIRE(editor);
    [editor insertText:@"MetaPost 2" replacementRange:NSMakeRange(0,editor.string.length)];
    SendKey(owner,window,KeyIn(window,@"\r",36,0));
    REQUIRE(!Renaming(window,rows) && window.firstResponder==rows && [macro.name isEqual:@"MetaPost 2"] && recorder.log.count==0 && [[owner valueForKey:@"dataTouched"] boolValue]);
    // Enter as Return; a name of spaces keeps the old one.
    SendKey(owner,window,KeyIn(window,@"\x03",76,0)); editor=Renaming(window,rows); REQUIRE(editor);
    [editor insertText:@"  " replacementRange:NSMakeRange(0,editor.string.length)];
    SendKey(owner,window,KeyIn(window,@"\x03",76,0));
    REQUIRE(!Renaming(window,rows) && [macro.name isEqual:@"MetaPost 2"] && recorder.log.count==0);
    // Another control taking the focus keeps the name typed.
    SendKey(owner,window,KeyIn(window,@"\r",36,0)); editor=Renaming(window,rows); REQUIRE(editor);
    [editor insertText:@"MetaPost" replacementRange:NSMakeRange(0,editor.string.length)];
    REQUIRE([window makeFirstResponder:contents] && !Renaming(window,rows) && [macro.name isEqual:@"MetaPost"]);
    // Only the editor's renaming edits a name: a double click does not.
    REQUIRE(![rows.delegate outlineView:rows shouldEditTableColumn:[rows tableColumnWithIdentifier:@"Name"] item:macro]);
    // A separator has no name: Return in the list does nothing more than beep.
    row=[rows rowForItem:separator]; [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    REQUIRE([window makeFirstResponder:rows]); SendKey(owner,window,KeyIn(window,@"\r",36,0));
    REQUIRE(!Renaming(window,rows) && window.firstResponder==rows && recorder.log.count==0 && ![owner beginRenamingSelectedItem]);
    // Several items: no renaming.
    [rows selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1,2)] byExtendingSelection:NO];
    SendKey(owner,window,KeyIn(window,@"\r",36,0)); REQUIRE(!Renaming(window,rows) && recorder.log.count==0);
    // Escape in the list does nothing.
    SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); REQUIRE(recorder.log.count==0 && window.firstResponder==rows && !Renaming(window,rows));
    // The contents keep Return, Enter and Escape.
    BOOL editable=contents.editable; contents.editable=YES;
    for(NSString *c in @[@"\r",@"\x03"]) {
        contents.string=@"ab"; contents.selectedRange=NSMakeRange(1,0);
        REQUIRE([window makeFirstResponder:contents]); SendKey(owner,window,KeyIn(window,c,[c isEqual:@"\r"]?36:76,0));
        if(![contents.string isEqual:@"a\nb"] || recorder.log.count) fprintf(stderr,"RETURN contents %s buttons %s\n",contents.string.UTF8String,recorder.log.description.UTF8String);
        REQUIRE([contents.string isEqual:@"a\nb"] && recorder.log.count==0);
    }
    contents.string=@"ab"; SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); REQUIRE(recorder.log.count==0 && [contents.string hasPrefix:@"ab"]);
    // Elsewhere: Return saves, Escape cancels.
    BOOL enabled=owner.shortcutField.enabled; owner.shortcutField.enabled=YES; REQUIRE([window makeFirstResponder:owner.shortcutField]);
    SendKey(owner,window,KeyIn(window,@"\r",36,0)); SendKey(owner,window,KeyIn(window,@"\x1b",53,0));
    REQUIRE([recorder.log isEqual:(@[save.title,cancel.title])]);
    // Other keys, and Command-Return, are not the monitor's.
    REQUIRE([window makeFirstResponder:contents]);
    NSEvent *letter=KeyIn(window,@"x",7,0); REQUIRE([owner keyForContents:letter]==letter);
    NSEvent *commandReturn=KeyIn(window,@"\r",36,NSEventModifierFlagCommand); REQUIRE([owner keyForContents:commandReturn]==commandReturn);
    owner.shortcutField.enabled=enabled; contents.editable=editable; contents.string=@""; [window makeFirstResponder:window];
    save.target=targets[0]; save.action=actions[0]; cancel.target=targets[1]; cancel.action=actions[1];
    [owner setValue:@NO forKey:@"dataTouched"];
    SampleRoot=kept; [rows reloadData]; [rows expandItem:nil expandChildren:YES];
}
// A second click renames only on the name of the selected item: not after the name, not on the shortcut,
// not on a separator (TSMacroOutlineView's isNameAtPoint:row:).
static void CheckSecondClick(TSMacroEditor *owner) {
    NSOutlineView *rows=[owner valueForKey:@"outlineView"];
    TSMacroTreeNode *kept=SampleRoot,*macro=nil,*separator=nil; SampleRoot=MakeSampleRoot(&macro,&separator);
    [rows reloadData]; [rows expandItem:nil expandChildren:YES]; [rows.window.contentView layoutSubtreeIfNeeded];
    BOOL (*named)(id,SEL,NSPoint,NSInteger)=(BOOL (*)(id,SEL,NSPoint,NSInteger))objc_msgSend; SEL at=@selector(isNameAtPoint:row:);
    NSInteger row=[rows rowForItem:macro], name=[rows columnWithIdentifier:@"Name"], key=[rows columnWithIdentifier:@"Key"];
    NSRect cell=[rows frameOfCellAtColumn:name row:row];
    CGFloat text=[@"MetaPost" sizeWithAttributes:@{NSFontAttributeName:((NSCell *)[rows tableColumnWithIdentifier:@"Name"].dataCell).font}].width;
    REQUIRE(named(rows,at,NSMakePoint(NSMinX(cell)+text/2,NSMidY(cell)),row));
    REQUIRE(!named(rows,at,NSMakePoint(NSMinX(cell)+text+20,NSMidY(cell)),row) && NSMinX(cell)+text+20<NSMaxX(cell));
    NSRect shortcut=[rows frameOfCellAtColumn:key row:row];
    REQUIRE(!named(rows,at,NSMakePoint(NSMidX(shortcut),NSMidY(shortcut)),row));
    NSInteger line=[rows rowForItem:separator]; NSRect lineCell=[rows frameOfCellAtColumn:name row:line];
    REQUIRE(!named(rows,at,NSMakePoint(NSMinX(lineCell)+5,NSMidY(lineCell)),line));
    SampleRoot=kept; [rows reloadData]; [rows expandItem:nil expandChildren:YES];
}
// The line of a separator: one line of the separator color, light and dark, nothing above or below.
static void CheckSeparatorImage(void) {
    NSImage *image=TSMacroSeparatorImage(40);
    REQUIRE(image.size.width==40 && image.size.height==3);
    for(NSAppearanceName mode in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) [[NSAppearance appearanceNamed:mode] performAsCurrentDrawingAppearance:^{
        NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:3 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
        [image drawInRect:NSMakeRect(0,0,40,3)]; [NSGraphicsContext restoreGraphicsState];
        NSColor *line=[[rep colorAtX:20 y:1] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace], *want=[NSColor.separatorColor colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        REQUIRE([rep colorAtX:20 y:0].alphaComponent<.01 && [rep colorAtX:20 y:2].alphaComponent<.01 && line.alphaComponent>.05);
        REQUIRE(fabs(line.alphaComponent-want.alphaComponent)<.05 && fabs(line.redComponent-want.redComponent)<.05);
    }];
}
// The frames in the main part, to compare after the window has been resized and back.
static NSArray<NSValue *> *MainFrames(TSMacroEditor *owner) {
    NSMutableArray *frames=[NSMutableArray array];
    for(NSView *v in owner.editorView.subviews) [frames addObject:[NSValue valueWithRect:v.frame]];
    return frames;
}
// Images: the window is drawn as the key window of the active application (it is never shown), so that the default
// button, the selection of the focused list and the field of a renamed item look as they do on screen; a sidebar's
// material blends within the window, which an offscreen image has nothing behind.
static BOOL Yes(id self, SEL cmd) { return YES; }
static void DrawAsKeyWindow(void) {
    for(NSString *name in @[@"isKeyWindow",@"isMainWindow",@"hasKeyAppearance",@"hasMainAppearance",@"_hasKeyAppearance",@"_hasMainAppearance",@"_isKeyWindow",@"_isKeyWindowIgnoringFocus"]) {
        Method m=class_getInstanceMethod(NSWindow.class,NSSelectorFromString(name)); if(m) method_setImplementation(m,(IMP)Yes); }
    for(NSString *name in @[@"isActive",@"_isActiveApp"]) { Method m=class_getInstanceMethod(NSApplication.class,NSSelectorFromString(name)); if(m) method_setImplementation(m,(IMP)Yes); }
}
static void DrawMaterialsWithinWindow(NSView *view) {
    NSMutableArray<NSView *> *pending=[view.subviews mutableCopy];
    while(pending.count) { NSView *v=pending.lastObject; [pending removeLastObject]; [pending addObjectsFromArray:v.subviews];
        if([v isKindOfClass:NSVisualEffectView.class]) ((NSVisualEffectView *)v).blendingMode=NSVisualEffectBlendingModeWithinWindow; }
}
static void WritePNG(NSView *view, NSAppearance *appearance, NSString *path) {
    [appearance performAsCurrentDrawingAppearance:^{
        view.appearance=appearance;
        DrawMaterialsWithinWindow(view); [view layoutSubtreeIfNeeded]; [view setNeedsDisplay:YES]; [view displayIfNeeded];
        NSBitmapImageRep *raw=[view bitmapImageRepForCachingDisplayInRect:view.bounds]; [view cacheDisplayInRect:view.bounds toBitmapImageRep:raw];
        NSImage *image=[[NSImage alloc] initWithSize:view.bounds.size]; [image lockFocus];
        [NSColor.windowBackgroundColor setFill]; NSRectFill(view.bounds);
        NSImage *cached=[[NSImage alloc] initWithSize:view.bounds.size]; [cached addRepresentation:raw];
        [cached drawInRect:view.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        [image unlockFocus];
        NSBitmapImageRep *painted=[[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
        REQUIRE([[painted representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
    }];
}
// Items to show in the images and to fit in the list: a submenu with macros, macros with and
// without shortcuts, a separator, one with a long name.
static TSMacroTreeNode *MakeSampleRoot(TSMacroTreeNode **selected, TSMacroTreeNode **separator) {
    TSMacroTreeNode *root=[TSMacroTreeNode submenuNodeWithName:@"root"], *group=[TSMacroTreeNode submenuNodeWithName:@"Begin/End"];
    [group addChild:[TSMacroTreeNode nodeWithName:@"equation" content:@"\\begin{equation}\n#SEL##INS#\n\\end{equation}" key:@"E+ControlKey"]];
    [group addChild:[TSMacroTreeNode nodeWithName:@"align" content:@"\\begin{align}\n#SEL##INS#\n\\end{align}" key:@""]];
    [root addChild:group];
    *selected=[TSMacroTreeNode nodeWithName:@"MetaPost" content:@"\\begin{mplibcode}\n#SEL##INS#\n\\end{mplibcode}" key:@"M+ShiftKey"];
    [root addChild:*selected];
    [root addChild:[TSMacroTreeNode nodeWithName:@"\\ref{•‹label›}" content:@"\\ref{•‹label›}" key:@"R+ControlKey+OptionKey"]];
    TSMacroTreeNode *line=[TSMacroTreeNode separatorNode]; [root addChild:line]; if(separator) *separator=line;
    [root addChild:[TSMacroTreeNode nodeWithName:@"A macro with a name longer than the sidebar is wide" content:@"x" key:@"W+ShiftKey+OptionKey+ControlKey"]];
    [root addChild:[TSMacroTreeNode nodeWithName:@"Insert Reference" content:@"x" key:@""]];
    return root;
}
// TS_RENDER_DIR with TS_RENDER_ONLY (state-light or state-dark): the image of one state of the window, title bar
// and all, alone in its run: drawn again, the title bar of an offscreen window draws a line under it that the
// window does not have at first. The states: as it opens (a macro selected, its contents, shortcut and ⊗, and a
// conflict), an item renamed, the contents focused, the shortcut field waiting for keys, larger, and smallest.
static void RenderOnly(const char *path, NSString *only) {
    DrawAsKeyWindow();
    TSMacroEditor *owner=[TSMacroEditor new]; Editor=owner;
    NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(path)] bundle:nil];
    NSArray *objects; REQUIRE([nib instantiateWithOwner:owner topLevelObjects:&objects]);
    NSWindow *window=[owner valueForKey:@"window"]; REQUIRE(window && !window.visible);
    UseNameCells(owner);
    [window setFrameUsingName:@"Macro Editor"];
    [owner useSystemFont]; [owner installShortcutStatus]; [owner installShortcutField]; [owner installPlaceholderControls]; [owner layoutDialogButtons]; [owner installSidebar];
    NSOutlineView *rows=[owner valueForKey:@"outlineView"];
    TSMacroTreeNode *shown=nil; SampleRoot=MakeSampleRoot(&shown,NULL); [rows reloadData]; [rows expandItem:nil expandChildren:YES];
    NSInteger row=[rows rowForItem:shown]; [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    owner.previousItem=shown; owner.pendingShortcutKey=shown.key; [owner syncShortcutField];
    [[owner valueForKey:@"nameField"] setStringValue:shown.name];
    NSTextView *contents=contentsOf(owner); contents.editable=YES; contents.string=shown.content; [owner syncPlaceholderControls];
    owner.shortcutStatus.stringValue=[NSString stringWithFormat:NSLocalizedString(@"This shortcut is inactive because it conflicts with “%@” (%@).",@""),@"MetaPost",@"⇧⌘M"];
    // As after the first key the window has had: the default button drawn as such.
    { NSButton *save=[owner valueForKey:@"saveButton"]; [save highlight:YES]; [save highlight:NO]; }
    NSArray *parts=[only componentsSeparatedByString:@"-"]; NSString *state=parts.firstObject; BOOL dark=[parts.lastObject isEqual:@"dark"];
    NSRect frame=window.frame;
    if([state isEqual:@"resized"]) { frame.size.width+=260; frame.size.height+=160; frame.origin.y-=160; }
    if([state isEqual:@"smallest"]) frame.size=window.minSize;
    [window setFrame:frame display:NO]; [window.contentView layoutSubtreeIfNeeded];
    [window makeFirstResponder:rows];
    if([state isEqual:@"renaming"]) REQUIRE([owner beginRenamingSelectedItem]);
    if([state isEqual:@"contents"]) { REQUIRE([window makeFirstResponder:contents]); contents.selectedRange=NSMakeRange(18,10); }
    if([state isEqual:@"recording"]) [owner.shortcutField beginRecording];
    NSString *name=[[@(path) stringByDeletingLastPathComponent].stringByDeletingLastPathComponent.lastPathComponent stringByDeletingPathExtension];
    if([@(path).lastPathComponent containsString:@"101300"]) name=[name stringByAppendingString:@"-10.13"];
    WritePNG(window.contentView.superview,[NSAppearance appearanceNamed:dark?NSAppearanceNameDarkAqua:NSAppearanceNameAqua],[NSString stringWithFormat:@"%s/%@-%@.png",getenv("TS_RENDER_DIR"),name,only]);
    [owner.shortcutField endRecording]; [owner stopKeyMonitor];
    window.releasedWhenClosed=NO; [window close];
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
// The editor is shared and outlives its window: closed and opened again, each new window gets
// its own sidebar, fields, buttons and key monitor, as the first did. Closing does what the
// editor's windowWillClose: does with the controls (releaseWindowControls; the runner checks
// that windowWillClose: calls it).
static void CheckReopening(const char *path) {
    TSMacroEditor *owner=[TSMacroEditor new]; Editor=owner; NSWindow *previous=nil; NSVisualEffectView *previousSidebar=nil; id previousMonitor=nil;
    for(int open=0;open<3;open++) {
        NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(path)] bundle:nil];
        NSArray *objects; REQUIRE([nib instantiateWithOwner:owner topLevelObjects:&objects]);
        NSWindow *window=[owner valueForKey:@"window"]; REQUIRE(window && window!=previous && !window.visible);
        UseNameCells(owner);
        [owner useSystemFont]; [owner installShortcutStatus]; [owner installShortcutField]; [owner installPlaceholderControls]; [owner layoutDialogButtons]; [owner installSidebar];
        REQUIRE(owner.sidebar && owner.sidebar!=previousSidebar && owner.sidebar.window==window && owner.editorView.window==window && contentsOf(owner).window==window && ContentsLine(owner).window==window);
        REQUIRE(owner.shortcutField.window==window && owner.insertPlaceholderButton.window==window && owner.shortcutStatus.window==window && owner.listBar.window==window);
        REQUIRE(owner.contentsKeyMonitor && owner.contentsKeyMonitor!=previousMonitor);
        CheckEditor(owner,window);
        CheckKeys(owner); CheckSecondClick(owner);
        // The shortcut field, Insert and its help work in the new window too.
        CheckShortcutBehavior(owner); CheckPlaceholderControls(owner);
        previous=window; previousSidebar=owner.sidebar; previousMonitor=owner.contentsKeyMonitor;
        [owner releaseWindowControls];
        REQUIRE(!owner.sidebar && !owner.listBar && !owner.editorView && !owner.shortcutField && !owner.shortcutLabel && !owner.insertPlaceholderButton && !owner.placeholdersButton && !owner.shortcutStatus && !owner.contentsKeyMonitor);
        window.releasedWhenClosed=NO; [window close];
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
    if(getenv("TS_RENDER_DIR") && getenv("TS_RENDER_ONLY")) { RenderOnly(argv[1],@(getenv("TS_RENDER_ONLY"))); return 0; }
    for(int round=0;round<4;round++) {
    TSMacroEditor *owner=[TSMacroEditor new]; Editor=owner;
    NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[1])] bundle:nil];
    NSArray *objects; REQUIRE([nib instantiateWithOwner:owner topLevelObjects:&objects]);
    NSWindow *window=[owner valueForKey:@"window"]; REQUIRE(window && !window.visible);
    UseNameCells(owner);
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
    [owner useSystemFont];
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
    CGFloat heightBefore=NSHeight(window.frame), minimumHeightBefore=window.minSize.height, contentsBefore=NSHeight([contentsOf(owner) enclosingScrollView].frame);
    [owner installSidebar];
    // The window keeps its top edge and height; it is at least as wide as both parts need. Its smallest height
    // is lower by what the contents gained (the name field and the labels): the contents keep their smallest height.
    CGFloat gained=NSHeight([contentsOf(owner) enclosingScrollView].frame)-contentsBefore;
    if(fabs(window.minSize.height-(minimumHeightBefore-gained))>=.5) fprintf(stderr,"MINIMUM HEIGHT %.1f, before %.1f, the contents gained %.1f\n",window.minSize.height,minimumHeightBefore,gained);
    REQUIRE(fabs(NSMaxY(window.frame)-originalTop)<.1 && NSHeight(window.frame)==heightBefore && gained>0 && fabs(window.minSize.height-(minimumHeightBefore-gained))<.5);
    NSSplitViewController *split=SplitOf(window);
    REQUIRE(fabs(window.minSize.width-(160+split.splitView.dividerThickness+split.splitViewItems[1].minimumThickness))<.5 && NSWidth(window.frame)>=window.minSize.width);
    REQUIRE(fabs(NSWidth(owner.sidebar.frame)-240)<.5 || NSWidth(window.frame)<240+split.splitView.dividerThickness+split.splitViewItems[1].minimumThickness+.5);
    // The items come after the window is laid out, as openMacroEditor: gives the list its tree.
    if(round==0) { SampleRoot=MakeSampleRoot(&shown,NULL); [rows reloadData]; [rows expandItem:nil expandChildren:YES]; }
    { NSVisualEffectView *sidebar=owner.sidebar; NSView *main=owner.editorView; [owner installSidebar]; REQUIRE(owner.sidebar==sidebar && owner.editorView==main && SplitOf(window)==split); }
    CheckEditor(owner,window);
    if(getenv("TS_CONTROLS") && round==0) DumpControls(owner);
    CheckListFitsSidebarWidths(owner);
    if(round==0) { CheckShortcutBehavior(owner); CheckPlaceholderControls(owner); CheckKeys(owner); CheckSecondClick(owner); CheckSeparatorImage(); }
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
    [window setFrame:frame display:NO];
    if(round==1) { NSRect resized=window.frame; resized.size.height+=80; [window setFrame:resized display:NO]; }
    savedHeight=window.frame.size.height;
    [window saveFrameUsingName:@"Macro Editor"];
    REQUIRE([[memoryDefaults stringForKey:@"NSWindow Frame Macro Editor"] length]>0);
    [owner stopKeyMonitor]; REQUIRE(!owner.contentsKeyMonitor);
    window.releasedWhenClosed=NO; [window close];
    }
    CheckReopening(argv[1]);
    printf("PASS: %s sidebar, contents, keys, renaming in the list, reopening, status band: bounds, wrapping, control separation, resizing, idempotence\n",argv[1]);
} return 0; }
