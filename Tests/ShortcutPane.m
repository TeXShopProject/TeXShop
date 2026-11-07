// Settings integration tests. No visible windows, user defaults or macro files.
#import "TestAppKitIsolation.h"
#import "TSKeyboardShortcuts.m"
#import "TSSettingsCategory.h"
#import "TSMacroTreeNode.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
static NSString *nibPath;
static NSDictionary *localizedStrings;
static IMP originalLocalization;
static NSString *Localized(NSBundle *bundle,SEL cmd,NSString *key,NSString *value,NSString *table){return localizedStrings[key] ?: ((id(*)(id,SEL,id,id,id))originalLocalization)(bundle,cmd,key,value,table);}
static void CheckButtons(NSView *view,NSView *root){
 for(NSView *child in view.subviews){
  if([child isKindOfClass:NSButton.class]) {NSRect rect=[child convertRect:child.bounds toView:root];REQUIRE(NSMinX(rect)>=0 && NSMaxX(rect)<=NSWidth(root.bounds)+1 && NSMinY(rect)>=0 && NSMaxY(rect)<=NSHeight(root.bounds)+1);REQUIRE(NSWidth(child.frame)+1>=child.intrinsicContentSize.width);}
  CheckButtons(child,root);
 }
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
static NSWindow *sheetParent;
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
 NSMenu *main=[NSMenu new],*menu=[NSMenu new];NSMenuItem *root=[[NSMenuItem alloc]initWithTitle:@"Actions" action:NULL keyEquivalent:@""];root.submenu=menu;[main addItem:root];NSApp.mainMenu=main;
 NSMenuItem *first=Item(@"First",@"f",C),*second=Item(@"Second",@"f",C),*equals=Item(@"Equals",@"=",C);
 for(NSMenuItem *item in @[first,second,equals])[menu addItem:item];
 NSDictionary *oldEntry=@{@"key":@"y",@"modifiers":@(C)};
 [TSIsolatedAppKitDefaults setObject:@{@"TSShortcut.First":@{@"key":@"k",@"modifiers":@(C)},@"TSShortcut.showKeyboardShortcuts:.0":oldEntry} forKey:TSMenuShortcutOverridesKey];
 TSKeyboardShortcuts *coordinator=[TSKeyboardShortcuts new];
 [coordinator startObservingMenu];
 REQUIRE([first.keyEquivalent isEqual:@"k"] && ![coordinator isKindOfClass:NSWindowController.class]);
 REQUIRE(menu.numberOfItems==3 && [TSIsolatedAppKitDefaults.values[TSMenuShortcutOverridesKey][@"TSShortcut.showKeyboardShortcuts:.0"] isEqual:oldEntry]);
 __block int routed=0;coordinator.showSettings=^{routed++;};[coordinator showKeyboardShortcuts:nil];REQUIRE(routed==1);
 [coordinator.store restoreAll];
 NSArray *macros=@[Macro(@"First macro",@"f",C,0),Macro(@"Free",@"z",C,1),Macro(@"Later free",@"z",C,2),Macro(@"JIS",@"-",C|S,3)];
 coordinator.macroProvider=^{return macros;};
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
 puts("PASS: saved assignments without a pane, compatibility routing, inert old ID, shared raw ownership and dynamic matches");
 Shell *shell=[[Shell alloc]initWithDefaults:TSIsolatedAppKitDefaults];Delegate *delegate=[Delegate new];shell.settingsDelegate=delegate;
 NSView *legacy=[[NSView alloc]initWithFrame:NSMakeRect(0,0,700,600)];NSTabView *tabs=[[NSTabView alloc]initWithFrame:legacy.bounds];[legacy addSubview:tabs];
 for(NSUInteger i=0;i<9;i++){NSTabViewItem *tab=[[NSTabViewItem alloc]initWithIdentifier:@(i)];tab.label=[NSString stringWithFormat:@"Pane %lu",i];tab.view=[NSView new];[tabs addTabViewItem:tab];}
 [shell hostLegacyContent:legacy tabView:tabs];
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
 for(NSString *key in @[@"q",@"w",@",",@"h",@"[",@"]"]){fixtureCharacters=key;REQUIRE([shell.window performKeyEquivalent:Event(key,C,0)] && pane.searchingByKey && [shell.history.currentIdentifier isEqual:TSSettingsCategoryKeyboard]);}
 fixtureCharacters=@"f";[shell.window keyDown:Event(@"f",C,3)];REQUIRE(pane.searchMatches.count==3 && pane.table.selectedRow==0 && [pane macroHeaderRow]==2);
 REQUIRE(pane.selectionButtons[0].enabled && !pane.macroButton.enabled);
 [pane.table selectRowIndexes:[NSIndexSet indexSetWithIndex:3] byExtendingSelection:NO];[pane updateSelectionButtons];
 REQUIRE(!pane.selectionButtons[0].enabled && pane.macroButton.enabled);
 fixtureCharacters=@"z";[shell.window performKeyEquivalent:Event(@"z",C,6)];REQUIRE(pane.searchMatches.count==2 && pane.table.selectedRow==1 && [pane macroHeaderRow]==0);
 fixtureCharacters=@"x";[shell.window performKeyEquivalent:Event(@"x",C,7)];REQUIRE(pane.searchMatches.count==0 && [pane.searchMessage containsString:@"No command"]);
 REQUIRE([shell.window makeFirstResponder:pane.table]);fixtureCharacters=@"x";[shell.window keyDown:Event(@"x",0,7)];REQUIRE(pane.searchMatches.count==0 && [pane.searchMessage containsString:@"cannot be used"] && forwardedKeys==0);
 REQUIRE([TSIsolatedAppKitDefaults.values isEqual:saved]);
 REQUIRE([shell.window performKeyEquivalent:Event(@"\033",0,53)] && !pane.searchingByKey && pane.search.editable && [pane.search.stringValue isEqual:@"First"]);
 for(NSUInteger reason=0;reason<4;reason++){
  [shell selectCategoryIdentifier:TSSettingsCategoryKeyboard];pane.searchMode.selectedSegment=1;[pane changeSearchMode:pane.searchMode];REQUIRE(pane.searchingByKey);
  if(reason==0)[pane changeSearchMode:pane.searchMode];
  if(reason==1)[shell selectCategoryIdentifier:TSSettingsCategorySource];
  if(reason==2)[NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidResignKeyNotification object:shell.window];
  if(reason==3)[shell endSession];
  REQUIRE(!pane.searchingByKey);
 }
 REQUIRE(created==1);
 [shell beginSession];[shell selectCategoryIdentifier:TSSettingsCategorySource];[shell selectCategoryIdentifier:TSSettingsCategoryKeyboard];
 fixtureCharacters=@"[";REQUIRE([shell.window performKeyEquivalent:Event(@"5",C|O,23)] && [shell.history.currentIdentifier isEqual:TSSettingsCategorySource]);
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
  NSWindow *host=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,700,570) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];host.contentView=translated.view;
  [host.contentView layoutSubtreeIfNeeded];CheckButtons(translated.view,translated.view);
  REQUIRE(NSWidth(translated.searchMode.frame)+1>=translated.searchMode.intrinsicContentSize.width);
  fprintf(stdout,"PASS: %s pane controls fit minimum content size\n",language.UTF8String);
 }}
 localizedStrings=nil;method_setImplementation(class_getInstanceMethod(NSBundle.class,@selector(localizedStringForKey:value:table:)),originalLocalization);
 REQUIRE(TSIsolatedAppKitDefaults==NSUserDefaults.standardUserDefaults);
}}
