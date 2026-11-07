#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "../Sources/TSKeyboardShortcuts.m"
#import "ShortcutRecordingBaseline.h"
// Test-only override: keep AppKit's real matching, bypass its repeated-action
// highlight/throttle (otherwise hundreds of thousands of matches take hours).
// Production never calls or overrides this private selector.
@interface SweepMenu : NSMenu
@end
@implementation SweepMenu
- (void)_performKeyEquivalentForItemAtIndex:(NSInteger)index {
    NSMenuItem *item = [self itemAtIndex:index];
    [NSApp sendAction:item.action to:item.target from:item];
}
@end
@interface DispatchTarget : NSObject
@property BOOL called;
- (void)run:(id)sender;
@end
@implementation DispatchTarget
- (void)run:(id)sender { self.called=YES; }
@end
static NSString *Translate(CFDataRef data, UInt16 code, UInt32 mods, UInt32 keyboard) {
    UniChar chars[8]; UniCharCount count=0; UInt32 dead=0;
    OSStatus status=UCKeyTranslate((const UCKeyboardLayout *)CFDataGetBytePtr(data),code,kUCKeyActionDown,mods,keyboard,kUCKeyTranslateNoDeadKeysBit,&dead,8,&count,chars);
    return status==noErr ? [NSString stringWithCharacters:chars length:count] : @"";
}
static BOOL Dispatch(NSMenu *menu, NSMenuItem *item, DispatchTarget *target, NSDictionary *binding, NSEvent *event) {
    target.called=NO; item.keyEquivalent=@"";
    item.keyEquivalentModifierMask=[binding[@"modifiers"] unsignedIntegerValue]; item.keyEquivalent=binding[@"key"];
    [menu performKeyEquivalent:event]; return target.called;
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSMenu *menu=[SweepMenu new]; menu.autoenablesItems=NO;
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"Command" action:@selector(run:) keyEquivalent:@""];
    DispatchTarget *target=[DispatchTarget new]; item.target=target; item.enabled=YES;
    item.allowsAutomaticKeyEquivalentLocalization=NO; [menu addItem:item];
    const NSUInteger C=NSEventModifierFlagCommand,S=NSEventModifierFlagShift,O=NSEventModifierFlagOption,K=NSEventModifierFlagControl,L=NSEventModifierFlagCapsLock;
    NSArray *combos=@[@(C),@(C|S),@(C|O),@(C|K),@(C|S|O),@(C|S|K),@(C|O|K),@(C|L),@(C|S|L),@(C|O|L)];
    CFArrayRef sources=TISCreateInputSourceList((__bridge CFDictionaryRef)@{(__bridge NSString *)kTISPropertyInputSourceType:(__bridge NSString *)kTISTypeKeyboardLayout},true);
    NSMutableSet *seen=[NSMutableSet set]; long total=0,allowed=0,newOK=0,oldOK=0,lost=0,gained=0;
    for (CFIndex i=0;i<CFArrayGetCount(sources);i++) {
        TISInputSourceRef source=(TISInputSourceRef)CFArrayGetValueAtIndex(sources,i);
        NSString *name=(__bridge NSString *)TISGetInputSourceProperty(source,kTISPropertyInputSourceID);
        CFDataRef data=TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData);
        if (!data || [seen containsObject:name]) continue; [seen addObject:name];
        for (NSNumber *kb in @[@40,@41,@48]) for (UInt16 code=0;code<128;code++) for (NSNumber *fn in combos) { @autoreleasepool {
            NSUInteger f=fn.unsignedIntegerValue;
            UInt32 cm=cmdKey|((f&S)?shiftKey:0)|((f&O)?optionKey:0)|((f&K)?controlKey:0)|((f&L)?alphaLock:0);
            NSString *chars=Translate(data,code,cm>>8,kb.unsignedIntValue), *ign=Translate(data,code,(f&S)?shiftKey>>8:0,kb.unsignedIntValue);
            if (!chars.length && !ign.length) continue;
            NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:f timestamp:0 windowNumber:0 context:nil characters:chars charactersIgnoringModifiers:ign isARepeat:NO keyCode:code];
            total++; NSString *key=TSShortcutCharacterForEvent(event);
            NSString *oldKey=PreviousCharacterForEvent(event);
            BOOL newAllowed=key.length && [TSShortcutStore isAllowedKey:key modifiers:f&TSShortcutModifiers];
            BOOL oldAllowed=oldKey.length && [TSShortcutStore isAllowedKey:oldKey modifiers:f&TSShortcutModifiers];
            if (!newAllowed && !oldAllowed) continue;
            allowed++;
            NSDictionary *current=TSRecordedBinding(event,Translate(data,code,0,kb.unsignedIntValue)), *previous=PreviousRecordingBinding(oldKey,f,data,kb.unsignedIntValue);
            BOOL a=newAllowed && Dispatch(menu,item,target,current,event),b=oldAllowed && Dispatch(menu,item,target,previous,event);
            newOK+=a; oldOK+=b; if (a&&!b) gained++;
            if (b&&!a) { lost++; if(lost<20) printf("REGRESSION %s kb=%u code=%u chars=%s ign=%s new=%s old=%s\n",name.UTF8String,kb.unsignedIntValue,code,chars.UTF8String,ign.UTF8String,current.description.UTF8String,previous.description.UTF8String); }
        }}
    }
    printf("layouts=%lu total=%ld allowed=%ld previousDispatch=%ld currentDispatch=%ld gained=%ld lost=%ld\n",(unsigned long)seen.count,total,allowed,oldOK,newOK,gained,lost);
    CFRelease(sources); return lost?1:0;
}}
