#!/usr/bin/env python3
"""Test production monitor and document integration without opening user documents."""
from pathlib import Path
import os
import subprocess
import tempfile
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
s = (root / 'Sources/Document/TSDocument.m').read_text()
a = s.index('- (void)watchFile:')
b = s.index('//END PATCH', a)
watch_methods = s[a:b]
a = s.index('- (BOOL)revertToContentsOfURL:')
b = s.index('//ULRICH BAUER PATCH\n- (void)revertDocumentToSaved:', a)
revert_method = s[a:b]
assert s.index('[self watchFile:([self fileURL] ?: absoluteURL).path]') < s.index('myData = sourceReloadData ?: [NSData dataWithContentsOfURL:absoluteURL options:')
assert '[self cancelWatchFile]' not in s[s.index('- (BOOL)writeToURL:'):s.index('- (BOOL)revertToContentsOfURL:', s.index('- (BOOL)writeToURL:'))]
assert '[self cancelWatchFile]' in s[s.index('- (void)close\n'):s.index('[super close]', s.index('- (void)close\n'))]
program = r'''
#import <Cocoa/Cocoa.h>
#import "TSFileChangeMonitor.h"
#import <unistd.h>
static BOOL activateBauerPatch=YES;
static NSString *writerScript, *python;
static void Write(NSString *path, NSString *mode, NSString *value) {
 NSTask *t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:python];
 t.arguments=@[writerScript,path,mode,value];[t launchAndReturnError:NULL];
 // Do not pump the run loop while simulating a write during a synchronous read.
 while(t.running) usleep(1000);
 [t waitUntilExit];
 NSCAssert(t.terminationStatus==0,@"Writer failed");
}
@interface TSDocument : NSDocument {
 TSFileChangeMonitor *sourceFileMonitor;
 NSData *sourceAcceptedFingerprint, *sourceWrittenFingerprint, *sourceReloadData, *sourceReloadFingerprint;
 NSUInteger sourceIOGeneration;
 BOOL sourceSaving;
 NSView *textView;
}
@property NSString *observed, *injectMode;
@property NSUInteger reads;
@property BOOL dirty, failRead;
- (void)watchFile:(NSString *)path;
- (void)cancelWatchFile;
@end
@implementation TSDocument
WATCH
REVERT
- (void)setupTags {}
- (void)colorizeAll {}
- (BOOL)hasUnautosavedChanges {return self.dirty;}
- (BOOL)doNotReadSource {return [self.fileURL.pathExtension isEqual:@"pdf"];}
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
 [self watchFile:(self.fileURL ?: url).path];
 if (self.failRead) return NO;
 NSData *data=sourceReloadData ?: [NSData dataWithContentsOfURL:url];
 if (!data) return NO;
 if(self.injectMode) {NSString *mode=self.injectMode;self.injectMode=nil;Write(url.path,mode,@"complete");}
 sourceAcceptedFingerprint=sourceReloadFingerprint ?: TSSourceFingerprint(data); ++sourceIOGeneration;
 self.observed=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];self.reads++;
 return YES;
}
- (void)dealloc {[sourceFileMonitor stop];}
@end
static void Pump(double seconds) {
 NSDate *until=[NSDate dateWithTimeIntervalSinceNow:seconds];
 while(until.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
static void Check(BOOL value, NSString *message) {if(!value){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
int main(int argc,char **argv) {@autoreleasepool {
 NSString *path=@(argv[1]), *mode=@(argv[2]);python=@(argv[3]);writerScript=@(argv[4]);
 Write(path,@"plain",@"initial!");
 TSDocument *d=[TSDocument new];d.fileType=@"public.text";d.fileURL=[NSURL fileURLWithPath:path];
 if([mode isEqualToString:@"initial"]) d.injectMode=@"preserved";
 [d readFromURL:d.fileURL ofType:d.fileType error:NULL];
 Pump(.3);
 if([mode isEqualToString:@"initial"]) {
  Check([d.observed isEqual:@"complete"],@"initial comparison closes asynchronous registration gap");
 } else if([mode isEqualToString:@"preserved"] || [mode isEqualToString:@"atomic"]) {
  d.injectMode=mode;Write(path,@"plain",@"partial!");Pump(.6);
  Check([d.observed isEqual:@"complete"],@"update during reload");
  Write(path,mode,@"last!!!!");Pump(.4);Check([d.observed isEqual:@"last!!!!"],@"watch retained/rebound");
 } else if([mode isEqualToString:@"dirty"]) {
  d.dirty=YES;d.observed=@"USER EDIT";Write(path,@"atomic",@"complete");Pump(.5);
  Check([d.observed isEqual:@"USER EDIT"],@"unsaved edits preserved");
  d.dirty=NO;Pump(2.5);Check([d.observed isEqual:@"complete"],@"pending event retried without a second write");
 } else if([mode isEqualToString:@"missing"]) {
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];Pump(1.3);
  Check([d.observed isEqual:@"initial!"],@"temporary deletion retains content");
  Write(path,@"plain",@"complete");Pump(.5);Check([d.observed isEqual:@"complete"],@"recreation");
 } else if([mode isEqualToString:@"siblings"]) {
  NSUInteger n=d.reads;
  for(int i=0;i<15;i++){Write([path stringByAppendingString:@".sibling"],@"atomic",@"unrelated");Pump(.02);}
  Pump(2.3);Check(d.reads==n,@"unrelated directory activity does not read document");
 } else if([mode isEqualToString:@"chunks"]) {
  NSUInteger n=d.reads;
  NSTask *t=[NSTask new];t.executableURL=[NSURL fileURLWithPath:python];
  t.arguments=@[writerScript,path,@"chunks",@"complete"];[t launchAndReturnError:NULL];
  Pump(1);[t waitUntilExit];Pump(.3);
  Check([d.observed isEqual:@"complete"] && d.reads-n<=2,@"burst coalescing");
 } else if([mode isEqualToString:@"retry"]) {
  d.failRead=YES;Write(path,@"plain",@"complete");Pump(.5);d.failRead=NO;Pump(2.4);
  Check([d.observed isEqual:@"complete"],@"failed read retried");
 } else if([mode isEqualToString:@"retarget"]) {
  NSString *other=[path stringByAppendingString:@".new"];Write(other,@"plain",@"new!!!!!");
  d.fileURL=[NSURL fileURLWithPath:other];[d readFromURL:d.fileURL ofType:d.fileType error:NULL];
  NSUInteger n=d.reads;Write(path,@"plain",@"old!!!!!");Pump(.4);Check(d.reads==n,@"old path ignored");
  Write(other,@"atomic",@"complete");Pump(.4);Check([d.observed isEqual:@"complete"],@"new path watched");
 } else if([mode isEqualToString:@"parent"]) {
  NSString *parent=path.stringByDeletingLastPathComponent;
  [[NSFileManager defaultManager] moveItemAtPath:parent toPath:[parent stringByAppendingString:@".old"] error:NULL];
  [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:NULL];
  Write(path,@"plain",@"complete");Pump(2.5);
  Check([d.observed isEqual:@"complete"],@"parent directory replacement");
 } else if([mode isEqualToString:@"preview-only"]) {
  NSString *pdf=[path stringByAppendingPathExtension:@"pdf"];
  Write(pdf,@"plain",@"initial!");d.fileURL=[NSURL fileURLWithPath:pdf];
  NSUInteger n=d.reads;Write(pdf,@"plain",@"complete");Pump(2.4);
  Check(d.reads==n,@"preview-only files are not monitored as source");
 } else if([mode isEqualToString:@"large-idle"]) {
  Write(path,@"large",@"complete");Pump(.7);NSUInteger n=d.reads;
  Check(d.observed.length==32*1024*1024,@"large file read");
  Pump(4.3);Check(d.reads==n,@"idle polling does not reread large content");
 } else if([mode isEqualToString:@"stop"]) {
  Write(path,@"plain",@"complete");Pump(.03);NSUInteger n=d.reads;[d cancelWatchFile];Pump(.5);
  Check(d.reads==n,@"no callback after stop");
 } else if([mode isEqualToString:@"lifetime"]) {
  [d cancelWatchFile];
  __weak TSFileChangeMonitor *weak;
  @autoreleasepool {
   TSFileChangeMonitor *monitor=[[TSFileChangeMonitor alloc] initWithPath:path prepare:^NSNumber *{return @0;} accept:^BOOL(NSData *d,NSData *f,NSNumber *g){return YES;}];
   weak=monitor;monitor=nil;
  }
  Pump(.3);Check(weak==nil,@"no watcher retain cycle");
 }
 printf("PASS %s reads=%lu\n",mode.UTF8String,(unsigned long)d.reads);
 [d cancelWatchFile];return 0;
}}
'''
writer = '''import os,sys,time
p,mode,value=sys.argv[1:]
if mode=='chunks':
 for i in range(10):
  with open(p,'wb') as f: f.write(('chunk'+str(i)).encode())
  time.sleep(.02)
old=os.stat(p) if mode=='preserved' else None
if mode=='large': value='x'*(32*1024*1024)
out=p+'.tmp' if mode=='atomic' else p
with open(out,'wb') as f: f.write(value.encode())
if mode=='atomic': os.replace(out,p)
if old: os.utime(p,ns=(old.st_atime_ns,old.st_mtime_ns))
'''
with tempfile.TemporaryDirectory(prefix='ts-continuous-watch-') as td:
    p = Path(td)
    (p/'test.m').write_text(program.replace('WATCH',watch_methods).replace('REVERT',revert_method))
    (p/'writer.py').write_text(writer)
    subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa',*include_args(root), str(p/'test.m'),str(root/'Sources/Document/TSFileChangeMonitor.m'),'-o',str(p/'test')],check=True)
    import sys
    for mode in ['initial','preserved','atomic','dirty','missing','siblings','chunks','retry','retarget','parent','preview-only','large-idle','stop','lifetime']:
        directory=p/mode;directory.mkdir()
        subprocess.run([str(p/'test'),str(directory/'source.tex'),mode,sys.executable,str(p/'writer.py')],check=True,timeout=15,env=dict(os.environ,CFFIXED_USER_HOME=str(p/'home')))
