// Settings integration tests. No visible windows, user defaults or macro files.
#import "TSMacroSelection.h"
#import "TestAppKitIsolation.h"
#import "TSKeyboardShortcuts.m"
#import "TSSettingsCategory.h"
#import "TSMacroTreeNode.h"
#import "TSPrefPaneLayout.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
static NSUInteger forwardedWindowEvents;
static void AppKitSendEventProbe(id receiver, SEL selector, NSEvent *event) { forwardedWindowEvents++; }
static NSString *nibPath;
static NSDictionary *localizedStrings;
static IMP originalLocalization;
static NSString *Localized(NSBundle *bundle,SEL cmd,NSString *key,NSString *value,NSString *table){return localizedStrings[key] ?: ((id(*)(id,SEL,id,id,id))originalLocalization)(bundle,cmd,key,value,table);}
static void CheckButtons(NSView *view,NSView *root){
 for(NSView *child in view.subviews){
  if(child.hidden)continue;
  if([child isKindOfClass:NSButton.class]) {NSRect rect=[child convertRect:child.bounds toView:root];REQUIRE(NSMinX(rect)>=0 && NSMaxX(rect)<=NSWidth(root.bounds)+1 && NSMinY(rect)>=0 && NSMaxY(rect)<=NSHeight(root.bounds)+1);REQUIRE(NSWidth(child.frame)+1>=child.intrinsicContentSize.width);}
  if([child isKindOfClass:NSClipView.class]) CheckButtons(((NSClipView *)child).documentView,((NSClipView *)child).documentView);
  else CheckButtons(child,root);
 }
}
// Independent input fixture: two groups with the production row identifiers.
static NSView *InputHeader(void) {
 NSView *header=[NSView new];NSMutableArray *groups=[NSMutableArray array];
 for(NSString *key in @[@"bindings",@"completion"]){
  NSBox *box=[NSBox new];[TSSettingsGroupStyle applyToBox:box];box.identifier=[@"group." stringByAppendingString:key];
  box.accessibilityLabel=NSLocalizedString([key isEqual:@"bindings"]?@"Key Bindings":@"Command Completion",@"");
  NSMutableArray *rows=[NSMutableArray array];
  NSTextField *heading=[NSTextField labelWithString:box.accessibilityLabel];heading.identifier=[@"heading." stringByAppendingString:key];[rows addObject:heading];
  for(NSUInteger i=0;i<([key isEqual:@"completion"]?3:1);i++){
   NSButton *button=[NSButton buttonWithTitle:i==0?NSLocalizedString(@"Completion trigger",@""):@"Input fixture" target:nil action:NULL];
   NSView *row=[TSPrefPaneLayout viewForRow:[[TSSettingsControlRow alloc]initWithControls:@[button] indentation:0]];
   if([key isEqual:@"completion"] && i==0)row.identifier=@"row.settings.completion-trigger-label";
   [rows addObject:row];
  }
  [TSPrefPaneLayout attachRows:rows toView:box.contentView];
  [NSLayoutConstraint activateConstraints:@[[box.contentView.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:8],[box.contentView.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-8],[box.contentView.topAnchor constraintEqualToAnchor:box.topAnchor constant:8],[box.contentView.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8]]];
  [groups addObject:box];
 }
 [TSPrefPaneLayout attachRows:groups toView:header];return header;
}
static NSString *fixtureCharacters;
static BOOL fixtureKeyWindow=YES;
static NSUInteger forwardedKeys;
static void RejectForwardedKey(id self,SEL cmd,NSEvent *event){forwardedKeys++;}
static NSString *Characters(id self,SEL cmd,NSEventModifierFlags flags){ return fixtureCharacters; }
static BOOL IsKey(id self,SEL cmd){return fixtureKeyWindow;}
static NSEvent *Event(NSString *text,NSUInteger flags,NSUInteger code){return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:code];}
@interface Shell:TSSettingsWindowController @end
@implementation Shell
- (void)loadWindow {NSArray *objects; REQUIRE([[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:nibPath] bundle:nil] instantiateWithOwner:self topLevelObjects:&objects]);}
@end
@interface Delegate:NSObject<TSSettingsWindowDelegate> @end
@implementation Delegate
- (BOOL)settingsMayChangeCategory{return YES;}
- (void)settingsChangeFont:(NSFontManager *)sender{}
@end
static NSMenuItem *Item(NSString *title,NSString *key,NSUInteger flags){NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:title action:@selector(description) keyEquivalent:key];item.identifier=[@"TSShortcut." stringByAppendingString:title];item.keyEquivalentModifierMask=flags;item.allowsAutomaticKeyEquivalentLocalization=NO;return item;}
static TSShortcutMacro *Macro(NSString *name,NSString *key,NSUInteger flags,NSUInteger index){return [[TSShortcutMacro alloc]initWithName:name path:[@"Group ▸ " stringByAppendingString:name] indexPath:[NSIndexPath indexPathWithIndex:index] serializedKey:key key:key modifiers:flags];}
static void CheckEventPriority(void) {
 const NSUInteger C=NSEventModifierFlagCommand,S=NSEventModifierFlagShift;
 // Before / nested Macros / After mirrors the application's top-level order.
 NSArray<NSDictionary *> *cases=@[
  @{@"input":@"{",@"plain":@"[",@"flags":@(C|S),@"before":@[@"{",@(C)],@"macros":@[@[@"{",@(C|S)]],@"winner":@"before"},
  @{@"input":@"+",@"plain":@"=",@"flags":@(C|S),@"after":@[@"=",@(C|S)],@"macros":@[@[@"+",@(C)]],@"winner":@"macro0"},
  @{@"input":@"?",@"plain":@"/",@"flags":@(C|S),@"after":@[@"?",@(C)],@"macros":@[@[@"?",@(C|S)]],@"winner":@"macro0"},
  @{@"input":@"=",@"plain":@"0",@"flags":@(C|S),@"before":@[@"=",@(C)],@"macros":@[@[@"0",@(C|S)]],@"winner":@"before"},
  @{@"input":@"1",@"plain":@"+",@"flags":@(C|S),@"after":@[@"1",@(C)],@"macros":@[@[@"+",@(C|S)]],@"winner":@"after"},
  @{@"input":@"1",@"plain":@"+",@"flags":@(C|S),@"before":@[@"+",@(C|S)],@"after":@[@"1",@(C)],@"macros":@[],@"winner":@"after"},
  @{@"input":@"z",@"plain":@"z",@"flags":@(C),@"macros":@[@[@"z",@(C)]],@"winner":@"macro0"},
  @{@"input":@"?",@"plain":@"/",@"flags":@(C|S),@"macros":@[@[@"?",@(C|S)],@[@"?",@(C)]],@"winner":@"macro0"},
  @{@"input":@"z",@"plain":@"z",@"flags":@(C),@"macros":@[@[@"z",@(C)],@[@"z",@(C)]],@"winner":@"macro0"},
  @{@"input":@"z",@"plain":@"z",@"flags":@(C),@"after":@[@"z",@(C)],@"macros":@[@[@"z",@(C)]],@"winner":@"after"},
  // Letter input does not acquire an unshifted punctuation fallback.
  @{@"input":@"a",@"plain":@"+",@"flags":@(C|S),@"before":@[@"+",@(C|S)],@"after":@[@"a",@(C|S)],@"macros":@[],@"winner":@"after"}
 ];
 for(NSDictionary *c in cases){
  NSMenu *main=[NSMenu new],*before=[NSMenu new],*macroMenu=[NSMenu new],*after=[NSMenu new];
  for(NSMenu *menu in @[before,macroMenu,after]){NSMenuItem *root=Item(@"Group",@"",0);root.submenu=menu;[main addItem:root];}
  NSMenuItem *beforeItem=nil,*afterItem=nil;
  if(c[@"before"]){NSArray *b=c[@"before"];beforeItem=Item(@"Before",b[0],[b[1] unsignedIntegerValue]);[before addItem:beforeItem];}
  if(c[@"after"]){NSArray *b=c[@"after"];afterItem=Item(@"After",b[0],[b[1] unsignedIntegerValue]);[after addItem:afterItem];}
  TSShortcutStore *store=[[TSShortcutStore alloc]initWithMenu:main defaults:TSIsolatedAppKitDefaults];
  NSMenu *nested=[NSMenu new];NSMenuItem *folder=Item(@"Folder",@"",0);folder.submenu=nested;[macroMenu addItem:folder];[nested addItem:NSMenuItem.separatorItem];
  NSMutableArray<TSShortcutMacro *> *macros=[NSMutableArray array];NSMutableArray<NSDictionary *> *raw=[NSMutableArray array];
  for(NSArray *b in c[@"macros"]){
   TSShortcutMacro *macro=Macro([NSString stringWithFormat:@"macro%lu",macros.count],b[0],[b[1] unsignedIntegerValue],macros.count);
   [macros addObject:macro];[raw addObject:@{@"path":macro.path,@"key":macro.key,@"modifiers":@(macro.modifiers)}];
  }
  NSMutableIndexSet *inactive=[NSMutableIndexSet indexSet];
  for(NSDictionary *conflict in [store conflictsForMacroShortcuts:raw]){[inactive addIndex:[conflict[@"index"] unsignedIntegerValue]];}
  for(NSUInteger index=0;index<macros.count;index++){
   TSShortcutMacro *macro=macros[index];NSMenuItem *item=Item(macro.name,[inactive containsIndex:index]?@"":macro.key,macro.modifiers);item.action=@selector(doMacro:);item.identifier=nil;[nested addItem:item];
  }
  fixtureCharacters=c[@"plain"];
  NSArray<TSShortcutMatch *> *hits=[TSShortcutSearch matchesEvent:Event(c[@"input"],[c[@"flags"] unsignedIntegerValue],0) store:store macros:macros];
  NSUInteger winners=0,macroIndex=0;NSString *actual=nil;
  for(TSShortcutMatch *hit in hits){
   if(hit.macro){REQUIRE(hit.macro==macros[macroIndex]);macroIndex++;}
   if(!hit.winner)continue;
   winners++;actual=hit.macro!=nil?hit.macro.name:hit.menuItem==beforeItem?@"before":@"after";
  }
  REQUIRE(winners==1 && [actual isEqual:c[@"winner"]] && macroIndex==macros.count);
 }
 puts("PASS: nested live macro positions, primary/fallback tiers, raw inactive macros, macro-only and file-order owners");
}
static NSWindow *sheetParent;
static NSWindow *fakeSheetOwner;
static NSWindow *fakeAttachedSheet;
static NSWindow *AttachedSheet(id self,SEL cmd){return self==fakeSheetOwner ? fakeAttachedSheet : nil;}
static NSUInteger endedSheets;
static void EndSheet(id self,SEL cmd,NSWindow *sheet,NSModalResponse response){endedSheets++;}
static void (^sheetReply)(NSModalResponse);
static void CaptureSheet(id self,SEL cmd,NSWindow *parent,void (^reply)(NSModalResponse)){sheetParent=parent;sheetReply=[reply copy];}
@interface ProbePane:TSShortcutPaneController
@property NSString *lastError;
@end
@implementation ProbePane
- (void)showError:(NSString *)error {self.lastError=error;}
@end
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 nibPath=@(argv[1]);
 const NSUInteger C=NSEventModifierFlagCommand,S=NSEventModifierFlagShift,O=NSEventModifierFlagOption;
 TSReplaceTestMethod(class_getInstanceMethod(NSEvent.class,@selector(charactersByApplyingModifiers:)),(IMP)Characters);
 TSReplaceTestMethod(class_getInstanceMethod(NSWindow.class,@selector(keyDown:)),(IMP)RejectForwardedKey);
 class_addMethod(TSSettingsWindow.class,@selector(isKeyWindow),(IMP)IsKey,"B@:");
 CheckEventPriority();
 NSMenu *main=[NSMenu new],*menu=[NSMenu new];NSMenuItem *root=[[NSMenuItem alloc]initWithTitle:@"Actions" action:NULL keyEquivalent:@""];root.submenu=menu;[main addItem:root];NSApp.mainMenu=main;
 NSMenuItem *first=Item(@"First",@"f",C),*second=Item(@"Second",@"f",C),*equals=Item(@"Equals",@"=",C);
 for(NSMenuItem *item in @[first,second,equals])[menu addItem:item];
 NSDictionary *oldEntry=@{@"key":@"y",@"modifiers":@(C)};
 [TSIsolatedAppKitDefaults setObject:@{@"TSShortcut.First":@{@"key":@"k",@"modifiers":@(C)},@"TSShortcut.showKeyboardShortcuts:.0":oldEntry,@"TSShortcut.openAutoCompletionListEditor:.0":oldEntry,@"TSShortcut.openCommandCompletionList:.0":oldEntry} forKey:TSMenuShortcutOverridesKey];
 TSKeyboardShortcuts *coordinator=[TSKeyboardShortcuts new];
 [coordinator startObservingMenu];
 REQUIRE([first.keyEquivalent isEqual:@"k"] && ![coordinator isKindOfClass:NSWindowController.class]);
 REQUIRE(menu.numberOfItems==3 && [TSIsolatedAppKitDefaults.values[TSMenuShortcutOverridesKey][@"TSShortcut.showKeyboardShortcuts:.0"] isEqual:oldEntry]);
 __block int routed=0;coordinator.showSettings=^{routed++;};[coordinator showKeyboardShortcuts:nil];REQUIRE(routed==1);
 TSVisitMenu(main,@"",^(NSMenuItem *item,NSString *path){REQUIRE(![item.keyEquivalent isEqual:@"y"]);});
 TSShortcutCommand *firstCommand=coordinator.store.commands.firstObject;
 REQUIRE([coordinator.store setKey:@"j" modifiers:C forCommand:firstCommand]==nil);
 REQUIRE([TSIsolatedAppKitDefaults.values[TSMenuShortcutOverridesKey][@"TSShortcut.showKeyboardShortcuts:.0"] isEqual:oldEntry]);
 for(NSString *removed in @[@"TSShortcut.openAutoCompletionListEditor:.0",@"TSShortcut.openCommandCompletionList:.0"]) REQUIRE([TSIsolatedAppKitDefaults.values[TSMenuShortcutOverridesKey][removed] isEqual:oldEntry]);
 [coordinator.store restoreAll];
 REQUIRE([TSIsolatedAppKitDefaults.values[TSMenuShortcutOverridesKey] count]==0);
 NSArray *macros=@[Macro(@"First macro",@"f",C,0),Macro(@"Free",@"z",C,1),Macro(@"Later free",@"z",C,2),Macro(@"JIS",@"-",C|S,3)];
 coordinator.macroProvider=^{return macros;};
 NSMenu *liveMacros=[NSMenu new];NSMenuItem *macroRoot=Item(@"Macros",@"",0);macroRoot.submenu=liveMacros;[main addItem:macroRoot];
 for(NSUInteger index=0;index<macros.count;index++){
  TSShortcutMacro *macro=macros[index];NSMenuItem *item=Item(macro.name,(index==1 || index==3)?macro.key:@"",macro.modifiers);item.action=@selector(doMacro:);item.identifier=nil;[liveMacros addItem:item];
 }

 id macroObserver=[[NSNotificationCenter defaultCenter] addObserverForName:TSRebuildMacrosNotification object:coordinator queue:nil usingBlock:^(NSNotification *notification){
  NSMutableArray *raw=[NSMutableArray array];
  for(TSShortcutMacro *macro in macros)[raw addObject:@{@"path":macro.path,@"key":macro.key,@"modifiers":@(macro.modifiers)}];
  NSMutableIndexSet *inactive=[NSMutableIndexSet indexSet];
  for(NSDictionary *conflict in [coordinator conflictsForMacroShortcuts:raw])[inactive addIndex:[conflict[@"index"] unsignedIntegerValue]];
  for(NSUInteger index=0;index<macros.count;index++){
   TSShortcutMacro *macro=macros[index];NSMenuItem *item=[liveMacros itemAtIndex:index];
   item.keyEquivalent=[inactive containsIndex:index]?@"":macro.key;item.keyEquivalentModifierMask=macro.modifiers;
  }
 }];

 NSArray<TSShortcutMatch *> *hits=[TSShortcutSearch matchesKey:@"f" modifiers:C store:coordinator.store macros:macros];
 REQUIRE(hits.count==3 && hits[0].menuItem==first && hits[0].winner && !hits[1].winner && !hits[2].winner);
 REQUIRE([coordinator.store conflictForKey:@"f" modifiers:C except:nil restoring:nil]!=nil);
 hits=[TSShortcutSearch matchesKey:@"z" modifiers:C store:coordinator.store macros:macros];REQUIRE(hits.count==2 && hits[0].winner && !hits[1].winner);
 hits=[TSShortcutSearch matchesKey:@"-" modifiers:C|S store:coordinator.store macros:macros];REQUIRE(hits.count==1 && hits[0].winner && hits[0].macro==macros[3]);
 hits=[TSShortcutSearch matchesKey:@"=" modifiers:C store:coordinator.store macros:macros];REQUIRE(hits.count==1 && hits[0].menuItem==equals && hits[0].winner);
 first.keyEquivalent=@"";second.keyEquivalent=@"";
 hits=[TSShortcutSearch matchesKey:@"f" modifiers:C store:coordinator.store macros:macros];REQUIRE(hits.count==1 && hits[0].winner);
 [coordinator refreshMenuAndMacros];
 NSMenuItem *dynamic=Item(@"Dynamic",@"d",C);dynamic.identifier=nil;[menu addItem:dynamic];
 hits=[TSShortcutSearch matchesKey:@"d" modifiers:C store:coordinator.store macros:macros];REQUIRE(hits.count==1 && hits[0].winner && hits[0].command==nil);
 // Multiple recorder spellings have one displayed owner in menu order.
 NSMenuItem *shiftEquals=Item(@"Shift equals",@"=",C|S);[menu insertItem:shiftEquals atIndex:0];
 fixtureCharacters=@"0";
 NSEvent *german=Event(@"=",C|S,29);
 NSArray *aliasMacros=@[Macro(@"Zero macro",@"0",C|S,10)];
 hits=[TSShortcutSearch matchesEvent:german store:coordinator.store macros:aliasMacros];
 REQUIRE(hits.count==3 && hits[0].menuItem==shiftEquals && hits[0].winner && hits[1].menuItem==equals && !hits[1].winner && !hits[2].winner);
 [menu removeItem:shiftEquals];[menu addItem:shiftEquals];
 hits=[TSShortcutSearch matchesEvent:german store:coordinator.store macros:aliasMacros];
 REQUIRE(hits.count==3 && hits[0].menuItem==equals && hits[0].winner && !hits[1].winner && !hits[2].winner);
 [menu removeItem:shiftEquals];
 hits=[TSShortcutSearch matchesKey:@"0" modifiers:C|S store:coordinator.store macros:aliasMacros];REQUIRE(hits.count==1 && hits[0].winner);
 puts("PASS: one displayed event owner follows menu order across spellings; raw macro ownership is unchanged");
 puts("PASS: saved assignments without a pane, compatibility routing, inert old ID, shared raw ownership and dynamic matches");
 Shell *shell=[[Shell alloc]initWithDefaults:TSIsolatedAppKitDefaults];Delegate *delegate=[Delegate new];shell.settingsDelegate=delegate;
 NSView *legacy=[[NSView alloc]initWithFrame:NSMakeRect(0,0,700,600)];NSTabView *tabs=[[NSTabView alloc]initWithFrame:legacy.bounds];[legacy addSubview:tabs];
 for(NSUInteger i=0;i<9;i++){NSTabViewItem *tab=[[NSTabViewItem alloc]initWithIdentifier:@(i)];tab.label=[NSString stringWithFormat:@"Pane %lu",i];tab.view=[NSView new];[tabs addTabViewItem:tab];}
 NSMutableDictionary *panes=[NSMutableDictionary dictionary];
 NSArray *ids=@[TSSettingsCategoryGeneral,TSSettingsCategoryDocuments,TSSettingsCategoryEditor,TSSettingsCategorySpelling,TSSettingsCategoryAppearance,TSSettingsCategoryPreview,TSSettingsCategoryTypesetting,TSSettingsCategoryConsole,TSSettingsCategoryUpdates];
 for(NSUInteger n=0;n<ids.count;n++){NSViewController *pane=[NSViewController new];pane.view=[tabs tabViewItemAtIndex:n].view;pane.title=ids[n];panes[ids[n]]=pane;}
 NSView *footer=[NSView new];[footer.heightAnchor constraintEqualToConstant:50].active=YES;
 [shell hostPaneControllers:panes footer:footer];
 __block NSUInteger created=0;__block ProbePane *pane;
 shell.keyboardPaneProvider=^{created++;pane=[[ProbePane alloc]initWithShortcuts:coordinator];return pane;};
 [shell beginSession];REQUIRE(created==0);
 REQUIRE([shell selectCategoryIdentifier:TSSettingsCategoryKeyboard] && created==1);
 REQUIRE(pane.view.window==shell.window && [shell.window.title isEqual:@"Keyboard"] && ![pane isKindOfClass:NSWindowController.class]);
 [shell.window.contentView layoutSubtreeIfNeeded];
 pane.search.stringValue=@"First";[pane reloadCommands];REQUIRE(pane.visibleCommands.count==1);
 NSDictionary *saved=[TSIsolatedAppKitDefaults.values copy];
 pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];
 REQUIRE(pane.searchingByKey && !pane.search.editable && shell.window.firstResponder==pane.keySearchView);
 REQUIRE([pane.keySearchView.accessibilityValue isEqual:@"Press a key"]);
 for(NSString *key in @[@"q",@"w",@",",@"h",@"[",@"]"]){fixtureCharacters=key;REQUIRE([shell.window performKeyEquivalent:Event(key,C,0)] && pane.searchingByKey && [shell.history.currentIdentifier isEqual:TSSettingsCategoryKeyboard]);}
 fixtureCharacters=@"f";[shell.window keyDown:Event(@"f",C,3)];REQUIRE(pane.searchMatches.count==3 && pane.table.selectedRow==0 && [pane macroHeaderRow]==2);
 REQUIRE(pane.selectionButtons[0].enabled && !pane.macroButton.enabled);
 NSTextField *inactive=(NSTextField *)[pane tableView:pane.table viewForTableColumn:pane.table.tableColumns[0] row:3];
 REQUIRE([inactive.stringValue containsString:@"conflicts with"] && [inactive.stringValue containsString:first.title]);
 REQUIRE([pane.keySearchView.accessibilityValue containsString:@"priority"]);
 REQUIRE([pane.keySearchView.accessibilityValue containsString:@"Matches: 3"]);
 NSScrollView *outer=pane.view.enclosingScrollView;
 REQUIRE(outer!=nil && !outer.hasVerticalScroller && pane.table.enclosingScrollView.hasVerticalScroller);

 [pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];[pane updateSelectionButtons];
 REQUIRE(!pane.selectionButtons[0].enabled && pane.macroButton.enabled);
 fixtureCharacters=@"z";[shell.window performKeyEquivalent:Event(@"z",C,6)];REQUIRE(pane.searchMatches.count==2 && pane.searchMatches[0].winner && !pane.searchMatches[1].winner && pane.table.selectedRow==1 && [pane macroHeaderRow]==0);
 fixtureCharacters=@"x";[shell.window performKeyEquivalent:Event(@"x",C,7)];REQUIRE(pane.searchMatches.count==0 && [pane.searchMessage containsString:@"No command"]);
 REQUIRE([shell.window makeFirstResponder:pane.table]);fixtureCharacters=@"x";
 IMP appKitSendEvent=method_setImplementation(class_getInstanceMethod(NSWindow.class,@selector(sendEvent:)),(IMP)AppKitSendEventProbe);
 forwardedWindowEvents=0;[shell.window sendEvent:Event(@"x",0,7)];
 method_setImplementation(class_getInstanceMethod(NSWindow.class,@selector(sendEvent:)),appKitSendEvent);
 REQUIRE(pane.searchMatches.count==0 && [pane.searchMessage containsString:@"cannot be used"] && forwardedKeys==0 && forwardedWindowEvents==0);
 // Existing non-assignable shortcuts remain searchable, but new assignments stay restricted.
 NSMenuItem *rotate=Item(@"Rotate",@"c",O),*switchViews=Item(@"Switch views",@"2",O);
 [menu addItem:rotate];[menu addItem:switchViews];
 for(NSMenuItem *item in @[rotate,switchViews]){
  fixtureCharacters=item.keyEquivalent;[shell.window performKeyEquivalent:Event(item.keyEquivalent,O,8)];
  REQUIRE(pane.searchMatches.count==1 && pane.searchMatches[0].menuItem==item && pane.searchMatches[0].winner && pane.table.selectedRow==0);
  REQUIRE([pane.searchMessage containsString:@"cannot be assigned to a new shortcut"] && ![TSShortcutStore isAllowedKey:item.keyEquivalent modifiers:O]);
 }
 [menu removeItem:rotate];[menu removeItem:switchViews];
 fixtureCharacters=@"0";[shell.window performKeyEquivalent:german];
 REQUIRE([pane.search.stringValue isEqual:[TSShortcutStore displayKey:@"=" modifiers:C]]);
 fixtureCharacters=@"\033";[shell.window performKeyEquivalent:Event(@"\033",S,53)];
 REQUIRE(pane.searchingByKey && [pane.search.stringValue isEqual:[TSShortcutStore displayKey:@"\033" modifiers:S]]);
 REQUIRE([TSIsolatedAppKitDefaults.values isEqual:saved]);
 REQUIRE([shell.window performKeyEquivalent:Event(@"\033",0,53)] && !pane.searchingByKey && pane.search.editable && [pane.search.stringValue isEqual:@"First"]);
 for(NSUInteger reason=0;reason<4;reason++){
  [shell selectCategoryIdentifier:TSSettingsCategoryKeyboard];pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];REQUIRE(pane.searchingByKey);
  if(reason==0)[pane changeSearchMode:pane.searchMode];
  if(reason==1)[shell selectCategoryIdentifier:TSSettingsCategoryGeneral];
  if(reason==2)[NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidResignKeyNotification object:shell.window];
  if(reason==3)[shell endSession];
  REQUIRE(!pane.searchingByKey);
 }
 REQUIRE(created==1);
 [shell beginSession];[shell selectCategoryIdentifier:TSSettingsCategoryGeneral];[shell selectCategoryIdentifier:TSSettingsCategoryKeyboard];
 fixtureCharacters=@"[";REQUIRE([shell.window performKeyEquivalent:Event(@"5",C|O,23)] && [shell.history.currentIdentifier isEqual:TSSettingsCategoryGeneral]);
 fixtureCharacters=@"]";REQUIRE([shell.window performKeyEquivalent:Event(@"6",C|O,22)] && [shell.history.currentIdentifier isEqual:TSSettingsCategoryKeyboard]);
 pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];fixtureCharacters=@"[";
 [shell.window performKeyEquivalent:Event(@"5",C|O,23)];REQUIRE([shell.history.currentIdentifier isEqual:TSSettingsCategoryKeyboard]);
 __block TSShortcutMacro *shown=nil;coordinator.showMacro=^(TSShortcutMacro *macro){shown=macro;};fixtureCharacters=@"z";[shell.window performKeyEquivalent:Event(@"z",C,6)];[pane showSelectedMacro:nil];REQUIRE(shown==macros[1] && !pane.searchingByKey);
 puts("PASS: embedded pane, function/key search, all command keys intercepted, five exits, macro rows and Option-bracket navigation");
 TSReplaceTestMethod(class_getInstanceMethod(NSAlert.class,@selector(beginSheetModalForWindow:completionHandler:)),(IMP)CaptureSheet);
 // Parented asynchronous confirmation cannot write before the user answers.
 coordinator.rebuildingMacros=YES;
 NSMenuItem *macroItem=Item(@"Live macro",@"z",C);macroItem.action=@selector(doMacro:);macroItem.identifier=nil;[menu addItem:macroItem];
 coordinator.rebuildingMacros=NO;
 __block BOOL accepted=NO;[pane confirmMacrosUsingKey:@"z" modifiers:C completion:^(BOOL value){accepted=value;}];
 REQUIRE(sheetParent==shell.window && sheetReply!=nil && !accepted);sheetReply(NSAlertFirstButtonReturn);REQUIRE(!accepted);
 [pane confirmMacrosUsingKey:@"z" modifiers:C completion:^(BOOL value){accepted=value;}];sheetReply(NSAlertSecondButtonReturn);REQUIRE(accepted);
 [pane restoreAll:nil];REQUIRE(sheetParent==shell.window && sheetReply!=nil);
 // Model an attached recording sheet without displaying or attaching an actual window.
 TSReplaceTestMethod(class_getInstanceMethod(NSWindow.class,@selector(attachedSheet)),(IMP)AttachedSheet);
 TSReplaceTestMethod(class_getInstanceMethod(NSWindow.class,@selector(endSheet:returnCode:)),(IMP)EndSheet);
 pane.capturePanel=[[TSShortcutCapturePanel alloc]initWithContentRect:NSMakeRect(0,0,400,200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 fakeSheetOwner=shell.window;fakeAttachedSheet=pane.capturePanel;
 sheetParent=nil;sheetReply=nil;accepted=NO;
 [pane confirmMacrosUsingKey:@"z" modifiers:C completion:^(BOOL value){accepted=value;}];
 REQUIRE(sheetParent==pane.capturePanel && sheetReply!=nil);sheetReply(NSAlertSecondButtonReturn);REQUIRE(accepted);
 sheetParent=nil;
 IMP showError=class_getMethodImplementation(TSShortcutPaneController.class,@selector(showError:));
 ((void(*)(id,SEL,id))showError)(pane,@selector(showError:),@"Fixture error");REQUIRE(sheetParent==pane.capturePanel);
 // Changing any captured value while a confirmation is pending must cancel the write.
 pane.applyButton=[NSButton new];pane.applyButton.enabled=YES;pane.captureError=[NSTextField new];
 for(NSUInteger change=0;change<3;change++){
  pane.editingCommand=firstCommand;pane.capturedKey=@"z";pane.capturedModifiers=C;pane.capturedBindings=nil;
  NSDictionary *before=[TSIsolatedAppKitDefaults.values copy];NSString *originalKey=[first.keyEquivalent copy];
  sheetReply=nil;[pane applyCapturedShortcut:nil];REQUIRE(sheetReply!=nil);
  if(change==0)pane.editingCommand=coordinator.store.commands.lastObject;
  if(change==1)pane.capturedKey=@"v";
  if(change==2)pane.capturedModifiers=C|S;
  sheetReply(NSAlertSecondButtonReturn);
  REQUIRE([TSIsolatedAppKitDefaults.values isEqual:before] && [first.keyEquivalent isEqual:originalKey] && endedSheets==0);
 }
 // The macro reservation is checked again when the asynchronous reply arrives.
 accepted=NO;sheetReply=nil;[pane confirmMacrosUsingKey:@"z" modifiers:C completion:^(BOOL value){accepted=value;}];REQUIRE(sheetReply!=nil);
 macroItem.keyEquivalent=@"v";sheetReply(NSAlertSecondButtonReturn);REQUIRE(!accepted);macroItem.keyEquivalent=@"z";
 // An unchanged confirmation still applies the requested shortcut normally.
 pane.editingCommand=firstCommand;pane.capturedKey=@"z";pane.capturedModifiers=C;pane.capturedBindings=nil;
 sheetReply=nil;[pane applyCapturedShortcut:nil];REQUIRE(sheetReply!=nil);sheetReply(NSAlertSecondButtonReturn);
 REQUIRE([first.keyEquivalent isEqual:@"z"] && endedSheets==1);
 fakeSheetOwner=nil;fakeAttachedSheet=nil;pane.capturePanel=nil;pane.editingCommand=nil;
 puts("PASS: confirmations are asynchronous sheets attached to Settings");
 TSMacroTreeNode *tree=[TSMacroTreeNode submenuNodeWithName:@"root"],*group=[TSMacroTreeNode submenuNodeWithName:@"group"];
 TSMacroTreeNode *a=[TSMacroTreeNode nodeWithName:@"same" content:@"unsaved" key:@"A"],*b=[TSMacroTreeNode nodeWithName:@"same" content:@"other" key:@"B"];
 [tree addChild:group];[group addChild:a];[group addChild:b];NSUInteger indexes[]={0,0};NSIndexPath *path=[NSIndexPath indexPathWithIndexes:indexes length:2];
 REQUIRE([TSMacroSelection nodeInRoot:tree indexPath:path name:@"same" key:@"A"]==a);
 [a removeFromParent];[group addChild:a];REQUIRE([TSMacroSelection nodeInRoot:tree indexPath:path name:@"same" key:@"A"]==a);
 TSMacroTreeNode *duplicate=[TSMacroTreeNode nodeWithName:@"same" content:@"keep" key:@"A"];[tree addChild:duplicate];
 REQUIRE([TSMacroSelection nodeInRoot:tree indexPath:path name:@"same" key:@"A"]==nil);
 REQUIRE([TSMacroSelection nodeInRoot:tree indexPath:path name:@"missing" key:@"A"]==nil && [a.content isEqual:@"unsaved"]);
 NSUInteger exact[]={0,1};REQUIRE([TSMacroSelection nodeInRoot:tree indexPath:[NSIndexPath indexPathWithIndexes:exact length:2] name:@"same" key:@"A"]==a);
 puts("PASS: exact index path, unique moved match, ambiguous/missing match and unsaved contents preserved");
 NSDictionary *translations=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] options:0 error:NULL];
 REQUIRE(translations.count==12);
 originalLocalization=method_setImplementation(class_getInstanceMethod(NSBundle.class,@selector(localizedStringForKey:value:table:)),(IMP)Localized);
 for(NSString *language in translations){@autoreleasepool{
  localizedStrings=translations[language];
  TSShortcutPaneController *translated=[[TSShortcutPaneController alloc]initWithShortcuts:coordinator];
  NSView *inputHeader=InputHeader();translated.settingsHeader=inputHeader;
  NSWindow *host=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,700,460) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];host.contentView=translated.view;
  [translated viewDidLayout];[host.contentView layoutSubtreeIfNeeded];CheckButtons(translated.view,translated.view);
  REQUIRE(translated.inputGroups.count==2 && translated.inputGroups[0].hidden && translated.inputGroups[1].hidden);
  REQUIRE(NSHeight(translated.table.enclosingScrollView.frame)>40);
  REQUIRE(translated.table.enclosingScrollView.documentView==translated.table && translated.table.headerView.superview!=nil);
  REQUIRE(![inputHeader isDescendantOf:translated.table.enclosingScrollView]);
  NSRect h=[inputHeader convertRect:inputHeader.bounds toView:translated.view];
  REQUIRE(NSMinY(h)>NSMaxY(translated.search.frame));
  [translated.table scrollRowToVisible:translated.table.numberOfRows-1];
  REQUIRE(NSIntersectsRect(translated.table.visibleRect,[translated.table rectOfRow:translated.table.numberOfRows-1]));
  translated.search.stringValue=@"missing command fixture";[translated reloadCommands];
  REQUIRE(translated.table.numberOfRows==0);
  translated.searchMode.selectedSegment=1;[translated changeSearchMode:translated.searchMode];
  for(id trigger in @[@"TAB",@"ESCAPE",NSNull.null,@"unexpected",@"ESC",@"TAB"]){
   [TSIsolatedAppKitDefaults setObject:trigger==NSNull.null?nil:trigger forKey:@"CommandCompletionChar"];
   NSDictionary *unchanged=[TSIsolatedAppKitDefaults.values copy];fixtureCharacters=@"\t";
   REQUIRE([translated handleKeySearchEvent:Event(@"\t",0,48)]);
   BOOL reserved=![trigger isEqual:@"ESCAPE"];
   REQUIRE([translated.searchMessage isEqual:NSLocalizedString(@"This key is reserved for command completion.",@"")]==reserved);
   REQUIRE((translated.highlightedCompletionRow!=nil)==reserved);
   if(reserved){
    REQUIRE(translated.inputGroups[0].hidden && !translated.inputGroups[1].hidden);
    REQUIRE(translated.highlightedCompletionRow.layer.borderWidth==2);
    [translated.view layoutSubtreeIfNeeded];CheckButtons(translated.view,translated.view);
    NSRect row=[translated.highlightedCompletionRow convertRect:translated.highlightedCompletionRow.bounds toView:translated.view];
    REQUIRE(NSContainsRect(translated.view.bounds,row));
    REQUIRE(NSHeight(translated.table.enclosingScrollView.frame)>40);
   }
   REQUIRE([TSIsolatedAppKitDefaults.values isEqual:unchanged]);
  }
  [TSIsolatedAppKitDefaults setObject:@"ESCAPE" forKey:@"CommandCompletionChar"];
  [NSNotificationCenter.defaultCenter postNotificationName:@"CommandCompletionCharNotification" object:nil];
  REQUIRE(translated.highlightedCompletionRow==nil && ![translated.searchMessage containsString:@"reserved"]);
  [TSIsolatedAppKitDefaults setObject:@"TAB" forKey:@"CommandCompletionChar"];
  fixtureCharacters=@"\t";[translated handleKeySearchEvent:Event(@"\t",NSEventModifierFlagShift,48)];
  REQUIRE(translated.highlightedCompletionRow==nil && ![translated.searchMessage isEqual:NSLocalizedString(@"This key is reserved for command completion.",@"")]);
  fixtureCharacters=@"\t";[translated handleKeySearchEvent:Event(@"\t",0,48)];
  NSView *highlighted=translated.highlightedCompletionRow;
  REQUIRE(highlighted!=nil && highlighted.layer.borderWidth==2);
  [translated stopKeySearch];REQUIRE(translated.highlightedCompletionRow==nil && highlighted.layer.borderWidth==0);
  translated.searchMode.selectedSegment=1;[translated changeSearchMode:translated.searchMode];
  for(NSString *plain in @[@"a",@"x"]){
   fixtureCharacters=plain;[translated handleKeySearchEvent:Event(plain,0,0)];
   REQUIRE([translated.searchMessage isEqual:NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.",@"")]);
  }
  fixtureCharacters=@"x";[translated handleKeySearchEvent:Event(@"x",NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagCommand,7)];
  REQUIRE(translated.searchMatches.count==0 && translated.highlightedCompletionRow==nil);
  REQUIRE([translated.searchMessage isEqual:NSLocalizedString(@"No command uses this key.",@"")]);
  [translated stopKeySearch];
  [host setContentSize:NSMakeSize(700,780)];[translated viewDidLayout];[translated.view layoutSubtreeIfNeeded];
  REQUIRE(!translated.inputGroups[0].hidden && !translated.inputGroups[1].hidden);
  translated.searchMode.selectedSegment=1;[translated changeSearchMode:translated.searchMode];fixtureCharacters=@"\t";
  [translated handleKeySearchEvent:Event(@"\t",0,48)];
  [host setContentSize:NSMakeSize(700,460)];[translated viewDidLayout];[translated.view layoutSubtreeIfNeeded];
  REQUIRE(translated.highlightedCompletionRow!=nil && !translated.inputGroups[1].hidden);
  CheckButtons(translated.view,translated.view);
  REQUIRE(NSContainsRect(translated.view.bounds,translated.table.enclosingScrollView.frame));
  REQUIRE(NSWidth(translated.searchMode.frame)+1>=translated.searchMode.intrinsicContentSize.width);
  fprintf(stdout,"PASS: %s pane controls fit minimum content size\n",language.UTF8String);
 }}
 localizedStrings=nil;method_setImplementation(class_getInstanceMethod(NSBundle.class,@selector(localizedStringForKey:value:table:)),originalLocalization);
 [[NSNotificationCenter defaultCenter] removeObserver:macroObserver];
 REQUIRE(TSIsolatedAppKitDefaults==NSUserDefaults.standardUserDefaults);
}}
