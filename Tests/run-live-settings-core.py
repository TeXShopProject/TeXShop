#!/usr/bin/env python3
"""Validate live-settings policies with memory defaults and temporary files only."""
from pathlib import Path
import subprocess,tempfile,sys,re,plistlib
from source_tree import include_args, source_file
ROOT=Path(__file__).resolve().parents[1]
mutation=sys.argv[1] if len(sys.argv)>1 else ''
sources={n:(source_file(ROOT, n)).read_text() for n in ['TSPreferenceProfile.m','TSPreferenceInput.m','TSThemeFileStore.m']}
mutations={
 'profile-notify':('TSPreferenceProfile.m','[NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:defaults];',';'),
 'profile-guard':('TSPreferenceProfile.m','profileApplicationDepth++;',';'),
 'input-empty':('TSPreferenceInput.m','if (!self.allowsEmpty && trimmed.length == 0) return nil;',';'),
 'input-tail':('TSPreferenceInput.m',' || !scanner.isAtEnd',''),
 'input-clamp':('TSPreferenceInput.m','number = MIN(self.maximum, MAX(self.minimum, number));',';'),
 'input-percent':('TSPreferenceInput.m','number:@(number / 100.0)','number:@(number)'),
 'theme-symlink':('TSThemeFileStore.m','if ([attributes[NSFileType] isEqual:NSFileTypeSymbolicLink]) return nil;','(void)attributes;'),
 'theme-title':('TSThemeFileStore.m','copy[@"Title"] = title;',';'),
}
if mutation:
 if mutation not in mutations:raise SystemExit('unknown mutation')
 file,old,new=mutations[mutation];assert old in sources[file];sources[file]=sources[file].replace(old,new)
 if mutation=='profile-guard':sources[file]=sources[file].replace('profileApplicationDepth--;',';')
