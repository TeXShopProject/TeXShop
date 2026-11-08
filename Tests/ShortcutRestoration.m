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
@interface RestorationUI : TSShortcutPaneController
@property TSShortcutCommand *selection;
@property NSString *error;
@property NSUInteger confirmations;
@end
@implementation RestorationUI
- (TSShortcutCommand *)selectedCommand { return self.selection; }
- (void)showError:(NSString *)error { self.error=error; }
- (void)confirmMacrosUsingKey:(NSString *)key modifiers:(NSEventModifierFlags)flags completion:(void (^)(BOOL))completion { self.confirmations++; completion(YES); }
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
// Independent input construction, using the actual modifier layers from the selected layout data.
static NSString *Input(NSData *data, UInt16 code, NSEventModifierFlags flags, UInt32 keyboard) {
    UInt32 cm=((flags&NSEventModifierFlagCommand)?cmdKey:0)|((flags&NSEventModifierFlagShift)?shiftKey:0)|
        ((flags&NSEventModifierFlagOption)?optionKey:0)|((flags&NSEventModifierFlagControl)?controlKey:0);
    UniChar chars[8];UniCharCount count=0;UInt32 dead=0;
    OSStatus status=UCKeyTranslate((const UCKeyboardLayout *)data.bytes,code,kUCKeyActionDown,cm>>8,keyboard,kUCKeyTranslateNoDeadKeysBit,&dead,8,&count,chars);
    return status==noErr?[NSString stringWithCharacters:chars length:count]:@"";
}
static NSEvent *KeyEvent(NSData *data, UInt16 code, NSEventModifierFlags flags, UInt32 keyboard) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil
        characters:Input(data,code,flags,keyboard) charactersIgnoringModifiers:Input(data,code,flags&NSEventModifierFlagShift,keyboard) isARepeat:NO keyCode:code];
}
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
    REQUIRE(german.length);
    // Symbols on digit keys must follow the recorder, including a digit as the saved key.
    for (NSString *name in @[@"Polish",@"Turkish"]) {
        NSData *data=Layout([@"com.apple.keylayout." stringByAppendingString:name]);
        REQUIRE([TSRestorationBindings(@"_",C|S,(__bridge CFDataRef)data,40) containsObject:TSBinding(@"_",C)]);
    }
    NSData *frenchPC=Layout(@"com.apple.keylayout.French-PC");
    REQUIRE([TSRestorationBindings(@"_",C|S,(__bridge CFDataRef)frenchPC,40) containsObject:TSBinding(@"8",C)]);
    NSData *czech=Layout(@"com.apple.keylayout.Czech");
    REQUIRE([TSRestorationBindings(@"+",C|S,(__bridge CFDataRef)czech,40) containsObject:TSBinding(@"1",C)]);
    REQUIRE([TSRestorationBindings(@"=",C|S,(__bridge CFDataRef)german,40) containsObject:TSBinding(@"=",C)]);
    NSData *dvorakCommand=Layout(@"com.apple.keylayout.DVORAK-QWERTYCMD");
    REQUIRE(![TSRestorationBindings(@":",C,(__bridge CFDataRef)dvorakCommand,40) containsObject:TSBinding(@";",C|S)]);
    REQUIRE(![TSRestorationBindings(@":",C,(__bridge CFDataRef)dvorakCommand,40) containsObject:TSBinding(@":",C|S)]);

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
    NSUInteger exercised=0, factory=0, selfRestores=0, highCodeConflicts=0;
    NSArray *layoutIDs=@[@"US",@"ABC",@"German",@"Danish",@"Turkish",@"Polish",@"Czech",@"Hungarian",@"French-PC",@"DVORAK-QWERTYCMD",@"Macedonian"];
    for (NSString *layoutID in layoutIDs) for (NSNumber *keyboard in @[@40,@41,@48]) { @autoreleasepool {
        store.layout=Layout([@"com.apple.keylayout." stringByAppendingString:layoutID]);store.keyboard=keyboard.unsignedIntValue;
        [store restoreAll];
        // Every factory command must remain restorable, including layout-dependent overlaps.
        for (TSShortcutCommand *command in store.commands) REQUIRE(![store conflictForRestoringCommand:command]);
        // Rejected saved overrides leave factory keys active; they are not custom alias conflicts.
        for (TSShortcutCommand *command in store.commands) if (TSRestorationSymbol(command.defaultKey))
            store.overrides[command.commandID]=TSBinding(@"t",C);
        [store applySavedOverrides];
        REQUIRE(store.unavailableCommands.count>0);
        for (TSShortcutCommand *command in store.commands) REQUIRE(![store conflictForRestoringCommand:command]);
        [store restoreAll];
        TSShortcutCommand *typeset=Find(store,@"TSShortcut.doTypeset:.-1"); REQUIRE(typeset);
        REQUIRE(![store setKey:@"\uf717" modifiers:K forCommand:typeset]);
        for (TSShortcutCommand *command in store.commands) {
            if (!TSRestorationSymbol(command.defaultKey)) continue;
            RestorationUI *ui=[[RestorationUI alloc] initWithShortcuts:[TSKeyboardShortcuts new]];ui.store=store;ui.selection=command;
            [ui restoreShortcut:nil]; REQUIRE(!ui.error);
            REQUIRE(![store setKey:@"\uf716" modifiers:K forCommand:command]);
            [ui restoreShortcut:nil]; REQUIRE(!ui.error);
            REQUIRE([TSBinding(command.item.keyEquivalent,command.item.keyEquivalentModifierMask) isEqual:TSBinding(command.defaultKey,command.defaultModifiers)]);
            factory++;
        }
        [store restoreAll];
        // Actual layout characters, rather than hard-coded US strings paired with another keyboard type.
        if ([layoutID isEqual:@"US"] && store.keyboard==48) {
            REQUIRE([Input(store.layout,94,0,48) isEqual:@"_"]);
            REQUIRE([Input(store.layout,94,S,48) isEqual:@"_"]);
            REQUIRE([Input(store.layout,27,S,48) isEqual:@"="]);
        }
        for (NSString *ident in @[@"TSShortcut.zoomIn:.0",@"TSShortcut.zoomOut:.0"]) {
            [store restoreAll];
            TSShortcutCommand *zoom=Find(store,ident); REQUIRE(zoom);
            NSDictionary *original=TSBinding(zoom.defaultKey,zoom.defaultModifiers);
            NSEvent *chosen=nil;
            // Exercise keypad-only spellings rather than stopping at a main-row match.
            UInt16 firstCode=[layoutID isEqual:@"Macedonian"]?64:0;
            for(UInt16 code=firstCode;code<128;code++) {
                if (code==66||code==68||code==70||code==72||code==73||code==74||code==77) continue;
                NSEvent *event=KeyEvent(store.layout,code,C|S,store.keyboard);
                NSString *plain=Input(store.layout,code,0,store.keyboard);
                NSArray *spellings=TSEventBindings(event,plain);
                if ([spellings containsObject:original] && ![spellings.firstObject isEqual:original] &&
                    [TSShortcutStore isAllowedKey:spellings.firstObject[@"key"] modifiers:[spellings.firstObject[@"modifiers"] unsignedIntegerValue]]) {
                    chosen=event;unshifted=plain;break;
                }
            }
            if (!chosen) continue; // Some physical layouts need only the unchanged raw check.
            // Recording a command's own default stroke can save a different raw spelling.
            // Its own live override must not prevent restoring the original spelling.
            RestorationUI *selfUI=[[RestorationUI alloc] initWithShortcuts:[TSKeyboardShortcuts new]];
            selfUI.store=store;selfUI.editingCommand=zoom;selfUI.selection=zoom;
            selfUI.captureDisplay=[NSTextField new];selfUI.captureError=[NSTextField new];selfUI.applyButton=[NSButton new];
            [selfUI recordShortcutEvent:chosen];
            if (![selfUI conflictForCapturedShortcut]) {
                REQUIRE(selfUI.applyButton.enabled);
                [selfUI applyCapturedShortcut:nil];
                NSDictionary *recorded=TSBinding(selfUI.capturedKey,selfUI.capturedModifiers);
                REQUIRE(![recorded isEqual:original]);
                REQUIRE([TSBinding(zoom.item.keyEquivalent,zoom.item.keyEquivalentModifierMask) isEqual:recorded]);
                REQUIRE([store.overrides[zoom.commandID] isEqual:recorded]);
                REQUIRE([[defaults objectForKey:TSMenuShortcutOverridesKey][zoom.commandID] isEqual:recorded]);
                [selfUI restoreShortcut:nil];
                REQUIRE(!selfUI.error);
                REQUIRE([TSBinding(zoom.item.keyEquivalent,zoom.item.keyEquivalentModifierMask) isEqual:original]);
                REQUIRE(store.overrides.count==0 && ![defaults objectForKey:TSMenuShortcutOverridesKey]);
                selfRestores++;
            }
            [store restoreAll];
            REQUIRE(![store setKey:@"z" modifiers:C|K forCommand:zoom]);
            RestorationUI *ui=[[RestorationUI alloc] initWithShortcuts:[TSKeyboardShortcuts new]];ui.store=store;ui.editingCommand=typeset;ui.selection=zoom;
            ui.captureDisplay=[NSTextField new];ui.captureError=[NSTextField new];ui.applyButton=[NSButton new];
            [ui recordShortcutEvent:chosen];
            // A few locales have another factory key for the same stroke; free it first.
            for(TSShortcutCommand *other in store.commands) if(other!=zoom && other!=typeset &&
                [ui.capturedBindings containsObject:TSBinding(other.item.keyEquivalent,other.item.keyEquivalentModifierMask)])
                REQUIRE(![store setKey:@"" modifiers:0 forCommand:other]);
            REQUIRE(![ui conflictForCapturedShortcut]);
            [ui applyCapturedShortcut:nil];REQUIRE([typeset.item.keyEquivalent isEqual:ui.capturedKey]);
            NSDictionary *saved=[[defaults objectForKey:TSMenuShortcutOverridesKey] copy];
            ui.confirmations=0;[ui restoreShortcut:nil];
            REQUIRE([ui.error containsString:typeset.path] && ui.confirmations==0);
            REQUIRE([zoom.item.keyEquivalent isEqual:@"z"] && [[defaults objectForKey:TSMenuShortcutOverridesKey] isEqual:saved]);
            REQUIRE([[store restoreCommand:zoom] containsString:typeset.path]);
            REQUIRE([zoom.item.keyEquivalent isEqual:@"z"] && [[defaults objectForKey:TSMenuShortcutOverridesKey] isEqual:saved]);
            REQUIRE(![store setKey:@"" modifiers:0 forCommand:typeset]);
            NSMenuItem *macro=[[NSMenuItem alloc] initWithTitle:@"Macro" action:NSSelectorFromString(@"doMacro:") keyEquivalent:ui.capturedKey];
            macro.keyEquivalentModifierMask=ui.capturedModifiers;[typeset.item.menu addItem:macro];
            REQUIRE(![store conflictForRestoringCommand:zoom]);
            [ui restoreShortcut:nil];REQUIRE(!ui.error && ui.confirmations==1);
            REQUIRE([TSBinding(zoom.item.keyEquivalent,zoom.item.keyEquivalentModifierMask) isEqual:original]);
            REQUIRE(![store conflictForRestoringCommand:zoom]);
            [macro.menu removeItem:macro];
            exercised++;
            if (chosen.keyCode>=64) highCodeConflicts++;
        }
    }}
    [store restoreAll];
    // Raw collisions still count for menu items without custom overrides, including anonymous items.
    TSShortcutCommand *zoom=Find(store,@"TSShortcut.zoomOut:.0");
    REQUIRE(![store setKey:@"z" modifiers:C|K forCommand:zoom]);
    NSMenuItem *dynamic=[[NSMenuItem alloc] initWithTitle:@"Dynamic raw conflict" action:@selector(description) keyEquivalent:zoom.defaultKey];
    dynamic.keyEquivalentModifierMask=zoom.defaultModifiers;[zoom.item.menu addItem:dynamic];
    REQUIRE([[store restoreCommand:zoom] containsString:@"Dynamic raw conflict"]);
    [dynamic.menu removeItem:dynamic];
    method_setImplementation(method,old);[store restoreAll];
    REQUIRE(exercised>=2);
    NSString *nibPath=@(argv[1]);
    if ([nibPath containsString:@"/Base.lproj/"] || [nibPath containsString:@"/ja.lproj/"]) REQUIRE(selfRestores>0);
    if ([nibPath containsString:@"/Base.lproj/"]) REQUIRE(highCodeConflicts>0);
    printf("PASS: %s layouts=%lu keyboardTypes=ANSI40/ISO41/JIS48 factory restores=%lu, conflict sequences=%lu, own-stroke restores=%lu, high-code conflicts=%lu; raw priority preserved\n",argv[1],(unsigned long)layoutIDs.count,(unsigned long)factory,(unsigned long)exercised,(unsigned long)selfRestores,(unsigned long)highCodeConflicts);
}return 0;}
