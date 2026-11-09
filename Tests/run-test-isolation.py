#!/usr/bin/env python3
"""Verify AppKit settings and frame writes stay in memory before running UI fixtures."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
program = r'''
#import "TestAppKitIsolation.h"
static void require(BOOL value) { if (!value) { fputs("FAIL: isolation contract\n",stderr); exit(1); } }
static id forbiddenDomainRead(id object, SEL selector, id name) {
    fprintf(stderr,"FAIL: persistent defaults access: %s\n",sel_getName(selector)); exit(2);
}
static void forbiddenDomainRemove(id object, SEL selector, id name) {
    fprintf(stderr,"FAIL: persistent defaults access: %s\n",sel_getName(selector)); exit(2);
}
static void forbiddenWrite(id object, SEL selector, id value, id key) {
    fprintf(stderr,"FAIL: persistent defaults write: %s\n",sel_getName(selector)); exit(2);
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    // A regression that calls the Foundation setter must fail before it can write.
    TSReplaceTestMethod(class_getInstanceMethod(NSUserDefaults.class,@selector(setObject:forKey:)),(IMP)forbiddenWrite);
    TSReplaceTestMethod(class_getInstanceMethod(NSUserDefaults.class,@selector(setPersistentDomain:forName:)),(IMP)forbiddenWrite);
    TSReplaceTestMethod(class_getInstanceMethod(NSUserDefaults.class,@selector(removePersistentDomainForName:)),(IMP)forbiddenDomainRemove);
    TSReplaceTestMethod(class_getInstanceMethod(NSUserDefaults.class,@selector(persistentDomainForName:)),(IMP)forbiddenDomainRead);
    [NSApplication sharedApplication];
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    require([defaults isKindOfClass:TSMemoryDefaults.class]);
    [defaults registerDefaults:@{@"value":@3}];
    [defaults setInteger:7 forKey:@"value"];
    [defaults setVolatileDomain:@{@"value":@9} forName:NSArgumentDomain];
    require([defaults integerForKey:@"value"]==9);
    [defaults removeVolatileDomainForName:NSArgumentDomain];
    require([defaults integerForKey:@"value"]==7);
    [defaults removeObjectForKey:@"value"];
    require([defaults integerForKey:@"value"]==3);
    [defaults setBool:YES forKey:@"LeftRightArrowsAlwaysPage"];
    require([defaults boolForKey:@"LeftRightArrowsAlwaysPage"]);
    NSString *appDomain=NSBundle.mainBundle.bundleIdentifier ?: @"TeXShop";
    [defaults setObject:@"stale" forKey:@"old"];
    NSMutableDictionary *nested=[@{@"path":@"memory-only"} mutableCopy];
    [defaults setPersistentDomain:@{@"nested":nested,@"value":@21} forName:appDomain];
    nested[@"path"]=@"changed outside defaults";
    require([defaults objectForKey:@"old"]==nil && [defaults integerForKey:@"value"]==21);
    require([[[defaults persistentDomainForName:appDomain][@"nested"] objectForKey:@"path"] isEqual:@"memory-only"]);
    [defaults setPersistentDomain:@{@"value":@31} forName:@"org.texshop.tests.other"];
    require([[defaults persistentDomainForName:@"org.texshop.tests.other"][@"value"] integerValue]==31);
    require([defaults integerForKey:@"value"]==21);
    [defaults setInteger:22 forKey:@"value"];
    require([[defaults persistentDomainForName:appDomain][@"value"] integerValue]==22);
    [defaults removePersistentDomainForName:appDomain];
    require([defaults persistentDomainForName:appDomain]==nil && [defaults integerForKey:@"value"]==3);
    [defaults removePersistentDomainForName:@"org.texshop.tests.other"];
    require([defaults persistentDomainForName:@"org.texshop.tests.other"]==nil);
    NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,200,100)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;
    require(![window setFrameAutosaveName:@"ExperimentConsole"]);
    [window saveFrameUsingName:@"ExperimentConsole"];
    [window orderFront:nil];
    require(window.frameAutosaveName.length==0 && !window.visible);
    require([defaults objectForKey:@"NSWindow Frame ExperimentConsole"]==nil);
    [window close];
    puts("PASS: memory scalar/volatile/registered/persistent domains (Foundation access traps installed), blocked frame persistence and window ordering");
} return 0; }
'''
cases = {
    'baseline': None,
    'persistent-set-falls-through': ('MemoryDefaults.h', '- (void)setPersistentDomain:', '- (void)disabledSetPersistentDomain:'),
    'persistent-remove-falls-through': ('MemoryDefaults.h', '- (void)removePersistentDomainForName:', '- (void)disabledRemovePersistentDomainForName:'),
    'persistent-read-falls-through': ('MemoryDefaults.h', '- (NSDictionary *)persistentDomainForName:', '- (NSDictionary *)disabledPersistentDomainForName:'),
    'volatile-priority': ('MemoryDefaults.h', 'self.volatileValues[NSArgumentDomain][key] ?: ', ''),
    'scalar-write': ('MemoryDefaults.h', '- (void)setInteger:(NSInteger)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }', '- (void)setInteger:(NSInteger)value forKey:(NSString *)key {}'),
    'frame-name': ('TestAppKitIsolation.h', 'static BOOL TSPreventTestFrameName(id receiver, SEL selector, NSString *name) { return NO; }', 'static BOOL TSPreventTestFrameName(id receiver, SEL selector, NSString *name) { return YES; }'),
}
for name, mutation in cases.items():
    with tempfile.TemporaryDirectory(prefix='texshop-isolation-') as td:
        temp=Path(td);home=temp/'home';(home/'Library/Preferences').mkdir(parents=True)
        for header in ['MemoryDefaults.h','TestAppKitIsolation.h']:
            content=(root/'Tests'/header).read_text()
            if mutation and mutation[0]==header:
                assert content.count(mutation[1])==1
                content=content.replace(mutation[1],mutation[2])
            (temp/header).write_text(content)
        (temp/'test.m').write_text(program)
        subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-I',td,str(temp/'test.m'),'-o',str(temp/'test')],check=True)
        result=subprocess.run([str(temp/'test')],env=dict(os.environ,HOME=str(home),CFFIXED_USER_HOME=str(home)),capture_output=True,text=True)
        if mutation:
            assert (result.returncode==2 and 'persistent defaults' in result.stderr) if name.startswith('persistent-') else (result.returncode==1 and 'FAIL: isolation contract' in result.stderr), (name,result.stdout,result.stderr)
            print('DETECTED:',name)
        else:
            assert result.returncode==0, result.stdout+result.stderr
            print(result.stdout.strip())
