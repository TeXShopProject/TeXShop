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
static void IgnoreAssignmentOutlet(id receiver,SEL selector,id value,NSString *key) {}
static void CollectAssignmentMenu(NSMenu *menu,NSMutableSet *assignments){for(NSMenuItem *item in menu.itemArray){if(item.submenu)CollectAssignmentMenu(item.submenu,assignments);else if(item.keyEquivalent.length)[assignments addObject:@[item.keyEquivalent,@(item.keyEquivalentModifierMask & (NSEventModifierFlagCommand|NSEventModifierFlagShift|NSEventModifierFlagOption|NSEventModifierFlagControl))]];}}
static void CollectAssignmentMacros(NSDictionary *node,NSMutableSet *assignments){
    NSString *serialized=node[@"key"];
    if(serialized.length){NSArray *parts=[serialized componentsSeparatedByString:@"+"];NSString *key=parts.firstObject;NSUInteger flags=NSEventModifierFlagCommand;
        if([parts containsObject:@"ShiftKey"])flags|=NSEventModifierFlagShift;
        if([parts containsObject:@"OptionKey"])flags|=NSEventModifierFlagOption;
        if([parts containsObject:@"ControlKey"])flags|=NSEventModifierFlagControl;
        if(key.length)[assignments addObject:@[key,@(flags)]];
    }
    for(NSDictionary *child in node[@"submenu"])CollectAssignmentMacros(child,assignments);
}
int main(int argc,char **argv){@autoreleasepool{
 TSInstallAppKitIsolation();TSReplaceTestMethod(class_getInstanceMethod(NSEvent.class,@selector(charactersByApplyingModifiers:)),(IMP)Characters);
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
 const NSUInteger C=NSEventModifierFlagCommand,S=NSEventModifierFlagShift,O=NSEventModifierFlagOption,K=NSEventModifierFlagControl;
 NSMutableSet *raw=[NSMutableSet set];
 for(NSString *name in @[@"HelpDocuments",@"TSAppDelegate",@"TSAutoCompletionListEditor",@"TSDocumentController",@"TSMacroEditor",@"TSMacroMenuController",@"TSMovie",@"TSPreferences",@"TSSparkleController",@"TSStationery",@"TextFinder"]){Class c=objc_allocateClassPair(NSObject.class,name.UTF8String,0);if(c){class_addMethod(c,@selector(setValue:forUndefinedKey:),(IMP)IgnoreAssignmentOutlet,"v@:@@");objc_registerClassPair(c);}}
 for(int n=1;n<argc;n++){
  NSString *path=@(argv[n]);
  if([path.pathExtension isEqual:@"plist"])CollectAssignmentMacros([NSDictionary dictionaryWithContentsOfFile:path],raw);
  else{NSArray *objects=nil;NSNib *nib=[[NSNib alloc]initWithNibData:[NSData dataWithContentsOfFile:path] bundle:nil];if(![nib instantiateWithOwner:NSApp topLevelObjects:&objects])return 2;CollectAssignmentMenu(NSApp.mainMenu,raw);}
 }
 if(raw.count<50)return 2;
 // Additional negative/shift-punctuation assignments have explicit raw meaning.
 for(NSString *key in @[@"x",@"-",@"=",@"[",@"]",@";",@"/",@"\\",@"9",@"0"])for(NSNumber *f in @[@(C),@(C|S),@(C|S|O),@(C|S|K)])[raw addObject:@[key,f]];
 NSMutableSet *assignments=[NSMutableSet set];
 for(NSArray *pair in raw){NSString *key=pair[0];NSUInteger f=[pair[1]unsignedIntegerValue];if(key.length==1 && [key characterAtIndex:0]>='A' && [key characterAtIndex:0]<='Z'){key=key.lowercaseString;f|=S;}[assignments addObject:@[key,@(f)]];}
 printf("ASSIGNMENTS raw=%lu normalized=%lu from Base/ja/de menus and shipped macro dictionaries\n",(unsigned long)raw.count,(unsigned long)assignments.count);
 CFArrayRef sources=TISCreateInputSourceList((__bridge CFDictionaryRef)@{(__bridge NSString *)kTISPropertyInputSourceType:(__bridge NSString *)kTISTypeKeyboardLayout},true);
 NSMutableSet<NSString *> *seen=[NSMutableSet set];NSUInteger menuChecks=0,macroChecks=0,unavailable=0,ambiguous=0;
 for(CFIndex i=0;i<CFArrayGetCount(sources);i++){
  TISInputSourceRef source=(TISInputSourceRef)CFArrayGetValueAtIndex(sources,i);CFDataRef data=TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData);
  NSString *name=(__bridge NSString *)TISGetInputSourceProperty(source,kTISPropertyInputSourceID);
  if(!data || [seen containsObject:name])continue;[seen addObject:name];
  for(NSNumber *keyboard in @[@40,@41,@48])for(NSArray *assignment in assignments){@autoreleasepool{
   NSString *key=assignment[0];NSUInteger f=[assignment[1]unsignedIntegerValue];BOOL produced=NO;
   NSMenu *menu=[NSMenu new];NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:@"Fixed assignment" action:@selector(description) keyEquivalent:key];item.keyEquivalentModifierMask=f;item.allowsAutomaticKeyEquivalentLocalization=NO;[menu addItem:item];
   TSShortcutStore *store=[[TSShortcutStore alloc]initWithMenu:menu defaults:TSIsolatedAppKitDefaults];
   TSShortcutMacro *macro=[[TSShortcutMacro alloc]initWithName:@"Fixed macro" path:@"Macros/Fixed" indexPath:[NSIndexPath indexPathWithIndex:0] serializedKey:@"fixture" key:key modifiers:f];
   for(UInt16 code=0;code<128;code++){
    NSString *base=Translate(data,code,0,keyboard.unsignedIntValue),*ign=Translate(data,code,(f&S)?shiftKey>>8:0,keyboard.unsignedIntValue);
    UInt32 cm=((f&C)?cmdKey:0)|((f&S)?shiftKey:0)|((f&O)?optionKey:0)|((f&K)?controlKey:0);
    NSString *chars=Translate(data,code,cm>>8,keyboard.unsignedIntValue);
    // Invert the documented Command layer for letters (including Dvorak-QWERTY).
    // For Option/Control, use the ordinary glyph instead of the produced symbol.
    BOOL commandLetter=(f&C) && !(f&(O|K)) && chars.length==1 && (([chars characterAtIndex:0]>='a' && [chars characterAtIndex:0]<='z') || ([chars characterAtIndex:0]>='A' && [chars characterAtIndex:0]<='Z'));
    if(commandLetter){if(![chars.lowercaseString isEqual:key])continue;}
    else if(![base isEqual:key] && ![ign.lowercaseString isEqual:key])continue;
    // A symbol key whose shifted layer is a letter is not an unambiguous
    // inverse of that raw symbol assignment. Record it for physical validation.
    if(!commandLetter && ![ign.lowercaseString isEqual:key] && ign.length==1 && [[NSCharacterSet letterCharacterSet]characterIsMember:[ign characterAtIndex:0]]){ambiguous++;continue;}
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
 printf("PASS: assignment-first search layouts=%lu menu=%lu macros=%lu unavailable-layout-assignments=%lu ambiguous-inverses=%lu; no actions dispatched\n",(unsigned long)seen.count,(unsigned long)menuChecks,(unsigned long)macroChecks,(unsigned long)unavailable,(unsigned long)ambiguous);
}return 0;}
