#!/usr/bin/env python3
"""Exercise production read, save, revert and watch methods through NSDocument.
Adapted from the independent second audit. Only text encoding and UI dependencies
are stubbed; fingerprint adoption and save/reload ordering come from TSDocument.
Use --revision to verify historical regressions, --mutation to test sensitivity.
"""
import argparse, os, re, subprocess, tempfile
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('--revision')
parser.add_argument('--mutation', choices=['read-baseline', 'write-baseline', 'disk-baseline', 'generation'])
parser.add_argument('modes', nargs='*')
args = parser.parse_args()
REPO = Path(__file__).resolve().parents[1]
_temp = tempfile.TemporaryDirectory(prefix='texshop-save-watch-')
OUT = Path(_temp.name)
def show(rev, path):
    text = (subprocess.check_output(['git', 'show', f'{rev}:{path}'], cwd=REPO, text=True)
            if rev else (REPO / path).read_text())
    if path == 'Sources/TSDocument.m':
        if args.mutation == 'generation':
            text, count = re.subn(r'generation.unsignedIntegerValue != document->sourceIOGeneration \|\|', '', text)
            if count != 1: raise SystemExit('generation replacement count')
        elif args.mutation == 'read-baseline':
            text, count = re.subn(r'sourceAcceptedFingerprint = (?:sourceReloadFingerprint \?: )?TSSourceFingerprint\(myData\);', '', text)
            if count != 1: raise SystemExit('read-baseline replacement count')
        elif args.mutation == 'write-baseline':
            old = 'sourceWrittenFingerprint = TSSourceFingerprint(data);'
            if text.count(old) != 1: raise SystemExit('write-baseline replacement count')
            text = text.replace(old, '')
        elif args.mutation == 'disk-baseline':
            if text.count('sourceAcceptedFingerprint = sourceWrittenFingerprint;') != 1: raise SystemExit('disk-baseline replacement count')
            text = text.replace('sourceAcceptedFingerprint = sourceWrittenFingerprint;',
                'sourceAcceptedFingerprint = TSSourceFingerprint([NSData dataWithContentsOfURL:url]);')
    return text
def cut(s, start, end):
    a = s.index(start); b = s.index(end, a); return s[a:b]

def methods(rev, variant):
    s = show(rev, 'Sources/TSDocument.m')
    w = cut(s, '- (NSString *)fileSignatureAtPath:' if variant == 'pr' else '- (void)watchFile:', '//END PATCH')
    rd = cut(s, '- (BOOL)readFromURL: (NSURL *)absoluteURL', '- (BOOL)writeToURL:')
    wr = cut(s, '- (BOOL)writeToURL:', '// zenitani 2.10 (A) -- decode utf.sty')
    wr = wr.replace('- (BOOL)writeToURL:', '- (BOOL)productionWriteToURL:')
    rv = cut(s, '- (BOOL)revertToContentsOfURL:', '//ULRICH BAUER PATCH\n- (void)revertDocumentToSaved:')
    if 'serializedSourceOfType' in s:
        dt = cut(s, '- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError\n{', '- (NSData *)serializedSourceOfType')
        dt += '- (NSData *)serializedSourceOfType:(NSString *)t error:(NSError **)e { return [_textStorage.string dataUsingEncoding:NSUTF8StringEncoding]; }\n'
    else:
        dt = '- (NSData *)dataOfType:(NSString *)t error:(NSError **)e { return [_textStorage.string dataUsingEncoding:NSUTF8StringEncoding]; }\n'
    return '\n'.join([w, rd, wr, rv, dt])

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/xattr.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <stdatomic.h>
#ifdef V5
#import "TSFileChangeMonitor.h"
#endif
BOOL activateBauerPatch=YES;
#define NSISOLatin9StringEncoding NSISOLatin1StringEncoding
static NSString *WatchServerKey=@"watch", *ConvertLFKey=@"convlf", *ptexUtfOutputEnabledKey=@"ptexutf", *UseOldHeadingCommandsKey=@"old";
static _Atomic(unsigned long) gContentReads=0; static double gMaxStall=0;
static int gInjectOnRead=0; static NSString *gInjectText=nil; static int gInjectHow=0;
static BOOL gInjectBeforeReturn=NO;
static _Atomic(int) gSlowRead=0, gReadStarted=0, gReleaseRead=0;
static _Atomic(int) gSlowStat=0, gStatStarted=0, gReleaseStat=0, gMainMonitorIO=0;
int TSProbeStat(const char *p,struct stat *s) {
 if(NSThread.isMainThread)gMainMonitorIO++;
 if(atomic_exchange(&gSlowStat,0)){gStatStarted=1;while(!gReleaseStat)usleep(10000);}
 return stat(p,s);
}
int TSProbeFstat(int fd,struct stat *s){if(NSThread.isMainThread)gMainMonitorIO++;return fstat(fd,s);}
int TSProbeOpen(const char*p,int flags){if(NSThread.isMainThread)gMainMonitorIO++;return open(p,flags);}
static int gInjectAfterSave=0; static NSString *gPath=nil;
static void Pump(double s){NSDate *t=[NSDate dateWithTimeIntervalSinceNow:s];while(t.timeIntervalSinceNow>0){CFAbsoluteTime a=CFAbsoluteTimeGetCurrent();[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];double d=CFAbsoluteTimeGetCurrent()-a-.01; if(d>gMaxStall)gMaxStall=d;}}
@interface Preferences : NSObject
- (BOOL)boolForKey:(NSString *)key;
@end
@implementation Preferences
- (BOOL)boolForKey:(NSString *)key { return [key isEqualToString:WatchServerKey]; }
@end
#define SUD ([Preferences new])
enum { OgreLfNewlineCharacter = 0 };
@interface OGRegularExpression : NSObject
+ (NSString *)replaceNewlineCharactersInString:(NSString *)s withCharacter:(int)c;
+ (id)regularExpressionWithString:(NSString *)s;
- (NSString *)replaceAllMatchesInString:(NSString *)s delegate:(id)d replaceSelector:(SEL)sel contextInfo:(id)c;
@end
@implementation OGRegularExpression
+ (NSString *)replaceNewlineCharactersInString:(NSString *)s withCharacter:(int)c { return s; }
+ (id)regularExpressionWithString:(NSString *)s { return [self new]; }
- (NSString *)replaceAllMatchesInString:(NSString *)s delegate:(id)d replaceSelector:(SEL)sel contextInfo:(id)c { return s; }
@end

