// Settings integration tests. No visible windows, user defaults or macro files.
#import "TSMacroSelection.h"
#import "TestAppKitIsolation.h"
#import "StripedRows.h"
#import "TSKeyboardShortcuts.m"
#import "TSSettingsCategory.h"
#import "TSMacroTreeNode.h"
#import "TSPrefPaneLayout.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
static void Check(BOOL value,NSString *message){if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
#include "SettingsSearchCoverage.inc"
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
// Independent three-section fixture with the approved catalog structure.
static NSView *InputHeader(void) {
 NSView *header=[NSView new];NSMutableArray *groups=[NSMutableArray array];
 for(NSString *key in @[@"bindings",@"completion",@"shortcuts"]){
  TSSettingsGroupView *box=[TSSettingsGroupView new];box.identifier=[@"group." stringByAppendingString:key];
  box.accessibilityLabel=NSLocalizedString([key isEqual:@"bindings"]?@"Key Bindings":[key isEqual:@"completion"]?@"Command Completion":@"Menu Shortcuts",@"");
  NSMutableArray *rows=[NSMutableArray array];
  NSTextField *heading=[NSTextField labelWithString:box.accessibilityLabel];heading.identifier=[@"heading.group." stringByAppendingString:key];[rows addObject:heading];
  if(![key isEqual:@"shortcuts"])for(NSUInteger i=0;i<([key isEqual:@"completion"]?3:1);i++){
   NSButton *button=[NSButton buttonWithTitle:i==0?NSLocalizedString(@"Completion trigger",@""):@"Input fixture" target:nil action:NULL];
   NSView *row=[TSPrefPaneLayout viewForRow:[[TSSettingsControlRow alloc]initWithControls:@[button] indentation:0]];
   if([key isEqual:@"completion"] && i==0)row.identifier=@"row.catalog.keyboard.1.0";
   if([key isEqual:@"completion"] && i==1)row.identifier=@"row.catalog.keyboard.1.3"; // the Option and Control mark keys
   [rows addObject:row];
  }
  [TSPrefPaneLayout attachRows:rows toView:box.contentView];
  [NSLayoutConstraint activateConstraints:@[[box.contentView.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],[box.contentView.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],[box.contentView.topAnchor constraintEqualToAnchor:box.topAnchor],[box.contentView.bottomAnchor constraintEqualToAnchor:box.bottomAnchor]]];
  [groups addObject:box];
 }
 [TSPrefPaneLayout attachRows:groups toView:header];[TSPrefPaneLayout decorateGroupsInView:header];return header;
}
static BOOL AllInputGroupsVisible(TSShortcutPaneController *pane) {
 for(NSString *key in @[@"group.bindings",@"group.completion",@"group.shortcuts"]){NSView *group=[pane viewWithIdentifier:key inView:pane.view];if(!group || group.hidden)return NO;}return YES;
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
static NSInteger fixtureClickedRow=-1,fixtureClickedColumn=-1;
static NSInteger ClickedRow(id self,SEL cmd){return fixtureClickedRow;}
static NSInteger ClickedColumn(id self,SEL cmd){return fixtureClickedColumn;}
static void (^sheetReply)(NSModalResponse);
static void CaptureSheet(id self,SEL cmd,NSWindow *parent,void (^reply)(NSModalResponse)){sheetParent=parent;sheetReply=[reply copy];}
@interface TSShortcutPaneController (InactiveReason)
- (NSString *)inactiveReasonForMatch:(TSShortcutMatch *)match;
- (TSShortcutMatch *)matchAtRow:(NSInteger)row;
@end
@interface ProbePane:TSShortcutPaneController
@property NSString *lastError;
@end
@implementation ProbePane
- (void)showError:(NSString *)error {self.lastError=error;}
@end
static NSString *DisplayChar(unichar c) { return [NSString stringWithCharacters:&c length:1]; }
static void SetShownKey(NSMenuItem *item, NSString *key, NSEventModifierFlags flags) {
 item.allowsAutomaticKeyEquivalentLocalization=NO;
 item.keyEquivalent=@"";
 item.keyEquivalentModifierMask=flags;
 if (key.length) item.keyEquivalent=key;
}
static NSString *ShortcutColumnText(TSShortcutPaneController *pane, BOOL (^select)(TSShortcutMatch *match)) {
 NSTableColumn *shortcut=nil;
 for (NSTableColumn *column in pane.table.tableColumns) if ([column.identifier isEqual:@"shortcut"]) shortcut=column;
 for (NSInteger row=0; row<pane.table.numberOfRows; row++) {
  TSShortcutMatch *match=[pane matchAtRow:row];
  if (match==nil || !select(match)) continue;
  id cell=[pane tableView:pane.table viewForTableColumn:shortcut row:row];
  return [cell isKindOfClass:NSTextField.class] ? [(NSTextField *)cell stringValue] : nil;
 }
 return nil;
}
// Tab, Escape and the mark key clear the result list when only Shift, Option or Control is held.
// The field is filled before that clear, from the menu item the key would have run.
static BOOL ReservedCompletionKey(NSUserDefaults *defaults, NSString *key, NSEventModifierFlags flags) {
 BOOL escapeTrigger=[[defaults stringForKey:TSCommandCompletionCharacterKey] isEqualToString:@"ESCAPE"];
 BOOL trigger=escapeTrigger ? [key isEqualToString:@"\033"] : ([key isEqualToString:@"\t"] || [key isEqualToString:@"\031"]);
 NSEventModifierFlags completion=flags & (NSEventModifierFlagShift|NSEventModifierFlagOption|NSEventModifierFlagControl|NSEventModifierFlagCommand);
 return trigger && (completion==0 || completion==NSEventModifierFlagShift || completion==NSEventModifierFlagOption || completion==NSEventModifierFlagControl);
}
// The key-search field shows the same string as the shortcut column. Shifted
// punctuation is still compared in its translated spelling (@ for Shift-2, | for
// JIS Shift+¥); the field follows the menu item that runs.
static void CheckKeySearchDisplayMatchesMenu(void) {
 const NSEventModifierFlags C=NSEventModifierFlagCommand,S=NSEventModifierFlagShift,O=NSEventModifierFlagOption,K=NSEventModifierFlagControl;
 NSMenu *main=[NSMenu new],*menu=[NSMenu new];
 NSMenuItem *root=[[NSMenuItem alloc] initWithTitle:@"Actions" action:NULL keyEquivalent:@""];
 root.submenu=menu; [main addItem:root];
 NSMenuItem *pattern=[[NSMenuItem alloc] initWithTitle:@"Pattern" action:@selector(description) keyEquivalent:@""];
 pattern.identifier=@"pattern.display"; pattern.allowsAutomaticKeyEquivalentLocalization=NO;
 NSMenuItem *letter=[[NSMenuItem alloc] initWithTitle:@"Letter" action:@selector(description) keyEquivalent:@"b"];
 letter.identifier=@"TSShortcut.displayLetter:.0"; letter.keyEquivalentModifierMask=C; letter.allowsAutomaticKeyEquivalentLocalization=NO;
 NSMenuItem *equals=[[NSMenuItem alloc] initWithTitle:@"Equals" action:@selector(description) keyEquivalent:@"="];
 equals.identifier=@"TSShortcut.displayEquals:.0"; equals.keyEquivalentModifierMask=C; equals.allowsAutomaticKeyEquivalentLocalization=NO;
 NSMenuItem *digit=[[NSMenuItem alloc] initWithTitle:@"Digit" action:@selector(description) keyEquivalent:@"2"];
 digit.identifier=@"TSShortcut.displayDigit:.0"; digit.keyEquivalentModifierMask=C|S; digit.allowsAutomaticKeyEquivalentLocalization=NO;
 NSMenuItem *backslash=[[NSMenuItem alloc] initWithTitle:@"Backslash" action:@selector(description) keyEquivalent:@"\\"];
 backslash.identifier=@"TSShortcut.displayBackslash:.0"; backslash.keyEquivalentModifierMask=C|S; backslash.allowsAutomaticKeyEquivalentLocalization=NO;
 NSMenuItem *yen=[[NSMenuItem alloc] initWithTitle:@"Yen" action:@selector(description) keyEquivalent:@"\u00a5"];
 yen.identifier=@"TSShortcut.displayYen:.0"; yen.keyEquivalentModifierMask=C|S; yen.allowsAutomaticKeyEquivalentLocalization=NO;
 [menu addItem:pattern];
 for (NSMenuItem *item in @[letter,equals,digit,backslash,yen]) [menu addItem:item];
 TSKeyboardShortcuts *local=[TSKeyboardShortcuts new];
 TSShortcutStore *store=[[TSShortcutStore alloc] initWithMenu:main defaults:[TSMemoryDefaults new]];
 local.store=store;
 __block NSArray<TSShortcutMacro *> *macros=@[];
 local.macroProvider=^{ return macros; };
 NSMenuItem *macroItem=[[NSMenuItem alloc] initWithTitle:@"Macro" action:@selector(doMacro:) keyEquivalent:@""];
 macroItem.allowsAutomaticKeyEquivalentLocalization=NO;
 [menu addItem:macroItem];
 TSShortcutPaneController *pane=[[TSShortcutPaneController alloc] initWithShortcuts:local];
 [pane loadView];
 pane.searchMode.selectedSegment=1; [pane changeSearchMode:pane.searchMode];
 REQUIRE(pane.searchingByKey);
 // The five commands stay out of the menu until their own cases. A shared key would
 // make another row the winner, and the field would follow that row.
 for (NSMenuItem *item in @[letter,equals,digit,backslash,yen]) [menu removeItem:item];
 __block NSUInteger shown=0;
 void (^search)(NSString *,NSString *,NSEventModifierFlags)=^(NSString *characters,NSString *plain,NSEventModifierFlags flags) {
  fixtureCharacters=plain;
  REQUIRE([pane handleKeySearchEvent:Event(characters,flags,0)]);
 };
 void (^requireColumn)(NSString *,NSString *,BOOL (^)(TSShortcutMatch *))=^(NSString *name,NSString *expected,BOOL (^select)(TSShortcutMatch *match)) {
  NSString *column=ShortcutColumnText(pane,select);
  if (column==nil || ![column isEqual:expected] || ![pane.search.stringValue isEqual:column]) {
   fprintf(stderr,"FAIL: display %s: menu %s field %s expected %s matches %lu\n",name.UTF8String,column.UTF8String ?: "(none)",pane.search.stringValue.UTF8String,expected.UTF8String,(unsigned long)pane.searchMatches.count);
   exit(1);
  }
  shown++;
 };
 NSEventModifierFlags sets[]={C,C|S,C|O,C|K,C|O|S,C|K|S,C|K|O,C|K|O|S,K,K|S,K|O,O|S,O,S,K|O|S};
 // Letters, digits, the ASCII symbols, and the editing keys, held as the menu stores them.
 NSMutableArray<NSString *> *direct=[NSMutableArray array];
 for (unichar c=0x20; c<0x7f; c++) {
  if (c>='A' && c<='Z') continue;
  [direct addObject:DisplayChar(c)];
 }
 for (NSString *key in @[@"\t",@"\r",@"\033",@"\031",@"\177",@"\uf700",@"\uf701",@"\uf702",@"\uf703",
   DisplayChar(NSHomeFunctionKey),DisplayChar(NSEndFunctionKey),DisplayChar(NSPageUpFunctionKey),DisplayChar(NSPageDownFunctionKey),DisplayChar(NSDeleteFunctionKey)]) [direct addObject:key];
 for (int f=1; f<=20; f++) [direct addObject:DisplayChar(NSF1FunctionKey+f-1)];
 unichar symbols[]={0x00a5,0xff0c,0x3001,0x00b7,0x2014,0xff0d};
 for (size_t s=0; s<sizeof symbols/sizeof *symbols; s++) [direct addObject:DisplayChar(symbols[s])];
 for (NSString *key in direct) {
  for (size_t i=0; i<sizeof sets/sizeof *sets; i++) {
   if (ReservedCompletionKey(store.defaults,key,sets[i])) continue;
   SetShownKey(pattern,key,sets[i]);
   search(key,key,sets[i]);
   TSShortcutBinding *live=TSShownBinding(pattern);
   NSString *expected=[TSShortcutStore displayKey:live.key modifiers:live.modifiers];
   requireColumn([NSString stringWithFormat:@"direct U+%04X", [key characterAtIndex:0]],expected,^BOOL(TSShortcutMatch *match){ return match.menuItem==pattern && match.winner; });
   REQUIRE([live isEqual:TSBinding(key,sets[i])]);
  }
 }
 // The same keys with only Shift, Option or Control: command completion hides the rows, and the field keeps the menu spelling.
 for (NSString *key in @[@"\t",@"\033",@"\031"]) {
  NSEventModifierFlags alone[]={S,O,K};
  for (size_t a=0; a<sizeof alone/sizeof *alone; a++) {
   NSEventModifierFlags flags=alone[a];
   if (!ReservedCompletionKey(store.defaults,key,flags)) continue;
   SetShownKey(pattern,key,flags);
   search(key,key,flags);
   TSShortcutBinding *live=TSShownBinding(pattern);
   NSString *expected=[TSShortcutStore displayKey:live.key modifiers:live.modifiers];
   if (pane.searchMatches.count!=0 || ![pane.search.stringValue isEqual:expected] || ![live isEqual:TSBinding(key,flags)]) {
    fprintf(stderr,"FAIL reserved U+%04X: menu %s field %s matches %lu\n",[key characterAtIndex:0],expected.UTF8String,pane.search.stringValue.UTF8String,(unsigned long)pane.searchMatches.count);
    exit(1);
   }
   shown++;
  }
 }
 // A capital letter in the menu is Shift, including when the item omitted the flag.
 SetShownKey(pattern,@"A",C);
 search(@"a",@"a",C|S);
 requireColumn(@"uppercase command",@"⇧⌘A",^BOOL(TSShortcutMatch *match){ return match.menuItem==pattern; });
 // Shifted symbols. The menu may store the symbol without Shift (@), the base
 // key with Shift (2), or the symbol with Shift as well (⇧@).
 struct { unichar base, shifted; } pairs[]={
  {'1','!'},{'2','@'},{'3','#'},{'4','$'},{'5','%'},{'6','^'},{'7','&'},{'8','*'},{'9','('},{'0',')'},
  {'-','_'},{'=','+'},{'[','{'},{']','}'},{'\\','|'},{';',':'},{'\'','"'},{',','<'},{'.','>'},{'/','?'},{'`','~'},
  {0x00a5,'|'}
 };
 NSEventModifierFlags extras[]={0,O,K,K|O};
 for (size_t p=0; p<sizeof pairs/sizeof *pairs; p++) {
  NSString *base=DisplayChar(pairs[p].base),*shifted=DisplayChar(pairs[p].shifted);
  for (size_t e=0; e<sizeof extras/sizeof *extras; e++) {
   NSEventModifierFlags extra=extras[e];
   SetShownKey(pattern,shifted,C|extra);
   search(shifted,base,C|S|extra);
   requireColumn([NSString stringWithFormat:@"symbol U+%04X",pairs[p].shifted],[TSShortcutStore displayKey:shifted modifiers:C|extra],^BOOL(TSShortcutMatch *match){ return match.menuItem==pattern; });
   SetShownKey(pattern,base,C|S|extra);
   search(shifted,base,C|S|extra);
   NSString *shiftedMenu=[TSShortcutStore displayKey:base modifiers:C|S|extra];
   TSShortcutBinding *recorded=TSRecordedBinding(Event(shifted,C|S|extra,0),base);
   NSString *translated=[TSShortcutStore displayKey:recorded.key modifiers:recorded.modifiers];
   REQUIRE(![shiftedMenu isEqual:translated]);
   requireColumn([NSString stringWithFormat:@"base U+%04X",pairs[p].base],shiftedMenu,^BOOL(TSShortcutMatch *match){ return match.menuItem==pattern; });
   SetShownKey(pattern,shifted,C|S|extra);
   search(shifted,base,C|S|extra);
   requireColumn([NSString stringWithFormat:@"shifted U+%04X",pairs[p].shifted],[TSShortcutStore displayKey:shifted modifiers:C|S|extra],^BOOL(TSShortcutMatch *match){ return match.menuItem==pattern; });
  }
 }
 // Two spellings of one keypress. The field follows the item that runs.
 NSMenuItem *alias=[[NSMenuItem alloc] initWithTitle:@"Alias" action:@selector(description) keyEquivalent:@""];
 alias.allowsAutomaticKeyEquivalentLocalization=NO; [menu addItem:alias];
 SetShownKey(pattern,@"2",C|S); SetShownKey(alias,@"@",C);
 search(@"@",@"2",C|S);
 requireColumn(@"winner at",@"⌘@",^BOOL(TSShortcutMatch *match){ return match.menuItem==alias && match.winner; });
 REQUIRE([ShortcutColumnText(pane,^BOOL(TSShortcutMatch *match){ return match.menuItem==pattern; }) isEqual:@"⇧⌘2"]);
 REQUIRE(![pane.search.stringValue isEqual:@"⇧⌘2"]);
 SetShownKey(pattern,@"\\",C|S); SetShownKey(alias,@"|",C);
 search(@"|",@"\\",C|S);
 requireColumn(@"winner pipe",@"⌘|",^BOOL(TSShortcutMatch *match){ return match.menuItem==alias && match.winner; });
 REQUIRE([ShortcutColumnText(pane,^BOOL(TSShortcutMatch *match){ return match.menuItem==pattern; }) isEqual:@"⇧⌘\\"]);
 [menu removeItem:alias];
 // A refused macro is not a winner. The field still follows the row the list selects.
 {
  TSShortcutMacro *refusedYen=Macro(@"refused yen",@"\u00a5",S,92);
  macros=@[refusedYen];
  SetShownKey(macroItem,@"\u00a5",S); macroItem.identifier=TSMacroItemIdentifier(refusedYen.indexPath);
  search(@"|",@"\u00a5",S);
  NSString *menuYen=[TSShortcutStore displayKey:@"\u00a5" modifiers:S];
  requireColumn(@"refused yen",menuYen,^BOOL(TSShortcutMatch *match){ return match.macro==refusedYen && !match.winner; });
  REQUIRE(pane.searchMatches.count==1 && !pane.searchMatches[0].winner && [pane.search.stringValue isEqual:menuYen]);
  TSShortcutMacro *refusedDigit=Macro(@"refused digit",@"2",S,93);
  macros=@[refusedDigit];
  SetShownKey(macroItem,@"2",S); macroItem.identifier=TSMacroItemIdentifier(refusedDigit.indexPath);
  search(@"@",@"2",S);
  requireColumn(@"refused digit",@"⇧2",^BOOL(TSShortcutMatch *match){ return match.macro==refusedDigit && !match.winner; });
  REQUIRE(pane.searchMatches.count==1 && [pane.search.stringValue isEqual:@"⇧2"]);
 }
 macros=@[]; SetShownKey(macroItem,@"",0);
 SetShownKey(pattern,@"",0);
 for (NSMenuItem *item in @[letter,equals,digit,backslash,yen]) [menu addItem:item];
 // Commands, whose column is the store's display of the menu key.
 struct { NSMenuItem *item; NSString *characters,*plain,*shown; NSEventModifierFlags flags; } commands[]={
  {letter,@"b",@"b",@"⌘B",C},
  {equals,@"=",@"0",@"⌘=",C|S},
  {digit,@"@",@"2",@"⇧⌘2",C|S},
  {backslash,@"|",@"\\",@"⇧⌘\\",C|S},
  {yen,@"|",@"\u00a5",@"⇧⌘\u00a5",C|S}
 };
 for (size_t i=0; i<sizeof commands/sizeof *commands; i++) {
  NSMenuItem *item=commands[i].item;
  search(commands[i].characters,commands[i].plain,commands[i].flags);
  requireColumn(item.title,commands[i].shown,^BOOL(TSShortcutMatch *match){ return match.menuItem==item && match.winner; });
 }
 for (NSMenuItem *item in @[letter,equals,digit,backslash,yen]) [menu removeItem:item];
 // Macros keep the key the file names. JIS Shift+¥ stays on the yen key there.
 for (size_t p=0; p<sizeof pairs/sizeof *pairs; p++) {
  NSString *base=DisplayChar(pairs[p].base);
  TSShortcutMacro *macro=Macro([NSString stringWithFormat:@"macro %u",pairs[p].base],base,C|S,90);
  macros=@[macro];
  SetShownKey(macroItem,base,C|S); macroItem.identifier=TSMacroItemIdentifier(macro.indexPath);
  search(DisplayChar(pairs[p].shifted),base,C|S);
  TSShortcutBinding *menuShown=[store shownBindingForGivenKey:base modifiers:C|S];
  NSString *menuDisplay=[TSShortcutStore displayKey:menuShown.key modifiers:menuShown.modifiers];
  TSShortcutBinding *recorded=TSRecordedBinding(Event(DisplayChar(pairs[p].shifted),C|S,0),base);
  REQUIRE(![menuDisplay isEqual:[TSShortcutStore displayKey:recorded.key modifiers:recorded.modifiers]]);
  requireColumn(macro.name,menuDisplay,^BOOL(TSShortcutMatch *match){ return match.macro==macro && match.winner; });
 }
 for (NSString *key in @[@"q",@"m",@"5"]) {
  NSEventModifierFlags flags=[key isEqual:@"m"]?C|S:C;
  TSShortcutMacro *macro=Macro(key,key,flags,91);
  macros=@[macro];
  SetShownKey(macroItem,key,flags); macroItem.identifier=TSMacroItemIdentifier(macro.indexPath);
  search(key,key,flags);
  requireColumn(macro.name,[TSShortcutStore displayKey:key modifiers:flags],^BOOL(TSShortcutMatch *match){ return match.macro==macro && match.winner; });
 }
 macros=@[]; SetShownKey(macroItem,@"",0);
 printf("PASS: key search matches the menu display for %lu shortcut patterns\n",(unsigned long)shown);
}
// The arrow sits between the status words and the link, and that group shares the guide's center.
static void RequireSystemSettingsLine(TSShortcutPaneController *pane) {
  REQUIRE(!pane.systemSettingsArrow.hidden && !pane.systemSettingsLink.hidden && !pane.systemSettingsGuide.hidden);
  REQUIRE(![NSAccessibilityUnignoredChildren(pane.systemSettingsArrow.superview.accessibilityChildren) containsObject:pane.systemSettingsArrow.cell]);
  REQUIRE(!pane.systemSettingsArrow.cell.accessibilityElement);
  REQUIRE([pane.systemSettingsArrow.stringValue isEqual:@"→"]);
  [pane.view layoutSubtreeIfNeeded];
  NSRect statusWords=[pane.statusText convertRect:pane.statusText.bounds toView:pane.view];
  NSRect arrowWords=[pane.systemSettingsArrow convertRect:pane.systemSettingsArrow.bounds toView:pane.view];
  NSRect linkWords=[pane.systemSettingsLink convertRect:pane.systemSettingsLink.bounds toView:pane.view];
  NSRect guideWords=[pane.systemSettingsGuide convertRect:pane.systemSettingsGuide.bounds toView:pane.view];
  REQUIRE(NSMinX(arrowWords)+.5>=NSMaxX(statusWords) && NSMinX(linkWords)+.5>=NSMaxX(arrowWords));
  REQUIRE(NSMaxY(arrowWords)>NSMidY(statusWords) && NSMinY(arrowWords)<NSMidY(statusWords));
  REQUIRE(NSMaxY(linkWords)>NSMidY(statusWords) && NSMinY(linkWords)<NSMidY(statusWords));
  NSRect group=NSUnionRect(NSUnionRect(statusWords,arrowWords),linkWords);
  REQUIRE(fabs(NSMidX(group)-NSMidX(guideWords))<=2);
}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 nibPath=@(argv[1]);
 const NSUInteger C=NSEventModifierFlagCommand,S=NSEventModifierFlagShift,O=NSEventModifierFlagOption;
 TSReplaceTestMethod(class_getInstanceMethod(NSEvent.class,@selector(charactersByApplyingModifiers:)),(IMP)Characters);
 TSReplaceTestMethod(class_getInstanceMethod(NSWindow.class,@selector(keyDown:)),(IMP)RejectForwardedKey);
 class_addMethod(TSSettingsWindow.class,@selector(isKeyWindow),(IMP)IsKey,"B@:");
 CheckEventPriority();
 { NSMenu *hiddenMenu=[NSMenu new];NSMenuItem *hidden=Item(@"Hidden",@"h",C);[hiddenMenu addItem:hidden];TSShortcutStore *hiddenStore=[[TSShortcutStore alloc]initWithMenu:hiddenMenu defaults:TSIsolatedAppKitDefaults];hidden.hidden=YES;hidden.allowsKeyEquivalentWhenHidden=NO;REQUIRE([TSShortcutSearch matchesKey:@"h" modifiers:C store:hiddenStore macros:@[]].count==0);NSArray *candidate=@[@{@"key":@"h",@"modifiers":@(C)}];
 REQUIRE([hiddenStore conflictsForMacroShortcuts:candidate].count==0);
 hidden.allowsKeyEquivalentWhenHidden=YES;REQUIRE([hiddenStore conflictsForMacroShortcuts:candidate].count==1);
 REQUIRE([TSShortcutSearch matchesKey:@"h" modifiers:C store:hiddenStore macros:@[]].count==1); }

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

 // Independent raw Shift distinction through the actual key-search route.
 for(NSNumber *macroFlags in @[@(C),@(C|S)]){
  NSArray *shiftMacros=@[Macro(@"Shift distinction",@"x",macroFlags.unsignedIntegerValue,90)];
  REQUIRE([TSShortcutSearch matchesKey:@"x" modifiers:macroFlags.unsignedIntegerValue store:coordinator.store macros:shiftMacros].count==1);
  REQUIRE([TSShortcutSearch matchesKey:@"x" modifiers:(macroFlags.unsignedIntegerValue^S) store:coordinator.store macros:shiftMacros].count==0);
 }
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
 pane.search.stringValue=@"pre-existing query";[pane reloadCommands];
 shell.commandNamesProvider=^NSArray<NSString *> *{NSMutableArray *names=[NSMutableArray array];for(TSShortcutCommand *command in coordinator.store.commands)[names addObject:command.path];return names;};
 [shell selectCategoryIdentifier:@"general"];
 REQUIRE([shell setSettingsSearchQuery:@"First"]);
 NSTableView *results=[shell valueForKey:@"categoryTable"];[results selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
 REQUIRE([shell.history.currentIdentifier isEqual:@"keyboard"]);
 REQUIRE([pane.search.stringValue hasSuffix:@"First"] && pane.visibleCommands.count==1);
 REQUIRE([shell setSettingsSearchQuery:@""] && [shell.history.currentIdentifier isEqual:@"keyboard"]);
 REQUIRE([pane.search.stringValue isEqual:@"pre-existing query"]);
 [shell selectCategoryIdentifier:@"keyboard"];
 pane.search.stringValue=@"First";[pane reloadCommands];REQUIRE(pane.visibleCommands.count==1);
 NSDictionary *saved=[TSIsolatedAppKitDefaults.values copy];
 pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];
 REQUIRE(pane.searchingByKey && !pane.search.editable && shell.window.firstResponder==pane.keySearchView);
 REQUIRE(![shell setSettingsSearchQuery:@"PDF"] && shell.searchQuery.length==0);
 REQUIRE(![(id<NSSearchFieldDelegate>)shell control:[shell valueForKey:@"settingsSearchField"] textShouldBeginEditing:[NSText new]]);
 REQUIRE([pane.keySearchView.accessibilityValue isEqual:@"Press a key"]);
 for(NSString *key in @[@"q",@"w",@",",@"h",@"[",@"]"]){fixtureCharacters=key;REQUIRE([shell.window performKeyEquivalent:Event(key,C,0)] && pane.searchingByKey && [shell.history.currentIdentifier isEqual:TSSettingsCategoryKeyboard]);}
 fixtureCharacters=@"f";[shell.window keyDown:Event(@"f",C,3)];REQUIRE(pane.searchMatches.count==3 && pane.table.selectedRow==0 && [pane macroHeaderRow]==2);
 REQUIRE(pane.selectionButtons[0].enabled && !pane.macroButton.enabled);
 // A macro file can name a key that recording refuses (Control-Escape belongs to the marks): it never runs, and the list says why.
 { NSArray<TSShortcutMatch *> *refused=[TSShortcutSearch matchesKey:@"\x1b" modifiers:NSEventModifierFlagControl store:coordinator.store macros:@[Macro(@"Control-Escape",@"\x1b",NSEventModifierFlagControl,80)]];
   REQUIRE(refused.count==1 && refused[0].macro!=nil && !refused[0].winner);
   REQUIRE([[pane inactiveReasonForMatch:refused[0]] isEqual:[TSShortcutStore reasonForMacroConflict:@{@"refused":@YES}]] && [[pane inactiveReasonForMatch:refused[0]] containsString:@"cannot be used"]); }
 // Inactive matches: the path line plus the settings warning style (yellow triangle, small label-colored text) that fits its row.
 REQUIRE([pane.table.tableColumns[0].identifier isEqual:@"command"]);
 NSTextField *assigned=(NSTextField *)[pane tableView:pane.table viewForTableColumn:pane.table.tableColumns[0] row:0];
 REQUIRE([assigned isKindOfClass:NSTextField.class] && [assigned.stringValue hasSuffix:@"Assigned"] && [pane tableView:pane.table heightOfRow:0]==pane.table.rowHeight);
 NSTextField *header=(NSTextField *)[pane tableView:pane.table viewForTableColumn:nil row:2];
 REQUIRE([pane tableView:pane.table isGroupRow:2] && [header.stringValue isEqual:@"Macros"]);
 for(NSNumber *width in @[@300,@200,@520]) {
  pane.table.tableColumns[0].width=width.doubleValue;[pane.table layoutSubtreeIfNeeded];
  for(NSNumber *rowNumber in @[@1,@3]) {
   NSInteger row=rowNumber.integerValue;
   REQUIRE(!pane.searchMatches[row==1?1:2].winner);
   NSView *cell=[pane.table viewAtColumn:0 row:row makeIfNecessary:YES];[cell.superview layoutSubtreeIfNeeded];[cell layoutSubtreeIfNeeded];
   REQUIRE([cell.identifier isEqual:@"shortcut.inactive-command"] && NSHeight([pane.table rectOfRow:row])==[pane tableView:pane.table heightOfRow:row] && [pane tableView:pane.table heightOfRow:row]>pane.table.rowHeight);
   NSTextField *path=nil,*reason=nil;NSImageView *icon=nil;
   for(NSView *v in cell.subviews) if([v isKindOfClass:NSTextField.class]) path=(NSTextField *)v; else for(NSView *w in ((NSStackView *)v).arrangedSubviews){ if([w isKindOfClass:NSImageView.class]) icon=(NSImageView *)w; else reason=(NSTextField *)w; }
   REQUIRE([path.stringValue isEqual:pane.searchMatches[row==1?1:2].path]);
   REQUIRE([reason.identifier isEqual:@"shortcut.inactive-reason"] && [reason.stringValue containsString:@"conflicts with"] && [reason.stringValue containsString:first.title]);
   REQUIRE([icon.identifier isEqual:@"settings.warning-symbol.multicolor"] && icon.contentTintColor==nil && !icon.accessibilityElement);
   REQUIRE([reason.textColor isEqual:NSColor.labelColor] && reason.font.pointSize==NSFont.smallSystemFontSize);
   NSRect r=[reason convertRect:reason.bounds toView:cell];
   NSRect pr=[path convertRect:path.bounds toView:cell];
   if(!(cell.isFlipped ? NSMinY(r)>=NSMaxY(pr) : NSMaxY(r)<=NSMinY(pr)) || !NSContainsRect(NSInsetRect(cell.bounds,-2.5,-.5),r)) fprintf(stderr,"cell %s path %s reason %s\n",NSStringFromRect(cell.bounds).UTF8String,NSStringFromRect(pr).UTF8String,NSStringFromRect(r).UTF8String);
   REQUIRE((cell.isFlipped ? NSMinY(r)>=NSMaxY(pr) : NSMaxY(r)<=NSMinY(pr)) && NSContainsRect(NSInsetRect(cell.bounds,-2.5,-.5),r));
   CGFloat needed=[reason.cell cellSizeForBounds:NSMakeRect(0,0,NSWidth(reason.bounds),CGFLOAT_MAX)].height;
   REQUIRE(needed<=NSHeight(reason.bounds)+.5);
   // No blank line under the warning, and the path text starts where ordinary rows start.
   REQUIRE(NSHeight([pane.table rectOfRow:row])-(NSHeight(pr)+2+needed+4+pane.table.intercellSpacing.height)<1);
   NSTextField *plain=(NSTextField *)[pane.table viewAtColumn:0 row:0 makeIfNecessary:YES];
   REQUIRE(fabs(NSMinX([cell convertRect:[path alignmentRectForFrame:path.frame] toView:pane.table])-NSMinX([plain convertRect:[plain alignmentRectForFrame:plain.bounds] toView:pane.table]))<.5);
   REQUIRE(fabs(NSMinX([cell convertRect:[icon.superview convertRect:[icon alignmentRectForFrame:icon.frame] toView:cell] toView:pane.table])-NSMinX([cell convertRect:[path alignmentRectForFrame:path.frame] toView:pane.table]))<.5);
  }
 }
 pane.table.tableColumns[0].width=300;
 REQUIRE(![pane.keySearchView.accessibilityValue containsString:@"depends"]);
 REQUIRE([pane.keySearchView.accessibilityValue containsString:@"Matches: 3"]);
 NSScrollView *outer=pane.view.enclosingScrollView;
 // Keyboard scrolls like the other categories; in a window taller than its
 // content it fills the window, and the command list takes the extra height.
 REQUIRE(outer!=nil && outer.hasVerticalScroller && pane.table.enclosingScrollView.hasVerticalScroller);
 REQUIRE(outer.documentView.frame.size.height>=outer.contentView.bounds.size.height-1);

 [pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];[pane updateSelectionButtons];
 REQUIRE(!pane.selectionButtons[0].enabled && pane.macroButton.enabled);
 fixtureCharacters=@"z";[shell.window performKeyEquivalent:Event(@"z",C,6)];REQUIRE(pane.searchMatches.count==2 && pane.searchMatches[0].winner && !pane.searchMatches[1].winner && pane.table.selectedRow==1 && [pane macroHeaderRow]==0);
 NSTextField *macroWinner=(NSTextField *)[pane tableView:pane.table viewForTableColumn:pane.table.tableColumns[0] row:1];
 REQUIRE(pane.searchMatches[0].macro!=nil && [macroWinner.stringValue hasSuffix:@" — Assigned"]);
 fixtureCharacters=@"x";[shell.window performKeyEquivalent:Event(@"x",C,7)];REQUIRE(pane.searchMatches.count==0 && [pane.searchMessage containsString:@"No command"]);
 REQUIRE([shell.window makeFirstResponder:pane.table]);fixtureCharacters=@"x";
 IMP appKitSendEvent=method_setImplementation(class_getInstanceMethod(NSWindow.class,@selector(sendEvent:)),(IMP)AppKitSendEventProbe);
 forwardedWindowEvents=0;[shell.window sendEvent:Event(@"x",0,7)];
 method_setImplementation(class_getInstanceMethod(NSWindow.class,@selector(sendEvent:)),appKitSendEvent);
 REQUIRE(pane.searchMatches.count==0 && [pane.searchMessage containsString:@"cannot be used"] && forwardedKeys==0 && forwardedWindowEvents==0);
 fixtureCharacters=@"\r";forwardedKeys=0;REQUIRE([shell.window performKeyEquivalent:Event(@"\r",0,36)] && pane.searchingByKey && forwardedKeys==0 && [pane.searchMessage containsString:@"cannot be used"]);
 // Focus that moves to a control outside the menu shortcut controls ends key search, and keys then reach that control.
 {
  NSSearchField *settingsSearch=[shell valueForKey:@"settingsSearchField"];NSTableView *sidebar=[shell valueForKey:@"categoryTable"];
  for(NSView *outside in @[settingsSearch,sidebar]){
   if(!pane.searchingByKey){pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];}
   fixtureCharacters=@"f";[shell.window performKeyEquivalent:Event(@"f",C,3)];REQUIRE(pane.searchingByKey && pane.searchEvent!=nil);
   // The results and the key field are part of key search.
   for(NSView *inside in @[pane.table,pane.keySearchView]) REQUIRE([shell.window makeFirstResponder:inside] && pane.searchingByKey && pane.searchEvent!=nil);
   REQUIRE([shell.window makeFirstResponder:outside]);
   REQUIRE(!pane.searchingByKey && pane.searchMode.selectedSegment==0 && pane.search.editable && pane.keySearchView.hidden && [pane.search.stringValue isEqual:@"First"]);
   REQUIRE(![(id)shell handleKeySearchEvent:Event(@"f",C,3)]);
  }
  REQUIRE([(id<NSSearchFieldDelegate>)shell control:settingsSearch textShouldBeginEditing:[NSText new]] && [shell setSettingsSearchQuery:@""]);
  pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];REQUIRE(pane.searchingByKey && shell.window.firstResponder==pane.keySearchView);
 }
 // The search field's cancel button clears the recorded key: key search stays on and takes the next key.
 {
  NSView *frameView=shell.window.contentView.superview;
  NSPoint fieldPoint=[pane.search convertPoint:NSMakePoint(NSMidX(pane.search.bounds),NSMidY(pane.search.bounds)) toView:nil];
  // Delivers a click the way the window does: the hit view takes focus, then gets the mouse down and up.
  void (^Click)(NSPoint)=^(NSPoint point){
   NSView *hit=[frameView hitTest:point];REQUIRE(hit!=nil);
   if(hit.acceptsFirstResponder)[shell.window makeFirstResponder:hit];
   NSEvent *(^Mouse)(NSEventType)=^NSEvent *(NSEventType type){return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0 windowNumber:shell.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:type==NSEventTypeLeftMouseDown];};
   [hit mouseDown:Mouse(NSEventTypeLeftMouseDown)];[hit mouseUp:Mouse(NSEventTypeLeftMouseUp)];
  };
  fixtureCharacters=@"f";[shell.window performKeyEquivalent:Event(@"f",C,3)];
  NSString *recorded=[pane.search.stringValue copy];REQUIRE(pane.searchEvent!=nil && pane.searchMatches.count==3 && recorded.length>0);
  // The field places its cancel button only while it shows text.
  NSRect cancelRect=[pane.search convertRect:[(NSSearchFieldCell *)pane.search.cell cancelButtonRectForBounds:pane.search.bounds] toView:nil];
  NSPoint cancelPoint=NSMakePoint(NSMidX(cancelRect),NSMidY(cancelRect));REQUIRE(NSWidth(cancelRect)>0 && !NSPointInRect(fieldPoint,cancelRect));
  REQUIRE([pane.keySearchView isAccessibilitySelectorAllowed:@selector(accessibilityPerformCancel)]);
  // A click elsewhere in the field keeps the key.
  Click(fieldPoint);REQUIRE(pane.searchEvent!=nil && [pane.search.stringValue isEqual:recorded] && pane.searchMatches.count==3);
  REQUIRE([shell.window makeFirstResponder:pane.table]);
  Click(cancelPoint);
  REQUIRE(pane.searchingByKey && pane.searchMode.selectedSegment==1 && !pane.search.editable && !pane.keySearchView.hidden);
  REQUIRE(pane.searchEvent==nil && pane.searchMatches.count==0 && pane.search.stringValue.length==0);
  REQUIRE([pane.searchMessage isEqual:NSLocalizedString(@"Press a key",@"")] && [pane.hint.stringValue isEqual:pane.searchMessage] && [pane.keySearchView.accessibilityValue isEqual:pane.searchMessage]);
  REQUIRE(pane.table.numberOfRows==(NSInteger)pane.functionRows.count && pane.table.selectedRow==-1 && !pane.selectionButtons[0].enabled && !pane.macroButton.enabled);
  REQUIRE(shell.window.firstResponder==pane.keySearchView);
  // With no key recorded the field shows no cancel button, and the same spot does nothing.
  REQUIRE(![pane.keySearchView isAccessibilitySelectorAllowed:@selector(accessibilityPerformCancel)] && ![pane.keySearchView accessibilityPerformCancel]);
  Click(cancelPoint);REQUIRE(pane.searchingByKey && pane.searchEvent==nil && shell.window.firstResponder==pane.keySearchView);
  fixtureCharacters=@"z";[shell.window performKeyEquivalent:Event(@"z",C,6)];REQUIRE(pane.searchingByKey && pane.searchMatches.count==2 && pane.search.stringValue.length>0);
  // Assistive technologies clear the key with the cancel action.
  REQUIRE([shell.window makeFirstResponder:pane.table] && [pane.keySearchView accessibilityPerformCancel]);
  REQUIRE(pane.searchingByKey && pane.searchEvent==nil && pane.search.stringValue.length==0 && shell.window.firstResponder==pane.keySearchView);
 }
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
 // JIS Shift+¥ produces | . Comparison keeps that absolute-value spelling.
 // The field shows the menu spelling of the command that runs: Shift and the
 // yen key (backslash or ¥), the same string as the shortcut column.
 {
  NSArray<TSShortcutMacro *> * (^provider)(void)=coordinator.macroProvider;
  BOOL wasRebuilding=coordinator.rebuildingMacros;
  coordinator.rebuildingMacros=YES;
  fixtureCharacters=@"\\";
  REQUIRE([pane handleKeySearchEvent:Event(@"|",C|S,93)]);
  REQUIRE(pane.searchMatches.count==0 && [pane.search.stringValue isEqual:[TSShortcutStore displayKey:@"|" modifiers:C]]);
  NSTableColumn *shortcutColumn=nil;
  for(NSTableColumn *column in pane.table.tableColumns) if([column.identifier isEqual:@"shortcut"]) shortcutColumn=column;
  REQUIRE(shortcutColumn!=nil);
  struct { NSString *stored, *plain, *shown; } yenKeys[]={{@"\\",@"\\",@"⇧⌘\\"},{@"\u00a5",@"\u00a5",@"⇧⌘\u00a5"}};
  for(size_t i=0;i<2;i++){
   TSShortcutMacro *yenMacro=Macro(@"Absolute value",yenKeys[i].stored,C|S,80);
   coordinator.macroProvider=^{return @[yenMacro];};
   NSMenuItem *yenItem=Item(yenMacro.name,yenMacro.key,yenMacro.modifiers);
   yenItem.action=@selector(doMacro:);yenItem.identifier=TSMacroItemIdentifier(yenMacro.indexPath);
   [menu addItem:yenItem];
   fixtureCharacters=yenKeys[i].plain;
   NSEvent *yenEvent=Event(@"|",C|S,93);
   TSShortcutBinding *recorded=TSRecordedBinding(yenEvent,yenKeys[i].plain);
   REQUIRE([recorded.key isEqual:@"|"] && (recorded.modifiers&S)==0);
   REQUIRE([pane handleKeySearchEvent:yenEvent]);
   REQUIRE(pane.searchMatches.count==1 && pane.searchMatches[0].macro==yenMacro && pane.searchMatches[0].winner);
   NSTextField *column=(NSTextField *)[pane tableView:pane.table viewForTableColumn:shortcutColumn row:1];
   REQUIRE([column.stringValue isEqual:yenKeys[i].shown] && [pane.search.stringValue isEqual:column.stringValue]);
   // A command that stores the absolute value still shows that spelling; it runs.
   NSMenuItem *pipe=Item(@"Pipe",@"|",C);[menu addItem:pipe];
   REQUIRE([pane handleKeySearchEvent:yenEvent]);
   BOOL pipeWins=NO,yenListed=NO;
   for(TSShortcutMatch *hit in pane.searchMatches){
    if(hit.menuItem==pipe){pipeWins=hit.winner;REQUIRE([pane.search.stringValue isEqual:[TSShortcutStore displayKey:@"|" modifiers:C]]);}
    if(hit.macro==yenMacro)yenListed=YES;
   }
   REQUIRE(pipeWins && yenListed);
   [menu removeItem:pipe];[menu removeItem:yenItem];
  }
  coordinator.macroProvider=provider;coordinator.rebuildingMacros=wasRebuilding;
 }
 fixtureCharacters=@"0";[shell.window performKeyEquivalent:german];
 REQUIRE([pane.search.stringValue isEqual:[TSShortcutStore displayKey:@"=" modifiers:C]]);
 CheckKeySearchDisplayMatchesMenu();
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
 __block TSShortcutMacro *shown=nil;coordinator.showMacro=^(TSShortcutMacro *macro){shown=macro;};fixtureCharacters=@"z";[shell.window performKeyEquivalent:Event(@"z",C,6)];
 REQUIRE(pane.table.selectedRow>=0 && [pane matchAtRow:pane.table.selectedRow].macro!=nil);
 REQUIRE(pane.systemSettingsArrow.hidden && pane.systemSettingsLink.hidden && pane.systemSettingsGuide.hidden);
 [pane showSelectedMacro:nil];REQUIRE(shown==macros[1] && !pane.searchingByKey);
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
 sheetParent=nil;
 IMP showError=class_getMethodImplementation(TSShortcutPaneController.class,@selector(showError:));
 ((void(*)(id,SEL,id))showError)(pane,@selector(showError:),@"Fixture error");REQUIRE(sheetParent==shell.window);
 // Changing any captured value while a confirmation is pending must cancel the write.
 for(NSUInteger change=0;change<3;change++){
  pane.editingCommand=firstCommand;pane.capturedKey=@"z";pane.capturedModifiers=C;pane.capturedBindings=nil;
  NSDictionary *before=[TSIsolatedAppKitDefaults.values copy];NSString *originalKey=[first.keyEquivalent copy];
  sheetReply=nil;sheetParent=nil;[pane applyCapturedShortcut:nil];REQUIRE(sheetReply!=nil && sheetParent==shell.window);
  if(change==0)pane.editingCommand=coordinator.store.commands.lastObject;
  if(change==1)pane.capturedKey=@"v";
  if(change==2)pane.capturedModifiers=C|S;
  sheetReply(NSAlertSecondButtonReturn);
  REQUIRE([TSIsolatedAppKitDefaults.values isEqual:before] && [first.keyEquivalent isEqual:originalKey]);
  [pane endRecording];
 }
 // The macro reservation is checked again when the asynchronous reply arrives.
 accepted=NO;sheetReply=nil;[pane confirmMacrosUsingKey:@"z" modifiers:C completion:^(BOOL value){accepted=value;}];REQUIRE(sheetReply!=nil);
 macroItem.keyEquivalent=@"v";sheetReply(NSAlertSecondButtonReturn);REQUIRE(!accepted);macroItem.keyEquivalent=@"z";
 // An unchanged confirmation still applies the requested shortcut normally and ends recording.
 pane.editingCommand=firstCommand;pane.capturedKey=@"z";pane.capturedModifiers=C;pane.capturedBindings=nil;
 sheetReply=nil;[pane applyCapturedShortcut:nil];REQUIRE(sheetReply!=nil);sheetReply(NSAlertSecondButtonReturn);
 REQUIRE([first.keyEquivalent isEqual:@"z"] && pane.editingCommand==nil);
 puts("PASS: confirmations are asynchronous sheets attached to Settings");
 // Custom shortcuts (#76): bold in every list; the filter lists them, keeps one restored to its default
 // until the filter or the search changes, and does not apply in key search.
 {
  [shell selectCategoryIdentifier:TSSettingsCategoryKeyboard];
  if(pane.searchingByKey)[pane stopKeySearch];
  pane.search.stringValue=@"";[pane controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:pane.search]];
  TSShortcutStore *store=coordinator.store;
  [store restoreAll];[coordinator refreshMenuAndMacros];
  TSShortcutCommand *secondCommand=nil,*equalsCommand=nil;
  for(TSShortcutCommand *command in store.commands){if(command.item==second)secondCommand=command;if(command.item==equals)equalsCommand=command;}
  REQUIRE(secondCommand!=nil && equalsCommand!=nil);
  NSInteger shortcutColumn=[pane.table columnWithIdentifier:@"shortcut"],all=pane.table.numberOfRows;
  NSTextField *(^shortcutCell)(NSInteger)=^NSTextField *(NSInteger row){return (NSTextField *)[pane tableView:pane.table viewForTableColumn:pane.table.tableColumns[(NSUInteger)shortcutColumn] row:row];};
  BOOL (^isBold)(NSTextField *)=^BOOL(NSTextField *field){return [field isKindOfClass:NSTextField.class] && ([NSFontManager.sharedFontManager traitsOfFont:field.font]&NSBoldFontMask)!=0;};
  REQUIRE(pane.customFilter.enabled && pane.customFilter.state==NSControlStateValueOff && [pane.customFilter.toolTip isEqual:NSLocalizedString(@"Show Only Custom Shortcuts",@"")]);
  // With no custom shortcut, the filtered list is empty and says so.
  pane.customFilter.state=NSControlStateValueOn;[pane changeCustomFilter:pane.customFilter];
  REQUIRE(pane.table.numberOfRows==0 && [pane.hint.stringValue isEqual:NSLocalizedString(@"No custom shortcuts.",@"")]);
  pane.customFilter.state=NSControlStateValueOff;[pane changeCustomFilter:pane.customFilter];
  REQUIRE(pane.table.numberOfRows==all && ![pane.hint.stringValue isEqual:NSLocalizedString(@"No custom shortcuts.",@"")]);
  // A changed key and a removed key are custom; both are bold, a default is not.
  REQUIRE([store setKey:@"k" modifiers:C forCommand:firstCommand]==nil && [store setKey:@"" modifiers:0 forCommand:secondCommand]==nil);
  [coordinator refreshMenuAndMacros];
  REQUIRE([store commandIsCustomized:firstCommand] && [store commandIsCustomized:secondCommand] && ![store commandIsCustomized:equalsCommand]);
  REQUIRE(isBold(shortcutCell([pane rowForCommand:firstCommand])) && isBold(shortcutCell([pane rowForCommand:secondCommand])) && !isBold(shortcutCell([pane rowForCommand:equalsCommand])));
  REQUIRE(!isBold((NSTextField *)[pane tableView:pane.table viewForTableColumn:pane.table.tableColumns[0] row:[pane rowForCommand:firstCommand]]));
  pane.customFilter.state=NSControlStateValueOn;[pane changeCustomFilter:pane.customFilter];
  REQUIRE(pane.table.numberOfRows==2 && [pane rowForCommand:firstCommand]>=0 && [pane rowForCommand:secondCommand]>=0 && [pane rowForCommand:equalsCommand]<0);
  REQUIRE(![pane.hint.stringValue isEqual:NSLocalizedString(@"No custom shortcuts.",@"")]);
  // A command restored to its default stays, no longer bold, until the search changes.
  REQUIRE([store restoreCommand:firstCommand]==nil);[coordinator refreshMenuAndMacros];
  REQUIRE(pane.table.numberOfRows==2 && [pane rowForCommand:firstCommand]>=0 && !isBold(shortcutCell([pane rowForCommand:firstCommand])));
  pane.search.stringValue=@"Second";[pane controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:pane.search]];
  REQUIRE(pane.table.numberOfRows==1 && [pane rowForCommand:secondCommand]==0);
  pane.search.stringValue=@"";[pane controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:pane.search]];
  REQUIRE(pane.table.numberOfRows==1 && [pane rowForCommand:firstCommand]<0);
  // A search that matches no custom shortcut leaves the list empty without the message.
  pane.search.stringValue=@"Equals";[pane controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:pane.search]];
  REQUIRE(pane.table.numberOfRows==0 && ![pane.hint.stringValue isEqual:NSLocalizedString(@"No custom shortcuts.",@"")]);
  pane.search.stringValue=@"";[pane controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:pane.search]];
  // ... or until the filter is turned off and on.
  REQUIRE([store setKey:@"k" modifiers:C forCommand:firstCommand]==nil);[coordinator refreshMenuAndMacros];
  REQUIRE(pane.table.numberOfRows==2);
  REQUIRE([store restoreCommand:firstCommand]==nil);[coordinator refreshMenuAndMacros];
  REQUIRE(pane.table.numberOfRows==2);
  pane.customFilter.state=NSControlStateValueOff;[pane changeCustomFilter:pane.customFilter];REQUIRE(pane.table.numberOfRows==all);
  pane.customFilter.state=NSControlStateValueOn;[pane changeCustomFilter:pane.customFilter];REQUIRE(pane.table.numberOfRows==1);
  // Key search lists every match, with custom keys bold; the filter is off there and comes back after it.
  REQUIRE([store setKey:@"k" modifiers:C forCommand:firstCommand]==nil);[coordinator refreshMenuAndMacros];
  pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];
  REQUIRE(pane.searchingByKey && !pane.customFilter.enabled && pane.customFilter.state==NSControlStateValueOn && pane.table.numberOfRows>2 && [pane rowForCommand:equalsCommand]>=0);
  fixtureCharacters=@"k";[shell.window performKeyEquivalent:Event(@"k",C,40)];
  NSInteger matchRow=-1;for(NSInteger row=0;row<pane.table.numberOfRows;row++)if([pane matchAtRow:row].command==firstCommand)matchRow=row;
  REQUIRE(matchRow>=0 && isBold(shortcutCell(matchRow)));
  [pane stopKeySearch];
  REQUIRE(pane.customFilter.enabled && pane.customFilter.state==NSControlStateValueOn && pane.table.numberOfRows==2);
  // Restore All empties the filtered list.
  sheetReply=nil;[pane restoreAll:nil];REQUIRE(sheetReply!=nil);sheetReply(NSAlertFirstButtonReturn);
  REQUIRE(pane.table.numberOfRows==0 && [pane.hint.stringValue isEqual:NSLocalizedString(@"No custom shortcuts.",@"")]);
  // A saved key that another menu item takes leaves the default shown: not bold, not listed.
  pane.customFilter.state=NSControlStateValueOff;[pane changeCustomFilter:pane.customFilter];
  REQUIRE([store setKey:@"j" modifiers:C forCommand:firstCommand]==nil);[coordinator refreshMenuAndMacros];
  REQUIRE([store commandIsCustomized:firstCommand] && isBold(shortcutCell([pane rowForCommand:firstCommand])));
  dynamic.keyEquivalent=@"j";[coordinator refreshMenuAndMacros];
  REQUIRE([store.unavailableCommands containsObject:firstCommand.path] && [TSShownBinding(first) isEqual:TSBinding(firstCommand.defaultKey,firstCommand.defaultModifiers)]);
  REQUIRE(![store commandIsCustomized:firstCommand] && !isBold(shortcutCell([pane rowForCommand:firstCommand])));
  pane.customFilter.state=NSControlStateValueOn;[pane changeCustomFilter:pane.customFilter];REQUIRE([pane rowForCommand:firstCommand]<0);
  pane.customFilter.state=NSControlStateValueOff;[pane changeCustomFilter:pane.customFilter];
  dynamic.keyEquivalent=@"d";[coordinator refreshMenuAndMacros];
  REQUIRE([store commandIsCustomized:firstCommand] && isBold(shortcutCell([pane rowForCommand:firstCommand])));
  // A command with no default whose key was set and removed again shows no key, as its default: not bold, not listed.
  NSMenuItem *blank=Item(@"Blank",@"",0);[menu addItem:blank];[coordinator refreshMenuAndMacros];
  TSShortcutCommand *blankCommand=nil;for(TSShortcutCommand *command in store.commands)if(command.item==blank)blankCommand=command;
  REQUIRE(blankCommand!=nil && blankCommand.defaultKey.length==0);
  REQUIRE([store setKey:@"b" modifiers:C|O forCommand:blankCommand]==nil);[coordinator refreshMenuAndMacros];
  REQUIRE([store commandIsCustomized:blankCommand] && isBold(shortcutCell([pane rowForCommand:blankCommand])));
  REQUIRE([store setKey:@"" modifiers:0 forCommand:blankCommand]==nil);[coordinator refreshMenuAndMacros];
  REQUIRE(![store commandIsCustomized:blankCommand] && !isBold(shortcutCell([pane rowForCommand:blankCommand])));
  pane.customFilter.state=NSControlStateValueOn;[pane changeCustomFilter:pane.customFilter];REQUIRE([pane rowForCommand:blankCommand]<0 && [pane rowForCommand:firstCommand]>=0);
  pane.customFilter.state=NSControlStateValueOff;[pane changeCustomFilter:pane.customFilter];
  [menu removeItem:blank];[coordinator refreshMenuAndMacros];
  // Search Settings shows the command it found, custom or not.
  REQUIRE([store setKey:@"k" modifiers:C forCommand:firstCommand]==nil);[coordinator refreshMenuAndMacros];
  pane.customFilter.state=NSControlStateValueOn;[pane changeCustomFilter:pane.customFilter];REQUIRE(pane.table.numberOfRows==1);
  [pane applySettingsQuery:@"Equals" targets:@[] filterCommands:YES];
  REQUIRE(pane.customFilter.state==NSControlStateValueOff && pane.table.numberOfRows==1 && [pane rowForCommand:equalsCommand]==0);
  [pane applySettingsQuery:@"" targets:@[] filterCommands:NO];REQUIRE(pane.table.numberOfRows==all);
  REQUIRE([store setKey:@"z" modifiers:C forCommand:firstCommand]==nil);[coordinator refreshMenuAndMacros];
  puts("PASS: custom shortcuts are bold, filtered, kept after a restore until the search or filter changes, and unfiltered in key search");
 }
 // In-cell recording, as in Xcode's key bindings.
 {
  [shell selectCategoryIdentifier:TSSettingsCategoryKeyboard];
  if(pane.searchingByKey)[pane stopKeySearch];
  pane.search.stringValue=@"";[pane reloadCommands];[shell.window.contentView layoutSubtreeIfNeeded];
  TSShortcutStore *store=coordinator.store;TSShortcutCommand *secondCommand=nil;
  for(TSShortcutCommand *command in store.commands)if(command.item==second)secondCommand=command;
  REQUIRE(secondCommand!=nil && [store setKey:@"k" modifiers:C forCommand:firstCommand]==nil && [store setKey:@"u" modifiers:C forCommand:secondCommand]==nil);
  [coordinator refreshMenuAndMacros];
  NSInteger firstRow=[pane rowForCommand:firstCommand],secondRow=[pane rowForCommand:secondCommand],shortcutColumn=[pane.table columnWithIdentifier:@"shortcut"];
  REQUIRE(firstRow>=0 && secondRow>=0 && shortcutColumn==1);
  NSStackView *status=(NSStackView *)[pane viewWithIdentifier:@"shortcut.status" inView:pane.view];
  REQUIRE(status==pane.status && [pane.statusText.identifier isEqual:@"shortcut.status-text"]);
  // Under the list: the selected command's default shortcut.
  [pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)firstRow] byExtendingSelection:NO];
  NSString *firstDefault=firstCommand.defaultKey.length?[NSString stringWithFormat:NSLocalizedString(@"Default shortcut: %@",@""),[TSShortcutStore displayKey:firstCommand.defaultKey modifiers:firstCommand.defaultModifiers]]:NSLocalizedString(@"Default shortcut: None",@"");
  REQUIRE([pane.statusText.stringValue isEqual:firstDefault] && status.arrangedSubviews[0].hidden);
  REQUIRE(![pane.view.subviews containsObject:pane.recordingCell] && [pane viewWithIdentifier:@"shortcut.edit" inView:pane.view]==nil && [pane viewWithIdentifier:@"shortcut.remove" inView:pane.view]==nil);
  // A click on the shortcut of the row that was already selected records; other clicks only select.
  IMP originalClickedRow=method_setImplementation(class_getInstanceMethod(NSTableView.class,@selector(clickedRow)),(IMP)ClickedRow);
  IMP originalClickedColumn=method_setImplementation(class_getInstanceMethod(NSTableView.class,@selector(clickedColumn)),(IMP)ClickedColumn);
  TSShortcutTableView *table=(TSShortcutTableView *)pane.table;REQUIRE([table isKindOfClass:TSShortcutTableView.class]);
  fixtureClickedRow=firstRow;fixtureClickedColumn=shortcutColumn;table.rowSelectedAtMouseDown=-1;[pane tableClicked:table];REQUIRE(pane.editingCommand==nil);
  fixtureClickedColumn=0;table.rowSelectedAtMouseDown=firstRow;[pane tableClicked:table];REQUIRE(pane.editingCommand==nil);
  fixtureClickedColumn=shortcutColumn;[pane tableClicked:table];
  REQUIRE(pane.editingCommand==firstCommand && shell.window.firstResponder==pane.recorder);
  REQUIRE([pane.table viewAtColumn:shortcutColumn row:firstRow makeIfNecessary:NO]==pane.recordingCell && [pane.recorder isDescendantOf:pane.table]);
  NSString *firstShown=[TSShortcutStore displayKey:@"k" modifiers:C];
  REQUIRE([pane.recorder.shortcut isEqual:firstShown] && [pane.recorder.accessibilityValue isEqual:firstShown] && !pane.recorder.removeButton.hidden && pane.recordingWarning.hidden);
  NSDictionary *saved=[TSIsolatedAppKitDefaults.values copy];
  // Escape ends recording, keeps the shortcut and gives the list the focus.
  REQUIRE([shell.window performKeyEquivalent:Event(@"\033",0,53)]);
  REQUIRE(pane.editingCommand==nil && shell.window.firstResponder==pane.table && [first.keyEquivalent isEqual:@"k"] && [TSIsolatedAppKitDefaults.values isEqual:saved]);
  REQUIRE(![pane.recorder isDescendantOf:pane.table] && [[pane.table viewAtColumn:shortcutColumn row:firstRow makeIfNecessary:YES] isKindOfClass:TSShortcutKeyLabel.class]);
  // A double click on a row records in it.
  fixtureClickedRow=secondRow;[pane editShortcut:pane.table];REQUIRE(pane.editingCommand==secondCommand && pane.table.selectedRow==secondRow);
  [shell.window makeFirstResponder:pane.table];REQUIRE(pane.editingCommand==nil);
  method_setImplementation(class_getInstanceMethod(NSTableView.class,@selector(clickedRow)),originalClickedRow);
  method_setImplementation(class_getInstanceMethod(NSTableView.class,@selector(clickedColumn)),originalClickedColumn);
  // Return in the list records in the selected row.
  [pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)firstRow] byExtendingSelection:NO];
  [pane.table keyDown:Event(@"\r",0,36)];REQUIRE(pane.editingCommand==firstCommand && shell.window.firstResponder==pane.recorder);
  // A key in use is refused: recording goes on, a triangle marks the row and the reason replaces the default under the list.
  fixtureCharacters=@"=";REQUIRE([shell.window performKeyEquivalent:Event(@"=",C,24)]);
  REQUIRE(pane.editingCommand==firstCommand && shell.window.firstResponder==pane.recorder && [first.keyEquivalent isEqual:@"k"] && [TSIsolatedAppKitDefaults.values isEqual:saved]);
  REQUIRE([pane.recordingError containsString:equals.title] && [pane.statusText.stringValue isEqual:pane.recordingError] && !status.arrangedSubviews[0].hidden);
  REQUIRE(!pane.recordingWarning.hidden && [pane.recorder.shortcut isEqual:[TSShortcutStore displayKey:@"=" modifiers:C]]);
  // A key that cannot be a shortcut says so, through the window as typed.
  fixtureCharacters=@"a";[shell.window keyDown:Event(@"a",0,0)];
  REQUIRE(pane.editingCommand==firstCommand && [pane.statusText.stringValue isEqual:NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.",@"")] && forwardedKeys==0);
  // Focus that moves elsewhere ends recording; the default returns under the list.
  REQUIRE([shell.window makeFirstResponder:pane.search]);
  REQUIRE(pane.editingCommand==nil && pane.recordingError==nil && [first.keyEquivalent isEqual:@"k"] && [pane.statusText.stringValue isEqual:firstDefault] && status.arrangedSubviews[0].hidden);
  REQUIRE(shell.window.firstResponder==pane.search.currentEditor || shell.window.firstResponder==pane.search);
  // The row shows its shortcut again once the focus has moved.
  [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
  REQUIRE(![pane.recorder isDescendantOf:pane.table] && [[pane.table viewAtColumn:shortcutColumn row:firstRow makeIfNecessary:YES] isKindOfClass:TSShortcutKeyLabel.class]);
  // Recording that starts before then takes the field from the earlier row.
  [pane beginRecordingAtRow:firstRow];REQUIRE([shell.window makeFirstResponder:pane.search] && pane.editingCommand==nil);
  [pane beginRecordingAtRow:secondRow];
  REQUIRE([[pane.table viewAtColumn:shortcutColumn row:firstRow makeIfNecessary:YES] isKindOfClass:TSShortcutKeyLabel.class] && [pane.table viewAtColumn:shortcutColumn row:secondRow makeIfNecessary:NO]==pane.recordingCell);
  [shell.window performKeyEquivalent:Event(@"\033",0,53)];REQUIRE(pane.editingCommand==nil);
  // Assistive technologies press a shortcut to record it; a free key is assigned at once.
  TSShortcutKeyLabel *label=(TSShortcutKeyLabel *)[pane.table viewAtColumn:shortcutColumn row:secondRow makeIfNecessary:YES];
  REQUIRE([label isKindOfClass:TSShortcutKeyLabel.class] && [label isAccessibilitySelectorAllowed:@selector(accessibilityPerformPress)] && [label accessibilityPerformPress]);
  REQUIRE(pane.editingCommand==secondCommand && pane.table.selectedRow==secondRow && shell.window.firstResponder==pane.recorder);
  fixtureCharacters=@"y";REQUIRE([shell.window performKeyEquivalent:Event(@"y",C,16)]);
  REQUIRE(pane.editingCommand==nil && [second.keyEquivalent isEqual:@"y"] && shell.window.firstResponder==pane.table);
  REQUIRE([TSIsolatedAppKitDefaults.values[TSMenuShortcutOverridesKey][secondCommand.commandID] isEqual:TSBinding(@"y",C)]);
  // A key that a macro uses waits for the confirmation; Cancel ends recording and keeps the shortcut.
  [pane beginRecordingAtRow:secondRow];sheetReply=nil;sheetParent=nil;
  fixtureCharacters=@"z";[shell.window performKeyEquivalent:Event(@"z",C,6)];
  REQUIRE(sheetReply!=nil && sheetParent==shell.window && pane.editingCommand==secondCommand && [second.keyEquivalent isEqual:@"y"]);
  sheetReply(NSAlertFirstButtonReturn);REQUIRE(pane.editingCommand==nil && [second.keyEquivalent isEqual:@"y"]);
  [pane beginRecordingAtRow:secondRow];sheetReply=nil;
  fixtureCharacters=@"z";[shell.window performKeyEquivalent:Event(@"z",C,6)];REQUIRE(sheetReply!=nil);
  sheetReply(NSAlertSecondButtonReturn);REQUIRE(pane.editingCommand==nil && [second.keyEquivalent isEqual:@"z"]);
  // Delete while recording removes the shortcut; so does the button in the field.
  [pane beginRecordingAtRow:secondRow];fixtureCharacters=@"\177";[shell.window keyDown:Event(@"\177",0,51)];
  REQUIRE(pane.editingCommand==nil && second.keyEquivalent.length==0);
  [pane beginRecordingAtRow:secondRow];REQUIRE(pane.recorder.removeButton.hidden && [pane.recorder.accessibilityValue isEqual:NSLocalizedString(@"Press a key",@"")]);
  [shell.window performKeyEquivalent:Event(@"\033",0,53)];
  REQUIRE([store setKey:@"u" modifiers:C forCommand:secondCommand]==nil);
  [pane beginRecordingAtRow:secondRow];REQUIRE(!pane.recorder.removeButton.hidden);
  [pane.recorder.removeButton performClick:nil];REQUIRE(pane.editingCommand==nil && second.keyEquivalent.length==0);
  // Tab ends recording and moves on; a reload of the list ends it too.
  [pane beginRecordingAtRow:firstRow];fixtureCharacters=@"\t";[shell.window keyDown:Event(@"\t",0,48)];
  REQUIRE(pane.editingCommand==nil && shell.window.firstResponder!=pane.recorder && [first.keyEquivalent isEqual:@"k"]);
  [pane beginRecordingAtRow:firstRow];[pane reloadCommands];REQUIRE(pane.editingCommand==nil && ![pane.recorder isDescendantOf:pane.table]);
  // Key search results record in place, and the results follow the change.
  pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];
  fixtureCharacters=@"k";[shell.window performKeyEquivalent:Event(@"k",C,40)];REQUIRE(pane.searchMatches.count==1 && pane.searchMatches[0].command==firstCommand);
  [pane beginRecordingAtRow:0];REQUIRE(pane.editingCommand==firstCommand && pane.searchingByKey && shell.window.firstResponder==pane.recorder);
  fixtureCharacters=@"b";REQUIRE([shell.window performKeyEquivalent:Event(@"b",C,11)]);
  REQUIRE(pane.editingCommand==nil && [first.keyEquivalent isEqual:@"b"] && pane.searchingByKey && pane.searchMatches.count==0);
  [pane stopKeySearch];
  // While documents autosave, Save As… keeps macOS's ⌥⇧⌘S: dimmed as in Xcode, not recorded, no buttons (#46).
  const NSUInteger O=NSEventModifierFlagOption;
  NSMenuItem *saveAsItem=Item(@"SaveAs",@"S",C|O);saveAsItem.action=@selector(saveDocumentAs:);
  NSMenuItem *duplicateItem=[[NSMenuItem alloc]initWithTitle:@"Duplicate" action:@selector(duplicateDocument:) keyEquivalent:@"S"];duplicateItem.identifier=@"duplicateDocument:";duplicateItem.alternate=YES;
  [first.menu addItem:saveAsItem];[first.menu addItem:duplicateItem];[coordinator refreshMenuAndMacros];[pane reloadCommands];
  TSShortcutCommand *saveAsCommand=nil,*duplicateCommand=nil;
  for(TSShortcutCommand *command in store.commands){if(command.item==saveAsItem)saveAsCommand=command;if(command.item==duplicateItem)duplicateCommand=command;}
  NSInteger saveAsRow=[pane rowForCommand:saveAsCommand],duplicateRow=[pane rowForCommand:duplicateCommand];
  REQUIRE(saveAsCommand.managedBySystem && !duplicateCommand.managedBySystem && saveAsRow>=0 && duplicateRow>=0);
  NSString *saveAsShown=[TSShortcutStore displayKey:@"S" modifiers:C|O];
  for(NSInteger column=0;column<2;column++){
   NSTextField *cell=(NSTextField *)[pane.table viewAtColumn:column row:saveAsRow makeIfNecessary:YES];
   REQUIRE(![cell isKindOfClass:TSShortcutKeyLabel.class] && [cell.textColor isEqual:NSColor.disabledControlTextColor]);
   if(column==shortcutColumn)REQUIRE([cell.stringValue isEqual:saveAsShown]);
  }
  REQUIRE([[pane.table viewAtColumn:shortcutColumn row:duplicateRow makeIfNecessary:YES] isKindOfClass:TSShortcutKeyLabel.class]);
  [pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)saveAsRow] byExtendingSelection:NO];
  for(NSButton *button in pane.selectionButtons)REQUIRE(!button.enabled);
  REQUIRE([pane.statusText.stringValue isEqual:NSLocalizedString(@"Cannot Be Changed",@"")]);
  REQUIRE(!pane.systemSettingsLink.hidden && !pane.systemSettingsGuide.hidden);
  [pane beginRecordingAtRow:saveAsRow];REQUIRE(pane.editingCommand==nil);
  [pane removeShortcut:nil];[pane restoreShortcut:nil];REQUIRE([saveAsItem.keyEquivalent isEqual:@"S"] && saveAsItem.keyEquivalentModifierMask==(C|O));
  [pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)duplicateRow] byExtendingSelection:NO];
  REQUIRE(pane.selectionButtons[0].enabled && pane.systemSettingsArrow.hidden && pane.systemSettingsLink.hidden && pane.systemSettingsGuide.hidden);
  [first.menu removeItem:saveAsItem];[first.menu removeItem:duplicateItem];[coordinator refreshMenuAndMacros];[pane reloadCommands];
  // Enter Full Screen has Globe-F, which macOS gives only its own items: shown as AppKit 27 shows it (🌐︎F), dimmed,
  // not recorded, no buttons, found by its name; Control-Command-F is Next Mark's, and a key saved for it before is left out.
  const NSUInteger FSControl=NSEventModifierFlagControl,FSFunction=NSEventModifierFlagFunction;
  NSMenuItem *fullScreen=[[NSMenuItem alloc]initWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@""];fullScreen.identifier=@"TSShortcut.toggleFullScreen:.0";
  NSMenuItem *nextMark=Item(@"NextMark",@"f",C|FSControl);
  [first.menu addItem:fullScreen];[first.menu addItem:nextMark];TSGiveFullScreenGlobeKey(first.menu);
  REQUIRE([fullScreen.keyEquivalent isEqual:@"f"] && fullScreen.keyEquivalentModifierMask==FSFunction);
  [coordinator refreshMenuAndMacros];[pane reloadCommands];
  TSShortcutCommand *fullScreenCommand=nil,*nextMarkCommand=nil;
  for(TSShortcutCommand *command in store.commands){if(command.item==fullScreen)fullScreenCommand=command;if(command.item==nextMark)nextMarkCommand=command;}
  NSInteger fullScreenRow=[pane rowForCommand:fullScreenCommand];
  REQUIRE(fullScreenCommand.managedBySystem && !nextMarkCommand.managedBySystem && fullScreenRow>=0);
  NSString *globeF=@"\U0001F310︎F";
  for(NSInteger column=0;column<2;column++){
   NSTextField *cell=(NSTextField *)[pane.table viewAtColumn:column row:fullScreenRow makeIfNecessary:YES];
   REQUIRE(![cell isKindOfClass:TSShortcutKeyLabel.class] && [cell.textColor isEqual:NSColor.disabledControlTextColor]);
   if(column==shortcutColumn)REQUIRE([cell.stringValue isEqual:globeF]);
  }
  [pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)fullScreenRow] byExtendingSelection:NO];
  for(NSButton *button in pane.selectionButtons)REQUIRE(!button.enabled);
  REQUIRE([pane.statusText.stringValue isEqual:NSLocalizedString(@"Cannot Be Changed",@"")]);
  [pane beginRecordingAtRow:fullScreenRow];REQUIRE(pane.editingCommand==nil);
  [pane removeShortcut:nil];[pane restoreShortcut:nil];
  REQUIRE([store setKey:@"j" modifiers:C|FSControl forCommand:fullScreenCommand]!=nil);
  [coordinator refreshMenuAndMacros];
  REQUIRE([fullScreen.keyEquivalent isEqual:@"f"] && fullScreen.keyEquivalentModifierMask==FSFunction);
  // Control-Command-F recorded for another command meets Next Mark, as any key in use.
  NSString *taken=[store setKey:@"f" modifiers:C|FSControl forCommand:firstCommand];
  REQUIRE(taken!=nil && [taken containsString:nextMarkCommand.path] && ![taken containsString:fullScreenCommand.path]);
  // Searching by name finds the row.
  NSString *query=pane.search.stringValue;pane.search.stringValue=@"Full Screen";[pane reloadCommands];
  REQUIRE([pane.visibleCommands containsObject:fullScreenCommand] && [store.settingsSearchCommandNames containsObject:fullScreenCommand.path]);
  pane.search.stringValue=query;[pane reloadCommands];
  // A key saved for Enter Full Screen by an earlier version is left out: the item keeps Globe-F.
  {
   TSMemoryDefaults *earlier=[TSMemoryDefaults new];
   [earlier setObject:@{@"TSShortcut.toggleFullScreen:.0":@{@"key":@"f",@"modifiers":@(C|FSControl)}} forKey:TSMenuShortcutOverridesKey];
   TSShortcutStore *earlierStore=[[TSShortcutStore alloc]initWithMenu:first.menu defaults:(NSUserDefaults *)earlier];
   REQUIRE([fullScreen.keyEquivalent isEqual:@"f"] && fullScreen.keyEquivalentModifierMask==FSFunction && earlierStore.unavailableCommands.count==0);
   REQUIRE([nextMark.keyEquivalent isEqual:@"f"] && (nextMark.keyEquivalentModifierMask&(C|FSControl))==(C|FSControl));
  }
  // Key search tells F from 🌐︎F (fn-F): F does not find Enter Full Screen; 🌐︎F finds it alone and the field shows 🌐︎F
  // as the list does. Control-Command-F still finds Next Mark.
  {
   BOOL wasSearching=pane.searchingByKey;
   if(!wasSearching){pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];}
   REQUIRE(pane.searchingByKey && pane.editingCommand==nil);
   fixtureCharacters=@"f";
   REQUIRE([pane handleKeySearchEvent:Event(@"f",0,3)]);
   BOOL bareFFindsFullScreen=NO;for(TSShortcutMatch *hit in pane.searchMatches)if(hit.menuItem==fullScreen)bareFFindsFullScreen=YES;
   REQUIRE(!bareFFindsFullScreen && [pane.search.stringValue isEqual:@"F"]);
   REQUIRE([pane handleKeySearchEvent:Event(@"f",FSFunction,3)]);
   REQUIRE(pane.searchMatches.count==1 && pane.searchMatches[0].menuItem==fullScreen && pane.searchMatches[0].winner);
   REQUIRE([pane.search.stringValue isEqual:globeF]);
   NSTextField *fullScreenLabel=(NSTextField *)[pane tableView:pane.table viewForTableColumn:pane.table.tableColumns[0] row:0];
   REQUIRE([fullScreenLabel.stringValue hasSuffix:@" — Cannot Be Changed"] && [fullScreenLabel.textColor isEqual:NSColor.disabledControlTextColor]);
   REQUIRE(pane.table.selectedRow==0 && [pane.statusText.stringValue isEqual:NSLocalizedString(@"Cannot Be Changed",@"")] && !pane.systemSettingsLink.hidden && !pane.systemSettingsGuide.hidden);
   // Minimize All is AppKit's Option alternate and has no command: key search says it cannot be changed.
   {
    NSMenuItem *minimizeAll=[[NSMenuItem alloc] initWithTitle:@"Minimize All" action:@selector(miniaturizeAll:) keyEquivalent:@"m"];
    minimizeAll.keyEquivalentModifierMask=C|O;
    [first.menu addItem:minimizeAll];[coordinator refreshMenuAndMacros];
    // Function search lists the same item in gray. The line under the list says it cannot be changed.
    {
     BOOL wasKey=pane.searchingByKey;
     if(wasKey)[pane stopKeySearch];
     pane.search.stringValue=@"Minimize All";[pane reloadCommands];
     REQUIRE(pane.visibleCommands.count==0 && pane.functionRows.count==1 && pane.functionRows[0].command==nil && pane.functionRows[0].item==minimizeAll && pane.table.numberOfRows==1);
     NSString *miniKey=[TSShortcutStore displayKey:@"m" modifiers:C|O];
     for(NSInteger column=0;column<2;column++){
      NSTextField *cell=(NSTextField *)[pane.table viewAtColumn:column row:0 makeIfNecessary:YES];
      REQUIRE([cell isKindOfClass:NSTextField.class] && ![cell isKindOfClass:TSShortcutKeyLabel.class] && [cell.textColor isEqual:NSColor.disabledControlTextColor]);
      REQUIRE([cell.stringValue isEqual:column==0?@"Actions › Minimize All":miniKey]);
     }
     [pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
     REQUIRE([pane.statusText.stringValue isEqual:NSLocalizedString(@"Cannot Be Changed",@"")] && pane.status.arrangedSubviews[0].hidden);
     REQUIRE(!pane.systemSettingsLink.hidden && !pane.systemSettingsGuide.hidden);
     REQUIRE([pane.systemSettingsLink.attributedStringValue.string isEqual:NSLocalizedString(@"Change in System Settings…",@"")]);
     REQUIRE([pane.systemSettingsGuide.stringValue isEqual:NSLocalizedString(@"To change it in System Settings, choose “App Shortcuts” in the sidebar.",@"")]);
     id systemURL=[pane.systemSettingsLink.attributedStringValue attribute:NSLinkAttributeName atIndex:0 effectiveRange:NULL];
     id underline=[pane.systemSettingsLink.attributedStringValue attribute:NSUnderlineStyleAttributeName atIndex:0 effectiveRange:NULL];
     REQUIRE([systemURL isKindOfClass:NSURL.class] && [[(NSURL *)systemURL absoluteString] isEqual:pane.systemShortcutSettingsURL.absoluteString] && [pane.systemShortcutSettingsURL.absoluteString isEqual:@"x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"]);
     REQUIRE(underline==nil || [underline integerValue]==NSUnderlineStyleNone);
     RequireSystemSettingsLine(pane);
     for(NSButton *button in pane.selectionButtons)REQUIRE(!button.enabled);
     [pane beginRecordingAtRow:0];REQUIRE(pane.editingCommand==nil);
     minimizeAll.hidden=YES;[pane reloadCommands];REQUIRE(pane.functionRows.count==0 && pane.table.numberOfRows==0);
     minimizeAll.allowsKeyEquivalentWhenHidden=YES;[pane reloadCommands];REQUIRE(pane.functionRows.count==1 && pane.functionRows[0].item==minimizeAll);
     minimizeAll.allowsKeyEquivalentWhenHidden=NO;minimizeAll.hidden=NO;
     NSMenuItem *noKey=[[NSMenuItem alloc] initWithTitle:@"No Key Item" action:@selector(arrangeInFront:) keyEquivalent:@""];
     [first.menu addItem:noKey];
     NSMenuItem *macroRowItem=[[NSMenuItem alloc] initWithTitle:@"Macro Item" action:TSMacroAction() keyEquivalent:@"q"];
     macroRowItem.keyEquivalentModifierMask=C;[first.menu addItem:macroRowItem];
     pane.search.stringValue=@"No Key Item";[pane reloadCommands];
     REQUIRE(pane.functionRows.count==0 && noKey.action!=nil);
     pane.search.stringValue=@"Macro Item";[pane reloadCommands];
     REQUIRE(pane.functionRows.count==0 && macroRowItem.action!=nil);
     [first.menu removeItem:noKey];[first.menu removeItem:macroRowItem];
     pane.search.stringValue=@"";[pane reloadCommands];
     if(wasKey){pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];}
    }
    REQUIRE(pane.searchingByKey);
    REQUIRE([pane handleKeySearchEvent:Event(@"m",C|O,46)]);
    NSInteger miniRow=-1;
    for(NSInteger row=0;row<(NSInteger)pane.table.numberOfRows;row++){
     TSShortcutMatch *hit=[pane matchAtRow:row];
     if(hit.menuItem!=minimizeAll)continue;
     miniRow=row;REQUIRE(hit.winner && hit.command==nil && hit.macro==nil);
    }
    REQUIRE(miniRow>=0);
    NSTextField *miniLabel=(NSTextField *)[pane tableView:pane.table viewForTableColumn:pane.table.tableColumns[0] row:miniRow];
    REQUIRE([miniLabel isKindOfClass:NSTextField.class] && ![miniLabel isKindOfClass:TSShortcutKeyLabel.class] && [miniLabel.stringValue isEqual:@"Actions › Minimize All — Cannot Be Changed"] && [miniLabel.textColor isEqual:NSColor.disabledControlTextColor]);
    [pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)miniRow] byExtendingSelection:NO];
    REQUIRE([pane.statusText.stringValue isEqual:NSLocalizedString(@"Cannot Be Changed",@"")] && !pane.systemSettingsLink.hidden && !pane.systemSettingsGuide.hidden);
    [first.menu removeItem:minimizeAll];[coordinator refreshMenuAndMacros];
   }
   REQUIRE([pane handleKeySearchEvent:Event(@"f",C|FSControl,3)]);
   BOOL controlCommandFFindsNextMark=NO;for(TSShortcutMatch *hit in pane.searchMatches){REQUIRE(hit.menuItem!=fullScreen);if(hit.menuItem==nextMark)controlCommandFFindsNextMark=YES;}
   REQUIRE(controlCommandFFindsNextMark && [pane.search.stringValue isEqual:[TSShortcutStore displayKey:@"f" modifiers:C|FSControl]]);
   NSInteger nextMarkRow=-1;for(NSInteger row=0;row<(NSInteger)pane.table.numberOfRows;row++)if([pane matchAtRow:row].menuItem==nextMark)nextMarkRow=row;
   REQUIRE(nextMarkRow>=0);[pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)nextMarkRow] byExtendingSelection:NO];
   REQUIRE(pane.systemSettingsArrow.hidden && pane.systemSettingsLink.hidden && pane.systemSettingsGuide.hidden);
   NSArray<TSShortcutMatch *> *bareF=[TSShortcutSearch matchesKey:@"f" modifiers:0 store:store macros:@[]];
   NSArray<TSShortcutMatch *> *globeFHits=[TSShortcutSearch matchesKey:@"f" modifiers:FSFunction store:store macros:@[]];
   REQUIRE(bareF.count==0 && globeFHits.count==1 && globeFHits[0].menuItem==fullScreen);
   if(!wasSearching){pane.searchMode.selectedSegment=0;[pane changeSearchMode:pane.searchMode];REQUIRE(!pane.searchingByKey);}
  }
  [first.menu removeItem:fullScreen];[first.menu removeItem:nextMark];[coordinator refreshMenuAndMacros];[pane reloadCommands];
  // 🌐︎⌃⌘B (fn) is refused while recording, before anything is saved: AppKit keeps fn only on its own items and would
  // give the command ⌃⌘B. ⌃⌘B records; ⌘↑ and F5, which carry the fn flag of their own, record as before. What the
  // store saves and what key search finds agree for each.
  {
   const NSUInteger G=NSEventModifierFlagFunction,K=NSEventModifierFlagControl,P=NSEventModifierFlagNumericPad;
   NSString *globeRefusal=NSLocalizedString(@"Shortcuts with the Globe key (fn) can't be assigned to TeXShop commands.",@"");
   if(pane.searchingByKey){pane.searchMode.selectedSegment=0;[pane changeSearchMode:pane.searchMode];}
   pane.search.stringValue=@"";[pane reloadCommands];
   NSString *keptKey=first.keyEquivalent;NSEventModifierFlags keptFlags=first.keyEquivalentModifierMask&TSShortcutModifiers;
   NSDictionary *unchanged=[TSIsolatedAppKitDefaults.values copy];
   // What key search finds for a key typed with these flags.
   NSArray<TSShortcutMatch *> *(^search)(NSString *,NSUInteger,unsigned short)=^NSArray<TSShortcutMatch *> *(NSString *c,NSUInteger flags,unsigned short code){
    pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];
    fixtureCharacters=c;REQUIRE([pane handleKeySearchEvent:Event(c,flags,code)]);NSArray *hits=pane.searchMatches;
    pane.searchMode.selectedSegment=0;[pane changeSearchMode:pane.searchMode];pane.search.stringValue=@"";[pane reloadCommands];return hits;};
   REQUIRE(search(@"b",C|K,11).count==0 && search(@"b",C|K|G,11).count==0);
   [pane beginRecordingAtRow:[pane rowForCommand:firstCommand]];REQUIRE(pane.editingCommand==firstCommand && shell.window.firstResponder==pane.recorder);
   fixtureCharacters=@"b";[shell.window performKeyEquivalent:Event(@"b",C|K|G,11)];
   NSDictionary *globeStored=TSIsolatedAppKitDefaults.values[TSMenuShortcutOverridesKey][firstCommand.commandID];
   printf("Recorded fn+ctrl+cmd+B -> item %s, stored %s, message %s\n",[TSShortcutStore displayKey:first.keyEquivalent modifiers:first.keyEquivalentModifierMask].UTF8String,globeStored?[TSShortcutStore displayKey:globeStored[@"key"] modifiers:[globeStored[@"modifiers"] unsignedIntegerValue]].UTF8String:"(none)",pane.statusText.stringValue.UTF8String);
   REQUIRE(pane.editingCommand==firstCommand && shell.window.firstResponder==pane.recorder && [first.keyEquivalent isEqual:keptKey] && (first.keyEquivalentModifierMask&TSShortcutModifiers)==keptFlags && [TSIsolatedAppKitDefaults.values isEqual:unchanged]);
   REQUIRE([pane.recordingError isEqual:globeRefusal] && [pane.statusText.stringValue isEqual:globeRefusal] && !status.arrangedSubviews[0].hidden && !pane.recordingWarning.hidden);
   REQUIRE([pane.recorder.shortcut isEqual:[TSShortcutStore displayKey:keptKey modifiers:keptFlags]]);
   [shell.window performKeyEquivalent:Event(@"\033",0,53)];REQUIRE(pane.editingCommand==nil && [first.keyEquivalent isEqual:keptKey]);
   REQUIRE(search(@"b",C|K,11).count==0 && search(@"b",C|K|G,11).count==0);
   // Characters beyond ASCII are character keys too, wherever they are in Unicode: the fullwidth comma of Cangjie's
   // key 43 (U+FF0C, above U+F700), the ideographic comma of Japanese layouts (U+3001) and a Latin letter (ö).
   // Each is refused with fn as B is, the old key kept and the recording going on.
   struct { NSString *c; unsigned short code; } globeKeys[]={{@"\uFF0C",43},{@"\u3001",43},{@"\u00F6",41}};
   for(size_t i=0;i<sizeof globeKeys/sizeof *globeKeys;i++){
    [pane beginRecordingAtRow:[pane rowForCommand:firstCommand]];REQUIRE(pane.editingCommand==firstCommand);
    sheetReply=nil;fixtureCharacters=globeKeys[i].c;[shell.window performKeyEquivalent:Event(globeKeys[i].c,C|K|G,globeKeys[i].code)];
    NSDictionary *stored=TSIsolatedAppKitDefaults.values[TSMenuShortcutOverridesKey][firstCommand.commandID];
    printf("Recorded fn+ctrl+cmd+U+%04X -> item %s, stored %s, message %s\n",[globeKeys[i].c characterAtIndex:0],[TSShortcutStore displayKey:first.keyEquivalent modifiers:first.keyEquivalentModifierMask].UTF8String,stored?[TSShortcutStore displayKey:stored[@"key"] modifiers:[stored[@"modifiers"] unsignedIntegerValue]].UTF8String:"(none)",pane.statusText.stringValue.UTF8String);
    REQUIRE(sheetReply==nil && pane.editingCommand==firstCommand && [first.keyEquivalent isEqual:keptKey] && (first.keyEquivalentModifierMask&TSShortcutModifiers)==keptFlags && [TSIsolatedAppKitDefaults.values isEqual:unchanged]);
    REQUIRE([pane.recordingError isEqual:globeRefusal] && [pane.statusText.stringValue isEqual:globeRefusal] && !pane.recordingWarning.hidden);
    [shell.window performKeyEquivalent:Event(@"\033",0,53)];REQUIRE(pane.editingCommand==nil && [first.keyEquivalent isEqual:keptKey]);
   }
   // Without fn the fullwidth comma records as any key; key search then finds ⌃⌘， and not 🌐︎⌃⌘，, as for B.
   {
    [pane beginRecordingAtRow:[pane rowForCommand:firstCommand]];sheetReply=nil;fixtureCharacters=@"\uFF0C";
    [shell.window performKeyEquivalent:Event(@"\uFF0C",C|K,43)];if(sheetReply)sheetReply(NSAlertSecondButtonReturn);
    REQUIRE(pane.editingCommand==nil && pane.recordingError==nil && [TSShownBinding(first) isEqual:TSBinding(@"\uFF0C",C|K)]);
    NSUInteger plainHits=search(@"\uFF0C",C|K,43).count,globeHits=search(@"\uFF0C",C|K|G,43).count;
    printf("Recorded ctrl+cmd+U+FF0C -> search hits %lu, with fn %lu\n",(unsigned long)plainHits,(unsigned long)globeHits);
    REQUIRE(plainHits==1 && globeHits==0);
    // The field of key search shows the Globe key with it, as with 🌐︎F.
    REQUIRE([TSShortcutDisplayKey(@"\uFF0C",C|K|G) isEqual:@"⌃⌘\U0001F310\uFE0E\uFF0C"] && [TSShortcutDisplayKey(@"\uF700",C|G) isEqual:@"⌘↑"]);
    REQUIRE([store setKey:keptKey modifiers:keptFlags forCommand:firstCommand]==nil);[coordinator refreshMenuAndMacros];[pane reloadCommands];
    unchanged=[TSIsolatedAppKitDefaults.values copy];
   }
   // Enter with fn (fn-Return on a laptop) ends the recording as Enter does: neither refused for fn nor recorded.
   [pane beginRecordingAtRow:[pane rowForCommand:firstCommand]];REQUIRE(pane.editingCommand==firstCommand);fixtureCharacters=@"\x03";
   [shell.window performKeyEquivalent:Event(@"\x03",G,36)];
   REQUIRE(pane.editingCommand==nil && pane.recordingError==nil && [first.keyEquivalent isEqual:keptKey] && [TSIsolatedAppKitDefaults.values isEqual:unchanged]);
   // ⌘Enter with fn meets the rule for keys that cannot be shortcuts, as ⌘Enter does, not the refusal for fn.
   [pane beginRecordingAtRow:[pane rowForCommand:firstCommand]];REQUIRE(pane.editingCommand==firstCommand);fixtureCharacters=@"\x03";
   [shell.window performKeyEquivalent:Event(@"\x03",C|G,36)];
   REQUIRE(pane.editingCommand==firstCommand && pane.recordingError!=nil && ![pane.recordingError isEqual:globeRefusal] && [first.keyEquivalent isEqual:keptKey]);
   [shell.window performKeyEquivalent:Event(@"\033",0,53)];REQUIRE(pane.editingCommand==nil);
   // ⌃⌘B, ⌘↑ (as a real arrow key comes: fn and the keypad flag), F5 (fn), ⌘⌦ (fn-Delete on a laptop: fn) and
   // ⌘⇟ (fn) record; search finds them as saved.
   struct { NSString *c; NSUInteger flags; unsigned short code; NSString *key; NSUInteger saved; } keys[]={
    {@"b",C|K,11,@"b",C|K},{@"\uF700",C|G|P,126,@"\uF700",C},{@"\uF708",G,96,@"\uF708",0},
    {@"\uF728",C|G,117,@"\uF728",C},{@"\uF72D",C|G,121,@"\uF72D",C}};
   for(size_t i=0;i<sizeof keys/sizeof *keys;i++){
    [pane beginRecordingAtRow:[pane rowForCommand:firstCommand]];REQUIRE(pane.editingCommand==firstCommand);
    sheetReply=nil;fixtureCharacters=keys[i].c;[shell.window performKeyEquivalent:Event(keys[i].c,keys[i].flags,keys[i].code)];
    if(sheetReply)sheetReply(NSAlertSecondButtonReturn);
    NSDictionary *stored=TSIsolatedAppKitDefaults.values[TSMenuShortcutOverridesKey][firstCommand.commandID];
    NSArray<TSShortcutMatch *> *hits=search(keys[i].c,keys[i].flags,keys[i].code);
    printf("Recorded %s -> stored %s, search hits %lu\n",[TSShortcutStore displayKey:keys[i].key modifiers:keys[i].saved].UTF8String,stored?[TSShortcutStore displayKey:stored[@"key"] modifiers:[stored[@"modifiers"] unsignedIntegerValue]].UTF8String:"(none)",(unsigned long)hits.count);
    REQUIRE(pane.editingCommand==nil && pane.recordingError==nil && [stored isEqual:TSBinding(keys[i].key,keys[i].saved)] && [TSShownBinding(first) isEqual:TSBinding(keys[i].key,keys[i].saved)]);
    REQUIRE(hits.count==1 && hits[0].command==firstCommand);
   }
   REQUIRE([store setKey:keptKey modifiers:keptFlags forCommand:firstCommand]==nil);[coordinator refreshMenuAndMacros];[pane reloadCommands];
  }
 }
 puts("PASS: Globe-key characters (B, U+FF0C, U+3001, ö) are refused while recording, nothing saved; Control-Command-B, Command-Up Arrow, F5, Command-Forward Delete and Command-Page Down record with fn and are found as saved; Enter with fn ends recording");
 puts("PASS: in-cell recording starts from the selected shortcut, double click, Return and VoiceOver; Escape, Tab and focus elsewhere end it; keys in use are refused under the list; free keys apply at once; macro keys confirm; Delete and the field button remove; Save As… under autosave is dimmed and kept");
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
  REQUIRE([localizedStrings[@"Shortcuts with the Globe key (fn) can't be assigned to TeXShop commands."] length]>0);
  TSShortcutPaneController *translated=[[TSShortcutPaneController alloc]initWithShortcuts:coordinator];
  NSView *inputHeader=InputHeader();translated.settingsHeader=inputHeader;
  NSWindow *host=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,700,460) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];NSScrollView *outer=[[NSScrollView alloc]initWithFrame:host.contentView.bounds];outer.hasVerticalScroller=YES;outer.automaticallyAdjustsContentInsets=NO;outer.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;host.contentView=outer;translated.view.translatesAutoresizingMaskIntoConstraints=NO;outer.documentView=translated.view;[translated.view.widthAnchor constraintEqualToAnchor:outer.contentView.widthAnchor].active=YES;
  [translated viewDidLayout];[host.contentView layoutSubtreeIfNeeded];CheckButtons(translated.view,translated.view);
  REQUIRE(AllInputGroupsVisible(translated));
  REQUIRE(NSHeight(translated.table.enclosingScrollView.frame)>40);
  REQUIRE(translated.table.enclosingScrollView.documentView==translated.table && translated.table.headerView.superview!=nil);
  REQUIRE(![inputHeader isDescendantOf:translated.table.enclosingScrollView]);
  REQUIRE([translated.table isDescendantOf:[translated viewWithIdentifier:@"group.shortcuts" inView:translated.view]]);
  // Striped rows, like the key binding list above it, light and dark.
  {NSIndexSet *selected=translated.table.selectedRowIndexes;[translated.table deselectAll:nil];
   for(NSAppearanceName name in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){NSString *detail=nil;BOOL menuRowsStriped=TSTestRowsStriped(translated.table,name,&detail);
    if([language hasPrefix:@"ja"])printf("STRIPES %s\n",detail.UTF8String);REQUIRE(menuRowsStriped);}
   [translated.table selectRowIndexes:selected byExtendingSelection:NO];}
  REQUIRE(translated.table.rowHeight==22 && translated.table.style==NSTableViewStyleInset && translated.table.usesAlternatingRowBackgroundColors);
  [translated.table scrollRowToVisible:translated.table.numberOfRows-1];
  REQUIRE(NSIntersectsRect(translated.table.visibleRect,[translated.table rectOfRow:translated.table.numberOfRows-1]));
  TSSettingsSearch *index=[[TSSettingsSearch alloc]initWithBundle:NSBundle.mainBundle categoryOrder:@[@"keyboard"] commandNames:@[]];
  searchExcludedView=translated.settingsHeader;
  SearchViews(translated.view,@"keyboard",index);searchExcludedView=nil;
  [translated applySettingsQuery:@"completion" targets:@[@"row.catalog.keyboard.1.0"] filterCommands:NO];
  REQUIRE(AllInputGroupsVisible(translated));
  [translated applySettingsQuery:@"bindings" targets:@[@"heading.group.bindings"] filterCommands:NO];
  REQUIRE(AllInputGroupsVisible(translated));
  [translated applySettingsQuery:@"ＦＩＲＳＴ" targets:@[] filterCommands:YES];
  REQUIRE(translated.visibleCommands.count==1);
  [translated applySettingsQuery:@"" targets:@[] filterCommands:NO];
  translated.search.stringValue=@"missing command fixture";[translated reloadCommands];
  REQUIRE(translated.table.numberOfRows==0);
  translated.searchMode.selectedSegment=1;[translated changeSearchMode:translated.searchMode];
  REQUIRE(translated.searchEvent==nil && translated.table.numberOfRows==(NSInteger)translated.functionRows.count);
  NSUInteger beforeFlags=translated.table.numberOfRows;NSEvent *flagsEvent=[NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint modifierFlags:S timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:56];
  @try { REQUIRE([translated handleKeySearchEvent:flagsEvent] && translated.searchEvent==nil && translated.table.numberOfRows==beforeFlags); } @catch(NSException *exception) { Check(NO,@"Modifier-only events must not reach character translation"); }
  for(id trigger in @[@"TAB",@"ESCAPE",NSNull.null,@"unexpected",@"ESC",@"TAB"]){
   [TSIsolatedAppKitDefaults setObject:trigger==NSNull.null?nil:trigger forKey:@"CommandCompletionChar"];
   NSDictionary *unchanged=[TSIsolatedAppKitDefaults.values copy];fixtureCharacters=@"\t";
   REQUIRE([translated handleKeySearchEvent:Event(@"\t",0,48)]);
   BOOL reserved=![trigger isEqual:@"ESCAPE"];
   REQUIRE([translated.searchMessage isEqual:NSLocalizedString(@"This key is reserved for command completion.",@"")]==reserved);
   REQUIRE((translated.highlightedCompletionRow!=nil)==reserved);
   if(!reserved)REQUIRE([translated.searchMessage isEqual:NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.",@"")]);
   if(reserved){
    REQUIRE(AllInputGroupsVisible(translated));
    REQUIRE(translated.highlightedCompletionRow.layer.backgroundColor!=nil && translated.highlightedCompletionRow.layer.borderWidth==0);
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
  // Shift with the trigger key is the previous candidate: the trigger row is shown too.
  fixtureCharacters=@"\t";[translated handleKeySearchEvent:Event(@"\t",NSEventModifierFlagShift,48)];
  REQUIRE([translated.highlightedCompletionRow.identifier isEqual:@"row.catalog.keyboard.1.0"] && [translated.searchMessage isEqual:NSLocalizedString(@"This key is reserved for command completion.",@"")]);
  // Option or Control with the trigger key moves between marks: the switch row of those keys is shown.
  fixtureCharacters=@"\t";[translated handleKeySearchEvent:Event(@"\t",NSEventModifierFlagOption,48)];
  REQUIRE([translated.highlightedCompletionRow.identifier isEqual:@"row.catalog.keyboard.1.3"]);
  fixtureCharacters=@"\t";[translated handleKeySearchEvent:Event(@"\t",NSEventModifierFlagControl,48)];
  REQUIRE([translated.highlightedCompletionRow.identifier isEqual:@"row.catalog.keyboard.1.3"]);
  fixtureCharacters=@"\t";[translated handleKeySearchEvent:Event(@"\t",0,48)];
  NSView *highlighted=translated.highlightedCompletionRow;
  REQUIRE(highlighted!=nil && highlighted.layer.backgroundColor!=nil && highlighted.layer.borderWidth==0);
  [translated stopKeySearch];REQUIRE(translated.highlightedCompletionRow==nil && highlighted.layer.backgroundColor==nil);
  translated.searchMode.selectedSegment=1;[translated changeSearchMode:translated.searchMode];
  for(NSString *plain in @[@"a",@"x"]){
   fixtureCharacters=plain;[translated handleKeySearchEvent:Event(plain,0,0)];
   REQUIRE([translated.searchMessage isEqual:NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.",@"")]);
  }
  fixtureCharacters=@"x";[translated handleKeySearchEvent:Event(@"x",S,7)];REQUIRE([translated.searchMessage isEqual:NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.",@"")]);
  fixtureCharacters=@"x";[translated handleKeySearchEvent:Event(@"x",NSEventModifierFlagControl|NSEventModifierFlagOption|NSEventModifierFlagCommand,7)];
  REQUIRE(translated.searchMatches.count==0 && translated.highlightedCompletionRow==nil);
  REQUIRE([translated.searchMessage isEqual:NSLocalizedString(@"No command uses this key.",@"")]);
  [translated stopKeySearch];
  [host setContentSize:NSMakeSize(700,780)];[translated viewDidLayout];[translated.view layoutSubtreeIfNeeded];
  REQUIRE(AllInputGroupsVisible(translated));
  translated.searchMode.selectedSegment=1;[translated changeSearchMode:translated.searchMode];fixtureCharacters=@"\t";
  [translated handleKeySearchEvent:Event(@"\t",0,48)];
  [host setContentSize:NSMakeSize(700,460)];[translated viewDidLayout];[translated.view layoutSubtreeIfNeeded];
  REQUIRE(AllInputGroupsVisible(translated));
  CheckButtons(translated.view,translated.view);
  REQUIRE(NSContainsRect(translated.view.bounds,translated.table.enclosingScrollView.frame));
  REQUIRE(NSWidth(translated.searchMode.frame)+1>=translated.searchMode.intrinsicContentSize.width);
  // The custom-shortcut filter sits whole between the search field and the search modes.
  REQUIRE(NSWidth(translated.customFilter.frame)+.5>=translated.customFilter.intrinsicContentSize.width && NSMaxX(translated.search.frame)<=NSMinX(translated.customFilter.frame) && NSMaxX(translated.customFilter.frame)<=NSMinX(translated.searchMode.frame));
  // The line under the list shows the longest default and refusal texts whole, and the recording field shows the longest key.
  {
   [translated stopKeySearch];translated.search.stringValue=@"";[translated reloadCommands];
   REQUIRE(translated.table.numberOfRows>0);[translated.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
   for(NSString *text in @[NSLocalizedString(@"Default shortcut: None",@""),[NSString stringWithFormat:NSLocalizedString(@"Default shortcut: %@",@""),@"⌃⌥⇧⌘F12"],
     [NSString stringWithFormat:NSLocalizedString(@"This shortcut is already used by “%@”.",@""),@"Format ▸ Font ▸ Bigger"],NSLocalizedString(@"This key cannot be used as a shortcut. Use Command or Control with a key, or F1–F20.",@""),
     NSLocalizedString(@"Shortcuts with the Globe key (fn) can't be assigned to TeXShop commands.",@"")]){
    translated.statusText.stringValue=text;translated.status.arrangedSubviews[0].hidden=NO;[translated.view layoutSubtreeIfNeeded];
    NSRect line=[translated.status convertRect:translated.status.bounds toView:translated.view];
    REQUIRE(NSContainsRect(NSInsetRect(translated.view.bounds,-.5,-.5),line));
    CGFloat needed=[translated.statusText.cell cellSizeForBounds:NSMakeRect(0,0,NSWidth(translated.statusText.bounds),CGFLOAT_MAX)].height;
    REQUIRE(needed<=NSHeight(translated.statusText.bounds)+.5);
    NSRect buttons=[translated.selectionButtons[0] convertRect:translated.selectionButtons[0].bounds toView:translated.view];
    REQUIRE(!NSIntersectsRect(line,buttons) && !NSIntersectsRect(line,[translated.table.enclosingScrollView convertRect:translated.table.enclosingScrollView.bounds toView:translated.view]));
   }
   [translated updateStatus];
   translated.systemSettingsArrow.hidden=NO;translated.systemSettingsLink.hidden=NO;translated.systemSettingsGuide.hidden=NO;[translated viewDidLayout];[translated.view layoutSubtreeIfNeeded];
   NSRect linkLine=[translated.systemSettingsLink convertRect:translated.systemSettingsLink.bounds toView:translated.view];
   NSRect guideLine=[translated.systemSettingsGuide convertRect:translated.systemSettingsGuide.bounds toView:translated.view];
   NSRect buttonLine=[translated.selectionButtons[0] convertRect:translated.selectionButtons[0].bounds toView:translated.view];
   REQUIRE(NSContainsRect(NSInsetRect(translated.view.bounds,-.5,-.5),linkLine) && NSContainsRect(NSInsetRect(translated.view.bounds,-.5,-.5),guideLine));
   RequireSystemSettingsLine(translated);
   REQUIRE(!NSIntersectsRect(linkLine,buttonLine) && !NSIntersectsRect(guideLine,buttonLine));
   REQUIRE(NSHeight(guideLine)+.5>=translated.systemSettingsGuide.intrinsicContentSize.height);
   [translated updateStatus];
   NSView *cell=translated.recordingCell;cell.frame=NSMakeRect(0,0,translated.table.tableColumns[1].width,translated.table.rowHeight);[cell layoutSubtreeIfNeeded];
   translated.recorder.shortcut=@"⌃⌥⇧⌘F12";[cell layoutSubtreeIfNeeded];
   REQUIRE(NSWidth(translated.recorder.label.frame)+.5>=translated.recorder.label.intrinsicContentSize.width);
   REQUIRE(NSMaxX(translated.recorder.frame)<=NSMinX(translated.recordingWarning.frame) && NSMaxX(translated.recordingWarning.frame)<=NSWidth(cell.bounds));
   REQUIRE(translated.table.tableColumns[1].width>=translated.table.tableColumns[1].headerCell.cellSize.width);
  }
  fprintf(stdout,"PASS: %s pane controls fit minimum content size\n",language.UTF8String);
 }}
 localizedStrings=nil;method_setImplementation(class_getInstanceMethod(NSBundle.class,@selector(localizedStringForKey:value:table:)),originalLocalization);
 [[NSNotificationCenter defaultCenter] removeObserver:macroObserver];
 REQUIRE(TSIsolatedAppKitDefaults==NSUserDefaults.standardUserDefaults);
}}
