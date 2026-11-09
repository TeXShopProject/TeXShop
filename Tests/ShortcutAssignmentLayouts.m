// SPDX-License-Identifier: GPL-2.0-or-later
// Start from fixed assignments, invert each installed layout to physical events.
// No recorder output or hidden NSMenu dispatch serves as the expected answer.
#import "TSKeyboardShortcuts.m"
#import "TestAppKitIsolation.h"
static NSString *unshifted;
static NSString *Characters(id object,SEL selector,NSEventModifierFlags flags){return unshifted;}
static NSString *Translate(CFDataRef data,UInt16 code,UInt32 modifiers,UInt32 keyboard){
 UniChar chars[8];UniCharCount count=0;UInt32 dead=0;
 OSStatus status=UCKeyTranslate((const UCKeyboardLayout *)CFDataGetBytePtr(data),code,kUCKeyActionDown,modifiers,keyboard,kUCKeyTranslateNoDeadKeysBit,&dead,8,&count,chars);
 return status==noErr?[NSString stringWithCharacters:chars length:count]:@"";
}
int main(void){@autoreleasepool{
 TSInstallAppKitIsolation();TSReplaceTestMethod(class_getInstanceMethod(NSEvent.class,@selector(charactersByApplyingModifiers:)),(IMP)Characters);
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 const NSUInteger C=NSEventModifierFlagCommand,S=NSEventModifierFlagShift,O=NSEventModifierFlagOption,K=NSEventModifierFlagControl;
 NSArray<NSString *> *keys=@[@"a",@"b",@"c",@"g",@"z",@"9",@"0",@"(",@")",@"[",@"]",@"\\",@";"];
 NSArray<NSNumber *> *flags=@[@(C),@(C|S),@(C|O),@(C|K),@(C|S|O),@(C|S|K)];
 CFArrayRef sources=TISCreateInputSourceList((__bridge CFDictionaryRef)@{(__bridge NSString *)kTISPropertyInputSourceType:(__bridge NSString *)kTISTypeKeyboardLayout},true);
 NSMutableSet<NSString *> *seen=[NSMutableSet set];NSUInteger menuChecks=0,macroChecks=0,unavailable=0;
 for(CFIndex i=0;i<CFArrayGetCount(sources);i++){
  TISInputSourceRef source=(TISInputSourceRef)CFArrayGetValueAtIndex(sources,i);CFDataRef data=TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData);
  NSString *name=(__bridge NSString *)TISGetInputSourceProperty(source,kTISPropertyInputSourceID);
  if(!data || [seen containsObject:name])continue;[seen addObject:name];
  for(NSNumber *keyboard in @[@40,@41,@48])for(NSString *key in keys)for(NSNumber *flag in flags){@autoreleasepool{
   NSUInteger f=flag.unsignedIntegerValue;BOOL produced=NO;
   NSMenu *menu=[NSMenu new];NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:@"Fixed assignment" action:@selector(description) keyEquivalent:key];item.keyEquivalentModifierMask=f;item.allowsAutomaticKeyEquivalentLocalization=NO;[menu addItem:item];
   TSShortcutStore *store=[[TSShortcutStore alloc]initWithMenu:menu defaults:TSIsolatedAppKitDefaults];
   TSShortcutMacro *macro=[[TSShortcutMacro alloc]initWithName:@"Fixed macro" path:@"Macros/Fixed" indexPath:[NSIndexPath indexPathWithIndex:0] serializedKey:@"fixture" key:key modifiers:f];
   for(UInt16 code=0;code<128;code++){
    NSString *base=Translate(data,code,0,keyboard.unsignedIntValue),*ign=Translate(data,code,(f&S)?shiftKey>>8:0,keyboard.unsignedIntValue);
    UInt32 cm=cmdKey|((f&S)?shiftKey:0)|((f&O)?optionKey:0)|((f&K)?controlKey:0);
    NSString *chars=Translate(data,code,cm>>8,keyboard.unsignedIntValue);
    // Invert the documented Command layer for letters (including Dvorak-QWERTY).
    // For Option/Control, use the ordinary glyph instead of the produced symbol.
    BOOL commandLetter=!(f&(O|K)) && chars.length==1 && (([chars characterAtIndex:0]>='a' && [chars characterAtIndex:0]<='z') || ([chars characterAtIndex:0]>='A' && [chars characterAtIndex:0]<='Z'));
    if(commandLetter){if(![chars.lowercaseString isEqual:key])continue;}
    else if(![base isEqual:key] && ![ign.lowercaseString isEqual:key])continue;
    // This fixed ASCII fixture excludes IME/fullwidth composition; real JIS results remain authoritative.
    if(ign.length!=1 || chars.length!=1 || [ign characterAtIndex:0]>127)continue;
    produced=YES;unshifted=base;
    NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:f timestamp:0 windowNumber:0 context:nil characters:chars charactersIgnoringModifiers:ign isARepeat:NO keyCode:code];
    item.action=@selector(description);
    NSArray<TSShortcutMatch *> *matches=[TSShortcutSearch matchesEvent:event store:store macros:@[]];BOOL found=NO;
    for(TSShortcutMatch *match in matches)if(match.menuItem==item && match.winner)found=YES;
    if(!found){fprintf(stderr,"FAIL fixed menu %s key=%s flags=%lu code=%u base=%s ign=%s chars=%s\n",name.UTF8String,key.UTF8String,f,code,base.UTF8String,ign.UTF8String,chars.UTF8String);return 1;}menuChecks++;
    item.action=NSSelectorFromString(@"doMacro:");matches=[TSShortcutSearch matchesEvent:event store:store macros:@[macro]];found=NO;
    for(TSShortcutMatch *match in matches)if(match.macro==macro && match.winner)found=YES;
    if(!found){fprintf(stderr,"FAIL fixed macro %s key=%s flags=%lu code=%u base=%s ign=%s chars=%s\n",name.UTF8String,key.UTF8String,f,code,base.UTF8String,ign.UTF8String,chars.UTF8String);return 1;}macroChecks++;
   }
   if(!produced)unavailable++;
  }}
 }
 CFRelease(sources);if(seen.count<262 || !menuChecks || menuChecks!=macroChecks)return 1;
 printf("PASS: assignment-first search layouts=%lu menu=%lu macros=%lu unavailable-layout-assignments=%lu; no actions dispatched\n",(unsigned long)seen.count,(unsigned long)menuChecks,(unsigned long)macroChecks,(unsigned long)unavailable);
}return 0;}
