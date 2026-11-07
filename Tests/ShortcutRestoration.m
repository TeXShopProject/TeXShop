// Production restoration paths with real menus, memory-only settings and no visible UI.
#pragma clang diagnostic ignored "-Wnullability-completeness"
#import "TSKeyboardShortcuts.m"
#import <objc/runtime.h>
#import "MemoryDefaults.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
@interface RestorationStore : TSShortcutStore
@property NSData *layout;
@property UInt32 keyboard;
@end
@implementation RestorationStore
- (NSArray *)restorationBindingsForCommand:(TSShortcutCommand *)command {
    return TSRestorationBindings(command.defaultKey, command.defaultModifiers, (__bridge CFDataRef)self.layout, self.keyboard);
}
@end
@interface RestorationUI : TSKeyboardShortcuts
@property TSShortcutCommand *selection;
@property NSString *error;
@property NSUInteger confirmations;
@end
@implementation RestorationUI
- (TSShortcutCommand *)selectedCommand { return self.selection; }
- (void)showError:(NSString *)error { self.error=error; }
- (BOOL)confirmMacrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags { self.confirmations++; return YES; }
- (void)refreshMenuAndMacros { [self.store refreshMenu]; }
@end
static TSShortcutCommand *Find(TSShortcutStore *store, NSString *ident) {
    for (TSShortcutCommand *command in store.commands) if ([command.commandID isEqual:ident]) return command;
    return nil;
}
static NSData *Layout(NSString *ident) {
    CFArrayRef sources=TISCreateInputSourceList((__bridge CFDictionaryRef)@{(__bridge NSString *)kTISPropertyInputSourceID:ident},true);
    NSData *data=nil;
    if(CFArrayGetCount(sources)) data=[(__bridge NSData *)TISGetInputSourceProperty((TISInputSourceRef)CFArrayGetValueAtIndex(sources,0),kTISPropertyUnicodeKeyLayoutData) copy];
    CFRelease(sources); REQUIRE(data.length); return data;
}
static void IgnoreOutlet(id s, SEL c, id v, NSString *key) {}
static TSMemoryDefaults *appDefaults;
static id StandardDefaults(id s, SEL c) { return appDefaults; }
static NSString *unshifted;
static id Unshifted(id s, SEL c, NSEventModifierFlags flags) { return unshifted; }
static void NoOrder(id self, SEL cmd, NSWindowOrderingMode mode, NSInteger relative) {}
int main(int argc,char **argv) { @autoreleasepool {
    appDefaults=[TSMemoryDefaults new];
    method_setImplementation(class_getClassMethod(NSUserDefaults.class,@selector(standardUserDefaults)),(IMP)StandardDefaults);
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    method_setImplementation(class_getInstanceMethod(NSWindow.class,@selector(orderWindow:relativeTo:)),(IMP)NoOrder);
    NSData *us=Layout(@"com.apple.keylayout.US");
    const NSUInteger C=NSEventModifierFlagCommand,S=NSEventModifierFlagShift,K=NSEventModifierFlagControl,O=NSEventModifierFlagOption;
    // Expansion belongs to restore validation only, and never drops Command/Control/Option.
    REQUIRE([TSRestorationBindings(@"_",C|S,(__bridge CFDataRef)us,40) containsObject:TSBinding(@"_",C)]);
    REQUIRE([TSRestorationBindings(@"_",C,(__bridge CFDataRef)us,40) containsObject:TSBinding(@"_",C|S)]);
    REQUIRE([TSRestorationBindings(@"=",C|S,(__bridge CFDataRef)us,40) containsObject:TSBinding(@"+",C)]);
    REQUIRE([TSRestorationBindings(@"+",C,(__bridge CFDataRef)us,40) containsObject:TSBinding(@"=",C|S)]);
    REQUIRE(![TSRestorationBindings(@"=",C,(__bridge CFDataRef)us,40) containsObject:TSBinding(@"+",C)]);
    REQUIRE(![TSRestorationBindings(@"=",C|S,(__bridge CFDataRef)us,40) containsObject:TSBinding(@"=",C)]);
    REQUIRE(TSRestorationBindings(@"=",C|S,NULL,40).count==1);
    NSData *german=Layout(@"com.apple.keylayout.German");
    REQUIRE(![TSRestorationBindings(@"+",C,(__bridge CFDataRef)german,40) containsObject:TSBinding(@"+",C|S)]);
    REQUIRE([TSRestorationBindings(@"_",C|S|K|O,(__bridge CFDataRef)us,40) containsObject:TSBinding(@"_",C|K|O)]);
    for(NSDictionary *b in TSRestorationBindings(@"_",C|S|K|O,(__bridge CFDataRef)us,40)) REQUIRE(([b[@"modifiers"] unsignedIntegerValue]&(C|K|O))==(C|K|O));
    for(NSString *key in @[@"a",@"A",@"Ж",@"1",@"\uf704",@"",@"ab"]) REQUIRE(TSRestorationBindings(key,C|S,(__bridge CFDataRef)us,40).count==1);
    REQUIRE(![TSBinding(@"-",C|S) isEqual:TSBinding(@"=",C)]);
    REQUIRE(![TSBinding(@"_",C|S) isEqual:TSBinding(@"_",C)]);
    // The runtime wrapper must use the current layout; this only reads the input source.
    TSShortcutStore *plain=[[TSShortcutStore alloc] initWithMenu:[NSMenu new] defaults:(id)[TSMemoryDefaults new]];
    TSShortcutCommand *probe=[TSShortcutCommand new];probe.defaultKey=@"=";probe.defaultModifiers=C|S;
    TISInputSourceRef current=TISCopyCurrentKeyboardLayoutInputSource();
    CFDataRef currentData=current?TISGetInputSourceProperty(current,kTISPropertyUnicodeKeyLayoutData):NULL;
    REQUIRE([[plain restorationBindingsForCommand:probe] isEqual:TSRestorationBindings(@"=",C|S,currentData,LMGetKbdType())]);
    if(current) CFRelease(current);
    for (NSString *name in @[@"HelpDocuments",@"TSAppDelegate",@"TSAutoCompletionListEditor",@"TSDocumentController",@"TSMacroEditor",@"TSMacroMenuController",@"TSMovie",@"TSPreferences",@"TSSparkleController",@"TSStationery",@"TextFinder"]) {
        Class c=objc_allocateClassPair(NSObject.class,name.UTF8String,0);
        class_addMethod(c,@selector(setValue:forUndefinedKey:),(IMP)IgnoreOutlet,"v@:@@");objc_registerClassPair(c);
    }
    NSArray *objects;
    REQUIRE([[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:@(argv[1])] bundle:nil] instantiateWithOwner:NSApp topLevelObjects:&objects]);
    TSMemoryDefaults *defaults=[TSMemoryDefaults new];
    RestorationStore *store=[[RestorationStore alloc] initWithMenu:NSApp.mainMenu defaults:(id)defaults];store.layout=us;
    Method method=class_getInstanceMethod(NSEvent.class,@selector(charactersByApplyingModifiers:));
    IMP old=method_setImplementation(method,(IMP)Unshifted);
    NSUInteger exercised=0;
    for (NSNumber *keyboard in @[@40,@41]) for(NSArray *c in @[@[@"TSShortcut.zoomIn:.0",@"+",@"=",@24],@[@"TSShortcut.zoomOut:.0",@"_",@"-",@27],@[@"TSShortcut.zoomOut:.0",@"_",@"\\",@94]]) {
        store.keyboard=keyboard.unsignedIntValue;
        if ([c[3] unsignedShortValue]==94 && store.keyboard!=41) continue;
        TSShortcutCommand *zoom=Find(store,c[0]),*typeset=Find(store,@"TSShortcut.doTypeset:.-1"); REQUIRE(zoom&&typeset);
        // These localized defaults are the actual shifted-symbol definitions at issue.
        if (!(zoom.defaultModifiers&S)) continue;
        if ([c[0] isEqual:@"TSShortcut.zoomIn:.0"] && ![zoom.defaultKey isEqual:@"="]) continue;
        [store restoreAll];
        REQUIRE(![store setKey:@"z" modifiers:C|K forCommand:zoom]);
        RestorationUI *ui=[[RestorationUI alloc] initWithWindow:nil];ui.store=store;ui.editingCommand=typeset;ui.selection=zoom;
        ui.captureDisplay=[NSTextField new];ui.captureError=[NSTextField new];ui.applyButton=[NSButton new];
        unshifted=c[2];
        NSEvent *event=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:C|S timestamp:0 windowNumber:0 context:nil characters:c[1] charactersIgnoringModifiers:c[1] isARepeat:NO keyCode:[c[3] unsignedShortValue]];
        [ui recordShortcutEvent:event];
        REQUIRE(![ui conflictForCapturedShortcut]);
        [ui applyCapturedShortcut:nil];REQUIRE([typeset.item.keyEquivalent isEqual:c[1]]);
        NSDictionary *saved=[[defaults objectForKey:TSMenuShortcutOverridesKey] copy];
        ui.confirmations=0;[ui restoreShortcut:nil];
        REQUIRE([ui.error containsString:typeset.path] && ui.confirmations==0);
        REQUIRE([zoom.item.keyEquivalent isEqual:@"z"] && [[defaults objectForKey:TSMenuShortcutOverridesKey] isEqual:saved]);
        REQUIRE([[store restoreCommand:zoom] containsString:typeset.path]);
        REQUIRE([zoom.item.keyEquivalent isEqual:@"z"] && [[defaults objectForKey:TSMenuShortcutOverridesKey] isEqual:saved]);
        // A conflicting macro with a different raw spelling is not promoted to a menu conflict.
        REQUIRE(![store setKey:@"" modifiers:0 forCommand:typeset]);
        NSMenuItem *macro=[[NSMenuItem alloc] initWithTitle:@"Macro" action:NSSelectorFromString(@"doMacro:") keyEquivalent:c[1]];
        macro.keyEquivalentModifierMask=C;[typeset.item.menu addItem:macro];
        REQUIRE(![store conflictForRestoringCommand:zoom]);
        [ui restoreShortcut:nil];REQUIRE(!ui.error && ui.confirmations==1);
        REQUIRE([TSBinding(zoom.item.keyEquivalent,zoom.item.keyEquivalentModifierMask) isEqual:TSBinding(zoom.defaultKey,zoom.defaultModifiers)]);
        REQUIRE(![store conflictForRestoringCommand:zoom]); // self must be excluded
        [macro.menu removeItem:macro];
        exercised++;
    }
    method_setImplementation(method,old);[store restoreAll];
    REQUIRE(exercised>=2);
    printf("PASS: %s restore sequences=%lu, blocked UI/store restore preserves settings; freed key restores; macros remain raw\n",argv[1],(unsigned long)exercised);
}return 0;}