program=r'''
#import <Cocoa/Cocoa.h>
#import "MemoryDefaults.h"
#import "TSPreferenceProfile.h"
#import "TSPreferenceInput.h"
#import "TSThemeFileStore.h"
@interface ObservedDefaults : TSMemoryDefaults @end
@implementation ObservedDefaults
- (void)setObject:(id)value forKey:(NSString *)key {
    [super setObject:value forKey:key];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}
- (void)removeObjectForKey:(NSString *)key {
    [super removeObjectForKey:key];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}
@end
static void check(BOOL ok, const char *message) { if (!ok) { fprintf(stderr,"FAIL: %s\n",message);exit(1); } }
int main(int argc,const char **argv) { @autoreleasepool {
    // An engine profile writes its keys, and observers see one change after all of them.
    ObservedDefaults *defaults=[ObservedDefaults new];
    NSDictionary *kept=@{@"FindMethod":@0,@"TSMenuShortcutOverrides":@{@"example":@1},@"DockIconStyle":@"classic",@"UnknownVendorKey":@"keep"};
    [defaults.values addEntriesFromDictionary:kept];
    NSDictionary *values=TSEngineProfileValues(TSEngineProfilePLaTeXDvipdfmx,YES);
    __block NSUInteger visible=0,intermediate=0;
    id token=[NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:defaults queue:nil usingBlock:^(NSNotification *note) {
        if (TSPreferenceProfileIsApplying()) { intermediate++; return; }
        visible++;
        for (NSString *key in values) check([defaults.values[key] isEqual:values[key]],"observers see the completed profile");
    }];
    TSEngineProfileApply(defaults,values);
    [NSNotificationCenter.defaultCenter removeObserver:token];
    check(visible==1 && intermediate==values.count,"one coherent observer update");
    for (NSString *key in kept) check([defaults.values[key] isEqual:kept[key]],"settings outside the profile are kept");
    TSPreferenceInput *text=[[TSPreferenceInput alloc] initWithKey:@"path" kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:NO notification:nil];
    check([text validatedValue:@"  "]==nil,"reject empty required text");
    check([[text validatedValue:@" /missing/volume "].textValue isEqual:@"/missing/volume"],"allow nonexisting path");
    check([text validatedValue:@"x\ny"]==nil,"reject control characters");
    TSPreferenceInput *optional=[[TSPreferenceInput alloc] initWithKey:@"optional" kind:TSPreferenceInputText minimum:0 maximum:0 allowsEmpty:YES notification:nil];
    check([[optional validatedValue:@""].textValue isEqual:@""],"allow optional blank");
    TSPreferenceInput *integer=[[TSPreferenceInput alloc] initWithKey:@"tabs" kind:TSPreferenceInputInteger minimum:2 maximum:50 allowsEmpty:NO notification:nil];
    for (NSString *bad in @[@"",@" ",@"x",@"12px",@"1e999",@"nan"]) check([integer validatedValue:bad]==nil,"invalid number");
    check([integer validatedValue:@"-9"].numberValue.integerValue==2 && [integer validatedValue:@"100"].numberValue.integerValue==50,"clamp numeric range");
    TSPreferenceInput *percentage=[[TSPreferenceInput alloc] initWithKey:@"zoom" kind:TSPreferenceInputPercentage minimum:20 maximum:400 allowsEmpty:NO notification:nil];
    check(fabs([percentage validatedValue:@"125"].numberValue.doubleValue-1.25)<0.0001,"percentage conversion");
    check([[percentage displayStringForValue:[percentage validatedValue:@"125"]] isEqual:@"125"],"percentage display");
    NSURL *directory=[NSURL fileURLWithPath:(@(argv[1]) ?: @"") isDirectory:YES];
    TSThemeFileStore *store=[[TSThemeFileStore alloc] initWithDirectory:directory];
    NSDictionary *original=@{@"Title":@"Original",@"EditorText":@[@1,@0,@0,@1]};
    check([store writeColors:original title:@"Original" error:NULL],"write theme");
    check([store writeColors:original title:@"Clone" error:NULL],"clone theme");
    check([[[store readTitle:@"Clone"] objectForKey:@"Title"] isEqual:@"Clone"] && [original[@"Title"] isEqual:@"Original"],"clone title without source mutation");
    for (NSString *bad in @[@"",@".",@".hidden",@"..",@"../outside",@"a/b",@"a\\b",@"a\nb"]) check([store URLForTitle:bad]==nil,"reject unsafe title");
    NSURL *link=[directory URLByAppendingPathComponent:@"Link.plist"];
    check([NSFileManager.defaultManager createSymbolicLinkAtURL:link withDestinationURL:([directory URLByAppendingPathComponent:@"Original.plist"] ?: directory) error:NULL],"make symlink fixture");
    check(![store writeColors:@{@"x":@1} title:@"Link" error:NULL],"reject even in-directory symlink");
    check([[[store readTitle:@"Original"] objectForKey:@"Title"] isEqual:@"Original"],"symlink target intact");
    check([NSFileManager.defaultManager createDirectoryAtURL:([directory URLByAppendingPathComponent:@"Blocked.plist"] ?: directory) withIntermediateDirectories:NO attributes:nil error:NULL],"blocked destination fixture");
    check(![store writeColors:original title:@"Blocked" error:NULL],"propagate write failure");
    NSURL *parent=directory.URLByDeletingLastPathComponent ?: directory;
    NSURL *parentLink=[parent URLByAppendingPathComponent:@"ParentLink"] ?: parent;
    NSURL *colorLink=[parent URLByAppendingPathComponent:@"ColorLink"] ?: parent;
    check([NSFileManager.defaultManager createSymbolicLinkAtURL:parentLink withDestinationURL:parent error:NULL],"parent symlink fixture");
    check([NSFileManager.defaultManager createSymbolicLinkAtURL:colorLink withDestinationURL:directory error:NULL],"Colors symlink fixture");
    for (NSURL *dir in @[directory, (directory.URLByResolvingSymlinksInPath ?: directory), colorLink, ([parentLink URLByAppendingPathComponent:@"Colors"] ?: directory)]) {
        TSThemeFileStore *linked=[[TSThemeFileStore alloc]initWithDirectory:dir];
        check([linked writeColors:original title:@"Fresh" error:NULL],"new theme below symlink parent");
        check([linked writeColors:original title:@"Original" error:NULL],"existing theme below symlink parent");
        check([linked readTitle:@"Fresh"]!=nil,"read written linked theme");
        [NSFileManager.defaultManager removeItemAtURL:([directory URLByAppendingPathComponent:@"Fresh.plist"] ?: directory) error:NULL];
    }
    puts("PASS: engine profile notification policy, isolated defaults, input validation, safe theme persistence");
} return 0; }
'''.replace('            check([defaults.stringForKey isEqual:nil],"unused");','')
with tempfile.TemporaryDirectory(prefix='texshop-live-core-',dir='/private/tmp') as tmp:
 t=Path(tmp);(t/'probe.m').write_text(program)
 for name,body in sources.items():(t/name).write_text(body)
 args=['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-deprecated-declarations','-Wnullability-completeness','-Wnullable-to-nonnull-conversion','-Wunguarded-availability-new',*include_args(ROOT),'-I',str(ROOT/'Tests'),'-framework','Cocoa',str(t/'probe.m'),*[str(t/n) for n in sources],str(ROOT/'Sources/App/globals.m'),'-o',str(t/'probe')]
 subprocess.run(args,check=True)
 themes=t/'Colors';themes.mkdir()
 subprocess.run([str(t/'probe'),str(themes)],check=True)
