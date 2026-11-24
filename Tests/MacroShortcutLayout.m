// Instantiate existing localized nibs offscreen and run the production layout of the macro editor: the sidebar,
// the contents, the status band and the placeholder row; the keys, renaming in the list, and the recording of a
// shortcut in the list's own cell, with its warnings.
#import "TSMacroEditor.h"
#import "TSMacroOutlineController.h"
#import "TSDialogButtonLayout.h"
#import "TSMarkMenu.h"
#import "TSListBottomBar.h"
#import "TSShortcutKeyRecorder.h"
#import "TSPrefPaneLayout.h"
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
#define NEW_ITEM_NAME @"New Item"
#define NEW_SUBMENU_NAME @"Submenu"
static TSMemoryDefaults *memoryDefaults;
static id StandardDefaults(id self, SEL cmd) { return memoryDefaults; }
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
static int reflections, pendingUpdates, tests;
// The editor of the window being checked (the outline controller asks the shared editor).
static TSMacroEditor *Editor;
// Why a macro's saved shortcut is inactive, as the editor's refreshShortcutConflicts finds it.
static NSMapTable *Conflicts;
@implementation TSMacroEditor
#include "MacroStatusLayout.inc"
#include "MacroListDoubleClick.inc"
// The rest of the editor, as far as the list and the recording ask of it: another selection ends a recording and
// brings the selected item's shortcut; a shortcut set is kept in the item, which the list shows again.
+ (id)sharedInstance { return Editor; }
- (void)updatePendingShortcutStatus { pendingUpdates++; }
- (void)outlineViewSelectionChanged:(NSNotification *)note { [self endShortcutRecordingUnlessSelected]; [self reflectChangesInEditor:NO]; }
- (void)reflectChangesInEditor:(BOOL)force {
    reflections++;
    if (self.previousItem && keyTouched) { self.previousItem.key=self.pendingShortcutKey?:@""; dataTouched=YES; [outlineView reloadItem:self.previousItem]; }
    keyTouched=NO;
    NSArray *selected=[outlineView allSelectedItems]; TSMacroTreeNode *item=selected.count==1?selected.firstObject:nil;
    if (item!=self.previousItem || force) { self.previousItem=item; self.pendingShortcutKey=item.isStandardItem?(item.key?:@""):@""; }
    [self updateShortcutStatus];
}
- (void)outlineViewItemsChanged:(NSNotification *)note { [self setValue:@YES forKey:@"dataTouched"]; [self endShortcutRecording]; }
- (NSString *)shortcutConflictForNode:(TSMacroTreeNode *)node { return node ? [Conflicts objectForKey:node] : nil; }
- (IBAction)doMacroTest:(id)sender { tests++; }
@end
// The list shows the items of SampleRoot (none unless set) in the outline controller's own cells
// (MacroOutlineCells.inc), and takes a name typed in it with the controller's own code (MacroOutlineEditing.inc);
// the list and its cells are the application's (MacroOutlineView.inc).
static TSMacroTreeNode *SampleRoot;
@implementation TSMacroOutlineController
- (void)setValue:(id)v forUndefinedKey:(NSString *)key {}
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item { return [(item ?: SampleRoot) numberOfChildren]; }
- (id)outlineView:(NSOutlineView *)view child:(NSInteger)index ofItem:(id)item { return [(item ?: SampleRoot) childAtIndex:index]; }
- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item { return [item isExpandable]; }
#include "MacroOutlineCells.inc"
- (TSMacroTreeNode *)rootOfTree { return SampleRoot; }
- (void)setRootOfTree:(TSMacroTreeNode *)root { SampleRoot=root; }
#include "MacroOutlineEditing.inc"
#include "MacroOutlineAdding.inc"
@end
#include "MacroOutlineView.inc"
// The names in cells that can be edited and the shortcuts in the list's own cells, as the outline controller's
// awakeFromNib makes them.
static void UseNameCells(TSMacroEditor *owner) {
    NSOutlineView *rows=[owner valueForKey:@"outlineView"]; NSTableColumn *name=[rows tableColumnWithIdentifier:@"Name"];
    ImageAndTextCell *cell=[ImageAndTextCell new]; cell.editable=YES; name.dataCell=cell;
    TSMacroUseShortcutCell(rows);
    REQUIRE([[rows tableColumnWithIdentifier:@"Key"].dataCell isKindOfClass:TSMacroShortcutCell.class]);
    // The list sends the editor its clicks, as loadUI sets it, and what the selection changes, as openMacroEditor: asks.
    rows.target=owner; rows.action=@selector(listClicked:); rows.doubleAction=@selector(listDoubleClicked:);
    [[NSNotificationCenter defaultCenter] removeObserver:owner name:NSOutlineViewSelectionDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:owner selector:@selector(outlineViewSelectionChanged:) name:NSOutlineViewSelectionDidChangeNotification object:rows];
}
// The menus whose commands a recorded shortcut may not take: File › Save (⌘S), File › Close (⌘W), Typeset › Typeset (⌘T);
// a hidden command's key (⌘U) works for nothing, so a macro may have it.
static void UseTestMenu(void) {
    NSMenu *main=[NSMenu new];
    for(NSArray *m in @[@[@"File",@[@[@"Save",@"s"],@[@"Close",@"w"]]],@[@"Typeset",@[@[@"Typeset",@"t"],@[@"Hidden",@"u"]]]]) {
        NSMenu *sub=[[NSMenu alloc] initWithTitle:m[0]]; NSMenuItem *root=[[NSMenuItem alloc] initWithTitle:m[0] action:NULL keyEquivalent:@""]; root.submenu=sub; [main addItem:root];
        for(NSArray *i in m[1]) { NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:i[0] action:@selector(description) keyEquivalent:i[1]]; item.keyEquivalentModifierMask=NSEventModifierFlagCommand; item.hidden=[i[0] isEqual:@"Hidden"]; [sub addItem:item]; }
    }
    [[TSKeyboardShortcuts sharedController] setValue:[[TSShortcutStore alloc] initWithMenu:main defaults:memoryDefaults] forKey:@"store"];
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
// Whether AppKit draws its focus ring around a list's scroll view while the list has the focus (an offscreen image
// does not get it; WritePNG draws it where AppKit would). AppKit draws it around the scroll view of a list of cells and
// of a list of an old nib, as the macro editor's, unless the list's focus ring type is none; around a list of views
// made in code, as the sets of the Multiple Replace window, the ring of the list itself, outside its visible part, is
// clipped by the scroll view and never seen. Without AppKit's private methods, the focus ring type alone.
static BOOL AppKitSays(NSView *view, NSString *name, BOOL otherwise) {
    SEL selector=NSSelectorFromString(name);
    return [view respondsToSelector:selector] ? ((BOOL(*)(id,SEL))objc_msgSend)(view,selector) : otherwise;
}
static BOOL DrawsFocusRingAroundList(NSTableView *table) {
    SEL effective=NSSelectorFromString(@"_effectiveFocusRingType");
    NSFocusRingType type=[table respondsToSelector:effective] ? ((NSFocusRingType(*)(id,SEL))objc_msgSend)(table,effective) : table.focusRingType;
    if(type==NSFocusRingTypeNone) return NO;
    return AppKitSays(table,@"_willDrawFocusRingAroundEnclosingScrollView",YES) || AppKitSays(table,@"_hasLegacyExternalFocusRingThatWasNormallyDrawnManually",NO);
}
@interface TSFocusRingSets : NSObject <NSTableViewDataSource,NSTableViewDelegate> @end
@implementation TSFocusRingSets
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return 2; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return [NSTextField labelWithString:@"Set"]; }
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return @"Set"; }
@end
// No focus ring around the sidebar while the list has the focus, as around the sets of the Multiple Replace window:
// the selection shows the focus. Beside it, in the same window, a list of cells with AppKit's ring and a list of views
// as the sets', without one, show that the decision checked is AppKit's own.
static void CheckSidebarFocusRing(TSMacroEditor *owner) {
    NSOutlineView *rows=[owner valueForKey:@"outlineView"]; NSWindow *window=rows.window; NSResponder *previous=window.firstResponder;
    // While a name is edited, the field has the focus and its own ring (the list reports AppKit's default meanwhile).
    if(rows.editedRow>=0) { REQUIRE(rows.currentEditor && window.firstResponder==rows.currentEditor); return; }
    REQUIRE(rows.focusRingType==NSFocusRingTypeNone);
    REQUIRE([window makeFirstResponder:rows] && !DrawsFocusRingAroundList(rows));
    TSFocusRingSets *source=[TSFocusRingSets new];
    for(int viewBased=0;viewBased<2;viewBased++) {
        NSTableView *table=[[NSTableView alloc] initWithFrame:NSMakeRect(0,0,100,60)]; table.style=viewBased?NSTableViewStyleSourceList:NSTableViewStyleInset;
        [table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"name"]];
        if(viewBased) table.delegate=source; table.dataSource=source; [table reloadData];
        NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,100,60)]; scroll.documentView=table; [owner.editorView addSubview:scroll];
        REQUIRE([window makeFirstResponder:table] && DrawsFocusRingAroundList(table)==!viewBased);
        [window makeFirstResponder:window]; [scroll removeFromSuperview];
    }
    [window makeFirstResponder:previous];
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
// The nib's rows of the shortcut (its key field, the Shift, Option and Control boxes and their labels) are hidden;
// the contents take them, down to the bottom of the field the shortcut had there, and the row of Insert comes below
// them; the key view loop goes past the hidden controls.
static void CheckNibShortcutRows(TSMacroEditor *owner) {
    NSView *host=owner.editorView;
    NSTextField *nameField=[owner valueForKey:@"nameField"],*keyField=[owner valueForKey:@"keyField"];
    NSButton *shift=[owner valueForKey:@"shiftCheckBox"];
    NSArray *old=@[keyField,shift,[owner valueForKey:@"optionCheckBox"],[owner valueForKey:@"controlCheckBox"]];
    for(NSView *v in old) REQUIRE(v.hidden && v.superview==host);
    CGFloat height=MAX(NSHeight(keyField.frame),[NSTextField textFieldWithString:@""].fittingSize.height), bottom=round(NSMidY(shift.frame)-height/2);
    NSRect rows=NSUnionRect(NSInsetRect(keyField.frame,0,-4),NSInsetRect(shift.frame,0,-4));
    NSPopUpButton *insert=owner.insertPlaceholderButton;
    // Nothing visible is left in the old rows but the row of Insert, which takes the bottom of the shortcut's field.
    for(NSView *v in host.subviews) if(!v.hidden && v!=insert && v!=owner.placeholdersButton && v!=[contentsOf(owner) enclosingScrollView] && NSMinX(v.frame)>=NSMinX(nameField.frame)-12 && NSIntersectsRect(NSInsetRect(v.frame,.5,.5),rows) && ![v isKindOfClass:NSBox.class]) {
        fprintf(stderr,"LEFT IN THE SHORTCUT ROWS %s %s %s\n",NSStringFromClass(v.class).UTF8String,NSStringFromRect(v.frame).UTF8String,[v isKindOfClass:NSTextField.class]?((NSTextField*)v).stringValue.UTF8String:""); REQUIRE(NO); }
    NSRect row=NSUnionRect(insert.frame,owner.placeholdersButton.frame);
    if(fabs(NSMinY(row)-bottom)>1) fprintf(stderr,"INSERT ROW %s, the shortcut's field began at %.1f\n",NSStringFromRect(row).UTF8String,bottom);
    REQUIRE(fabs(NSMinY(row)-bottom)<=1);
    NSMutableArray *pending=[host.subviews mutableCopy];
    while(pending.count){ NSView *v=pending.lastObject; [pending removeLastObject]; [pending addObjectsFromArray:v.subviews]; REQUIRE(v.nextKeyView!=keyField || v.hidden); }
}
// What a click on a cell of the list sends, as the list does: the row that was selected alone when the mouse went
// down, the focus and the selection the click leaves, the clicked row and column, then the action. A double click
// sends the action of its first click, then, unless that click put the field over the cell, the double action.
static NSInteger ClickedRow=-1, ClickedColumn=-1;
static NSInteger FakeClickedRow(id self, SEL cmd) { return ClickedRow; }
static NSInteger FakeClickedColumn(id self, SEL cmd) { return ClickedColumn; }
static void Click(TSMacroEditor *owner, NSInteger row, NSString *column, BOOL twice) {
    TSMacroOutlineView *rows=[owner valueForKey:@"outlineView"]; NSWindow *window=rows.window;
    IMP r=method_setImplementation(class_getInstanceMethod(NSTableView.class,@selector(clickedRow)),(IMP)FakeClickedRow);
    IMP c=method_setImplementation(class_getInstanceMethod(NSTableView.class,@selector(clickedColumn)),(IMP)FakeClickedColumn);
    for(int click=0;click<(twice?2:1);click++) {
        if(click && window.firstResponder==owner.recordingCell.recorder) break; // the second click goes to the field
        rows.rowSelectedAtMouseDown=rows.numberOfSelectedRows==1?rows.selectedRow:-1;
        [window makeFirstResponder:rows];
        [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        ClickedRow=row; ClickedColumn=[rows columnWithIdentifier:column];
        [NSApp sendAction:click?rows.doubleAction:rows.action to:rows.target from:rows];
        ClickedRow=ClickedColumn=-1;
    }
    method_setImplementation(class_getInstanceMethod(NSTableView.class,@selector(clickedRow)),r);
    method_setImplementation(class_getInstanceMethod(NSTableView.class,@selector(clickedColumn)),c);
}
static void Wait(NSTimeInterval seconds) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static NSEvent *KeyIn(NSWindow *window, NSString *c, unsigned short code, NSEventModifierFlags flags);
static NSEvent *Typed(NSWindow *window, NSString *characters, NSString *ignoring, unsigned short code, NSEventModifierFlags flags) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:window.windowNumber context:nil
        characters:characters charactersIgnoringModifiers:ignoring isARepeat:NO keyCode:code];
}
static void SendKey(TSMacroEditor *owner, NSWindow *window, NSEvent *event);
// The text a row's shortcut cell shows, as the list draws it.
static NSString *Shown(NSOutlineView *rows, NSInteger row) { return [rows preparedCellAtColumn:[rows columnWithIdentifier:@"Key"] row:row].stringValue; }
// How many pixels of the yellow of the warning triangle the shortcut cell of a row draws, drawn alone into a bitmap
// (caching the list's own drawing would end its later editing of names).
static NSInteger YellowPixels(NSOutlineView *rows, NSInteger row) {
    NSInteger key=[rows columnWithIdentifier:@"Key"]; NSRect frame=[rows frameOfCellAtColumn:key row:row]; NSCell *cell=[rows preparedCellAtColumn:key row:row];
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)ceil(NSWidth(frame))*2 pixelsHigh:(NSInteger)ceil(NSHeight(frame))*2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    CGContextRef cg=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep].CGContext;
    CGContextScaleCTM(cg,2,2); CGContextTranslateCTM(cg,0,ceil(NSHeight(frame))); CGContextScaleCTM(cg,1,-1); CGContextTranslateCTM(cg,-NSMinX(frame),-NSMinY(frame));
    [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithCGContext:cg flipped:YES];
    [rows.effectiveAppearance performAsCurrentDrawingAppearance:^{ [cell drawWithFrame:frame inView:rows]; }];
    [NSGraphicsContext restoreGraphicsState];
    NSInteger yellow=0;
    for(NSInteger y=0;y<rep.pixelsHigh;y++) for(NSInteger x=0;x<rep.pixelsWide;x++) {
        NSColor *c=[[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        if(c.alphaComponent>.5 && c.redComponent>.8 && c.greenComponent>.55 && c.blueComponent<.35) yellow++; }
    return yellow;
}
// The box of the yellow pixels an image draws, in points (it is drawn at twice its size), and their number.
static NSRect YellowBoundsOfImage(NSImage *image, NSAppearance *appearance, NSInteger *count) {
    NSSize size=image.size; NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)ceil(size.width)*2 pixelsHigh:(NSInteger)ceil(size.height)*2 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [appearance performAsCurrentDrawingAppearance:^{ [image drawInRect:NSMakeRect(0,0,rep.pixelsWide,rep.pixelsHigh)]; }];
    [NSGraphicsContext restoreGraphicsState];
    NSInteger minX=NSIntegerMax,minY=NSIntegerMax,maxX=-1,maxY=-1,yellow=0;
    for(NSInteger y=0;y<rep.pixelsHigh;y++) for(NSInteger x=0;x<rep.pixelsWide;x++) {
        NSColor *c=[[rep colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        if(c.alphaComponent>.5 && c.redComponent>.8 && c.greenComponent>.55 && c.blueComponent<.35) { yellow++; minX=MIN(minX,x); minY=MIN(minY,y); maxX=MAX(maxX,x); maxY=MAX(maxY,y); } }
    if(count) *count=yellow;
    return yellow ? NSMakeRect(minX/2.,minY/2.,(maxX-minX+1)/2.,(maxY-minY+1)/2.) : NSZeroRect;
}
// The same box for the triangle the shortcut cell of a row draws.
static NSRect YellowBoundsOfCell(NSOutlineView *rows, NSInteger row) {
    NSInteger key=[rows columnWithIdentifier:@"Key"]; NSRect frame=[rows frameOfCellAtColumn:key row:row]; NSCell *cell=[rows preparedCellAtColumn:key row:row];
    NSImage *image=[NSImage imageWithSize:frame.size flipped:YES drawingHandler:^BOOL(NSRect rect) {
        NSAffineTransform *move=[NSAffineTransform transform]; [move translateXBy:-NSMinX(frame) yBy:-NSMinY(frame)]; [move concat];
        [cell drawWithFrame:frame inView:rows]; return YES; }];
    return YellowBoundsOfImage(image,rows.effectiveAppearance,NULL);
}
// The triangles of the macro editor are those of Settings › Keyboard (TSShortcutWarningLine, the triangle at the end
// of the field that records): the multicolor symbol, yellow, of the same size, not read by VoiceOver; the one in
// the list as large as the one below the contents.
static void CheckWarningMarksAsSettings(TSMacroEditor *owner, NSOutlineView *rows, NSInteger warnedRow) {
    NSImageView *mark=owner.shortcutStatusMark, *settings=(NSImageView *)TSShortcutWarningLine(@"x").arrangedSubviews[0], *recording=owner.recordingCell.warning;
    REQUIRE([settings.identifier isEqual:@"settings.warning-symbol.multicolor"] && !mark.isAccessibilityElement && !settings.isAccessibilityElement);
    REQUIRE(NSEqualSizes(mark.image.size,settings.image.size) && NSEqualSizes(mark.intrinsicContentSize,settings.intrinsicContentSize) && NSEqualSizes(recording.image.size,settings.image.size));
    for(NSString *name in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        NSAppearance *appearance=[NSAppearance appearanceNamed:name]; NSInteger ours=0, theirs=0;
        NSRect a=YellowBoundsOfImage(mark.image,appearance,&ours), b=YellowBoundsOfImage(settings.image,appearance,&theirs);
        if(ours<20 || ours!=theirs || !NSEqualRects(a,b)) fprintf(stderr,"MARK %s %ld %s settings %ld %s\n",name.UTF8String,(long)ours,NSStringFromRect(a).UTF8String,(long)theirs,NSStringFromRect(b).UTF8String);
        REQUIRE(ours>=20 && ours==theirs && NSEqualRects(a,b));
    }
    NSRect cell=YellowBoundsOfCell(rows,warnedRow), status=YellowBoundsOfImage(mark.image,rows.effectiveAppearance,NULL);
    if(fabs(NSWidth(cell)-NSWidth(status))>.5 || fabs(NSHeight(cell)-NSHeight(status))>.5) fprintf(stderr,"LIST MARK %s message %s\n",NSStringFromRect(cell).UTF8String,NSStringFromRect(status).UTF8String);
    REQUIRE(NSWidth(status)>5 && fabs(NSWidth(cell)-NSWidth(status))<=.5 && fabs(NSHeight(cell)-NSHeight(status))<=.5);
}
// The field over the shortcut of a row: from the trailing edge of the shortcut's cell, at least as wide as the
// longest shortcut, ⊖ and the triangle need, but not beyond the start of the names; the row's height. The field
// 18 points high, the triangle's 20 points after it; the longest shortcut shows whole.
static void CheckRecordingCell(TSMacroEditor *owner, NSInteger row) {
    TSMacroOutlineView *rows=[owner valueForKey:@"outlineView"]; TSShortcutRecordingCell *cell=owner.recordingCell; [cell layoutSubtreeIfNeeded];
    NSRect key=[rows frameOfCellAtColumn:[rows columnWithIdentifier:@"Key"] row:row], line=[rows rectOfRow:row];
    CGFloat leading=NSMinX([rows rectOfColumn:[rows columnWithIdentifier:@"Name"]]), room=NSMaxX(key)-leading;
    if(fabs(NSMaxX(cell.frame)-NSMaxX(key))>=.5 || NSMinX(cell.frame)<leading-.5 || fabs(NSWidth(cell.frame)-MAX(NSWidth(key),MIN(rows.recordingWidth,room)))>=.5) fprintf(stderr,"RECORDING CELL %s, shortcut %s, names from %.1f, wanted %.1f\n",NSStringFromRect(cell.frame).UTF8String,NSStringFromRect(key).UTF8String,leading,rows.recordingWidth);
    REQUIRE(cell.superview==rows && !cell.hidden && fabs(NSMaxX(cell.frame)-NSMaxX(key))<.5 && NSMinX(cell.frame)>=leading-.5);
    REQUIRE(fabs(NSWidth(cell.frame)-MAX(NSWidth(key),MIN(rows.recordingWidth,room)))<.5 && fabs(NSMinY(cell.frame)-NSMinY(line))<.5 && fabs(NSHeight(cell.frame)-NSHeight(line))<.5);
    NSRect field=cell.recorder.frame, warning=cell.warning.frame;
    REQUIRE(fabs(NSHeight(field)-18)<.5 && NSMinX(field)==0 && fabs(NSMaxX(field)-(NSWidth(cell.bounds)-20))<.5 && fabs(NSMidY(field)-NSMidY(cell.bounds))<.5);
    REQUIRE(NSMinX(warning)>=NSMaxX(field) && NSMaxX(warning)<=NSWidth(cell.bounds) && fabs(NSMidY(warning)-NSMidY(cell.bounds))<1);
    NSString *kept=cell.recorder.shortcut;
    if(rows.recordingWidth<=room+.5) for(NSString *longest in @[@"⌃⌥⇧⌘F20",@"⌃⌥⇧⌘F12",@"⌃⌥⇧⌘W"]) {
        cell.recorder.shortcut=longest; [cell layoutSubtreeIfNeeded];
        NSTextField *label=cell.recorder.label; CGFloat needed=label.attributedStringValue.size.width;
        if(needed>NSWidth(label.frame)+.5) fprintf(stderr,"FIELD %s needs %.1f, has %.1f\n",longest.UTF8String,needed,NSWidth(label.frame));
        REQUIRE(needed<=NSWidth(label.frame)+.5 && NSMaxX(label.frame)<=NSMinX(cell.recorder.removeButton.frame));
    }
    cell.recorder.shortcut=kept;
}
// A shortcut is recorded in the list, in its item's own cell, as in Settings › Keyboard (Xcode's key bindings): a
// click on the shortcut of the item selected alone, a double click on a shortcut, VoiceOver's press. The key
// pressed becomes it at once, Command-S, -W and -Q too; a key another command uses is refused, shown with the
// triangle and the reason below the contents, and the recording goes on, as after a key that cannot be one.
// Escape and Return end it, Tab moves on, Delete and ⊖ remove the shortcut; a click elsewhere, another selection
// and changed items end it. Separators and submenus have none. A saved shortcut that is inactive has the
// triangle before it in the list, and the reason below the contents when it is selected.
static NSEvent *KeyIn(NSWindow *window, NSString *c, unsigned short code, NSEventModifierFlags flags);
static NSEvent *Mouse(NSWindow *window, NSEventType type, NSPoint at, NSInteger clicks);
static TSMacroTreeNode *MakeSampleRoot(TSMacroTreeNode **selected, TSMacroTreeNode **separator);
static NSTextView *Renaming(NSWindow *window, NSOutlineView *rows);
static void CheckRecording(TSMacroEditor *owner) {
    NSWindow *window=[owner valueForKey:@"window"]; TSMacroOutlineView *rows=[owner valueForKey:@"outlineView"];
    NSButton *save=[owner valueForKey:@"saveButton"],*cancel=[owner valueForKey:@"cancelButton"]; NSTextView *contents=contentsOf(owner);
    TSMacroTreeNode *kept=SampleRoot,*macro=nil,*separator=nil; SampleRoot=MakeSampleRoot(&macro,&separator);
    [rows reloadData]; [rows expandItem:nil expandChildren:YES]; [window.contentView layoutSubtreeIfNeeded];
    id targets[]={save.target,cancel.target}; SEL actions[]={save.action,cancel.action};
    ActionRecorder *pressed=[ActionRecorder new]; pressed.log=[NSMutableArray new];
    for(NSButton *b in @[save,cancel]) { b.target=pressed; b.action=@selector(hit:); }
    TSShortcutRecordingCell *cell=owner.recordingCell; TSShortcutKeyRecorder *recorder=cell.recorder;
    REQUIRE(cell && recorder && cell.superview==nil && rows.recordingWidth>=[TSShortcutRecordingCell widthForShortcut:@"⌃⌥⇧⌘F20"]);
    REQUIRE(recorder.removeButton.target==owner && recorder.removeButton.action==@selector(removeRecordedShortcut:));
    TSMacroTreeNode *group=[SampleRoot childAtIndex:0], *equation=[group childAtIndex:0], *other=[SampleRoot childAtIndex:2], *noKey=[SampleRoot childAtIndex:5];
    NSInteger row=[rows rowForItem:macro], otherRow=[rows rowForItem:other], groupRow=[rows rowForItem:group], line=[rows rowForItem:separator];
    NSString *macros=NSLocalizedString(@"Macros",@""), *used=NSLocalizedString(@"This shortcut is already used by “%@”.",@"");
    NSString *unusable=NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.",@"");
    BOOL (^recording)(TSMacroTreeNode *)=^BOOL(TSMacroTreeNode *item) { return owner.recordingItem==item && window.firstResponder==recorder && cell.superview==rows && rows.recordingItem==item; };
    void (^ended)(void)=^{ REQUIRE(!owner.recordingItem && window.firstResponder==rows && cell.superview==nil && !rows.recordingItem && pressed.log.count==0); };
    // The list keeps, from the mouse going down, the row that was selected alone then (a real mouse down on a cell, its
    // mouse up already waiting; the actions are not sent here, and the window, not key, does not select): none after a click with Command or with several rows selected.
    { SEL single=rows.action, twice=rows.doubleAction; rows.action=NULL; rows.doubleAction=NULL;
      NSPoint (^at)(NSInteger)=^NSPoint(NSInteger r){ NSRect c=[rows frameOfCellAtColumn:[rows columnWithIdentifier:@"Key"] row:r]; return [rows convertPoint:NSMakePoint(NSMidX(c),NSMidY(c)) toView:nil]; };
      void (^press)(NSInteger,NSEventModifierFlags)=^(NSInteger r,NSEventModifierFlags flags){ NSEvent *down=Mouse(window,NSEventTypeLeftMouseDown,at(r),1);
          if(flags) down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:at(r) modifierFlags:flags timestamp:down.timestamp windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
          [NSApp postEvent:Mouse(window,NSEventTypeLeftMouseUp,at(r),1) atStart:YES]; [rows mouseDown:down]; };
      [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:otherRow] byExtendingSelection:NO];
      press(row,0); REQUIRE(rows.rowSelectedAtMouseDown==otherRow);
      [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; press(row,0); REQUIRE(rows.rowSelectedAtMouseDown==row);
      press(row,NSEventModifierFlagCommand); REQUIRE(rows.rowSelectedAtMouseDown==-1);
      [rows selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(row,2)] byExtendingSelection:NO]; press(row,0); REQUIRE(rows.rowSelectedAtMouseDown==-1);
      [rows cancelPendingRename]; rows.action=single; rows.doubleAction=twice; REQUIRE(!owner.recordingItem); }
    // A click on the shortcut of an item that was not selected only selects it; one on the name of the selected item does not record.
    [rows deselectAll:nil]; Click(owner,row,@"Key",NO);
    REQUIRE(rows.selectedRow==row && owner.previousItem==macro && !owner.recordingItem && window.firstResponder==rows);
    Click(owner,row,@"Name",NO); REQUIRE(!owner.recordingItem);
    // Several items selected: a click selects the one clicked; it does not record.
    [rows selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(row,2)] byExtendingSelection:NO]; Click(owner,row,@"Key",NO); REQUIRE(!owner.recordingItem && rows.selectedRow==row);
    // A click on the shortcut of the selected item records: the field over its shortcut, the key in it, ⊖, no triangle, no message.
    Click(owner,row,@"Key",NO);
    REQUIRE(recording(macro) && [recorder.shortcut isEqual:@"⇧⌘M"] && !recorder.removeButton.hidden && cell.warning.hidden);
    REQUIRE(owner.shortcutStatusMark.hidden && owner.shortcutStatus.stringValue.length==0 && [Shown(rows,row) isEqual:@""]);
    CheckRecordingCell(owner,row);
    REQUIRE([recorder.accessibilityRole isEqual:NSAccessibilityTextFieldRole] && [recorder.accessibilityLabel isEqual:NSLocalizedString(@"Change Shortcut",@"")] && [recorder.accessibilityValue isEqual:@"⇧⌘M"] && [recorder.accessibilityHelp isEqual:NSLocalizedString(@"Press a key",@"")]);
    REQUIRE([recorder.removeButton.toolTip isEqual:NSLocalizedString(@"Remove Shortcut",@"")] && recorder.removeButton.refusesFirstResponder);
    // Escape ends it and keeps the shortcut; the list is focused again, the window stays open.
    SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); ended(); REQUIRE([macro.key isEqual:@"M+ShiftKey"] && [Shown(rows,row) isEqual:@"⇧⌘M"]);
    // Escape in the list, not recording, does nothing.
    SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); ended();
    // Return and Enter end it as Escape does; neither saves. Return in the list then renames, it does not record.
    for(NSString *c in @[@"\r",@"\x03"]) { Click(owner,row,@"Key",NO); REQUIRE(recording(macro)); SendKey(owner,window,KeyIn(window,c,[c isEqual:@"\r"]?36:76,0)); ended(); REQUIRE([macro.key isEqual:@"M+ShiftKey"]); }
    SendKey(owner,window,KeyIn(window,@"\r",36,0)); REQUIRE(Renaming(window,rows) && !owner.recordingItem); SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); REQUIRE(!Renaming(window,rows));
    // Keys of menu commands reach the recording, not the menus or Save, and are refused: the key in the field, the
    // triangle after it, the reason below the contents with the triangle before it; the recording goes on.
    Click(owner,row,@"Key",NO);
    struct { NSString *c; unsigned short code; NSString *shown, *user; } taken[]={{@"s",1,@"⌘S",@"File › Save"},{@"w",13,@"⌘W",@"File › Close"},{@"t",17,@"⌘T",@"Typeset › Typeset"}};
    for(size_t i=0;i<3;i++) {
        SendKey(owner,window,KeyIn(window,taken[i].c,taken[i].code,NSEventModifierFlagCommand));
        NSString *reason=[NSString stringWithFormat:used,taken[i].user];
        if(![owner.shortcutStatus.stringValue isEqual:reason]) fprintf(stderr,"REFUSED %s: %s\n",taken[i].shown.UTF8String,owner.shortcutStatus.stringValue.UTF8String);
        REQUIRE(recording(macro) && [recorder.shortcut isEqual:taken[i].shown] && !cell.warning.hidden && [owner.recordingError isEqual:reason]);
        REQUIRE([owner.shortcutStatus.stringValue isEqual:reason] && !owner.shortcutStatusMark.hidden && pressed.log.count==0 && [macro.key isEqual:@"M+ShiftKey"]);
    }
    // Another macro's shortcut, as the path of its menu item.
    SendKey(owner,window,Typed(window,@"\x05",@"e",14,NSEventModifierFlagControl|NSEventModifierFlagCommand));
    REQUIRE(recording(macro) && [recorder.shortcut isEqual:@"⌃⌘E"] && [owner.shortcutStatus.stringValue isEqual:[NSString stringWithFormat:used,[macros stringByAppendingString:@" › Begin/End › equation"]]]);
    // A key that cannot be a shortcut: the field shows the key pressed, the triangle and the reason stay; recording goes on.
    NSEvent *refused[]={KeyIn(window,@"a",0,0),Typed(window,@"K",@"K",40,NSEventModifierFlagShift),Typed(window,@"˚",@"k",40,NSEventModifierFlagOption),KeyIn(window,@"\r",36,NSEventModifierFlagCommand),KeyIn(window,@"\t",48,NSEventModifierFlagCommand)};
    for(size_t i=0;i<5;i++) {
        SendKey(owner,window,refused[i]);
        TSShortcutBinding *pressedKey=TSRecordedBinding(refused[i],[refused[i] charactersByApplyingModifiers:0]); NSString *shown=TSShortcutDisplayKey(pressedKey.key,pressedKey.modifiers);
        if(![recorder.shortcut isEqual:shown]) fprintf(stderr,"REFUSED KEY %zu shown %s, pressed %s\n",i,recorder.shortcut.UTF8String,shown.UTF8String);
        REQUIRE(recording(macro) && [recorder.shortcut isEqual:shown] && ![shown isEqual:@"⇧⌘M"] && !cell.warning.hidden && [owner.shortcutStatus.stringValue isEqual:unusable] && !owner.shortcutStatusMark.hidden && [macro.key isEqual:@"M+ShiftKey"]);
    }
    // A character key with the Globe key (fn), which AppKit would drop from the macro's item: refused, the field showing
    // the key pressed with 🌐︎; recording goes on.
    NSString *globeRefusal=NSLocalizedString(@"Shortcuts with the Globe key (fn) can't be assigned to TeXShop commands.",@"");
    SendKey(owner,window,Typed(window,@"\x02",@"b",11,NSEventModifierFlagControl|NSEventModifierFlagCommand|NSEventModifierFlagFunction));
    if(![owner.shortcutStatus.stringValue isEqual:globeRefusal]) fprintf(stderr,"GLOBE shown %s, message %s, key %s\n",recorder.shortcut.UTF8String,owner.shortcutStatus.stringValue.UTF8String,macro.key.UTF8String);
    REQUIRE(recording(macro) && [recorder.shortcut isEqual:@"⌃⌘\U0001F310\uFE0EB"] && !cell.warning.hidden && [owner.recordingError isEqual:globeRefusal] && [owner.shortcutStatus.stringValue isEqual:globeRefusal] && [macro.key isEqual:@"M+ShiftKey"]);
    // The next key that can be one becomes the shortcut and ends the recording: no triangle, no message.
    int before=reflections; [owner setValue:@NO forKey:@"dataTouched"];
    SendKey(owner,window,KeyIn(window,@"j",38,NSEventModifierFlagCommand)); ended();
    REQUIRE([macro.key isEqual:@"J"] && [owner.pendingShortcutKey isEqual:@"J"] && [Shown(rows,row) isEqual:@"⌘J"] && reflections>before && [[owner valueForKey:@"dataTouched"] boolValue]);
    REQUIRE(owner.shortcutStatus.stringValue.length==0 && owner.shortcutStatusMark.hidden && !owner.recordingError);
    // Command-Q, which no menu command has here, becomes the shortcut too, and so does the key of a hidden command.
    Click(owner,row,@"Key",NO); SendKey(owner,window,KeyIn(window,@"q",12,NSEventModifierFlagCommand)); ended(); REQUIRE([macro.key isEqual:@"Q"]);
    Click(owner,row,@"Key",NO); SendKey(owner,window,KeyIn(window,@"u",32,NSEventModifierFlagCommand)); ended(); REQUIRE([macro.key isEqual:@"U"]);
    // How shortcuts are saved: +NoCommandKey only without Command; F1–F20 alone.
    struct { NSString *chars, *ignoring; unsigned short code; NSEventModifierFlags flags; NSString *saved, *shown; } cases[]={
        {@"K",@"K",40,NSEventModifierFlagCommand|NSEventModifierFlagShift,@"K+ShiftKey",@"⇧⌘K"},
        {@"\x0b",@"k",40,NSEventModifierFlagControl,@"K+ControlKey+NoCommandKey",@"⌃K"},
        {@"",@"",96,0,@"+NoCommandKey",@"F5"},
        {@"",@"",96,NSEventModifierFlagCommand|NSEventModifierFlagOption,@"+OptionKey",@"⌥⌘F5"},
        {@"k",@"k",40,NSEventModifierFlagCommand,@"K",@"⌘K"},
        // An arrow and a function key as the keyboard sends them, with the fn flag of their own.
        {@"\uF700",@"\uF700",126,NSEventModifierFlagCommand|NSEventModifierFlagFunction|NSEventModifierFlagNumericPad,@"\uF700",@"⌘↑"},
        {@"\uF708",@"\uF708",96,NSEventModifierFlagFunction,@"\uF708+NoCommandKey",@"F5"},
    };
    for(size_t i=0;i<sizeof cases/sizeof *cases;i++) {
        Click(owner,row,@"Key",NO); REQUIRE(recording(macro));
        SendKey(owner,window,Typed(window,cases[i].chars,cases[i].ignoring,cases[i].code,cases[i].flags));
        if(![macro.key isEqual:cases[i].saved]) fprintf(stderr,"saved %s for case %zu\n",macro.key.UTF8String,i);
        ended(); REQUIRE([macro.key isEqual:cases[i].saved] && [Shown(rows,row) isEqual:cases[i].shown]);
    }
    // Delete removes the shortcut and ends; then the field is empty, without ⊖, and reads "Press a key".
    Click(owner,row,@"Key",NO); SendKey(owner,window,KeyIn(window,@"\x7f",51,0)); ended(); REQUIRE([macro.key isEqual:@""] && [Shown(rows,row) isEqual:@""]);
    Click(owner,row,@"Key",NO); REQUIRE(recording(macro) && recorder.shortcut.length==0 && recorder.removeButton.hidden && [recorder.accessibilityValue isEqual:NSLocalizedString(@"Press a key",@"")]);
    // Without a shortcut too, the field shows a refused key until the next key that can be one.
    SendKey(owner,window,KeyIn(window,@"a",0,0)); REQUIRE(recording(macro) && [recorder.shortcut isEqual:@"A"] && !cell.warning.hidden && recorder.removeButton.hidden && [macro.key isEqual:@""]);
    SendKey(owner,window,KeyIn(window,@"m",46,NSEventModifierFlagCommand|NSEventModifierFlagShift)); ended(); REQUIRE([macro.key isEqual:@"M+ShiftKey"]);
    // ⊖ removes it.
    Click(owner,row,@"Key",NO); REQUIRE(!recorder.removeButton.hidden && [recorder hitTest:[recorder convertPoint:NSMakePoint(NSMidX(recorder.removeButton.frame),NSMidY(recorder.removeButton.frame)) toView:recorder.superview]]==recorder.removeButton);
    [recorder.removeButton performClick:nil]; ended(); REQUIRE([macro.key isEqual:@""]);
    macro.key=@"M+ShiftKey"; owner.pendingShortcutKey=macro.key; [rows reloadItem:macro];
    // Tab and Shift-Tab end it and move on.
    Click(owner,row,@"Key",NO); SendKey(owner,window,KeyIn(window,@"\t",48,0)); REQUIRE(!owner.recordingItem && window.firstResponder!=recorder && cell.superview==nil && [macro.key isEqual:@"M+ShiftKey"]);
    Click(owner,row,@"Key",NO); SendKey(owner,window,KeyIn(window,@"\x19",48,NSEventModifierFlagShift)); REQUIRE(!owner.recordingItem && window.firstResponder!=recorder && cell.superview==nil);
    // A click elsewhere ends it, the focus where the click put it; the field leaves the row once the focus has moved.
    Click(owner,row,@"Key",NO); BOOL editable=contents.editable; contents.editable=YES;
    REQUIRE([window makeFirstResponder:contents] && !owner.recordingItem && window.firstResponder==contents);
    // The field leaves the row on the next turn of the main queue: wait for it, up to two seconds.
    for (NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:2]; cell.superview!=nil && limit.timeIntervalSinceNow>0;) Wait(.01);
    REQUIRE(cell.superview==nil && [Shown(rows,row) isEqual:@"⇧⌘M"] && [macro.key isEqual:@"M+ShiftKey"]);
    // Started on another item before then, the field goes there and stays.
    Click(owner,row,@"Key",NO); REQUIRE([window makeFirstResponder:contents]); Click(owner,otherRow,@"Key",YES);
    REQUIRE(recording(other)); Wait(.05); REQUIRE(recording(other) && [Shown(rows,row) isEqual:@"⇧⌘M"]); CheckRecordingCell(owner,otherRow);
    SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); ended(); contents.editable=editable;
    // A double click on a shortcut records, on an item that was not selected too; on a name it tests the macro.
    [rows deselectAll:nil]; Click(owner,otherRow,@"Key",YES); REQUIRE(recording(other)); SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); ended();
    tests=0; [rows deselectAll:nil]; Click(owner,otherRow,@"Name",YES); REQUIRE(tests==1 && !owner.recordingItem);
    // A double click on a submenu opens or closes it, on its name or its shortcut; submenus and separators have no shortcut.
    BOOL open=[rows isItemExpanded:group];
    Click(owner,groupRow,@"Key",YES); REQUIRE([rows isItemExpanded:group]!=open && !owner.recordingItem);
    Click(owner,[rows rowForItem:group],@"Name",YES); REQUIRE([rows isItemExpanded:group]==open && !owner.recordingItem);
    [rows expandItem:group]; row=[rows rowForItem:macro]; otherRow=[rows rowForItem:other]; line=[rows rowForItem:separator];
    for(TSMacroTreeNode *item in @[group,separator]) {
        Click(owner,[rows rowForItem:item],@"Key",NO); Click(owner,[rows rowForItem:item],@"Key",NO); Click(owner,[rows rowForItem:item],@"Key",YES);
        REQUIRE(!owner.recordingItem && ![owner beginRecordingShortcutAtRow:[rows rowForItem:item]] && cell.superview==nil);
        [rows expandItem:group];
    }
    row=[rows rowForItem:macro]; otherRow=[rows rowForItem:other]; line=[rows rowForItem:separator];
    // VoiceOver's press on a macro's shortcut records; a submenu's and a separator's cannot be pressed.
    NSInteger key=[rows columnWithIdentifier:@"Key"];
    TSMacroShortcutCell *pressedCell=(TSMacroShortcutCell *)[rows preparedCellAtColumn:key row:otherRow];
    REQUIRE([pressedCell isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)] && [pressedCell accessibilityPerformPress] && recording(other));
    SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); ended();
    for(NSNumber *n in @[@([rows rowForItem:group]),@(line)]) { NSCell *c=[rows preparedCellAtColumn:key row:n.integerValue]; REQUIRE(![c isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)] && ![c accessibilityPerformPress] && !owner.recordingItem); }
    // Another selection ends it; so do changed items (added, removed, moved), and closing the window (releaseWindowControls).
    Click(owner,row,@"Key",NO); [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:otherRow] byExtendingSelection:NO]; REQUIRE(!owner.recordingItem && cell.superview==nil);
    Click(owner,otherRow,@"Key",NO); REQUIRE(recording(other)); [owner outlineViewItemsChanged:nil]; ended();
    // The conflicts sheet's Return to Editing records the shortcut of the item it selects.
    REQUIRE([owner beginRecordingShortcutForItem:macro] && recording(macro) && rows.selectedRow==row); SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); ended();
    // While an item is renamed, recording ends the renaming first, keeping the name typed.
    [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; REQUIRE([window makeFirstResponder:rows] && [owner beginRenamingSelectedItem]);
    [Renaming(window,rows) insertText:@"MetaPost 2" replacementRange:NSMakeRange(0,8)];
    REQUIRE([owner beginRecordingShortcutAtRow:row] && recording(macro) && [macro.name isEqual:@"MetaPost 2"] && !Renaming(window,rows));
    SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); ended(); macro.name=@"MetaPost";
    // Not recording, Command-S is the menus' (Save, saveDocument:): the editor's key monitor passes it on.
    NSEvent *commandS=KeyIn(window,@"s",1,NSEventModifierFlagCommand); REQUIRE([owner keyForContents:commandS]==commandS);
    // A sheet on the window: no recording.
    { NSWindow *sheet=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,10,10) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
      Method m=class_getInstanceMethod(NSWindow.class,@selector(attachedSheet)); IMP real=method_setImplementation(m,imp_implementationWithBlock(^id(id w){ return w==window?sheet:nil; }));
      REQUIRE(![owner beginRecordingShortcutAtRow:row] && !owner.recordingItem); method_setImplementation(m,real); }
    // A saved shortcut that is inactive: the triangle before it in the list, read out with the reason; the reason
    // below the contents, after the triangle, while the item is selected.
    NSString *reason=[NSString stringWithFormat:NSLocalizedString(@"This shortcut is inactive because macro “%@” (%@) uses it first.",@""),[macros stringByAppendingString:@" › MetaPost"],@"⌃⌥⌘R"];
    [Conflicts setObject:reason forKey:other]; [rows reloadData]; [rows expandItem:nil expandChildren:YES]; [window.contentView layoutSubtreeIfNeeded];
    TSMacroShortcutCell *warned=(TSMacroShortcutCell *)[rows preparedCellAtColumn:key row:otherRow]; NSRect tipRect=[rows frameOfCellAtColumn:key row:otherRow];
    REQUIRE(warned.showsWarning && [warned.accessibilityLabel isEqual:reason] && [warned.accessibilityValue isEqual:@"⌃⌥⌘R"] && [warned.stringValue isEqual:@"⌃⌥⌘R"]);
    REQUIRE(![(TSMacroShortcutCell *)[rows preparedCellAtColumn:key row:row] showsWarning] && [(id)rows.delegate outlineView:rows toolTipForCell:warned rect:&tipRect tableColumn:[rows tableColumnWithIdentifier:@"Key"] item:other mouseLocation:NSZeroPoint]==reason);
    REQUIRE(YellowPixels(rows,otherRow)>3 && YellowPixels(rows,row)==0);
    [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:otherRow] byExtendingSelection:NO];
    REQUIRE([owner.shortcutStatus.stringValue isEqual:reason] && !owner.shortcutStatusMark.hidden && YellowPixels(rows,otherRow)>3);
    CheckWarningMarksAsSettings(owner,rows,otherRow);
    // Recorded, the field shows the shortcut without a triangle; a refusal replaces the reason, which comes back after it.
    Click(owner,otherRow,@"Key",NO); REQUIRE(recording(other) && cell.warning.hidden && [owner.shortcutStatus.stringValue isEqual:reason]);
    SendKey(owner,window,KeyIn(window,@"a",0,0)); REQUIRE([owner.shortcutStatus.stringValue isEqual:unusable] && !cell.warning.hidden);
    SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); ended(); REQUIRE([owner.shortcutStatus.stringValue isEqual:reason] && !owner.shortcutStatusMark.hidden);
    [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; REQUIRE(owner.shortcutStatus.stringValue.length==0 && owner.shortcutStatusMark.hidden);
    [Conflicts removeAllObjects];
    // The status mark sits on the first line of the message, just before it.
    owner.recordingError=nil; [owner showShortcutStatus:unusable]; [owner.editorView layoutSubtreeIfNeeded];
    { NSTextField *label=owner.shortcutStatus; NSImageView *mark=owner.shortcutStatusMark; NSRect m=[mark alignmentRectForFrame:mark.frame], t=[label alignmentRectForFrame:label.frame];
      REQUIRE(fabs(NSMaxX(m)+4-NSMinX(t))<.5 && NSMaxY(m)<=NSMaxY(t)+2 && NSMinY(m)>=NSMaxY(t)-2*label.font.boundingRectForFont.size.height); }
    [owner showShortcutStatus:nil]; REQUIRE(owner.shortcutStatusMark.hidden && owner.shortcutStatus.stringValue.length==0);
    (void)noKey;
    save.target=targets[0]; save.action=actions[0]; cancel.target=targets[1]; cancel.action=actions[1];
    [window makeFirstResponder:window]; [owner setValue:@NO forKey:@"dataTouched"];
    SampleRoot=kept; [rows reloadData]; [rows expandItem:nil expandChildren:YES];
}
// The field follows its row when the sidebar is resized, at the narrowest, the first and the widest width.
static void CheckRecordingAtSidebarWidths(TSMacroEditor *owner) {
    NSWindow *window=[owner valueForKey:@"window"]; TSMacroOutlineView *rows=[owner valueForKey:@"outlineView"]; NSSplitView *splitView=SplitOf(window).splitView;
    TSMacroTreeNode *kept=SampleRoot,*macro=nil; SampleRoot=MakeSampleRoot(&macro,NULL); [rows reloadData]; [rows expandItem:nil expandChildren:YES]; [window.contentView layoutSubtreeIfNeeded];
    NSInteger row=[rows rowForItem:macro]; CGFloat first=NSWidth(splitView.arrangedSubviews.firstObject.frame);
    REQUIRE([owner beginRecordingShortcutAtRow:row]);
    for(NSNumber *wanted in @[@160,@(first),@320]) { [splitView setPosition:wanted.doubleValue ofDividerAtIndex:0]; [window.contentView layoutSubtreeIfNeeded]; CheckRecordingCell(owner,row); }
    [splitView setPosition:first ofDividerAtIndex:0]; [window.contentView layoutSubtreeIfNeeded];
    [owner endShortcutRecording]; REQUIRE(!owner.recordingCell.superview);
    SampleRoot=kept; [rows reloadData]; [rows expandItem:nil expandChildren:YES];
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
    // No label is left but the message; nothing runs into the contents.
    for(NSView *v in main.subviews) if(!v.hidden && v!=scroll && v!=line) {
        if([v isKindOfClass:NSTextField.class] && v!=owner.shortcutStatus) { fprintf(stderr,"LABEL LEFT %s\n",((NSTextField *)v).stringValue.UTF8String); REQUIRE(NO); }
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
    CheckSidebar(owner,list); CheckSidebarFocusRing(owner);
    CheckNibShortcutRows(owner);
    CheckContents(owner,window);
    NSScrollView *scroll=[contentsOf(owner) enclosingScrollView];
    // The message in the band 20 points from the sidebar and from the trailing edge, as Insert: the triangle where
    // the text of a label in that band begins, the text 4 points after it.
    { NSTextField *label=owner.shortcutStatus; NSImageView *mark=owner.shortcutStatusMark; NSRect m=[mark alignmentRectForFrame:mark.frame], t=[label alignmentRectForFrame:label.frame];
      NSEdgeInsets inset=label.alignmentRectInsets; CGFloat start=20+inset.left, end=NSWidth(host.bounds)-20-inset.right;
      REQUIRE(label.superview==host && mark.superview==host && [label.textColor isEqual:NSColor.labelColor] && label.font.pointSize==NSFont.smallSystemFontSize);
      if(fabs(NSMinX(m)-start)>=.5 || fabs(NSMinX(t)-NSMaxX(m)-4)>=.5 || fabs(NSMaxX(t)-end)>=.5) fprintf(stderr,"MESSAGE mark %s text %s in %.1f\n",NSStringFromRect(m).UTF8String,NSStringFromRect(t).UTF8String,NSWidth(host.bounds));
      REQUIRE(fabs(NSMinX(m)-start)<.5 && fabs(NSMinX(t)-NSMaxX(m)-4)<.5 && fabs(NSMaxX(t)-end)<.5); }
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
    NSArray *placed=@[scroll,owner.insertPlaceholderButton,owner.placeholdersButton,save,cancel,test];
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
// - elsewhere (nothing focused, Insert, the buttons): Return saves, Escape cancels.
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
    REQUIRE([window makeFirstResponder:window]);
    SendKey(owner,window,KeyIn(window,@"\r",36,0)); SendKey(owner,window,KeyIn(window,@"\x1b",53,0));
    REQUIRE([recorder.log isEqual:(@[save.title,cancel.title])]);
    // Other keys, and Command-Return, are not the monitor's.
    REQUIRE([window makeFirstResponder:contents]);
    NSEvent *letter=KeyIn(window,@"x",7,0); REQUIRE([owner keyForContents:letter]==letter);
    NSEvent *commandReturn=KeyIn(window,@"\r",36,NSEventModifierFlagCommand); REQUIRE([owner keyForContents:commandReturn]==commandReturn);
    contents.editable=editable; contents.string=@""; [window makeFirstResponder:window];
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
// The renaming that a second click on a name starts after the double-click interval: it starts then, and
// whatever comes first cancels it: a key (an arrow, Escape, a letter), another selection, a double click,
// Return (which renames at once), the list leaving its window, the window closing. The window is taken for the
// key window here, as on screen.
static IMP KeyWindowIMP, AppKeyWindowIMP; static BOOL KeyWindow(id self, SEL cmd) { return YES; }
static NSWindow *TheKeyWindow; static id AppKeyWindow(id self, SEL cmd) { return TheKeyWindow; }
static NSEvent *Mouse(NSWindow *window, NSEventType type, NSPoint at, NSInteger clicks) {
    return [NSEvent mouseEventWithType:type location:at modifierFlags:0 timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:clicks pressure:type==NSEventTypeLeftMouseDown?1:0];
}
static void CheckPendingRename(TSMacroEditor *owner) {
    NSWindow *window=[owner valueForKey:@"window"]; TSMacroOutlineView *rows=[owner valueForKey:@"outlineView"];
    REQUIRE([rows isKindOfClass:TSMacroOutlineView.class] && (id)window.delegate==owner);
    // The responder chain of an action sent to no target starts at the application's key window.
    Method key=class_getInstanceMethod(NSWindow.class,@selector(isKeyWindow)); KeyWindowIMP=method_setImplementation(key,(IMP)KeyWindow);
    Method appKey=class_getInstanceMethod(NSApplication.class,@selector(keyWindow)); TheKeyWindow=window; AppKeyWindowIMP=method_setImplementation(appKey,(IMP)AppKeyWindow);
    TSMacroTreeNode *kept=SampleRoot,*macro=nil,*separator=nil; SampleRoot=MakeSampleRoot(&macro,&separator);
    [rows reloadData]; [rows expandItem:nil expandChildren:YES]; [window.contentView layoutSubtreeIfNeeded];
    NSInteger row=[rows rowForItem:macro], other=[rows rowForItem:separator];
    NSTimeInterval later=NSEvent.doubleClickInterval+.25;
    void (^select)(void)=^{ [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; REQUIRE([window makeFirstResponder:rows]); };
    // Nothing else: the name is renamed.
    select(); [rows scheduleRenameOfRow:row]; REQUIRE(rows.pendingRename); Wait(later);
    REQUIRE(Renaming(window,rows) && rows.editedRow==row && !rows.pendingRename);
    SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); REQUIRE(!Renaming(window,rows) && [macro.name isEqual:@"MetaPost"]);
    NSString *arrow=[NSString stringWithFormat:@"%C",(unichar)NSRightArrowFunctionKey], *down=[NSString stringWithFormat:@"%C",(unichar)NSDownArrowFunctionKey];
    NSArray *cancels=@[
        @[@"an arrow key",^{ SendKey(owner,window,KeyIn(window,arrow,124,NSEventModifierFlagFunction|NSEventModifierFlagNumericPad)); }],
        @[@"Escape",^{ SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); }],
        @[@"a letter",^{ SendKey(owner,window,KeyIn(window,@"q",12,0)); }],
        @[@"another selection and back",^{ [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:other] byExtendingSelection:NO]; select(); }],
        @[@"the list leaving its window",^{ [rows viewWillMoveToWindow:nil]; }],
        @[@"a double click",^{
            // The second click of a double click: its mouse up is already waiting, so the list's tracking ends at once.
            NSRect cell=[rows frameOfCellAtColumn:[rows columnWithIdentifier:@"Name"] row:row]; NSPoint at=[rows convertPoint:NSMakePoint(NSMinX(cell)+6,NSMidY(cell)) toView:nil];
            SEL action=rows.doubleAction; id target=rows.target; rows.doubleAction=NULL;
            [NSApp postEvent:Mouse(window,NSEventTypeLeftMouseUp,at,2) atStart:YES]; [rows mouseDown:Mouse(window,NSEventTypeLeftMouseDown,at,2)];
            rows.doubleAction=action; rows.target=target; }],
        @[@"Return",^{ SendKey(owner,window,KeyIn(window,@"\r",36,0)); REQUIRE(Renaming(window,rows)); SendKey(owner,window,KeyIn(window,@"\x1b",53,0)); }],
        @[@"the window closing",^{ [owner cancelPendingListRename]; }],
    ];
    for(NSArray *c in cancels) {
        select(); [rows scheduleRenameOfRow:row]; ((void (^)(void))c[1])();
        if(window.firstResponder!=rows) REQUIRE([window makeFirstResponder:rows]);
        if(rows.selectedRow!=row) select();
        Wait(later);
        if(Renaming(window,rows) || rows.pendingRename) fprintf(stderr,"PENDING RENAME after %s\n",[c[0] UTF8String]);
        REQUIRE(!Renaming(window,rows) && !rows.pendingRename);
    }
    // Down arrow moves the selection; the renaming does not follow it.
    select(); [rows scheduleRenameOfRow:row]; SendKey(owner,window,KeyIn(window,down,125,NSEventModifierFlagFunction|NSEventModifierFlagNumericPad)); Wait(later); REQUIRE(!Renaming(window,rows));
    method_setImplementation(key,KeyWindowIMP); method_setImplementation(appKey,AppKeyWindowIMP); TheKeyWindow=nil;
    [window makeFirstResponder:window];
    SampleRoot=kept; [rows reloadData]; [rows expandItem:nil expandChildren:YES];
}
// A new item or submenu, made by ＋ or the menu of the bar, is named at once (the outline controller's own code
// adds it after the selection and selects it); a new separator is not.
@interface TSMacroEditor (Bar)
- (void)listAddPressed:(id)sender;
- (void)listActionChosen:(NSMenuItem *)sender;
@end
static void CheckNewItemNamed(TSMacroEditor *owner) {
    NSWindow *window=[owner valueForKey:@"window"]; NSOutlineView *rows=[owner valueForKey:@"outlineView"];
    NSButton *newItem=[owner valueForKey:@"newItemButton"],*submenu=[owner valueForKey:@"submenuButton"],*separatorButton=[owner valueForKey:@"separatorButton"];
    REQUIRE(newItem.action==@selector(addNewItem:) && submenu.action==@selector(addSubmenu:) && separatorButton.action==@selector(addSeparator:));
    TSMacroTreeNode *kept=SampleRoot,*macro=nil,*separator=nil; SampleRoot=MakeSampleRoot(&macro,&separator);
    [rows reloadData]; [rows expandItem:nil expandChildren:YES]; [window.contentView layoutSubtreeIfNeeded];
    for(NSButton *b in @[newItem,submenu,separatorButton]) b.enabled=YES;
    [owner syncListControls];
    NSArray<NSMenuItem *> *items=owner.listBar.actionItems;
    struct { int how; NSString *name; BOOL named; } cases[]={{0,NEW_ITEM_NAME,YES},{1,NEW_SUBMENU_NAME,YES},{2,nil,NO}};
    for(size_t i=0;i<3;i++) {
        [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:[rows rowForItem:macro]] byExtendingSelection:NO]; REQUIRE([window makeFirstResponder:rows]);
        NSInteger count=SampleRoot.numberOfChildren;
        if(cases[i].how==0) [owner listAddPressed:nil]; else [owner listActionChosen:items[cases[i].how-1]];
        REQUIRE(SampleRoot.numberOfChildren==count+1);
        TSMacroTreeNode *added=[rows itemAtRow:rows.selectedRow];
        NSTextView *editor=Renaming(window,rows);
        if(!!editor!=cases[i].named) fprintf(stderr,"NEW %s %s renamed\n",added.name.UTF8String,editor?"is":"is not");
        REQUIRE(!!editor==cases[i].named && added==[SampleRoot childAtIndex:[SampleRoot indexOfChild:macro]+1]);
        if(editor) { REQUIRE(rows.editedRow==rows.selectedRow && [editor.string isEqual:cases[i].name] && NSEqualRanges(editor.selectedRange,NSMakeRange(0,cases[i].name.length)));
            [editor insertText:@"Named" replacementRange:NSMakeRange(0,editor.string.length)]; SendKey(owner,window,KeyIn(window,@"\r",36,0)); REQUIRE([added.name isEqual:@"Named"] && !Renaming(window,rows)); }
        else REQUIRE(added.isSeparator);
    }
    [window makeFirstResponder:window]; [owner setValue:@NO forKey:@"dataTouched"];
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
        // The focus ring AppKit draws around the scroll view of a focused list, which caching the display leaves out.
        NSTableView *focused=(NSTableView *)view.window.firstResponder;
        if([focused isKindOfClass:NSTableView.class] && focused.enclosingScrollView && DrawsFocusRingAroundList(focused)) {
            NSScrollView *scroll=focused.enclosingScrollView; NSRect ring=[scroll convertRect:scroll.focusRingMaskBounds toView:view];
            if(view.isFlipped) ring.origin.y=NSHeight(view.bounds)-NSMaxY(ring);
            [NSGraphicsContext saveGraphicsState]; NSSetFocusRingStyle(NSFocusRingOnly); NSRectFill(ring); [NSGraphicsContext restoreGraphicsState];
        }
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
// window does not have at first. The states: as it opens (a macro selected, its contents), an item renamed, the
// contents focused, a shortcut recorded in the list (recording), a key refused there because another macro uses
// it (refused) or because it cannot be a shortcut (invalid), a saved shortcut that is inactive selected (conflict),
// larger, and smallest.
static void RenderOnly(const char *path, NSString *only) {
    DrawAsKeyWindow();
    TSMacroEditor *owner=[TSMacroEditor new]; Editor=owner;
    NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(path)] bundle:nil];
    NSArray *objects; REQUIRE([nib instantiateWithOwner:owner topLevelObjects:&objects]);
    NSWindow *window=[owner valueForKey:@"window"]; REQUIRE(window && !window.visible);
    UseNameCells(owner);
    [window setFrameUsingName:@"Macro Editor"];
    [owner useSystemFont]; [owner installShortcutStatus]; [owner hideNibShortcutRows]; [owner installPlaceholderControls]; [owner layoutDialogButtons]; [owner installSidebar];
    NSArray *parts=[only componentsSeparatedByString:@"-"]; NSString *state=parts.firstObject; BOOL dark=[parts.lastObject isEqual:@"dark"];
    NSOutlineView *rows=[owner valueForKey:@"outlineView"];
    TSMacroTreeNode *shown=nil; SampleRoot=MakeSampleRoot(&shown,NULL);
    if([state isEqual:@"conflict"]) {
        // Two saved shortcuts that another macro uses first: the selected one and \ref{•‹label›}.
        NSString *format=NSLocalizedString(@"This shortcut is inactive because macro “%@” (%@) uses it first.",@""), *macros=NSLocalizedString(@"Macros",@"");
        [Conflicts setObject:[NSString stringWithFormat:format,[macros stringByAppendingString:@" › Begin/End › equation*"],@"⇧⌘M"] forKey:shown];
        [Conflicts setObject:[NSString stringWithFormat:format,[macros stringByAppendingString:@" › Insert Reference"],@"⌃⌥⌘R"] forKey:[SampleRoot childAtIndex:2]];
    }
    [rows reloadData]; [rows expandItem:nil expandChildren:YES];
    NSInteger row=[rows rowForItem:shown]; [rows selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    REQUIRE(owner.previousItem==shown);
    [[owner valueForKey:@"nameField"] setStringValue:shown.name];
    NSTextView *contents=contentsOf(owner); contents.editable=YES; contents.string=shown.content; [owner syncPlaceholderControls];
    // As after the first key the window has had: the default button drawn as such.
    { NSButton *save=[owner valueForKey:@"saveButton"]; [save highlight:YES]; [save highlight:NO]; }
    NSRect frame=window.frame;
    if([state isEqual:@"resized"]) { frame.size.width+=260; frame.size.height+=160; frame.origin.y-=160; }
    if([state isEqual:@"smallest"]) frame.size=window.minSize;
    [window setFrame:frame display:NO]; [window.contentView layoutSubtreeIfNeeded];
    [window makeFirstResponder:rows];
    if([state isEqual:@"renaming"]) REQUIRE([owner beginRenamingSelectedItem]);
    if([state isEqual:@"contents"]) { REQUIRE([window makeFirstResponder:contents]); contents.selectedRange=NSMakeRange(18,10); }
    if([@[@"recording",@"refused",@"invalid"] containsObject:state]) REQUIRE([owner beginRecordingShortcutAtRow:row]);
    if([state isEqual:@"refused"]) { SendKey(owner,window,Typed(window,@"\x05",@"e",14,NSEventModifierFlagControl|NSEventModifierFlagCommand)); REQUIRE(owner.recordingError && [owner.refusedShortcut isEqual:@"⌃⌘E"]); }
    if([state isEqual:@"invalid"]) { SendKey(owner,window,KeyIn(window,@"a",0,0)); REQUIRE(owner.recordingError && [owner.refusedShortcut isEqual:@"A"]); }
    NSString *name=[[@(path) stringByDeletingLastPathComponent].stringByDeletingLastPathComponent.lastPathComponent stringByDeletingPathExtension];
    if([@(path).lastPathComponent containsString:@"101300"]) name=[name stringByAppendingString:@"-10.13"];
    WritePNG(window.contentView.superview,[NSAppearance appearanceNamed:dark?NSAppearanceNameDarkAqua:NSAppearanceNameAqua],[NSString stringWithFormat:@"%s/%@-%@.png",getenv("TS_RENDER_DIR"),name,only]);
    [owner endShortcutRecording]; [owner stopKeyMonitor];
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
    TSMacroEditor *owner=[TSMacroEditor new]; Editor=owner; NSWindow *previous=nil; NSVisualEffectView *previousSidebar=nil; id previousMonitor=nil; TSShortcutRecordingCell *previousCell=nil;
    for(int open=0;open<3;open++) {
        NSNib *nib=[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(path)] bundle:nil];
        NSArray *objects; REQUIRE([nib instantiateWithOwner:owner topLevelObjects:&objects]);
        NSWindow *window=[owner valueForKey:@"window"]; REQUIRE(window && window!=previous && !window.visible);
        UseNameCells(owner);
        [owner useSystemFont]; [owner installShortcutStatus]; [owner hideNibShortcutRows]; [owner installPlaceholderControls]; [owner layoutDialogButtons]; [owner installSidebar];
        REQUIRE(owner.sidebar && owner.sidebar!=previousSidebar && owner.sidebar.window==window && owner.editorView.window==window && contentsOf(owner).window==window && ContentsLine(owner).window==window);
        REQUIRE(owner.recordingCell && owner.recordingCell!=previousCell && owner.recordingCell.window==nil && owner.insertPlaceholderButton.window==window && owner.shortcutStatus.window==window && owner.shortcutStatusMark.window==window && owner.listBar.window==window);
        REQUIRE(owner.contentsKeyMonitor && owner.contentsKeyMonitor!=previousMonitor);
        CheckEditor(owner,window);
        CheckKeys(owner); CheckSecondClick(owner);
        // The recording of a shortcut, Insert and its help work in the new window too.
        CheckRecording(owner); CheckPlaceholderControls(owner);
        previous=window; previousSidebar=owner.sidebar; previousMonitor=owner.contentsKeyMonitor; previousCell=owner.recordingCell;
        // Closing ends a recording and takes the field away with the other controls.
        { TSMacroOutlineView *rows=[owner valueForKey:@"outlineView"]; TSMacroTreeNode *macro=nil; SampleRoot=MakeSampleRoot(&macro,NULL); [rows reloadData]; [rows expandItem:nil expandChildren:YES];
          REQUIRE([owner beginRecordingShortcutAtRow:[rows rowForItem:macro]]); [rows scheduleRenameOfRow:0]; [owner releaseWindowControls];
          REQUIRE(!rows.pendingRename && !owner.recordingItem && !rows.recordingView && previousCell.superview==nil); SampleRoot=nil; }
        REQUIRE(!owner.sidebar && !owner.listBar && !owner.editorView && !owner.recordingCell && !owner.insertPlaceholderButton && !owner.placeholdersButton && !owner.shortcutStatus && !owner.shortcutStatusMark && !owner.contentsKeyMonitor);
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
    Conflicts=[NSMapTable strongToStrongObjectsMapTable]; UseTestMenu();
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
    [owner hideNibShortcutRows];[owner installPlaceholderControls];
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
    if(round==0) { CheckRecording(owner); CheckRecordingAtSidebarWidths(owner); CheckPlaceholderControls(owner); CheckKeys(owner); CheckSecondClick(owner); CheckPendingRename(owner); CheckNewItemNamed(owner); CheckSeparatorImage(); }
    NSArray<NSValue *> *openedFrames=MainFrames(owner);
    NSTextField *label=owner.shortcutStatus; NSView *host=owner.editorView;
    // The messages, as long as they come, wrap within the band, at this width and at the narrowest.
    NSMutableArray<NSString *> *messages=[NSMutableArray arrayWithObjects:@"This shortcut is inactive because it conflicts with “Typeset › plain TeX” (⇧⌘T).",@"このキーは“タイプセット › plain TeX”（⇧⌘T）と重なっているため無効です。",nil];
    for(NSString *format in @[@"This shortcut is inactive because macro “%@” (%@) uses it first.",@"This shortcut is inactive because it conflicts with “%@” (%@).",@"This shortcut conflicts with macro “%@” (%@), whose shortcut will be inactive because it appears later."])
        [messages addObject:[NSString stringWithFormat:NSLocalizedString(format,@""),[NSString stringWithFormat:@"%@ › Begin/End › equation*",NSLocalizedString(@"Macros",@"")],@"⌃⌥⇧⌘W"]];
    // The reasons a key pressed while recording is refused: one command that uses it, two, or a key that cannot be one.
    NSString *longMacro=[NSString stringWithFormat:@"%@ › Begin/End › equation*",NSLocalizedString(@"Macros",@"")];
    [messages addObject:[NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.",@""),longMacro]];
    [messages addObject:[NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by:\n%@",@""),[@[@"Typeset › Typeset",longMacro] componentsJoinedByString:@"\n"]]];
    [messages addObject:NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.",@"")];
    [messages addObject:NSLocalizedString(@"Shortcuts with the Globe key (fn) can't be assigned to TeXShop commands.",@"")];
    NSRect frame=window.frame;
    for(int narrow=0;narrow<2;narrow++) {
      if(narrow) { NSRect n=window.frame; n.size.width=window.minSize.width; [window setFrame:n display:NO]; [window.contentView layoutSubtreeIfNeeded]; }
      for (NSString *text in messages)
      for (NSAppearanceName mode in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]) {
        host.appearance=[NSAppearance appearanceNamed:mode];[owner showShortcutStatus:text];
        REQUIRE(NSContainsRect(host.bounds,label.frame));
        CGFloat needed=[label.cell cellSizeForBounds:NSMakeRect(0,0,label.bounds.size.width,CGFLOAT_MAX)].height;
        if(needed>label.bounds.size.height) fprintf(stderr,"MESSAGE %.0f > %.0f at width %.0f: %s\n",needed,label.bounds.size.height,label.bounds.size.width,text.UTF8String);
        REQUIRE(needed<=label.bounds.size.height);
        REQUIRE(!owner.shortcutStatusMark.hidden && NSContainsRect(host.bounds,owner.shortcutStatusMark.frame));
        for (NSView *v in host.subviews) if(v!=label && v!=owner.shortcutStatusMark && !v.hidden) { if([v isKindOfClass:NSScrollView.class]) REQUIRE(NSContainsRect(host.bounds,v.frame)); if(NSIntersectsRect(label.frame,v.frame)) fprintf(stderr,"OVERLAP %s %s label %s\n",NSStringFromClass(v.class).UTF8String,NSStringFromRect(v.frame).UTF8String,NSStringFromRect(label.frame).UTF8String); REQUIRE(!NSIntersectsRect(label.frame,v.frame)); }
        NSBitmapImageRep *rep=[window.contentView bitmapImageRepForCachingDisplayInRect:[window.contentView bounds]];[window.contentView cacheDisplayInRect:[window.contentView bounds] toBitmapImageRep:rep];
        REQUIRE(rep.pixelsWide>400 && rep.pixelsHigh>300 && !window.visible);
      }
    }
    [owner showShortcutStatus:nil]; host.appearance=nil;
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
    printf("PASS: %s sidebar, contents, keys, renaming in the list, recording shortcuts in the list and their warnings, reopening, status band: bounds, wrapping, control separation, resizing, idempotence\n",argv[1]);
} return 0; }
