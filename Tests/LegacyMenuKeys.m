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
  NSMenuItem *completion=Item(source.submenu,@"Command Completion");completion.submenu=[NSMenu new];Item(completion.submenu,@"Add Word");Item(completion.submenu,@"Marks");
  if(old.boolValue)Item(completion.submenu,@"Edit Command Completion File…");
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
  Check([other.keyEquivalent isEqual:@"z"] && (other.keyEquivalentModifierMask & NSEventModifierFlagControl),@"Removed completion or invalid menu does not interrupt other assignments");
  if(!old.boolValue){Check([toggle.keyEquivalent isEqual:@"k"],@"Removed editor never targets toggle");Apply(main,@{@"1":@{@"1":@{@"2":@[@"e",@NO,@NO],@"Edit Key Bindings File…":@[@"e",@NO,@NO]}}});Check([toggle.keyEquivalent isEqual:@"k"],@"Removed editor compatibility entries stay inert");}
  Apply(main,@{@"1":@{@"3":@[],@"999":@[@"x",@NO,@NO],@"-1":@[@"x",@NO,@NO],@"2":@{@"999":@[@"x",@NO,@NO],@"1":@[@"a",@NO,@NO],@"2":@[@"b",@NO,@NO]}}});
  Check([other.keyEquivalent isEqual:@"z"],@"Malformed entries do not rewrite unrelated keys");
  Check([[completion.submenu itemAtIndex:0].keyEquivalent isEqual:@"a"] && [[completion.submenu itemAtIndex:1].keyEquivalent isEqual:@"b"],@"Every child dictionary entry is processed");
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
 puts("PASS: 12 legacy title fixtures; CJK-Latin spacing; numeric/named migration, removed entries, bounds and sibling assignments; Open Style File moved from Help to File");
}return 0;}
