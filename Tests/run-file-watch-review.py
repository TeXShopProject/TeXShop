#!/usr/bin/env python3
"""Exercise the real watcher/revert methods with a minimal NSDocument model."""
from pathlib import Path
import subprocess,tempfile,os
root=Path(__file__).resolve().parents[1]
base=subprocess.check_output(['git','show','46df39d:Sources/TSDocument.m'],cwd=root,text=True)
patched=(root/'Sources/TSDocument.m').read_text()
def methods(s,pr):
 start=s.index('- (NSString *)fileSignatureAtPath:') if pr else s.index('- (void)watchFile:')
 watch=s[start:s.index('//END PATCH',start)]
 start=s.index('- (BOOL)revertToContentsOfURL:')
 revert=s[start:s.index('//ULRICH BAUER PATCH\n- (void)revertDocumentToSaved:',start)]
 return watch+'\n'+revert
program=r'''
#import <Cocoa/Cocoa.h>
#import <fcntl.h>
#import <unistd.h>
static BOOL activateBauerPatch=YES;
static NSString *WatchServerKey=@"watch";
@interface Preferences : NSObject
- (BOOL)boolForKey:(NSString *)key;
@end
@implementation Preferences
- (BOOL)boolForKey:(NSString *)key { return YES; }
@end
#define SUD ([Preferences new])
@interface TSDocument : NSDocument {
@public dispatch_source_t dispatch_source;
NSString *watchedFileSignature;
NSUInteger watchReloadGeneration;
NSView *textView;
}
@property NSString *observed;
@property BOOL inject, preserveTime;
@property NSUInteger reads;
- (void)watchFile:(NSString *)path;
- (void)cancelWatchFile;
- (void)setupTags;
- (void)colorizeAll;
@end
@implementation TSDocument
- (void)setupTags {}
- (void)colorizeAll {}
METHODS
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
SIGNATURE
 NSData *data=[NSData dataWithContentsOfURL:url];
 if(self.inject) {
  self.inject=NO;
  NSDictionary *attrs=[[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:NULL];
  [@"complete" writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:NULL];
  if(self.preserveTime) [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate:attrs[NSFileModificationDate]} ofItemAtPath:url.path error:NULL];
 }
 [self watchFile:url.path];
 self.observed=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
 self.reads++;
 return data!=nil;
}
@end
static void Pump(double seconds) {
 NSDate *until=[NSDate dateWithTimeIntervalSinceNow:seconds];
 while(until.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
int main(int argc,char **argv) { @autoreleasepool {
 NSString *path=@(argv[1]),*mode=@(argv[2]);
 [@"initial!" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
 TSDocument *d=[TSDocument new];d.fileURL=[NSURL fileURLWithPath:path];d.fileType=@"public.text";
 [d readFromURL:d.fileURL ofType:d.fileType error:NULL];
 if([mode hasPrefix:@"gap"]) {
  d.inject=YES;d.preserveTime=[mode isEqualToString:@"gap-preserved-time"];
  [@"partial!" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
 } else if([mode isEqualToString:@"dirty"]) {
  [@"complete" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
  Pump(.03);[d updateChangeCount:NSChangeDone];d.observed=@"USER EDIT";
 } else if([mode isEqualToString:@"atomic"]) {
  [@"complete" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 } else {
  for(int i=0;i<12;i++) {
   [[NSString stringWithFormat:@"chunk-%d",i] writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];Pump(.02);
  }
  [@"complete" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
 }
 Pump(1.5);
 printf("%s: observed=%s reads=%lu\n",mode.UTF8String,d.observed.UTF8String,(unsigned long)d.reads);
 [d cancelWatchFile];return 0;
} }
'''
with tempfile.TemporaryDirectory(prefix='ts-watch-review-') as td:
 p=Path(td)
 for label,s,pr in [('baseline',base,False),('PR',patched,True)]:
  code=program.replace('METHODS',methods(s,pr)).replace('SIGNATURE','watchedFileSignature = [self fileSignatureAtPath:url.path];' if pr else '')
  (p/'test.m').write_text(code)
  subprocess.run(['xcrun','clang','-fobjc-arc','-w','-framework','Cocoa',str(p/'test.m'),'-o',str(p/'test')],check=True)
  for mode in ['gap','chunks','dirty','atomic','gap-preserved-time']:
   result=subprocess.run([str(p/'test'),str(p/'data.txt'),mode],capture_output=True,text=True,timeout=12,env=dict(os.environ,CFFIXED_USER_HOME=str(p/'home')))
   print(label,result.stdout.strip(), 'exit='+str(result.returncode),flush=True)
   if result.returncode: print(result.stderr)
