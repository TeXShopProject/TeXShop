// SPDX-License-Identifier: GPL-2.0-or-later
#import "TestAppKitIsolation.h"
#import "TSKeyboardShortcuts.h"
static void Check(BOOL condition,NSString *reason){if(!condition){fprintf(stderr,"FAIL: %s\n",reason.UTF8String);exit(1);}}
int main(void){@autoreleasepool{
 TSInstallAppKitIsolation();[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 [TSIsolatedAppKitDefaults setObject:@{@"TSShortcut.performFindPanelAction:.2":@{@"key":@"k",@"modifiers":@(NSEventModifierFlagCommand)}} forKey:TSMenuShortcutOverridesKey];
 NSDictionary *before=[TSIsolatedAppKitDefaults dictionaryRepresentation];
 NSMenu *menu=[NSMenu new];NSApp.mainMenu=menu;
 TSKeyboardShortcuts *shortcuts=[TSKeyboardShortcuts new];__block BOOL configured=NO;__block NSUInteger shown=0;
 [shortcuts startAfterLaunchWithConfiguration:^(TSKeyboardShortcuts *controller){configured=YES;controller.showSettings=^{shown++;};controller.macroProvider=^NSArray *{return @[];};}];
 Check(shortcuts.store==nil && !configured,@"Installation waits until all launch observers finish");
 // Model the late Find-menu provider while running the real deferred startup path.
 NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:@"Find Next" action:@selector(performFindPanelAction:) keyEquivalent:@"g"];item.identifier=@"TSShortcut.performFindPanelAction:.2";item.tag=2;item.keyEquivalentModifierMask=NSEventModifierFlagCommand;item.allowsAutomaticKeyEquivalentLocalization=NO;[menu addItem:item];
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];while(!shortcuts.store && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
 Check(configured && shortcuts.store.commands.count==1 && [item.keyEquivalent isEqual:@"k"],@"Launch installs saved shortcut on the final Find menu without opening settings");
 NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:0 context:nil characters:@"k" charactersIgnoringModifiers:@"k" isARepeat:NO keyCode:40];
 Check([TSKeyboardShortcuts event:event matchesAction:@selector(performFindPanelAction:) tag:2],@"Runtime lookup sees the saved assignment immediately after deferred startup");
 [shortcuts showKeyboardShortcuts:nil];Check(shown==1,@"Configuration callbacks survive startup");
 Check([[TSIsolatedAppKitDefaults dictionaryRepresentation] isEqual:before],@"Startup applies assignments without rewriting preferences");
 puts("PASS: actual deferred startup, late Find menu, immediate runtime binding, callbacks, memory-only defaults");
}return 0;}
