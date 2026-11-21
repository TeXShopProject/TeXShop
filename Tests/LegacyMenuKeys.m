// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#include "TSLegacyMenuKeyEquivalents.inc"
static NSDictionary *fixtureEntries;
static NSDictionary *FixtureEntries(NSString *path){NSCAssert([path hasSuffix:@"KeyEquivalents.plist"],@"Legacy filename");return fixtureEntries;}
static NSString *MenuShortcutsPath=@"/memory-only/Keyboard";
@interface LegacyEntry:NSObject
- (void)finishMenuKeyEquivalentsConfigure;
@end
@implementation LegacyEntry
// APPLICATION_ENTRY
@end
static void Apply(NSMenu *main,NSDictionary *entries){NSApp.mainMenu=main;fixtureEntries=entries;[[LegacyEntry new] finishMenuKeyEquivalentsConfigure];}
static void Check(BOOL ok, NSString *message) { if (!ok) {fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);} }
static NSMenuItem *Item(NSMenu *menu, NSString *title) {NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:title action:NULL keyEquivalent:@""];[menu addItem:item];return item;}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];
 NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:nil];
 for(NSString *title in [fixture[@"titles"] allValues])for(NSNumber *old in @[@YES,@NO]){
  NSMenu *main=[NSMenu new];NSMenuItem *source=Item(main,@"Source");source.submenu=[NSMenu new];
  NSMenuItem *bindings=Item(source.submenu,@"Key Bindings");NSMenuItem *toggle=bindings;
  if(old.boolValue){bindings.submenu=[NSMenu new];toggle=Item(bindings.submenu,title);Item(bindings.submenu,@"Edit Key Bindings File…");}
  toggle.identifier=@"TSShortcut.changeAutoComplete:.0";
  NSMenuItem *completion=Item(source.submenu,@"Add to Command Completion List");completion.identifier=@"TSShortcut.registerForCommandCompletion:.0";
  NSMenuItem *other=Item(source.submenu,@"Other");
  NSArray *key=@[@"k",@YES,@NO];
  for(NSString *child in @[@"1",title]){
   toggle.keyEquivalent=@"";
   Apply(main,@{@"1":@{@"1":@{child:key}}});
   Check([toggle.keyEquivalent isEqual:@"k"],@"Numeric parent plus legacy child retains toggle");
   toggle.keyEquivalent=@"";
   Apply(main,@{@"Source":@{@"Key Bindings":@{child:key}}});
   Check([toggle.keyEquivalent isEqual:@"k"],@"Named path retains toggle");
   for(NSNumber *option in @[@NO,@YES])for(NSNumber *control in @[@NO,@YES]){
    Apply(main,@{@"Source":@{@"Key Bindings":@{child:@[@"k",option,control]}}});
    NSEventModifierFlags mask=toggle.keyEquivalentModifierMask;
    Check((mask & NSEventModifierFlagCommand)!=0 && ((mask & NSEventModifierFlagOption)!=0)==option.boolValue && ((mask & NSEventModifierFlagControl)!=0)==control.boolValue,@"Legacy Command/Option/Control modifiers are retained independently");
   }
  }
  Apply(main,@{@"1":@{@"2":@{@"3":@[@"e",@NO,@NO]},@"3":@[@"z",@NO,@YES]},@"999":@{},@"-2":@{}});
  Check([other.keyEquivalent isEqual:@"z"] && (other.keyEquivalentModifierMask & NSEventModifierFlagControl) && [completion.keyEquivalent isEqual:@""],@"Removed completion or invalid menu does not interrupt other assignments");
  if(!old.boolValue){Check([toggle.keyEquivalent isEqual:@"k"],@"Removed editor never targets toggle");Apply(main,@{@"1":@{@"1":@{@"2":@[@"e",@NO,@NO],@"Edit Key Bindings File…":@[@"e",@NO,@NO]}}});Check([toggle.keyEquivalent isEqual:@"k"],@"Removed editor compatibility entries stay inert");}
  Apply(main,@{@"1":@{@"3":@[],@"999":@[@"x",@NO,@NO],@"-1":@[@"x",@NO,@NO],@"2":@{@"999":@[@"x",@NO,@NO],@"1":@[@"a",@NO,@NO],@"2":@[@"b",@NO,@NO]}}});
  Check([other.keyEquivalent isEqual:@"z"],@"Malformed entries do not rewrite unrelated keys");
  Check([completion.keyEquivalent isEqual:@"a"] && [other.keyEquivalent isEqual:@"z"],@"Every child dictionary entry is processed; the former Marks position stays inert");
 }
 // Source › Show Status Bar is new in 6.00, right after Show Line Numbers: positions saved before skip it.
 {
  TSLegacyMenuHadFindAndReplace=1;
  NSMenu *main=[NSMenu new];NSMenuItem *source=Item(main,@"Source");source.submenu=[NSMenu new];
  NSMenuItem *numbers=Item(source.submenu,@"Show Line Numbers");numbers.identifier=@"TSShortcut.showHideLineNumbers:.0";
  NSMenuItem *bar=Item(source.submenu,@"Show Status Bar");bar.identifier=@"TSShortcut.toggleStatusBar:.0";
  NSMenuItem *syntax=Item(source.submenu,@"Show Syntax Color");
  Apply(main,@{@"1":@{@"1":@[@"1",@NO,@YES],@"2":@[@"2",@NO,@YES]}});
  Check([numbers.keyEquivalent isEqual:@"1"] && [syntax.keyEquivalent isEqual:@"2"] && [bar.keyEquivalent isEqual:@""],@"positions skip Show Status Bar, added in 6.00");
  Apply(main,@{@"Source":@{@"Show Status Bar":@[@"b",@NO,@YES]}});
  Check([bar.keyEquivalent isEqual:@"b"],@"the title reaches Show Status Bar");
 }
 // Edit › Find: only the English menu had Find and Replace… before 6.00. Positions saved for another language's menu
 // skip it, which that menu now has after Find…; the English positions count it, as before. Titles reach it in both.
 for(NSNumber *english in @[@YES,@NO]){
  NSMenu *main=[NSMenu new];NSMenuItem *edit=Item(main,@"Edit");edit.submenu=[NSMenu new];
  NSMenuItem *findItem=Item(edit.submenu,@"Find");findItem.submenu=[NSMenu new];
  NSMenuItem *find=Item(findItem.submenu,@"Find…");NSMenuItem *replace=Item(findItem.submenu,@"Find and Replace…");replace.identifier=@"TSShortcut.performTextFinderAction:.12";
  NSMenuItem *next=Item(findItem.submenu,@"Find Next");NSMenuItem *previous=Item(findItem.submenu,@"Find Previous");
  TSLegacyMenuHadFindAndReplace=english.intValue;
  Apply(main,@{@"Edit":@{@"Find":@{@"2":@[@"n",@NO,@YES],@"3":@[@"p",@NO,@YES],@"1":@[@"f",@NO,@YES]}}});
  NSString *language=english.boolValue?@"English":@"another language";
  Check([find.keyEquivalent isEqual:@"f"],[NSString stringWithFormat:@"%@: position 1 is Find…",language]);
  if(english.boolValue) Check([replace.keyEquivalent isEqual:@"n"] && [next.keyEquivalent isEqual:@"p"] && [previous.keyEquivalent isEqual:@""],@"English: positions count Find and Replace…, as in 5.58");
  else Check([next.keyEquivalent isEqual:@"n"] && [previous.keyEquivalent isEqual:@"p"] && [replace.keyEquivalent isEqual:@""],@"another language: positions skip the Find and Replace… added in 6.00");
  replace.keyEquivalent=@"";
  Apply(main,@{@"2":@{@"1":@{@"Find and Replace…":@[@"r",@NO,@YES]}}});
  Check([replace.keyEquivalent isEqual:@""],[NSString stringWithFormat:@"%@: a missing top-level position changes nothing",language]);
  Apply(main,@{@"Edit":@{@"Find":@{@"Find and Replace…":@[@"r",@NO,@YES]}}});
  Check([replace.keyEquivalent isEqual:@"r"],[NSString stringWithFormat:@"%@: the title reaches Find and Replace…",language]);
 }
 TSLegacyMenuHadFindAndReplace=1;
 Check(TSLegacyMenuPathHadFindAndReplace(@"/Applications/TeXShop.app/Contents/Resources/Base.lproj/MainMenu.nib") && TSLegacyMenuPathHadFindAndReplace(nil)
       && !TSLegacyMenuPathHadFindAndReplace(@"/Applications/TeXShop.app/Contents/Resources/ja.lproj/MainMenu.nib")
       && !TSLegacyMenuPathHadFindAndReplace(@"/Applications/TeXShop.app/Contents/Resources/pt-PT.lproj/MainMenu.nib"),
       @"the Base menu had Find and Replace… before 6.00, the other languages' menus did not");
 // Source › Command Completion was a submenu whose first item was Add Word. It is now
 // the command itself, Add to Command Completion List, at the same position.
 NSDictionary *completions=fixture[@"command_completion"];
 Check(completions.count==12,@"Former Command Completion titles for 12 languages");
 for(NSString *language in completions){
  NSString *former=completions[language][0];NSArray *words=completions[language][1];
  NSMenu *main=[NSMenu new];NSMenuItem *source=Item(main,@"Source");source.submenu=[NSMenu new];
  NSMenuItem *bindings=Item(source.submenu,@"Key Bindings");bindings.identifier=@"TSShortcut.changeAutoComplete:.0";
  NSMenuItem *completion=Item(source.submenu,@"Add to Command Completion List");completion.identifier=@"TSShortcut.registerForCommandCompletion:.0";
  NSMenuItem *wrap=Item(source.submenu,@"Wrap Lines");wrap.submenu=[NSMenu new];NSMenuItem *none=Item(wrap.submenu,@"None");
  void (^reset)(void)=^{for(NSMenuItem *item in @[bindings,completion,none])item.keyEquivalent=@"";};
  for(NSString *parent in @[former,@"2"])for(NSString *child in [words arrayByAddingObject:@"1"]){
   reset();Apply(main,@{@"Source":@{parent:@{child:@[@"w",@YES,@YES]}}});
   NSEventModifierFlags mask=completion.keyEquivalentModifierMask;
   Check([completion.keyEquivalent isEqual:@"w"] && (mask & NSEventModifierFlagOption) && (mask & NSEventModifierFlagControl) && [bindings.keyEquivalent isEqual:@""] && [none.keyEquivalent isEqual:@""],[NSString stringWithFormat:@"%@: Source › %@ › %@ reaches Add to Command Completion List",language,parent,child]);
  }
  reset();Apply(main,@{@"1":@{former:@{@"2":@{@"1":@[@"m",@NO,@NO]},@"3":@[@"e",@NO,@NO],@"Marks":@[@"m",@NO,@NO],@"Edit Command Completion File...":@[@"e",@NO,@NO]}}});
  Check([completion.keyEquivalent isEqual:@""] && [bindings.keyEquivalent isEqual:@""] && [none.keyEquivalent isEqual:@""],[NSString stringWithFormat:@"%@: the other former Command Completion items stay inert",language]);
  reset();Apply(main,@{@"Source":@{@"Add to Command Completion List":@[@"j",@NO,@YES],@"Wrap Lines":@{@"1":@[@"n",@NO,@NO]}}});
  Check([completion.keyEquivalent isEqual:@"j"] && [none.keyEquivalent isEqual:@"n"],@"The current title and the submenu after it still apply");
  reset();Apply(main,@{@"Source":@{@"Wrap Lines":@{former:@[@"x",@NO,@NO]}}});
  Check([completion.keyEquivalent isEqual:@""] && [none.keyEquivalent isEqual:@""],@"A former title only names the item in the Source menu");
 }
 // Japanese and Chinese titles lost the space between CJK and Latin text in 5.60.
 {
  NSMenu *main=[NSMenu new];NSMenuItem *appTop=Item(main,@"TeXShop");appTop.submenu=[NSMenu new];
  NSMenuItem *hide=Item(appTop.submenu,@"TeXShopを隠す");NSMenuItem *engine=Item(appTop.submenu,@"TeX引擎");
  NSMenuItem *korean=Item(appTop.submenu,@"Safari종료");NSMenuItem *exact=Item(appTop.submenu,@"LaTeX パネル");NSMenuItem *joined=Item(appTop.submenu,@"LaTeXパネル");
  Apply(main,@{@"TeXShop":@{@"TeXShop を隠す":@[@"h",@NO,@NO],@"TeX 引擎":@[@"e",@NO,@NO],@"Safari 종료":@[@"q",@NO,@NO],@"LaTeX パネル":@[@"l",@NO,@NO]}});
  Check([hide.keyEquivalent isEqual:@"h"] && [engine.keyEquivalent isEqual:@"e"],@"Titles saved with a space between CJK and Latin text reach the current titles");
  Check([korean.keyEquivalent isEqual:@""],@"Korean word spacing is not ignored");
  Check([exact.keyEquivalent isEqual:@"l"] && [joined.keyEquivalent isEqual:@""],@"An exact title match wins over a spacing match");
 }
 // Open Style File moved from Help (after Show Help for Package) to File (after Open).
 // Legacy entries name or number the items as they were before the move.
 for(NSNumber *numericMenus in @[@NO,@YES]){
  NSMenu *main=[NSMenu new];
  NSMenuItem *fileTop=Item(main,@"File");fileTop.submenu=[NSMenu new];NSMenu *file=fileTop.submenu;
  Item(file,@"New");Item(file,@"New from Stationery...");NSMenuItem *open=Item(file,@"Open...");open.identifier=@"TSShortcut.openDocument:.0";
  NSMenuItem *style=Item(file,@"Open Style File...");style.identifier=@"TSShortcut.displayStyleFile:.0";
  Item(file,@"Open Recent");Item(file,@"Open for Preview...");[file addItem:NSMenuItem.separatorItem];
  NSMenuItem *close=Item(file,@"Close");NSMenuItem *save=Item(file,@"Save");
  NSMenuItem *helpTop=Item(main,@"Help");helpTop.submenu=[NSMenu new];NSMenu *help=helpTop.submenu;
  Item(help,@"TeXShop Help");[help addItem:NSMenuItem.separatorItem];Item(help,@"TeX Live Documentation");
  NSMenuItem *package=Item(help,@"Show Help for Package...");package.identifier=@"TSShortcut.displayHelpForPackage:.0";
  NSMenuItem *helpSeparator=NSMenuItem.separatorItem;[help addItem:helpSeparator];NSMenuItem *first=Item(help,@"First Steps with TeXShop");
  NSString *fileKey=numericMenus.boolValue?@"1":@"File",*helpKey=numericMenus.boolValue?@"2":@"Help";
  void (^reset)(void)=^{for(NSMenuItem *item in @[style,close,save,package,first,helpSeparator]){item.keyEquivalent=@"";}};
  reset();Apply(main,@{helpKey:@{@"Open Style File...":@[@"j",@NO,@NO]}});
  Check([style.keyEquivalent isEqual:@"j"],@"Former Help path by name reaches the moved Open Style File");
  reset();Apply(main,@{helpKey:@{@"5":@[@"j",@NO,@NO]}});
  Check([style.keyEquivalent isEqual:@"j"] && [first.keyEquivalent isEqual:@""] && [helpSeparator.keyEquivalent isEqual:@""],@"Former Help position of Open Style File reaches it, not the separator");
  reset();Apply(main,@{helpKey:@{@"7":@[@"k",@NO,@NO]}});
  Check([first.keyEquivalent isEqual:@"k"],@"Help items after the former position keep their former numbers");
  reset();Apply(main,@{fileKey:@{@"8":@[@"j",@NO,@NO],@"4":@[@"r",@NO,@NO]}});
  Check([save.keyEquivalent isEqual:@"j"] && [close.keyEquivalent isEqual:@""] && [style.keyEquivalent isEqual:@""],@"File positions after Open keep their former numbers instead of shifting to Close");
  reset();Apply(main,@{fileKey:@{@"Open Style File...":@[@"j",@NO,@NO],@"Save":@[@"s",@NO,@NO]}});
  Check([style.keyEquivalent isEqual:@"j"] && [save.keyEquivalent isEqual:@"s"],@"Names in the current File menu still apply");
 }
 // The typesetting methods in the Typeset menu were renamed Direct PDF and Via DVI.
 // Entries naming them by a former title in any language still reach them.
 NSDictionary *methods=fixture[@"typeset_methods"];
 Check(methods.count==12,@"Former typesetting method titles for 12 languages");
 for(NSString *language in methods){
  NSArray *former=methods[language];
  NSMenu *main=[NSMenu new];NSMenuItem *typesetTop=Item(main,@"Typeset");typesetTop.submenu=[NSMenu new];NSMenu *typeset=typesetTop.submenu;
  Item(typeset,@"Typeset");NSMenuItem *pdf=Item(typeset,@"Direct PDF");pdf.identifier=@"TSShortcut.doChooseMethod:.100";
  NSMenuItem *dvi=Item(typeset,@"Via DVI");dvi.identifier=@"TSShortcut.doChooseMethod:.101";
  NSMenuItem *personal=Item(typeset,@"Personal Script");personal.identifier=@"TSShortcut.doChooseMethod:.102";
  Apply(main,@{@"Typeset":@{former[0]:@[@"1",@NO,@YES],former[1]:@[@"2",@YES,@NO]}});
  Check([pdf.keyEquivalent isEqual:@"1"] && (pdf.keyEquivalentModifierMask & NSEventModifierFlagControl) && [dvi.keyEquivalent isEqual:@"2"] && (dvi.keyEquivalentModifierMask & NSEventModifierFlagOption) && [personal.keyEquivalent isEqual:@""],[NSString stringWithFormat:@"Former %@ titles reach Direct PDF and Via DVI",language]);
  for(NSMenuItem *item in @[pdf,dvi,personal])item.keyEquivalent=@"";
  Apply(main,@{@"Typeset":@{@"Direct PDF":@[@"3",@NO,@NO],@"4":@[@"4",@NO,@NO]}});
  Check([pdf.keyEquivalent isEqual:@"3"] && [personal.keyEquivalent isEqual:@"4"] && [dvi.keyEquivalent isEqual:@""],@"Current titles and positions still apply");
 }
 {
  NSMenu *main=[NSMenu new];NSMenuItem *typesetTop=Item(main,@"Typeset");typesetTop.submenu=[NSMenu new];
  NSMenuItem *dvi=Item(typesetTop.submenu,@"DVI経由");dvi.identifier=@"TSShortcut.doChooseMethod:.101";
  Apply(main,@{@"Typeset":@{@"TeX和DVI":@[@"5",@NO,@NO]}});
  Check([dvi.keyEquivalent isEqual:@"5"],@"A former title reaches its item with or without the space between CJK and Latin text");
 }
 // Titles that had a stray space at the start or end lost it in 6.00. Entries saved with
 // the former title, in the menus as they are now in each language, still reach the item.
 NSArray *stray=fixture[@"stray_spaces"];
 Check(stray.count==18,@"18 former titles with a stray space");
 NSUInteger reached=0;
 for(NSDictionary *entry in stray){
  NSArray<NSString *> *former=entry[@"former"],*current=entry[@"current"];
  NSString *where=[NSString stringWithFormat:@"%@: %@",entry[@"language"],[former componentsJoinedByString:@" › "]];
  Check(former.count==current.count && ![former isEqual:current],where);
  for(NSUInteger i=0;i<former.count;i++)Check([TSLegacyComparableTitle(former[i]) isEqualToString:TSLegacyComparableTitle(current[i])],[where stringByAppendingString:@": former and current titles compare equal"]);
  if(former.count>3)continue; // KeyEquivalents.plist reaches three levels at most
  NSMenu *main=[NSMenu new];NSMenu *menu=main;NSMenuItem *leaf=nil;NSMutableArray<NSMenuItem *> *decoys=[NSMutableArray array];
  for(NSString *title in current){
   if(menu!=main)[decoys addObject:Item(menu,[title stringByAppendingString:@" 2"])];
   leaf=Item(menu,title);
   if(title!=current.lastObject){leaf.submenu=[NSMenu new];menu=leaf.submenu;}
  }
  NSArray *key=@[@"y",@YES,@NO];id entries=key;
  for(NSInteger i=(NSInteger)former.count-1;i>=1;i--)entries=@{former[i]:entries};
  Apply(main,@{former[0]:entries});
  Check([leaf.keyEquivalent isEqual:@"y"] && (leaf.keyEquivalentModifierMask & NSEventModifierFlagOption),[where stringByAppendingString:@": the former title reaches the item"]);
  for(NSMenuItem *decoy in decoys)Check([decoy.keyEquivalent isEqual:@""],[where stringByAppendingString:@": no other item is reached"]);
  reached++;
 }
 Check(reached==17,@"17 of the former titles are within the three levels KeyEquivalents.plist reaches");
 {
  NSMenu *main=[NSMenu new];NSMenuItem *top=Item(main,@"Window");top.submenu=[NSMenu new];
  NSMenuItem *spaced=Item(top.submenu,@" Switch Views");NSMenuItem *plain=Item(top.submenu,@"Switch Views");
  NSMenuItem *korean=Item(top.submenu,@"보기 전환");[top.submenu addItem:NSMenuItem.separatorItem];NSMenuItem *separator=top.submenu.itemArray.lastObject;
  Apply(main,@{@"Window":@{@" Switch Views":@[@"1",@NO,@NO],@"보기전환":@[@"2",@NO,@NO],@" ":@[@"3",@NO,@NO]}});
  Check([spaced.keyEquivalent isEqual:@"1"] && [plain.keyEquivalent isEqual:@""],@"An exact title match wins over a match without the stray space");
  Check([korean.keyEquivalent isEqual:@""],@"A space inside a Korean title still matters");
  Check([separator.keyEquivalent isEqual:@""],@"A title of spaces alone names no item");
  Apply(main,@{@"Window":@{@" 보기  전환":@[@"4",@NO,@NO]}});
  Check([korean.keyEquivalent isEqual:@"4"],@"A doubled space inside a former title compares as one");
 }
 // Command completion and the mark keys own Tab and Escape: as in recording, a saved key never takes them,
 // another control character or Delete. The item keeps its key; other saved keys still apply.
 {
  NSMenu *main=[NSMenu new];NSMenuItem *file=Item(main,@"File");file.submenu=[NSMenu new];
  NSMenuItem *open=Item(file.submenu,@"Open…");open.keyEquivalent=@"o";
  for(NSString *k in @[@"\t",@"\x19",@"\x1b",@"\x7f",@"\x03"])for(NSNumber *option in @[@NO,@YES])for(NSNumber *control in @[@NO,@YES]){
   Apply(main,@{@"File":@{@"Open…":@[k,option,control]}});
   Check([open.keyEquivalent isEqual:@"o"] && open.keyEquivalentModifierMask==NSEventModifierFlagCommand,@"a saved Tab, Escape, control character or Delete is not applied");
  }
  Apply(main,@{@"File":@{@"Open…":@[@"p",@NO,@YES]}});
  Check([open.keyEquivalent isEqual:@"p"] && (open.keyEquivalentModifierMask & NSEventModifierFlagControl),@"an ordinary saved key still applies");
  NSString *f5=[NSString stringWithFormat:@"%C",(unichar)NSF5FunctionKey];
  Apply(main,@{@"File":@{@"Open…":@[f5,@NO,@NO]}});Check([open.keyEquivalent isEqual:f5],@"a saved function key still applies");
  Apply(main,@{@"File":@{@"Open…":@[@"",@NO,@NO]}});Check(open.keyEquivalent.length==0,@"a saved empty key still removes the shortcut");
  puts("PASS: saved Tab, Escape, control characters and Delete are not applied; ordinary keys, function keys and removal still are");
 }
 // Positions in the Edit menu were saved for the menu of 5.58: the items 6.00 added there (Copy with Style, Swap with
 // Clipboard, Character Type Conversion, Unicode Normalization, Marks) are skipped, in every language, so that each
 // position still reaches the command it named. argv[2] holds, per language, the compiled menu of now and the actions
 // of the 5.58 Edit menu (the first action of a submenu), position by position.
 if(argc>2){
  NSDictionary *edits=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[2])] options:0 error:nil];
  for(NSString *language in edits){
   NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:edits[language][@"nib"]] bundle:nil];NSArray *objects=nil;
   Check([nib instantiateWithOwner:NSApp topLevelObjects:&objects],language);
   NSMenu *main=nil;for(id o in objects)if([o isKindOfClass:NSMenu.class]&&[o numberOfItems]>5)main=o;
   NSMenu *edit=nil;for(NSMenuItem *top in main.itemArray)for(NSMenuItem *i in top.submenu.itemArray)if(i.action==@selector(undo:))edit=top.submenu;
   NSArray *old=edits[language][@"actions"];
   for(NSUInteger i=0;i<old.count;i++){
    if([old[i] length]==0)continue;
    NSMenuItem *item=TSLegacyMenuItem(edit,[NSString stringWithFormat:@"%lu",(unsigned long)i+1]);
    // A submenu counts by its items, which may have gained some (Change Encoding joined Transformations).
    NSString *action=NSStringFromSelector(item.action);
    for(NSMenuItem *child in item.submenu.itemArray)if([NSStringFromSelector(child.action) isEqual:old[i]])action=old[i];
    Check([action isEqual:old[i]],[NSString stringWithFormat:@"%@: Edit position %lu reaches %@, not %@",language,(unsigned long)i+1,action,old[i]]);
   }
  }
  printf("PASS: Edit menu positions of 5.58 reach the same commands in %lu languages\n",(unsigned long)edits.count);
  // Fullscreen (Old Method) is gone (6.00). A KeyEquivalents.plist that names it by its name of 5.58 or of 6.00 beta 8
  // gives its key to no item of the Window menu, in the compiled menu of every language.
  for(NSString *language in edits){
   NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:edits[language][@"nib"]] bundle:nil];NSArray *objects=nil;
   Check([nib instantiateWithOwner:NSApp topLevelObjects:&objects],language);
   NSMenu *main=nil;for(id o in objects)if([o isKindOfClass:NSMenu.class]&&[o numberOfItems]>5)main=o;
   NSMenuItem *window=nil;
   for(NSMenuItem *top in main.itemArray)for(NSMenuItem *i in top.submenu.itemArray){
    if(i.action==@selector(toggleFullScreen:))window=top;
    Check(i.action!=NSSelectorFromString(@"fullscreen:"),[language stringByAppendingString:@": Fullscreen (Old Method) is not in the menu"]);
   }
   Check(window!=nil,[language stringByAppendingString:@": the Window menu is found"]);
   for(NSString *title in @[edits[language][@"fullscreen"],edits[language][@"fullscreen600b8"]]){
    for(NSMenuItem *i in window.submenu.itemArray){i.keyEquivalent=@"";}
    Apply(main,@{window.title:@{title:@[@"9",@YES,@YES]}});
    for(NSMenuItem *i in window.submenu.itemArray)Check([i.keyEquivalent isEqual:@""],[NSString stringWithFormat:@"%@: the former name %@ reaches no item (%@ got it)",language,title,i.title]);
   }
  }
  printf("PASS: a saved key for Fullscreen (Old Method), by its name of 5.58 or of 6.00 beta 8, reaches no item in %lu languages\n",(unsigned long)edits.count);
  NSUInteger checkedWindows=0;
  // Positions saved for the Window menu of 5.58 keep a place for Fullscreen (Old Method): its own position reaches no item
  // of the menu, and the items after it are reached at their former positions.
  for(NSString *language in edits){
   NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:edits[language][@"nib"]] bundle:nil];NSArray *objects=nil;
   Check([nib instantiateWithOwner:NSApp topLevelObjects:&objects],language);
   NSMenu *main=nil;for(id o in objects)if([o isKindOfClass:NSMenu.class]&&[o numberOfItems]>5)main=o;
   NSMenu *window=nil;for(NSMenuItem *top in main.itemArray)for(NSMenuItem *i in top.submenu.itemArray)if(i.action==@selector(toggleFullScreen:))window=top.submenu;
   NSArray *old=edits[language][@"window"];NSUInteger reached=0;
   // A menu that dropped one of these items on purpose (TetsuTeXShop has no Minimize in English and Japanese) has its
   // positions moved anyway; it is left out.
   BOOL complete=YES;
   for(NSUInteger i=0;i<MIN(old.count,(NSUInteger)5);i++)
    if([old[i] length]>0 && ![old[i] isEqual:@"fullscreen:"] && [window indexOfItemWithTarget:nil andAction:NSSelectorFromString(old[i])]<0)complete=NO;
   if(!complete){printf("SKIP: %s: the Window menu lacks one of its first items of 5.58\n",language.UTF8String);continue;}
   checkedWindows++;
   // The first five items: Minimize, Zoom, Fullscreen (Old Method), Enter Full Screen and Arrange in Front (later items changed for other reasons).
   for(NSUInteger i=0;i<MIN(old.count,(NSUInteger)5);i++){
    if([old[i] length]==0)continue;
    NSMenuItem *item=TSLegacyMenuItem(window,[NSString stringWithFormat:@"%lu",(unsigned long)i+1]);
    if([old[i] isEqual:@"fullscreen:"]){
     Check(item==nil || [window indexOfItem:item]<0,[NSString stringWithFormat:@"%@: Window position %lu (Fullscreen (Old Method)) reaches no item, not %@",language,(unsigned long)i+1,item.title]);
     continue;
    }
    Check([NSStringFromSelector(item.action) isEqual:old[i]],[NSString stringWithFormat:@"%@: Window position %lu reaches %@, not %@",language,(unsigned long)i+1,NSStringFromSelector(item.action),old[i]]);
    reached++;
   }
   Check(reached>=4,[language stringByAppendingString:@": Window positions after Fullscreen (Old Method) are checked"]);
  }
  Check(checkedWindows>=10,@"Window menu positions are checked in most languages");
  printf("PASS: Window menu positions of 5.58 keep the place of Fullscreen (Old Method) in %lu languages\n",(unsigned long)checkedWindows);
 }
 puts("PASS: Show Status Bar skipped in positions; Find and Replace… skipped in positions of the menus that lacked it; 12 legacy title fixtures; CJK-Latin spacing; 18 former titles with a stray space; numeric/named migration, removed entries, bounds and sibling assignments; Open Style File moved from Help to File; former typesetting method titles in 12 languages; Command Completion submenu entries in 12 languages reach Add to Command Completion List");
}return 0;}
