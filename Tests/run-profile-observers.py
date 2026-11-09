#!/usr/bin/env python3
"""Production observers must ignore every intermediate write in a real profile apply."""
from pathlib import Path
import subprocess,tempfile
R=Path(__file__).resolve().parents[1]
def method(file,sig):
 s=(R/'Sources'/file).read_text(encoding='latin1');a=s.rindex('\n'+sig)+1;return s[a:s.index('\n}',a)+2]
a=method('MyPDFKitView.m','- (void)previewAppearanceDefaultsChanged:');b=method('TSDocument.m','- (void)externalPDFSettingsChanged:')
program=r'''
#import <Cocoa/Cocoa.h>
#import "MemoryDefaults.h"
#import "TSPreferenceProfile.h"
static TSMemoryDefaults *memory;
#define SUD memory
#define RefreshTimeKey @"RefreshTime"
static void check(BOOL ok,const char *why){if(!ok){fprintf(stderr,"FAIL: %s\n",why);exit(1);}}
@interface ObservedDefaults:TSMemoryDefaults @end
@implementation ObservedDefaults
- (void)setObject:(id)value forKey:(NSString *)key {[super setObject:value forKey:key];[NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];}
- (void)removeObjectForKey:(NSString *)key {[super removeObjectForKey:key];[NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];}
@end
@interface Probe:NSObject
@property NSUInteger appearances,observations;
@property NSTimer *pdfRefreshTimer;
@end
@implementation Probe
- (void)updateDarkModeInversion {check(!TSPreferenceProfileIsApplying(),"appearance observer must not read intermediate profile");self.appearances++;}
- (BOOL)externalPDFObservationEnabled {return YES;}
- (void)startExternalPDFObservation {check(!TSPreferenceProfileIsApplying(),"PDF watch must not restart during profile writes");self.observations++;}
METHODS
@end
int main(void){@autoreleasepool{
 memory=[ObservedDefaults new];Probe *p=[Probe new];__block NSUInteger notes=0;
 id token=[NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:memory queue:nil usingBlock:^(NSNotification *n){notes++;[p previewAppearanceDefaultsChanged:n];[p externalPDFSettingsChanged:n];}];
 TSPreferenceProfile *profile=[[TSPreferenceProfile alloc]initWithProfile:@{@"TetexBinPath":@"/test",@"RefreshTime":@1} documentFont:[@"font" dataUsingEncoding:NSUTF8StringEncoding]];
 [profile applyToDefaults:memory];
 check(notes>100 && p.appearances==1 && p.observations==1,"each observer reconciles exactly once after all profile writes");
 [NSNotificationCenter.defaultCenter removeObserver:token];puts("PASS: real appearance and external PDF observers defer intermediate profile notifications");
}return 0;}
'''.replace('METHODS',a+'\n'+b)
with tempfile.TemporaryDirectory(prefix='texshop-profile-observers-') as td:
 p=Path(td);(p/'test.m').write_text(program)
 subprocess.run(['xcrun','clang','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fobjc-arc','-I',str(R/'Sources'),'-I',str(R/'Tests'),'-framework','Cocoa',str(p/'test.m'),str(R/'Sources/TSPreferenceProfile.m'),str(R/'Sources/globals.m'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
