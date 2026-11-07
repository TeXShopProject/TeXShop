#!/usr/bin/env python3
"""Validate live-settings policies with memory defaults and temporary files only."""
from pathlib import Path
import subprocess,tempfile,sys,re,plistlib
ROOT=Path(__file__).resolve().parents[1]
mutation=sys.argv[1] if len(sys.argv)>1 else ''
sources={n:(ROOT/'Sources'/n).read_text() for n in ['TSPreferenceProfile.m','TSPreferenceInput.m','TSThemeFileStore.m']}
mutations={
 'profile-preserve':('TSPreferenceProfile.m','if (TSPreferenceProfilePreservesKey(key)) continue;','if (NO) continue;'),
 'profile-remove':('TSPreferenceProfile.m','else [removals addObject:key];','else {}'),
 'profile-used':('TSPreferenceProfile.m','updates[TSProfileKeyTSHasBeenUsed] = @YES;','updates[TSProfileKeyTSHasBeenUsed] = @NO;'),
 'profile-path':('TSPreferenceProfile.m','if (![path isKindOfClass:NSString.class] ||','if (NO && (![path isKindOfClass:NSString.class] ||'),
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
 if mutation=='profile-path':sources[file]=sources[file].replace('length] == 0) return nil;','length] == 0)) return nil;')
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
    NSData *font = [@"serialized-font" dataUsingEncoding:NSUTF8StringEncoding];
    for (int index=2;index<argc;index++) {
        NSMutableDictionary *profile = [[NSDictionary dictionaryWithContentsOfFile:(@(argv[index]) ?: @"")] mutableCopy];
        profile[@"DocumentFontAttributes"] = @"profile-attributes";
        check(profile != nil,"load bundled profile");
        for (NSString *key in profile) check([TSKnownPreferenceKeys() containsObject:key],"classify every bundled key");
        TSPreferenceProfile *proposal = [[TSPreferenceProfile alloc] initWithProfile:profile documentFont:font];
        check(proposal != nil,"valid profile");
        for (NSNumber *withPreservedValues in @[@NO,@YES]) {
            ObservedDefaults *defaults=[ObservedDefaults new];
            NSDictionary *kept=@{@"TSMenuShortcutOverrides":@{@"example":@1},@"NSUserKeyEquivalents":@{@"Menu":@"@1"},
                @"AppleLanguages":@[@"ja"],@"SparkleAutomaticUpdate":@YES,@"SparkleInterval":@3,
                @"SUEnableAutomaticChecks":@YES,@"SUHasLaunchedBefore":@YES,@"SUScheduledCheckInterval":@99,
                @"NSWindow Frame Settings":@"frame",@"NSToolbar Configuration PDF":@{@"x":@1},
                @"NSSplitView Subview Frames A":@[@"frame"],@"TSSettingsUICategory":@"source",@"UnknownVendorKey":@"keep"};
            if (withPreservedValues.boolValue) [defaults.values addEntriesFromDictionary:kept];
            defaults.values[@"DockIconStyle"]=@"classic";
            defaults.values[@"TeXAwareSpellChecking"]=@NO;
            defaults.values[@"TSHasBeenUsed"]=@NO;
            defaults.values[@"DocumentFontAttributes"]=@"old";
            defaults.values[@"AltPath"]=@"stale";defaults.values[@"AutoReloadExternalPDF"]=@NO;
            // Exercise every B key, including hidden preferences absent from all profiles.
            for (NSString *key in TSKnownPreferenceKeys())
                if (profile[key] == nil && !TSPreferenceProfilePreservesKey(key)) defaults.values[key]=@"stale";
            [defaults registerDefaults:@{@"TeXAwareSpellChecking":@YES}];
            __block NSUInteger visible=0,intermediate=0;
            id token=[NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:defaults queue:nil usingBlock:^(NSNotification *note) {
                if (TSPreferenceProfileIsApplying()) { intermediate++; return; }
                visible++;
                check([defaults boolForKey:@"TSHasBeenUsed"],"observers see completed profile");
            }];
            [proposal applyToDefaults:defaults];
            [NSNotificationCenter.defaultCenter removeObserver:token];
            check(visible==1 && intermediate>0,"one coherent observer update");
            for (NSString *key in kept) check(withPreservedValues.boolValue ? [defaults.values[key] isEqual:kept[key]] : defaults.values[key]==nil,"C values and absence preserved");
            for (NSString *key in profile) if (!TSPreferenceProfilePreservesKey(key) && ![key isEqual:@"DocumentFontAttributes"] && ![key isEqual:@"DocumentFont"] && ![key isEqual:@"TSHasBeenUsed"] && ![key isEqual:@"ConvertToYen"])
                check([defaults.values[key] isEqual:profile[key]],"A profile override");
            for (NSString *key in TSKnownPreferenceKeys()) {
                if (profile[key] == nil && !TSPreferenceProfilePreservesKey(key) &&
                    ![@[@"DocumentFont",@"TSHasBeenUsed",@"ConvertToYen"] containsObject:key])
                    check(defaults.values[key]==nil,"every B key resets including hidden settings");
            }
            check([defaults boolForKey:@"ConvertToYen"],"generated yen conversion default");
            check(defaults.values[@"AutoReloadExternalPDF"]==nil,"hidden PDF reload preference is B not preserved");
            check(defaults.values[@"DockIconStyle"]==nil,"B Dock defaults to current");
            check(defaults.values[@"DocumentFontAttributes"]==nil && [defaults.values[@"DocumentFont"] isEqual:font],"font generation");
            if (profile[@"TeXAwareSpellChecking"]==nil) check([defaults boolForKey:@"TeXAwareSpellChecking"],"B registered default");
            check([defaults.stringForKey isEqual:nil],"unused");
        }
    }
    ObservedDefaults *firstLaunch=[ObservedDefaults new];
    NSDictionary *factory=@{@"AntiAlias":@YES,@"DocumentWindowFixedPos":@"factory-position"};
    [firstLaunch setBool:NO forKey:@"AntiAlias"];
    TSPreferenceProfile *first=[[TSPreferenceProfile alloc]initWithProfile:@{@"TetexBinPath":@"/test/bin"} documentFont:font registeredDefaults:factory];
    [first applyToDefaults:firstLaunch];
    check([firstLaunch boolForKey:@"AntiAlias"] && [[firstLaunch stringForKey:@"DocumentWindowFixedPos"] isEqual:@"factory-position"],"first launch registers absent factory defaults during apply");
    check([[TSPreferenceProfile alloc] initWithProfile:@{} documentFont:font]==nil,"reject missing engine path");
    check([[TSPreferenceProfile alloc] initWithProfile:@{@"TetexBinPath":@"  "} documentFont:font]==nil,"reject empty engine path");
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
    puts("PASS: all nine profile policies, isolated defaults, input validation, safe theme persistence");
} return 0; }
'''.replace('            check([defaults.stringForKey isEqual:nil],"unused");','')
with tempfile.TemporaryDirectory(prefix='texshop-live-core-',dir='/private/tmp') as tmp:
 t=Path(tmp);(t/'probe.m').write_text(program)
 for name,body in sources.items():(t/name).write_text(body)
 args=['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-deprecated-declarations','-Wnullability-completeness','-Wnullable-to-nonnull-conversion','-Wunguarded-availability-new','-I',str(ROOT/'Sources'),'-I',str(ROOT/'Tests'),'-framework','Cocoa',str(t/'probe.m'),*[str(t/n) for n in sources],'-o',str(t/'probe')]
 subprocess.run(args,check=True)
 themes=t/'Colors';themes.mkdir()
 profiles=sorted((ROOT/'Resources/Shellscripts').glob('*Defaults*.plist'));assert len(profiles)==9
 subprocess.run([str(t/'probe'),str(themes),*map(str,profiles)],check=True)
