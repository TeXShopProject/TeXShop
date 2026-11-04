#!/usr/bin/env python3
"""Regression based on the independent audit's NSDocument save probe.
Uses temporary documents; never starts TeXShop or writes application defaults.
"""
import os, subprocess, sys, tempfile
from pathlib import Path

REPO = str(Path(__file__).resolve().parents[1])
_temp = tempfile.TemporaryDirectory(prefix='texshop-save-watch-')
OUT = Path(_temp.name)
OUT.mkdir(parents=True, exist_ok=True)

def show(rev, path):
    return (Path(REPO) / path).read_text()

def cut(s, start, end):
    a = s.index(start); b = s.index(end, a); return s[a:b]

def methods(rev, variant):
    s = show(rev, 'Sources/TSDocument.m')
    w = cut(s, '- (NSString *)fileSignatureAtPath:' if variant == 'pr' else '- (void)watchFile:', '//END PATCH')
    wr = cut(s, '- (BOOL)writeToURL:', '// zenitani 2.10 (A) -- decode utf.sty')
    rv = cut(s, '- (BOOL)revertToContentsOfURL:', '//ULRICH BAUER PATCH\n- (void)revertDocumentToSaved:')
    return w + '\n' + wr + '\n' + rv

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/xattr.h>
#import <sys/stat.h>
#ifdef V5
#import "TSFileChangeMonitor.h"
#endif
BOOL activateBauerPatch=YES;
static void Pump(double s){NSDate *t=[NSDate dateWithTimeIntervalSinceNow:s];while(t.timeIntervalSinceNow>0)[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
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
#ifdef V5
 TSFileChangeMonitor *sourceFileMonitor;
 NSData *sourceAcceptedFingerprint, *sourceWrittenFingerprint, *sourceReloadData;
 BOOL sourceSaving;
#endif
 NSTextView *textView;
}
@property NSTextStorage *storage;
@property NSUInteger reads;
@property BOOL injectOnce;
- (void)watchFile:(NSString *)path;
- (void)cancelWatchFile;
@end
@implementation TSDocument
+ (BOOL)autosavesInPlace { return YES; }
+ (BOOL)preservesVersions { return NO; } // Versions ストアへの書込みを避けるため
+ (NSArray *)readableTypes { return @[@"public.plain-text"]; }
+ (NSArray *)writableTypes { return @[@"public.plain-text"]; }
+ (BOOL)isNativeType:(NSString *)t { return YES; }
- (void)setupTags {}
- (void)colorizeAll {}
- (BOOL)doNotReadSource { return NO; }
METHODS
- (NSData *)dataOfType:(NSString *)type error:(NSError **)e { NSData *d=[self.storage.string dataUsingEncoding:NSUTF8StringEncoding]; if(sourceSaving) sourceWrittenFingerprint=TSSourceFingerprint(d); return d; }
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)e {
 PRE
 NSData *d=sourceReloadData ?: [NSData dataWithContentsOfURL:url options:0 error:e]; if(!d) return NO;
 if(self.injectOnce){ self.injectOnce=NO; [@"complete-longer" writeToFile:url.path atomically:NO encoding:NSUTF8StringEncoding error:NULL]; }
 POST
 if(!self.storage) self.storage=[NSTextStorage new];
 [[self.storage mutableString] setString:[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]];
 sourceAcceptedFingerprint=TSSourceFingerprint(d); self.reads++; return YES;
}
- (void)setText:(NSString *)s { [[self.storage mutableString] setString:s]; }
- (void)edit:(NSString *)s {
 NSUndoManager *u=self.undoManager; u.groupsByEvent=NO; [u beginUndoGrouping];
 [[u prepareWithInvocationTarget:self] setText:self.storage.string];
 [u endUndoGrouping]; [self setText:s]; Pump(.3);
}
@end
static BOOL Save(TSDocument *d, NSURL *u, NSSaveOperationType op){
 __block BOOL done=NO; __block NSError *err=nil;
 [d saveToURL:u ofType:d.fileType forSaveOperation:op completionHandler:^(NSError *e){err=e;done=YES;}];
 for(int i=0;i<300&&!done;i++) Pump(.01);
 if(err) fprintf(stderr,"save error %s\n",err.description.UTF8String);
 return done&&!err;
}
static int CountFDs(void){int n=0;for(int fd=0;fd<4096;fd++) if(fcntl(fd,F_GETFD)!=-1) n++; return n;}
int main(int argc,char **argv){@autoreleasepool{
 [NSApplication sharedApplication];
 NSString *path=@(argv[1]),*mode=@(argv[2]);
 [@"initial!" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
 NSURL *url=[NSURL fileURLWithPath:path];
 TSDocument *d=nil; NSError *e=nil;
 if([mode isEqualToString:@"initial-gap"]){
  d=[TSDocument alloc]; d=[d init]; d.injectOnce=YES; d.fileType=@"public.plain-text";
  // initWithContentsOfURL: 相当の順序 (read -> setFileURL)
  [d readFromURL:url ofType:d.fileType error:&e]; d.fileURL=url;
  Pump(2.6);
  printf("%s reads=%lu text=%s\n",mode.UTF8String,(unsigned long)d.reads,d.storage.string.UTF8String);
  [d cancelWatchFile]; return 0;
 }
 d=[[TSDocument alloc] initWithContentsOfURL:url ofType:@"public.plain-text" error:&e];
 if(!d){fprintf(stderr,"open failed %s\n",e.description.UTF8String);return 2;}
 Pump(.3);
 NSUInteger r0=d.reads;
 if([mode isEqualToString:@"save"]||[mode isEqualToString:@"autosave"]){
  [d edit:@"edited by user"];
  BOOL ok=Save(d,url,[mode isEqualToString:@"save"]?NSSaveOperation:NSAutosaveInPlaceOperation);
  BOOL undoBefore=d.undoManager.canUndo; BOOL editedAfter=d.isDocumentEdited;
  Pump(3.0); printf("editedAfterSave=%d ",editedAfter);
  printf("%s saved=%d extraReads=%lu canUndoAfterSave=%d canUndoNow=%d text=%s\n",mode.UTF8String,ok,(unsigned long)(d.reads-r0),undoBefore,d.undoManager.canUndo,d.storage.string.UTF8String);
 } else if([mode isEqualToString:@"saveas"]){
  NSURL *nu=[NSURL fileURLWithPath:[path stringByAppendingString:@".new.tex"]];
  [d edit:@"saved as"]; BOOL ok=Save(d,nu,NSSaveAsOperation); Pump(.6);
  NSUInteger r1=d.reads;
  [@"old path write" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL]; Pump(2.5);
  NSUInteger r2=d.reads;
  [@"new path write" writeToFile:nu.path atomically:YES encoding:NSUTF8StringEncoding error:NULL]; Pump(2.5);
  printf("%s saved=%d readsAfterSaveAs=%lu oldPathWriteReads=%lu newPathWrite text=%s fileURL=%s\n",mode.UTF8String,ok,(unsigned long)(r1-r0),(unsigned long)(r2-r1),d.storage.string.UTF8String,d.fileURL.lastPathComponent.UTF8String);
 } else if([mode isEqualToString:@"save-then-external"]){
  [d edit:@"edited by user"]; BOOL ok=Save(d,url,NSSaveOperation); Pump(3.0); NSUInteger r1=d.reads;
  [@"external after save" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL]; Pump(1.5);
  printf("%s saved=%d readsAfterOwnSave=%lu readsAfterExternal=%lu text=%s\n",mode.UTF8String,ok,(unsigned long)(r1-r0),(unsigned long)(d.reads-r1),d.storage.string.UTF8String);
 } else if([mode isEqualToString:@"xattr"]){
  setxattr(path.fileSystemRepresentation,"com.example.audit","1",1,0,0); Pump(2.6);
  printf("%s extraReads=%lu\n",mode.UTF8String,(unsigned long)(d.reads-r0));
 } else if([mode isEqualToString:@"chmod"]){
  chmod(path.fileSystemRepresentation,0600); Pump(2.6);
  printf("%s extraReads=%lu\n",mode.UTF8String,(unsigned long)(d.reads-r0));
 } else if([mode isEqualToString:@"external"]){
  [@"external content" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]; Pump(2.6);
  printf("%s extraReads=%lu text=%s\n",mode.UTF8String,(unsigned long)(d.reads-r0),d.storage.string.UTF8String);
 } else if([mode isEqualToString:@"dirty-external-autosave"]){
  // 未保存編集中に外部変更 -> その後 TeXShop の自動保存 -> 外部内容はどうなるか
  [d edit:@"user edit"]; Pump(.1);
  [@"external content" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]; Pump(.6);
  NSString *t1=d.storage.string;
  BOOL ok=Save(d,url,NSAutosaveInPlaceOperation); Pump(2.6);
  NSString *disk=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  printf("%s beforeAutosave=%s autosaved=%d editor=%s disk=%s extraReads=%lu\n",mode.UTF8String,t1.UTF8String,ok,d.storage.string.UTF8String,disk.UTF8String,(unsigned long)(d.reads-r0));
 } else if([mode isEqualToString:@"fdleak"]){
  int before=CountFDs();
  for(int i=0;i<300;i++){[d cancelWatchFile];[d watchFile:path];}
  Pump(.5); int mid=CountFDs(); [d cancelWatchFile]; Pump(.5); int after=CountFDs();
  printf("%s fdsBefore=%d after300Rewatch=%d afterCancel=%d\n",mode.UTF8String,before,mid,after);
 }
 [d cancelWatchFile]; return 0;
}}
'''

variants = {
    'branch5': ('17c4123', '[self watchFile:([self fileURL] ?: url).path];', '', ['-DV5']),
}
monitor = OUT / 'TSFileChangeMonitor.m'
(OUT / 'TSFileChangeMonitor.m').write_text(show('17c4123', 'Sources/TSFileChangeMonitor.m'))
(OUT / 'TSFileChangeMonitor.h').write_text(show('17c4123', 'Sources/TSFileChangeMonitor.h'))
modes = sys.argv[1:] or ['save', 'autosave', 'saveas', 'xattr', 'chmod', 'external', 'initial-gap', 'save-then-external', 'fdleak']
for name, (rev, pre, post, flags) in variants.items():
    src = PROGRAM.replace('METHODS', methods(rev, name)).replace('PRE', pre).replace('POST', post)
    m = OUT / f'{name}.m'; m.write_text(src)
    exe = OUT / name
    cmd = ['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I' + str(OUT), *flags, str(m)]
    if name == 'branch5': cmd.append(str(monitor))
    subprocess.run(cmd + ['-o', str(exe)], check=True)
    for mode in modes:
        if mode == 'fdleak' and name != 'branch5': continue
        with tempfile.TemporaryDirectory(dir=OUT) as td:
            p = Path(td) / 'source.tex'
            r = subprocess.run([str(exe), str(p), mode], capture_output=True, text=True, timeout=30,
                               env=os.environ.copy())
            print(f'{name:8} {r.stdout.strip()} exit={r.returncode}', flush=True)
            if r.returncode or r.stderr.strip():
                print('   stderr:', r.stderr.strip()[:600])

            assert r.returncode == 0, r.stderr
            expected = {
                'save': ['saved=1 extraReads=0 canUndoAfterSave=1 canUndoNow=1'],
                'autosave': ['saved=1 extraReads=0 canUndoAfterSave=1 canUndoNow=1'],
                'saveas': ['saved=1 readsAfterSaveAs=0 oldPathWriteReads=0', 'text=new path write'],
                'xattr': ['extraReads=0'], 'chmod': ['extraReads=0'],
                'external': ['extraReads=1 text=external content'],
                'initial-gap': ['text=complete-longer'],
                'save-then-external': ['readsAfterOwnSave=0 readsAfterExternal=1 text=external after save'],
            }
            for value in expected.get(mode, []):
                assert value in r.stdout, (mode, value, r.stdout)
print('PASS: real NSDocument save / autosave / Save As retain undo; external writes still reload')
