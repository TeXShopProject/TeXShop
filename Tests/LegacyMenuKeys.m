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
 puts("PASS: Find and Replace… skipped in positions of the menus that lacked it; 12 legacy title fixtures; CJK-Latin spacing; numeric/named migration, removed entries, bounds and sibling assignments; Open Style File moved from Help to File; former typesetting method titles in 12 languages; Command Completion submenu entries in 12 languages reach Add to Command Completion List");
}return 0;}
