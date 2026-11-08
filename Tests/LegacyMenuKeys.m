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
  }
  Apply(main,@{@"1":@{@"2":@{@"3":@[@"e",@NO,@NO]},@"3":@[@"z",@NO,@YES]},@"999":@{},@"-2":@{}});
  Check([other.keyEquivalent isEqual:@"z"] && (other.keyEquivalentModifierMask & NSEventModifierFlagControl),@"Removed completion or invalid menu does not interrupt other assignments");
  if(!old.boolValue){Check([toggle.keyEquivalent isEqual:@"k"],@"Removed editor never targets toggle");Apply(main,@{@"1":@{@"1":@{@"2":@[@"e",@NO,@NO],@"Edit Key Bindings File…":@[@"e",@NO,@NO]}}});Check([toggle.keyEquivalent isEqual:@"k"],@"Removed editor compatibility entries stay inert");}
  Apply(main,@{@"1":@{@"3":@[],@"999":@[@"x",@NO,@NO],@"-1":@[@"x",@NO,@NO],@"2":@{@"999":@[@"x",@NO,@NO],@"1":@[@"a",@NO,@NO],@"2":@[@"b",@NO,@NO]}}});
  Check([other.keyEquivalent isEqual:@"z"],@"Malformed entries do not rewrite unrelated keys");
  Check([[completion.submenu itemAtIndex:0].keyEquivalent isEqual:@"a"] && [[completion.submenu itemAtIndex:1].keyEquivalent isEqual:@"b"],@"Every child dictionary entry is processed");
 }
 puts("PASS: 12 legacy title fixtures; numeric/named migration, removed entries, bounds and sibling assignments");
}return 0;}
