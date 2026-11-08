// SPDX-License-Identifier: GPL-2.0-or-later
#import "TestAppKitIsolation.h"
#import "TSKeyboardShortcuts.m"
#import "TSSettingsSearch.h"
static void Check(BOOL value,NSString *message){if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
#include "SettingsSearchCoverage.inc"
static void IgnoreOutlet(id receiver,SEL selector,id value,NSString *key) {}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 for(NSString *name in @[@"HelpDocuments",@"TSAppDelegate",@"TSAutoCompletionListEditor",@"TSDocumentController",@"TSMacroEditor",@"TSMacroMenuController",@"TSMovie",@"TSPreferences",@"TSSparkleController",@"TSStationery",@"TextFinder"]){
  Class c=objc_allocateClassPair(NSObject.class,name.UTF8String,0);class_addMethod(c,@selector(setValue:forUndefinedKey:),(IMP)IgnoreOutlet,"v@:@@");objc_registerClassPair(c);
 }
 NSArray *objects=nil;NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:@(argv[1])] bundle:nil];Check([nib instantiateWithOwner:NSApp topLevelObjects:&objects],@"Compiled menu loads");
 TSShortcutStore *store=[[TSShortcutStore alloc]initWithMenu:NSApp.mainMenu defaults:TSIsolatedAppKitDefaults];
 NSArray *names=[store settingsSearchCommandNames];NSMutableDictionary *bindings=[NSMutableDictionary dictionary];
 for(TSShortcutCommand *command in store.commands)if(!command.item.hidden || command.item.allowsKeyEquivalentWhenHidden){bindings[command.commandID]=@[command.item.keyEquivalent,@(command.item.keyEquivalentModifierMask)];}
 Check(names.count>150,@"Real localized command model");
 TSShortcutCommand *visibilityCommand=store.commands.firstObject;
 BOOL wasHidden=visibilityCommand.item.hidden, wasAllowed=visibilityCommand.item.allowsKeyEquivalentWhenHidden;
 visibilityCommand.item.hidden=YES; visibilityCommand.item.allowsKeyEquivalentWhenHidden=NO;
 Check(![[store settingsSearchCommandNames] containsObject:visibilityCommand.path],@"Production provider excludes hidden commands");
 visibilityCommand.item.allowsKeyEquivalentWhenHidden=YES;
 Check([[store settingsSearchCommandNames] containsObject:visibilityCommand.path],@"Production provider includes explicitly allowed hidden commands");
 visibilityCommand.item.hidden=wasHidden; visibilityCommand.item.allowsKeyEquivalentWhenHidden=wasAllowed;
 TSSettingsSearch *index=[[TSSettingsSearch alloc]initWithBundle:NSBundle.mainBundle categoryOrder:@[@"keyboard"] commandNames:names];
 for(NSString *name in names)CheckSearchText(index,name,@"keyboard");
 TSKeyboardShortcuts *coordinator=[TSKeyboardShortcuts new];coordinator.store=store;
 TSShortcutPaneController *pane=[[TSShortcutPaneController alloc]initWithShortcuts:coordinator];(void)pane.view;
 for(TSShortcutCommand *command in store.commands){
  if(command.item.hidden && !command.item.allowsKeyEquivalentWhenHidden)continue;
  [pane applySettingsQuery:command.path.uppercaseString targets:@[] filterCommands:YES];
  Check([pane.visibleCommands containsObject:command],@"Actual function list uses same normalized query");
  Check([bindings[command.commandID] isEqual:@[command.item.keyEquivalent,@(command.item.keyEquivalentModifierMask)]],@"Searching never changes raw keys");
 }
 for(NSWindow *window in NSApp.windows)Check(!window.visible,@"No window shown");
 printf("PASS %s: %lu commands, %lu query variants, raw bindings unchanged\n",argv[1],(unsigned long)names.count,(unsigned long)searchChecks);
}return 0;}