static void ExtWrite(NSString *path, NSString *text, int how){
 NSData *d=[text dataUsingEncoding:NSUTF8StringEncoding];
 if(how==1){[d writeToFile:path atomically:YES]; return;}
 struct stat st; stat(path.fileSystemRepresentation,&st);
 int fd=open(path.fileSystemRepresentation, how==2? O_WRONLY : (O_WRONLY|O_TRUNC|O_CREAT), 0644);
 write(fd,d.bytes,d.length); close(fd);
 if(how==2){struct timeval tv[2]; TIMESPEC_TO_TIMEVAL(&tv[0],&st.st_atimespec); TIMESPEC_TO_TIMEVAL(&tv[1],&st.st_mtimespec); utimes(path.fileSystemRepresentation,tv);}
}
@interface TSDocument : NSDocument {
@public dispatch_source_t dispatch_source;
 NSString *watchedFileSignature;
 NSUInteger watchReloadGeneration;
#ifdef V5
 TSFileChangeMonitor *sourceFileMonitor;
#endif
#ifdef V6
 NSData *sourceAcceptedFingerprint, *sourceWrittenFingerprint, *sourceReloadData, *sourceReloadFingerprint;
 NSUInteger sourceIOGeneration;
 BOOL sourceSaving;
#endif
 NSTextView *textView;
 NSTextStorage *_textStorage;
 NSStringEncoding _encoding, _tempencoding, _badEncoding;
 BOOL showBadEncodingDialog, isLoading, firstTime;
}
@property NSUInteger reads;
@property (readonly) NSTextStorage *storage;
@property NSMutableArray *ops;
- (void)watchFile:(NSString *)path;
- (void)cancelWatchFile;
@end
@implementation TSDocument
+ (BOOL)autosavesInPlace { return YES; }
+ (BOOL)preservesVersions { return NO; }
+ (NSArray *)readableTypes { return @[@"public.plain-text"]; }
+ (NSArray *)writableTypes { return @[@"public.plain-text"]; }
+ (BOOL)isNativeType:(NSString *)t { return YES; }
- (instancetype)init { if((self=[super init])){ _textStorage=[NSTextStorage new]; _encoding=NSUTF8StringEncoding; _ops=[NSMutableArray new]; } return self; }
- (NSTextStorage *)storage { return _textStorage; }
- (void)setupTags {}
- (void)colorizeAll {}
- (BOOL)doNotReadSource { return NO; }
- (NSStringEncoding)dataEncoding:(NSData *)d {
 self.reads++;
 if(gInjectOnRead>0 && --gInjectOnRead==0) ExtWrite(gPath, gInjectText, gInjectHow);
 return NSUTF8StringEncoding;
}
- (void)saveToURL:(NSURL *)u ofType:(NSString *)t forSaveOperation:(NSSaveOperationType)op completionHandler:(void (^)(NSError *))h {
 [self.ops addObject:@(op)]; [super saveToURL:u ofType:t forSaveOperation:op completionHandler:h];
}
- (void)setFileModificationDate:(NSDate *)date {
 if(gInjectAfterSave){ int how=gInjectAfterSave-1; gInjectAfterSave=0; ExtWrite(self.fileURL.path, gInjectText, how); }
 [super setFileModificationDate:date];
}
METHODS
- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
 BOOL ok=[self productionWriteToURL:url ofType:type error:error];
 if(ok && gInjectBeforeReturn) {gInjectBeforeReturn=NO;ExtWrite(url.path,@"racing external",0);}
 return ok;
}
- (void)setText:(NSString *)s { [[_textStorage mutableString] setString:s]; }
- (void)edit:(NSString *)s {
 NSUndoManager *u=self.undoManager; u.groupsByEvent=NO; [u beginUndoGrouping];
 [[u prepareWithInvocationTarget:self] setText:_textStorage.string];
 [u endUndoGrouping]; [self setText:s]; Pump(.3);
}
@end
@interface TSDocProbe : TSDocument
@end
static NSString *gInjectBeforeSetURLPath=nil;
@implementation TSDocProbe
- (void)setFileURL:(NSURL *)u {
 if(gInjectBeforeSetURLPath && [u.path isEqualToString:gInjectBeforeSetURLPath]){ NSString *q=gInjectBeforeSetURLPath; gInjectBeforeSetURLPath=nil; ExtWrite(q,@"race on new path",0); }
 [super setFileURL:u];
}
@end
static id (*origDWCOU)(id,SEL,NSURL*,NSDataReadingOptions,NSError**);
static id countingDWCOU(id c,SEL s,NSURL *u,NSDataReadingOptions o,NSError **e){
 gContentReads++;
 id data=origDWCOU(c,s,u,o,e);
 if(!NSThread.isMainThread && atomic_exchange(&gSlowRead,0)) {
  gReadStarted=1;
  while(!gReleaseRead) usleep(10000);
 }
 return data;
}
static BOOL Save(TSDocument *d, NSURL *u, NSSaveOperationType op){
 __block BOOL done=NO; __block NSError *err=nil;
 [d saveToURL:u ofType:d.fileType forSaveOperation:op completionHandler:^(NSError *e){err=e;done=YES;}];
 for(int i=0;i<300&&!done;i++) Pump(.01);
 if(err) fprintf(stderr,"save error %ld %s\n",(long)err.code,err.localizedDescription.UTF8String);
 return done&&!err;
}
static NSString *Disk(NSString *p){ return [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL]; }
static int CountFDs(void){int n=0;for(int fd=0;fd<4096;fd++) if(fcntl(fd,F_GETFD)!=-1) n++; return n;}
static NSString *Short(NSString *s){ return s.length>40? [NSString stringWithFormat:@"<%lu chars>",(unsigned long)s.length] : s; }
int main(int argc,char **argv){@autoreleasepool{
 [NSApplication sharedApplication];
 Method m=class_getClassMethod([NSData class],@selector(dataWithContentsOfURL:options:error:));
 origDWCOU=(void*)method_getImplementation(m); method_setImplementation(m,(IMP)countingDWCOU);
 NSString *path=@(argv[1]),*mode=@(argv[2]); gPath=path; long mb=argc>3? atol(argv[3]):0;
 NSString *initial=@"initial!";
 if(mb>0){ NSMutableString *b=[NSMutableString stringWithCapacity:mb<<20]; NSString *line=@"\\section{x} 0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJ\n"; while(b.length<(NSUInteger)(mb<<20)) [b appendString:line]; initial=b; }
 [initial writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
 NSURL *url=[NSURL fileURLWithPath:path];
 TSDocument *d=nil; NSError *e=nil;
 if([mode isEqualToString:@"initial-gap"]){
  d=[[TSDocument alloc] init]; d.fileType=@"public.plain-text";
  gInjectOnRead=1; gInjectText=@"complete-longer"; gInjectHow=0;
  [d readFromURL:url ofType:d.fileType error:&e]; d.fileURL=url;
  Pump(2.6);
  printf("%s reads=%lu text=%s\n",mode.UTF8String,(unsigned long)d.reads,d.storage.string.UTF8String);
  [d cancelWatchFile]; return 0;
 }
 d=[[TSDocProbe alloc] initWithContentsOfURL:url ofType:@"public.plain-text" error:&e];
 if(!d){fprintf(stderr,"open failed %s\n",e.description.UTF8String);return 2;}
 Pump(.3);
 NSUInteger r0=d.reads; unsigned long c0=gContentReads; gMaxStall=0;
 #define EXTRA (unsigned long)(d.reads-r0)
 #define CREADS (gContentReads-c0)
 if([mode isEqual:@"slow-stat"]){
  gSlowStat=1;utimes(path.fileSystemRepresentation,NULL);
  for(int i=0;i<300&&!gStatStarted;i++) Pump(.01);
  if(!gStatStarted){fprintf(stderr,"No background stat started\n");return 3;}
  double begin=CFAbsoluteTimeGetCurrent();Pump(.3);[d cancelWatchFile];
  BOOL responsive=CFAbsoluteTimeGetCurrent()-begin<.8;gReleaseStat=1;Pump(.5);
  printf("slow-stat responsive=%d mainIO=%d\n",responsive,gMainMonitorIO);
 } else if([mode hasPrefix:@"slow-"]){
  gSlowRead=1;ExtWrite(path,@"background old",1);
  for(int i=0;i<100&&!gReadStarted;i++) Pump(.01);
  if(!gReadStarted){fprintf(stderr,"No background snapshot started\n");return 3;}
  double begin=CFAbsoluteTimeGetCurrent();Pump(.3);
  BOOL responsive=CFAbsoluteTimeGetCurrent()-begin<.8;
  BOOL saved=YES;
  if([mode isEqual:@"slow-edit"]) [d edit:@"local edit"];
  if([mode isEqual:@"slow-save"] || [mode isEqual:@"slow-saveas"]) {
   [d edit:@"saved while reading"];d.fileModificationDate=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL][NSFileModificationDate];
   NSURL *dest=[mode isEqual:@"slow-saveas"] ? [NSURL fileURLWithPath:[path stringByAppendingString:@".new"]] : url;
   saved=Save(d,dest,[mode isEqual:@"slow-saveas"]?NSSaveAsOperation:NSSaveOperation);
  }
  if([mode isEqual:@"slow-stop"]) {double t=CFAbsoluteTimeGetCurrent();[d cancelWatchFile];responsive &= CFAbsoluteTimeGetCurrent()-t<.1;}
  if([mode isEqual:@"slow-replace"]) ExtWrite(path,@"background new",2);
  gReleaseRead=1;Pump(4.5);
  printf("%s responsive=%d saved=%d extraReads=%lu text=%s\n",mode.UTF8String,responsive,saved,EXTRA,d.storage.string.UTF8String);
 } else if([mode isEqualToString:@"save"]||[mode isEqualToString:@"autosave"]){
  [d edit:@"edited by user"];
  BOOL ok=Save(d,url,[mode isEqualToString:@"save"]?NSSaveOperation:NSAutosaveInPlaceOperation);
  BOOL undoBefore=d.undoManager.canUndo;
  Pump(3.0);
  printf("%s saved=%d extraReads=%lu contentReads=%lu canUndoAfterSave=%d canUndoNow=%d text=%s\n",mode.UTF8String,ok,EXTRA,CREADS,undoBefore,d.undoManager.canUndo,Short(d.storage.string).UTF8String);
 } else if([mode isEqualToString:@"saveas-race"]){

  NSURL *nu=[NSURL fileURLWithPath:[path stringByAppendingString:@".new.tex"]];
  [d edit:@"saved as"]; gInjectBeforeSetURLPath=nu.path; BOOL ok=Save(d,nu,NSSaveAsOperation); Pump(3.0);
  printf("%s saved=%d injected=%d extraReads=%lu editor=%s disk=%s edited=%d\n",mode.UTF8String,ok,gInjectBeforeSetURLPath==nil,EXTRA,d.storage.string.UTF8String,Disk(nu.path).UTF8String,d.isDocumentEdited);
 } else if([mode isEqualToString:@"saveas"]){
  NSURL *nu=[NSURL fileURLWithPath:[path stringByAppendingString:@".new.tex"]];
  [d edit:@"saved as"]; BOOL ok=Save(d,nu,NSSaveAsOperation); Pump(2.5);
  NSUInteger r1=d.reads; BOOL undo1=d.undoManager.canUndo;
  ExtWrite(path,@"old path write",0); Pump(2.5);
  NSUInteger r2=d.reads;
  ExtWrite(nu.path,@"new path write",1); Pump(2.5);
  printf("%s saved=%d readsAfterSaveAs=%lu canUndo=%d oldPathWriteReads=%lu text=%s fileURL=%s\n",mode.UTF8String,ok,(unsigned long)(r1-r0),undo1,(unsigned long)(r2-r1),d.storage.string.UTF8String,d.fileURL.lastPathComponent.UTF8String);
 } else if([mode isEqualToString:@"saveto"]){
  NSURL *nu=[NSURL fileURLWithPath:[path stringByAppendingString:@".export.tex"]];
  [d edit:@"exported"]; BOOL ok=Save(d,nu,NSSaveToOperation); Pump(3);
  printf("%s saved=%d extraReads=%lu edited=%d text=%s\n",mode.UTF8String,ok,EXTRA,d.isDocumentEdited,d.storage.string.UTF8String);
 } else if([mode isEqualToString:@"save-then-external"]){
  [d edit:@"edited by user"]; BOOL ok=Save(d,url,NSSaveOperation); Pump(3.0); NSUInteger r1=d.reads;
  ExtWrite(path,@"external after save",0); Pump(1.5);
  printf("%s saved=%d readsAfterOwnSave=%lu readsAfterExternal=%lu text=%s\n",mode.UTF8String,ok,(unsigned long)(r1-r0),(unsigned long)(d.reads-r1),d.storage.string.UTF8String);
 } else if([mode hasPrefix:@"save-race"]){

  int how=[mode hasSuffix:@"atomic"]?1:([mode hasSuffix:@"samelen"]?2:0);
  [d edit:@"edited by user"];
  gInjectText= how==2? @"EDITED BY USER" : @"racing external"; gInjectAfterSave=how+1;
  if([mode hasSuffix:@"before-return"]) {gInjectAfterSave=0;gInjectBeforeReturn=YES;}
  BOOL ok=Save(d,url,NSSaveOperation); Pump(3.0);
  printf("%s saved=%d injected=%d extraReads=%lu editor=%s disk=%s\n",mode.UTF8String,ok,gInjectAfterSave==0,EXTRA,d.storage.string.UTF8String,Disk(path).UTF8String);
 } else if([mode isEqualToString:@"same-bytes"]){
  ExtWrite(path,@"initial!",1); Pump(2.6);
  printf("%s extraReads=%lu contentReads=%lu text=%s\n",mode.UTF8String,EXTRA,CREADS,d.storage.string.UTF8String);
 } else if([mode isEqualToString:@"same-len-mtime"]){
  ExtWrite(path,@"INITIAL?",2); Pump(2.6);
  printf("%s extraReads=%lu text=%s\n",mode.UTF8String,EXTRA,d.storage.string.UTF8String);
 } else if([mode isEqualToString:@"write-during-revert"]){

  gInjectOnRead=1; gInjectText=@"SECOND-version"; gInjectHow=0;
  ExtWrite(path,@"first-version!",0); Pump(3.0);
  printf("%s extraReads=%lu text=%s disk=%s\n",mode.UTF8String,EXTRA,d.storage.string.UTF8String,Disk(path).UTF8String);
 } else if([mode isEqualToString:@"write-during-revert-samelen"]){
  gInjectOnRead=1; gInjectText=@"FIRST-VERSION!"; gInjectHow=2;
  ExtWrite(path,@"first-version!",0); Pump(3.0);
  printf("%s extraReads=%lu text=%s disk=%s\n",mode.UTF8String,EXTRA,d.storage.string.UTF8String,Disk(path).UTF8String);
 } else if([mode isEqualToString:@"xattr"]){
  setxattr(path.fileSystemRepresentation,"com.example.audit","1",1,0,0); Pump(2.6);
  printf("%s extraReads=%lu contentReads=%lu\n",mode.UTF8String,EXTRA,CREADS);
 } else if([mode isEqualToString:@"chmod"]){
  chmod(path.fileSystemRepresentation,0600); Pump(2.6);
  printf("%s extraReads=%lu contentReads=%lu\n",mode.UTF8String,EXTRA,CREADS);
 } else if([mode isEqualToString:@"touch"]){
  utimes(path.fileSystemRepresentation,NULL); Pump(2.6);
  printf("%s extraReads=%lu contentReads=%lu\n",mode.UTF8String,EXTRA,CREADS);
 } else if([mode isEqualToString:@"xattr-burst"]){
  for(int i=0;i<10;i++){ char v[8]; snprintf(v,8,"%d",i); setxattr(path.fileSystemRepresentation,"com.example.audit",v,strlen(v),0,0); Pump(.3);} Pump(2.2);
  printf("%s extraReads=%lu contentReads=%lu maxStallMs=%.1f\n",mode.UTF8String,EXTRA,CREADS,gMaxStall*1000);
 } else if([mode isEqualToString:@"big-save"]){
  [d edit:[d.storage.string stringByAppendingString:@"%"]]; c0=gContentReads; gMaxStall=0;
  CFAbsoluteTime a=CFAbsoluteTimeGetCurrent(); BOOL ok=Save(d,url,NSAutosaveInPlaceOperation); double st=CFAbsoluteTimeGetCurrent()-a;
  gMaxStall=0; Pump(3.0);
  printf("%s MB=%ld saved=%d saveMs=%.0f extraReads=%lu contentReadsAfterSave=%lu maxStallAfterSaveMs=%.1f canUndo=%d\n",mode.UTF8String,mb,ok,st*1000,EXTRA,CREADS,gMaxStall*1000,d.undoManager.canUndo);
 } else if([mode isEqualToString:@"external"]){
  ExtWrite(path,@"external content",1); Pump(2.6);
  printf("%s extraReads=%lu text=%s\n",mode.UTF8String,EXTRA,d.storage.string.UTF8String);
 } else if([mode isEqualToString:@"dirty-poll"]){
  [d edit:@"user edit"]; c0=gContentReads;
  ExtWrite(path,@"external content",1); Pump(6.0);
  printf("%s contentReadsWhileDirty=%lu extraReads=%lu editor=%s\n",mode.UTF8String,CREADS,EXTRA,d.storage.string.UTF8String);
 } else if([mode isEqualToString:@"dirty-external-autosave"]){
  [d edit:@"user edit"]; Pump(.1);
  ExtWrite(path,@"external content",1); Pump(.6);
  BOOL ok=Save(d,url,NSAutosaveInPlaceOperation); Pump(2.6);
  printf("%s autosaved=%d editor=%s disk=%s extraReads=%lu edited=%d\n",mode.UTF8String,ok,d.storage.string.UTF8String,Disk(path).UTF8String,EXTRA,d.isDocumentEdited);
 } else if([mode isEqualToString:@"dirty-external-implicit"]){

  [d edit:@"user edit"]; Pump(.1);
  ExtWrite(path,@"external content",1); Pump(.6);
  __block BOOL done=NO; __block NSError *er=nil;
  [d autosaveWithImplicitCancellability:NO completionHandler:^(NSError *x){er=x;done=YES;}];
  for(int i=0;i<300&&!done;i++) Pump(.01);
  Pump(3.0);
  printf("%s ops=%s err=%ld editor=%s disk=%s extraReads=%lu edited=%d unautosaved=%d autosavedURL=%d\n",mode.UTF8String,[[d.ops componentsJoinedByString:@","] UTF8String],(long)er.code,d.storage.string.UTF8String,Disk(path).UTF8String,EXTRA,d.isDocumentEdited,d.hasUnautosavedChanges,d.autosavedContentsFileURL!=nil);
 } else if([mode hasPrefix:@"readonly-implicit"]){

  BOOL dirRO=[mode hasSuffix:@"dir"];
  [d edit:@"user edit"]; Pump(.1);
  ExtWrite(path,@"external content",1); chmod(path.fileSystemRepresentation,0444);
  NSString *dir=[path stringByDeletingLastPathComponent]; if(dirRO) chmod(dir.fileSystemRepresentation,0555);
  Pump(.6);
  __block BOOL done=NO; __block NSError *er=nil;
  [d autosaveWithImplicitCancellability:NO completionHandler:^(NSError *x){er=x;done=YES;}];
  for(int i=0;i<300&&!done;i++) Pump(.01);
  NSString *asv=d.autosavedContentsFileURL.path;
  Pump(3.0);
  printf("%s ops=%s err=%ld editor=%s disk=%s extraReads=%lu edited=%d unautosaved=%d autosaveFileExistsAfter=%d autosavedURLNow=%d\n",mode.UTF8String,[[d.ops componentsJoinedByString:@","] UTF8String],(long)er.code,d.storage.string.UTF8String,Disk(path).UTF8String,EXTRA,d.isDocumentEdited,d.hasUnautosavedChanges,asv?[[NSFileManager defaultManager] fileExistsAtPath:asv]:-1,d.autosavedContentsFileURL!=nil);
  if(dirRO) chmod(dir.fileSystemRepresentation,0755);
 } else if([mode hasPrefix:@"ro-first"]){

  NSString *dir=[path stringByDeletingLastPathComponent]; int kind=[mode hasSuffix:@"dir"]?1:([mode hasSuffix:@"uchg"]?2:0);
  if(kind==0) chmod(path.fileSystemRepresentation,0444); else if(kind==1) chmod(dir.fileSystemRepresentation,0555); else chflags(path.fileSystemRepresentation,UF_IMMUTABLE);
  [d edit:@"user edit"]; Pump(.1);
  __block BOOL done=NO; __block NSError *er=nil;
  [d autosaveWithImplicitCancellability:NO completionHandler:^(NSError *x){er=x;done=YES;}];
  for(int i=0;i<300&&!done;i++) Pump(.01);
  BOOL un1=d.hasUnautosavedChanges; NSString *asv=d.autosavedContentsFileURL.path;
  if(kind==1) chmod(dir.fileSystemRepresentation,0755); if(kind==2) chflags(path.fileSystemRepresentation,0);
  chmod(path.fileSystemRepresentation,0644);
  ExtWrite(path,@"external content",1); if(kind==0) chmod(path.fileSystemRepresentation,0444);
  Pump(3.0);
  printf("%s ops=%s err=%ld unautosavedAfterAutosave=%d autosaveURL=%s editor=%s disk=%s extraReads=%lu edited=%d autosaveFileExistsAfter=%d\n",mode.UTF8String,[[d.ops componentsJoinedByString:@","] UTF8String],(long)er.code,un1,asv?asv.lastPathComponent.UTF8String:"nil",d.storage.string.UTF8String,Disk(path).UTF8String,EXTRA,d.isDocumentEdited,asv?[[NSFileManager defaultManager] fileExistsAtPath:asv]:-1);
  chmod(path.fileSystemRepresentation,0644);
 } else if([mode hasPrefix:@"typeset-autosave"]){

  BOOL ext=[mode hasSuffix:@"ext"];
  [d edit:@"user edit"]; Pump(.1);
  if(ext){ ExtWrite(path,@"external content",1); Pump(.6); }
  [d autosaveDocumentWithDelegate:nil didAutosaveSelector:NULL contextInfo:NULL];
  Pump(3.0);
  printf("%s ops=%s canUndo=%d editor=%s disk=%s extraReads=%lu edited=%d unautosaved=%d autosavedURL=%s\n",mode.UTF8String,[[d.ops componentsJoinedByString:@","] UTF8String],d.undoManager.canUndo,d.storage.string.UTF8String,Disk(path).UTF8String,EXTRA,d.isDocumentEdited,d.hasUnautosavedChanges,d.autosavedContentsFileURL?d.autosavedContentsFileURL.lastPathComponent.UTF8String:"nil");
 } else if([mode isEqualToString:@"elsewhere-then-external"]){
  [d edit:@"user edit"]; Pump(.1);
  NSURL *au=[NSURL fileURLWithPath:[[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"autosave.tex"]];
  BOOL ok=Save(d,au,NSAutosaveElsewhereOperation); Pump(.5);
  ExtWrite(path,@"external content",1); Pump(3.0);
  printf("%s autosaved=%d editor=%s disk=%s extraReads=%lu edited=%d autosaveFileAfter=%d\n",mode.UTF8String,ok,d.storage.string.UTF8String,Disk(path).UTF8String,EXTRA,d.isDocumentEdited,[[NSFileManager defaultManager] fileExistsAtPath:au.path]);
 } else if([mode isEqualToString:@"implicit-then-external"]||[mode isEqualToString:@"external-then-implicit"]){

  BOOL extFirst=[mode hasPrefix:@"external-then"];
  printf("NSCloseAlwaysConfirmsChanges=%d ",[[NSUserDefaults standardUserDefaults] boolForKey:@"NSCloseAlwaysConfirmsChanges"]);
  [d edit:@"user edit"]; Pump(.1);
  if(extFirst){ ExtWrite(path,@"external content",1); Pump(.6); }
  __block BOOL done=NO; __block NSError *er=nil;
  [d autosaveWithImplicitCancellability:NO completionHandler:^(NSError *x){er=x;done=YES;}];
  for(int i=0;i<300&&!done;i++) Pump(.01);
  NSString *asv=d.autosavedContentsFileURL.path; BOOL un=d.hasUnautosavedChanges;
  if(!extFirst){ Pump(.5); ExtWrite(path,@"external content",1); }
  Pump(3.0);
  printf("%s ops=%s err=%ld unautosavedAfterAutosave=%d autosaveURL=%s editor=%s disk=%s extraReads=%lu edited=%d autosaveFileExistsAfter=%d\n",mode.UTF8String,[[d.ops componentsJoinedByString:@","] UTF8String],(long)er.code,un,asv?"set":"nil",d.storage.string.UTF8String,Disk(path).UTF8String,EXTRA,d.isDocumentEdited,asv?[[NSFileManager defaultManager] fileExistsAtPath:asv]:-1);
 } else if([mode isEqualToString:@"dirty-external-elsewhere"]){

  [d edit:@"user edit"]; Pump(.1);
  ExtWrite(path,@"external content",1); Pump(.6);
  NSURL *au=[NSURL fileURLWithPath:[[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"autosave.tex"]];
  BOOL ok=Save(d,au,NSAutosaveElsewhereOperation); BOOL un=d.hasUnautosavedChanges; Pump(3.0);
  printf("autosaveFileAfter=%d autosaveContents=%s ",[[NSFileManager defaultManager] fileExistsAtPath:au.path],Disk(au.path).UTF8String);
  printf("%s autosaved=%d unautosavedAfter=%d editor=%s disk=%s extraReads=%lu edited=%d\n",mode.UTF8String,ok,un,d.storage.string.UTF8String,Disk(path).UTF8String,EXTRA,d.isDocumentEdited);
 } else if([mode isEqualToString:@"dirty-external-undo"]){
  [d edit:@"user edit"]; Pump(.1);
  ExtWrite(path,@"external content",1); Pump(.6);
  [d.undoManager undo]; Pump(3.0);
  printf("%s edited=%d editor=%s disk=%s extraReads=%lu\n",mode.UTF8String,d.isDocumentEdited,d.storage.string.UTF8String,Disk(path).UTF8String,EXTRA);
 } else if([mode isEqualToString:@"fdleak"]){
  int before=CountFDs();
  for(int i=0;i<300;i++){[d cancelWatchFile];[d watchFile:path];}
  Pump(.5); int mid=CountFDs(); [d cancelWatchFile]; Pump(.5); int after=CountFDs();
  printf("%s fdsBefore=%d after300Rewatch=%d afterCancel=%d\n",mode.UTF8String,before,mid,after);
 }
 [d cancelWatchFile]; if(gMainMonitorIO){fprintf(stderr,"Monitor I/O ran on main thread\n");return 4;}return 0;
}}
'''
checks = {
 'slow-stat': ['responsive=1 mainIO=0'],
 'slow-edit': ['responsive=1 saved=1 extraReads=0 text=local edit'],
 'slow-save': ['responsive=1 saved=1 extraReads=0 text=saved while reading'],
 'slow-saveas': ['responsive=1 saved=1 extraReads=0 text=saved while reading'],
 'slow-stop': ['responsive=1 saved=1 extraReads=0 text=initial!'],
 'slow-replace': ['responsive=1 saved=1', 'text=background new'],
 'save': ['saved=1 extraReads=0', 'canUndoAfterSave=1 canUndoNow=1', 'text=edited by user'],
 'autosave': ['saved=1 extraReads=0', 'canUndoAfterSave=1 canUndoNow=1'],
 'saveas': ['saved=1 readsAfterSaveAs=0 canUndo=1 oldPathWriteReads=0', 'text=new path write'],
 'saveas-race': ['saved=1 injected=1', 'editor=race on new path disk=race on new path'],
 'save-then-external': ['readsAfterOwnSave=0 readsAfterExternal=1 text=external after save'],
 'save-race': ['saved=1 injected=1 extraReads=1 editor=racing external disk=racing external'],
 'save-race-before-return': ['saved=1 injected=1 extraReads=1 editor=racing external disk=racing external'],
 'save-race-atomic': ['saved=1 injected=1 extraReads=1 editor=racing external disk=racing external'],
 'save-race-samelen': ['saved=1 injected=1 extraReads=1 editor=EDITED BY USER disk=EDITED BY USER'],
 'same-bytes': ['extraReads=0'],
 'same-len-mtime': ['extraReads=1 text=INITIAL?'],
 'write-during-revert': ['text=SECOND-version disk=SECOND-version'],
 'write-during-revert-samelen': ['text=FIRST-VERSION! disk=FIRST-VERSION!'],
 'xattr': ['extraReads=0'], 'chmod': ['extraReads=0'], 'touch': ['extraReads=0'],
 'external': ['extraReads=1 text=external content'], 'initial-gap': ['text=complete-longer'],
 'dirty-poll': ['contentReadsWhileDirty=0 extraReads=0 editor=user edit'],
 'dirty-external-elsewhere': ['autosaveFileAfter=1 autosaveContents=user edit',
     'autosaved=1 unautosavedAfter=0 editor=user edit disk=external content extraReads=0 edited=1'],
 'elsewhere-then-external': ['autosaved=1 editor=user edit disk=external content extraReads=0 edited=1 autosaveFileAfter=1'],
 'typeset-autosave': ['canUndo=1 editor=user edit disk=user edit extraReads=0'],
 'dirty-external-undo': ['editor=external content disk=external content'],
 'saveto': ['saved=1 extraReads=0', 'text=exported'],
 'fdleak': [],
}
modes = args.modes or list(checks)
for mode in modes:
    if mode not in checks: raise SystemExit('Unknown test: ' + mode)
rev = args.revision
m = OUT / 'probe.m'; m.write_text(PROGRAM.replace('METHODS', methods(rev, 'watch')))
for suffix in ['m', 'h']:
    content = show(rev, 'Sources/TSFileChangeMonitor.' + suffix)
    if suffix == 'm':
        content = content.replace('#import <unistd.h>', '#import <unistd.h>\nextern int TSProbeStat(const char *, struct stat *);\nextern int TSProbeFstat(int, struct stat *);\nextern int TSProbeOpen(const char *, int);')
        for name in ['stat', 'fstat', 'open']:
            content = re.sub(r'\b'+name+r'\(', 'TSProbe'+name.capitalize()+'(', content)
    (OUT / ('TSFileChangeMonitor.' + suffix)).write_text(content)
exe = OUT / 'probe'
subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-I'+str(OUT),
                '-DV5', '-DV6', str(m), str(OUT/'TSFileChangeMonitor.m'), '-o', str(exe)], check=True)
for mode in modes:
    with tempfile.TemporaryDirectory(dir=OUT) as td:
        result = subprocess.run([str(exe), str(Path(td)/'source.tex'), mode],
                                capture_output=True, text=True, timeout=30)
        print(result.stdout.strip(), flush=True)
        if result.returncode: raise SystemExit(result.stderr)
        for expected in checks[mode]:
            if expected not in result.stdout:
                raise SystemExit(f'FAIL {mode}: missing {expected!r}')
        if mode == 'fdleak':
            match = re.search(r'fdsBefore=(\d+) after300Rewatch=(\d+) afterCancel=(\d+)', result.stdout)
            if not match or int(match[2]) > int(match[1]) or int(match[3]) >= int(match[2]):
                raise SystemExit('FAIL: file descriptor leak')
print(f'PASS: {len(modes)} production NSDocument scenarios')
