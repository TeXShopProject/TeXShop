#!/usr/bin/env python3
"""Exercise production PDF reload methods with real PDFKit views in isolation."""
from pathlib import Path
import ast, os, shutil, subprocess, sys, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
# --mutation=NAME reverts one behaviour in memory to show that its checks fail.
mutation = next((a.split('=',1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
# Reuse only the inert view/window fixtures, not the old method-selection logic.
tree = ast.parse((root/'Tests/run-pdf-recovery.py').read_text())
fixture = max((n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value,str)),key=len)
fixture = fixture[:fixture.index('static void check(')]
fixture = fixture.replace('-(void)reShowWithPath:(NSString*)path;', '-(void)reShowWithPath:(NSString*)path;\n-(void)reShowWithDocument:(PDFDocument*)document;')
s=(root/'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
def method(s, signature):
    a=s.rindex(signature); return s[a:s.index('\n}',a)+2]
window_source=(root/'Sources/Windows/TSPreviewWindow.m').read_text()
window_methods='\n'.join(method(window_source,x) for x in ['- (void)close', '- (void)orderWindow:'])
fixture=fixture.replace('WINDOW_METHODS',window_methods.replace('TSDocument *theDocument', 'TestDocument *theDocument'))
methods='\n'.join(method(s,x) for x in ['- (void)reShowWithPath:', '- (void)reShowWithDocument:', '- (void)shareDocumentWithSecondView', '- (void)prepareSecond', '- (void) reShowForSecond', '- (void) initializeDisplay', '- (void)removeHideView1:', '- (void)removeHideView2:', '- (void)setDocument:(PDFDocument *)document', '- (instancetype)initWithFrame:'])
fixture=fixture.replace('METHODS',methods.replace('MyPDFKitView *weakSelf', 'RecoveryView *weakSelf'))
fixture=fixture.replace('@implementation TestWindow', '@implementation TestWindow\n- (void)setRepresentedFilename:(NSString *)s {}\n- (void)setTitle:(NSString *)s {}\n- (void)makeKeyAndOrderFront:(id)sender {[self orderWindow:NSWindowAbove relativeTo:0];}')
s=(root/'Sources/Document/TSDocument.m').read_text()
controller='\n'.join(method(s,x) for x in ['- (NSString *)externalPDFPath','- (BOOL)externalPDFChecksAllowed','- (BOOL)externalPDFObservationEnabled','- (void)externalPDFPreviewActivated:','- (void)followExternalPDFChange','- (void)stopFollowingExternalPDF', '- (void)externalPDFSettingsChanged:', '- (void)configureExternalPDFObservation','- (void)stopExternalPDFObservation','- (void)startExternalPDFObservation','- (void)notePDFLoadedAtPath:', '- (void)acceptExternalPDFAtPath:', '- (void)prepareExternalPDFContent', '- (BOOL)externalPDFReloadBlocked'])
# Count and optionally stall the file checks made by the polling path only.
controller+='\n'+'\n'.join(method(s,x) for x in ['- (void)refreshPDFWindow:','- (void)checkExternalPDF:']).replace('TSExternalPDFState(', 'CheckedState(')
controller+='\n'+'\n'.join(method(s,x) for x in ['- (void)finishExternalPDFCheck:', '- (void)applyExternalPDFPath:'])
controller=controller.replace('TSExternalPDFSnapshot(', 'CountedSnapshot(')
mutations={
 'inline': ('dispatch_async(self.externalPDFQueue, ^{', 'RunInline(^{'),
 'generation': ('generation == self.externalPDFGeneration && ', ''),
 'taskdone': ('return ![self externalPDFChecksAllowed] || ', 'return ![self externalPDFChecksAllowed] || !taskDone || '),
 # Returning to the preview does not check the PDF.
 'noactivation': ('[self checkExternalPDF:YES];\n}', '}'),
 # A change found on returning is not followed until the file settles.
 'nofollow': ('    self.externalPDFQuietSince = now;\n    if (self.pdfRefreshTimer || self.externalPDFFollowTimer) return;', '    return;'),
 # Following never stops once the file is quiet.
 'nostop': ('else if (self.externalPDFFollowTimer && now - self.externalPDFQuietSince > 2.5) [self stopFollowingExternalPDF];', ''),
 # Each quiet check counts as a second, so returning several times in a row ends following early.
 'countchecks': ('now - self.externalPDFQuietSince > 2.5', '(self.externalPDFQuietSince -= 1, now - self.externalPDFQuietSince > 2.5)'),
 # A PDF that stays unopenable counts as quiet, so a writer pausing between pages ends following.
 'pausestop': ('else if (!matching) self.externalPDFQuietSince = now;\n', ''),
 # A state turned down a moment ago counts as quiet when its cheap signature matches the display.
 'failedquiet': ('BOOL matching = signature && !key;\n        if ([key isEqualToString:failed]) key = changeTime = nil;', 'if ([key isEqualToString:failed]) key = changeTime = nil;\n        BOOL matching = !key && [signature isEqualToString:loaded];'),
 # A PDF missing for the moment counts as quiet.
 'missingquiet': ('BOOL matching = signature && !key;', 'BOOL matching = !key;'),
 # Checks on returning wait for a second observation, as the timer does.
 'twoobservations': ('BOOL attempted = key && (immediate || [key isEqualToString:pending]);', 'BOOL attempted = [key isEqualToString:pending];'),
 # Ignore a new ctime when the cheap signature is unchanged, as before content comparison.
 'nohash': ('if (changeTime && loadedChangeTime && ![changeTime isEqualToString:loadedChangeTime]) {', 'if (0) {'),
 # Digest a file read in place on the main thread.
 'mainhash': ('dispatch_async(self.externalPDFQueue, ^{ [content prepareDigest]; });', '[content prepareDigest];'),
}
if mutation in mutations:
    old,new=mutations[mutation]; assert old in controller; controller=controller.replace(old,new)
program=fixture+r'''
#import "TSExternalPDFReload.h"
#import "TSPreferenceProfile.h"
#include <stdatomic.h>
#include <sys/xattr.h>
#include <fcntl.h>
static atomic_ulong snapshotCount, mainSnapshots, mainSignatures, workerSignatures, stallEntries;
// Counted by the instrumented copy of TSExternalPDFSnapshot.m.
atomic_ulong TSTestDigests, TSTestMainDigests;
static atomic_bool stallChecks;
static dispatch_semaphore_t stallRelease;
static PDFDocument *CountedSnapshot(NSString *p, NSString *s) { snapshotCount++; if(NSThread.isMainThread) mainSnapshots++; return TSExternalPDFSnapshot(p,s); }
// Simulates a stalled network volume or an online-only file being fetched.
static NSString *CheckedState(NSString *p, NSString **changeTime) {
 if(NSThread.isMainThread) mainSignatures++; else workerSignatures++;
 if(stallChecks){stallEntries++;dispatch_semaphore_wait(stallRelease,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC));}
 return TSExternalPDFState(p,changeTime);
}
static void RunInline(dispatch_block_t block) { block(); }
#define PdfRefreshKey @"PdfRefresh"
#define PdfFileRefreshKey @"PdfFileRefresh"
#define isPDF 2
#define isTeX 0
#define RefreshTimeKey @"RefreshTime"
#define BringPdfFrontOnAutomaticUpdateKey @"BringPdfFrontOnAutomaticUpdate"
@interface TSDocument:NSObject { @public BOOL taskDone,_externalEditor,PDFfromKit; }
@property NSURL *fileURL;
@property RecoveryView *myPDFKitView,*myPDFKitView2;
@property TestWindow *pdfKitWindow;
@property NSTask *texTask;
@property BOOL annotationsExist, useOldSyncParser, useConTeXtSyncParser;
@property NSInteger documentType;
@property NSString *externalPDFLoadedSignature,*externalPDFPendingSignature,*externalPDFLoadedChangeTime;
@property TSExternalPDFContent *externalPDFLoadedContent;
@property NSTimer *pdfRefreshTimer;
@property NSDate *pdfLastModDate;
@property id pdfActivity;
@property NSString *externalPDFFailedSignature;
@property NSTimeInterval externalPDFFailedRetryTime;
@property BOOL externalPDFObservationClosed;
@property (strong) dispatch_queue_t externalPDFQueue;
@property NSUInteger externalPDFGeneration;
@property BOOL externalPDFCheckRunning;
@property NSTimer *externalPDFFollowTimer;
@property NSTimeInterval externalPDFFollowDeadline;
@property NSTimeInterval externalPDFQuietSince;
- (void)refreshPDFWindow:(NSTimer*)timer;
- (void)checkExternalPDF:(BOOL)immediate;
- (void)notePDFLoadedAtPath:(NSString *)path signature:(NSString *)signature changeTime:(NSString *)changeTime;
@end
@implementation TSDocument
- (void)allocateSyncScanner {}
- (void)allocateSyncScannerOld {}
- (void)fillLogWindowIfVisible {}
CONTROLLER
@end
// Views must be in a visible window for checks on returning; nothing is shown.
@interface VisibleWindow:NSWindow
@end
@implementation VisibleWindow
- (BOOL)isVisible {return YES;}
@end
static void Check(BOOL ok,NSString *message){if(!ok){NSLog(@"FAIL: %@",message);exit(1);}}
// Independent checks report every failure before exiting.
static BOOL failures;
static void Expect(BOOL ok,NSString *message){if(!ok){NSLog(@"FAIL: %@",message);failures=YES;}}
static void Pump(double seconds){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];while(end.timeIntervalSinceNow>0)[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
static NSData *PDF(NSInteger pages,NSInteger revision) {
 NSMutableData *data=[NSMutableData data]; CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
 CGRect box=CGRectMake(0,0,612,792);CGContextRef context=CGPDFContextCreate(consumer,&box,NULL);
 for(NSInteger i=0;i<pages;i++) {CGPDFContextBeginPage(context,NULL);CGContextSetRGBFillColor(context,1,1,1,1);CGContextFillRect(context,box);CGContextSetRGBFillColor(context,.2,.4,.6,1);CGContextFillRect(context,CGRectMake(40,100+i*10,100+revision*10,30));CGPDFContextEndPage(context);}
 CGPDFContextClose(context);CGContextRelease(context);CGDataConsumerRelease(consumer);return data;
}
// Polls are asynchronous; wait for each check to be applied on the main queue.
static void WaitIdle(TSDocument *d){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5];while(d.externalPDFCheckRunning && end.timeIntervalSinceNow>0)Pump(.01);Check(!d.externalPDFCheckRunning,@"Background check finished");}
static void Poll(TSDocument *d){[d refreshPDFWindow:nil];WaitIdle(d);}
static void StablePoll(TSDocument *d){Poll(d);Poll(d);Pump(.15);}
// Records an application load of the file's current state.
static void NoteLoaded(TSDocument *d,NSString *path){NSString *t=nil,*s=TSExternalPDFState(path,&t);[d notePDFLoadedAtPath:path signature:s changeTime:t];}
static BOOL SameTime(struct timespec a,struct timespec b){return a.tv_sec==b.tv_sec && a.tv_nsec==b.tv_nsec;}
// Sync clients and Finder set extended attributes after typesetting; only ctime changes.
static void SetAttribute(NSString *path){
 static uint8_t value;struct stat before,after;Check(stat(path.fileSystemRepresentation,&before)==0,@"stat");usleep(20000);
 uint8_t used[16]={++value,2,3};Check(setxattr(path.fileSystemRepresentation,"com.apple.lastuseddate#PS",used,sizeof used,0,0)==0,@"Set extended attribute");
 Check(stat(path.fileSystemRepresentation,&after)==0 && !SameTime(after.st_ctimespec,before.st_ctimespec) && SameTime(after.st_mtimespec,before.st_mtimespec),
  @"Extended attribute changes ctime but not mtime");
}
// Overwrites in place with bytes of the same size and restores the modification
// time to the nanosecond, so only ctime reveals the write.
static void OverwriteKeepingTimes(NSString *path,NSData *data){
 struct stat before,after;Check(stat(path.fileSystemRepresentation,&before)==0,@"stat");usleep(20000);
 Check([data writeToFile:path atomically:NO],@"Overwrite in place");
 struct timespec times[2]={before.st_atimespec,before.st_mtimespec};
 Check(utimensat(AT_FDCWD,path.fileSystemRepresentation,times,0)==0,@"Restore modification time");
 Check(stat(path.fileSystemRepresentation,&after)==0 && after.st_dev==before.st_dev && after.st_ino==before.st_ino && after.st_size==before.st_size &&
  SameTime(after.st_mtimespec,before.st_mtimespec) && !SameTime(after.st_ctimespec,before.st_ctimespec),@"Overwrite keeps inode, size and mtime; ctime changes");
}
static NSData *Padded(NSData *data,NSUInteger size){NSMutableData *m=[data mutableCopy];while(m.length<size)[m appendBytes:" " length:1];return m;}
static void SamePosition(RecoveryView *v,TSExternalPDFPosition old,NSString *label){
 TSExternalPDFPosition now=TSExternalPDFCapture(v);
 CGFloat delta=hypot(now.pagePoint.x-old.pagePoint.x,now.pagePoint.y-old.pagePoint.y);
 Check(now.valid && now.pageIndex==old.pageIndex && delta<1.5 && (old.autoScales || fabs(v.scaleFactor-old.scale)<.001) && v.autoScales==old.autoScales,
 [NSString stringWithFormat:@"%@ page %lu -> %lu delta %.3f zoom %.3f -> %.3f",label,old.pageIndex,now.pageIndex,delta,old.scale,v.scaleFactor]);
}
int main(int argc,char **argv){@autoreleasepool{
 if(argc==5 && [@(argv[1])isEqualToString:@"--write"]) {
   Check([PDF(12,[@(argv[3]) integerValue])writeToFile:@(argv[2]) atomically:[@(argv[4])boolValue]],@"External writer saved PDF");
   return 0;
 }
 TSInstallAppKitIsolation();[NSApplication sharedApplication];
 BOOL rtlBook=![NSProcessInfo.processInfo.arguments containsObject:@"--ltr"];
 TSIsolatedAppKitDefaults.values=[@{@"PdfRefresh":@YES,@"PdfFileRefresh":@YES,@"RefreshTime":@0.5} mutableCopy];
 NSString *path=[@(argv[1]) stringByAppendingPathComponent:@"test.PDF"];
 NSData *first=PDF(12,1),*changed=PDF(12,2);
 for(NSNumber *fit in @[@NO,@YES]) for(NSNumber *mode in @[@(kPDFDisplaySinglePage),@(kPDFDisplaySinglePageContinuous),@(kPDFDisplayTwoUp),@(kPDFDisplayTwoUpContinuous)]) {
 [first writeToFile:path atomically:YES];
 NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 window.releasedWhenClosed=NO;
 TSDocument *d=[TSDocument new];d.fileURL=[NSURL fileURLWithPath:path];d->taskDone=YES;d.pdfKitWindow=[TestWindow new];
 // Both panes are shown: the preview is split.
 d.pdfKitWindow.windowIsSplit=YES;
 d.myPDFKitView=[[RecoveryView alloc] initWithFrame:NSMakeRect(0,0,450,600)];d.myPDFKitView2=[[RecoveryView alloc] initWithFrame:NSMakeRect(450,0,450,600)];
 for(RecoveryView *v in @[d.myPDFKitView,d.myPDFKitView2]) {
 v.myPDFWindow=d.pdfKitWindow;v.myDocument=[TestDocument new];v.myDocument.previewDisplaysRTL=rtlBook;v.myDocument.previewDisplaysAsBook=rtlBook;v.myDocument.pdfKitWindow=d.pdfKitWindow;v.myDocument.myPDFKitView2=d.myPDFKitView2;
 [window.contentView addSubview:v];v.document=[[PDFDocument alloc]initWithData:first];v.displayMode=mode.integerValue;v.autoScales=fit.boolValue;if(!fit.boolValue)v.scaleFactor=1.6;
 [v goToDestination:[[PDFDestination alloc]initWithPage:[v.document pageAtIndex:(v==d.myPDFKitView?4:8)] atPoint:NSMakePoint(170,520)]];
 }
 Pump(.1);
 TSIsolatedAppKitDefaults.values=[@{@"PdfRefresh":@NO} mutableCopy];
 [d startExternalPDFObservation];Check(d.pdfRefreshTimer==nil && d.pdfActivity==nil,@"Disabled observation has no timer/activity");
 TSIsolatedAppKitDefaults.values=[@{@"PdfRefresh":@YES,@"PdfFileRefresh":@NO,@"RefreshTime":@0.5} mutableCopy];
 d.documentType=isPDF; [d configureExternalPDFObservation];
 Check(!d.pdfRefreshTimer && !d.pdfActivity,@"PDF-only opt-out prevents startup");
 d.documentType=3;[d configureExternalPDFObservation];[d startExternalPDFObservation];
 Check(!d.pdfRefreshTimer && !d.pdfActivity,@"Image document cannot observe a sibling PDF");
 d.documentType=isPDF;
 TSIsolatedAppKitDefaults.values=[@{@"PdfRefresh":@YES,@"PdfFileRefresh":@YES,@"RefreshTime":@0.5} mutableCopy];
 [d startExternalPDFObservation];Check([[d externalPDFPath]isEqualToString:path],@"Uppercase PDF path");
 [d.pdfRefreshTimer invalidate];
 TSExternalPDFPosition one=TSExternalPDFCapture(d.myPDFKitView),two=TSExternalPDFCapture(d.myPDFKitView2);
 PDFDocument *old=d.myPDFKitView.document;
 [changed writeToFile:path atomically:YES];Poll(d);Check(d.myPDFKitView.document==old,@"Wait for stable observation");
 Poll(d);Pump(.15);Check(d.myPDFKitView.document!=old,@"Atomic replacement reload");Check(d.myPDFKitView.displaysRTL==rtlBook && d.myPDFKitView.displaysAsBook==rtlBook && d.myPDFKitView2.displaysRTL==rtlBook && d.myPDFKitView2.displaysAsBook==rtlBook,@"Reload applies resolved direction and cover to both panes");SamePosition(d.myPDFKitView,one,@"primary");SamePosition(d.myPDFKitView2,two,@"secondary");
 old=d.myPDFKitView.document;[[changed subdataWithRange:NSMakeRange(0,changed.length/2)]writeToFile:path atomically:NO];StablePoll(d);Check(d.myPDFKitView.document==old,@"Partial PDF retains good display");
 NSUInteger attempts=snapshotCount;for(int retry=0;retry<10;retry++)Poll(d);
 Check(snapshotCount==attempts,@"Unchanged rejected PDF is not reparsed");
 NSMutableData *padded=[changed mutableCopy];[padded appendData:[@"\nTrailing text\n" dataUsingEncoding:NSUTF8StringEncoding]];
 [padded writeToFile:path atomically:YES];StablePoll(d);Check(d.myPDFKitView.document!=old,@"PDFKit-compatible trailing data accepted");
 old=d.myPDFKitView.document;

 [first writeToFile:path atomically:NO];StablePoll(d);Check(d.myPDFKitView.document!=old,@"Partial to valid recovery");SamePosition(d.myPDFKitView,one,@"recovered");
 old=d.myPDFKitView.document;[[NSFileManager defaultManager]removeItemAtPath:path error:NULL];StablePoll(d);Check(d.myPDFKitView.document==old,@"Deleted PDF retains display");[changed writeToFile:path atomically:YES];StablePoll(d);Check(d.myPDFKitView.document!=old,@"Recreation reload");
 old=d.myPDFKitView.document;d.annotationsExist=YES;[first writeToFile:path atomically:YES];StablePoll(d);Check(d.myPDFKitView.document==old,@"Protect annotations");d.annotationsExist=NO;
 NSTask *job=[NSTask new];job.executableURL=[NSURL fileURLWithPath:@"/bin/sleep"];job.arguments=@[@"3"];
 [job launchAndReturnError:NULL];d.texTask=job;StablePoll(d);Check(d.myPDFKitView.document==old,@"Real running typesetter blocks reload");
 [job terminate];[job waitUntilExit];d.texTask=nil;
 // AppleScript commands clear taskDone even when no job starts.
 d->taskDone=NO;StablePoll(d);Check(d.myPDFKitView.document!=old,@"Stale taskDone without a running job does not stop reloads");d->taskDone=YES;
 old=d.myPDFKitView.document;[changed writeToFile:path atomically:YES];
 [d.pdfKitWindow close];StablePoll(d);Check(d.myPDFKitView.document==old,@"Do not reopen preview");
 [d.pdfKitWindow orderWindow:NSWindowAbove relativeTo:0];StablePoll(d);Check(d.myPDFKitView.document!=old,@"Resume after production preview reopening");
 // Exercise the actual timer, rather than only calling its action.
 [d startExternalPDFObservation];
 for(NSNumber *atomic in @[@NO,@YES]) {
 old=d.myPDFKitView.document;
 TSExternalPDFPosition externalOne=TSExternalPDFCapture(d.myPDFKitView),externalTwo=TSExternalPDFCapture(d.myPDFKitView2);
 NSTask *writer=[NSTask new];writer.executableURL=[NSURL fileURLWithPath:@(argv[0])];
 writer.arguments=@[@"--write",path,atomic.boolValue?@"5":@"4",atomic.stringValue];
 Check([writer launchAndReturnError:NULL],@"Launch independent writer");[writer waitUntilExit];Check(writer.terminationStatus==0,@"Writer exited");
 Pump(1.8);Check(d.myPDFKitView.document!=old,@"Automatic reload from independent process");
 SamePosition(d.myPDFKitView,externalOne,@"independent writer primary");SamePosition(d.myPDFKitView2,externalTwo,@"independent writer secondary");
 }
 [d.pdfRefreshTimer invalidate];
 [PDF(2,3)writeToFile:path atomically:YES];StablePoll(d);Check(d.myPDFKitView.document.pageCount==2 && d.myPDFKitView.currentPage!=nil,@"Fewer pages clamp");
 [first writeToFile:path atomically:YES];StablePoll(d);
 BOOL firstSpreadVisible=NO;
 // PDFKit can report an empty visiblePages array for an RTL/book layout
 // after replacement, even though currentPage and its onscreen rect are valid.
 NSClipView *clip=d.myPDFKitView.documentView.enclosingScrollView.contentView;
 NSRect viewport=[d.myPDFKitView convertRect:clip.bounds fromView:clip];
 for(NSUInteger index=0;index<MIN(2,d.myPDFKitView.document.pageCount);index++) {
  PDFPage *page=[d.myPDFKitView.document pageAtIndex:index];
  NSRect pageRect=[d.myPDFKitView convertRect:[page boundsForBox:d.myPDFKitView.displayBox] fromPage:page];
  if(NSIntersectsRect(pageRect,viewport)) firstSpreadVisible=YES;
 }
 Check(firstSpreadVisible,@"Short-to-long PDF keeps original first spread visible within scroll bounds");
 old=d.myPDFKitView.document;NoteLoaded(d,path);
 StablePoll(d);Check(d.myPDFKitView.document==old,@"Do not repeat an acknowledged application reload");
 Check(screenUpdates==0,@"Screen updates balanced");
 [d stopExternalPDFObservation];
 [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:SUD];
 [d externalPDFSettingsChanged:nil];[d configureExternalPDFObservation];
 Check(!d.pdfRefreshTimer && !d.pdfActivity,@"Closed document cannot restart observation");
 [window close];printf("PASS autoScale=%d mode=%ld: viewport, zoom, atomic save, partial/deleted/recreated PDF, annotations, typesetting, independent writer + timer\n",fit.boolValue,(long)mode.integerValue);
 }
 stallRelease=dispatch_semaphore_create(0);
 [first writeToFile:path atomically:YES];
 NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 window.releasedWhenClosed=NO;
 TSDocument *d=[TSDocument new];d.fileURL=[NSURL fileURLWithPath:path];d->taskDone=YES;d.pdfKitWindow=[TestWindow new];d.documentType=isPDF;
 d.myPDFKitView=[[RecoveryView alloc] initWithFrame:NSMakeRect(0,0,450,600)];d.myPDFKitView2=[[RecoveryView alloc] initWithFrame:NSMakeRect(450,0,450,600)];
 for(RecoveryView *v in @[d.myPDFKitView,d.myPDFKitView2]) {
 v.myPDFWindow=d.pdfKitWindow;v.myDocument=[TestDocument new];v.myDocument.previewDisplaysRTL=rtlBook;v.myDocument.previewDisplaysAsBook=rtlBook;v.myDocument.pdfKitWindow=d.pdfKitWindow;v.myDocument.myPDFKitView2=d.myPDFKitView2;
 [window.contentView addSubview:v];v.document=[[PDFDocument alloc]initWithData:first];
 }
 // An unsplit preview gives the second view no document.
 d.myPDFKitView2.document=nil;
 [d startExternalPDFObservation];[d.pdfRefreshTimer invalidate];
 PDFDocument *old=d.myPDFKitView.document;

 // The PDF was read in place: its digest is taken in the background before any check.
 SetAttribute(path);
 NSUInteger attempts=snapshotCount;StablePoll(d);StablePoll(d);
 Expect(d.myPDFKitView.document==old && snapshotCount==attempts,@"Metadata-only change does not reload the PDF");
 NSUInteger digests=TSTestDigests;StablePoll(d);
 Expect(TSTestDigests==digests,@"Content is compared only once for a new change time");

 // Same-size PDFs with different bytes; writing one over the other in place and
 // restoring mtime leaves path, device, inode, size and mtime unchanged.
 NSData *base=PDF(12,6),*edit=PDF(12,7);NSUInteger size=MAX(base.length,edit.length)+128;
 base=Padded(base,size);edit=Padded(edit,size);Check(![base isEqualToData:edit] && base.length==edit.length,@"Different PDFs of one size");
 // Displayed from a snapshot clone after an external reload.
 [base writeToFile:path atomically:YES];StablePoll(d);Check(d.myPDFKitView.document!=old,@"Reload before same-size checks");
 Check(!d.myPDFKitView2.document,@"Unsplit preview: reload leaves the second view without a document");
 old=d.myPDFKitView.document;attempts=snapshotCount;digests=TSTestDigests;
 SetAttribute(path);StablePoll(d);StablePoll(d);
 Expect(d.myPDFKitView.document==old && snapshotCount==attempts && TSTestDigests>digests,@"Snapshot: metadata-only change is compared and not reloaded");
 digests=TSTestDigests;StablePoll(d);Expect(TSTestDigests==digests,@"Snapshot: same content is not compared again");
 NSString *signature=TSExternalPDFSignature(path);
 OverwriteKeepingTimes(path,edit);Expect([signature isEqualToString:TSExternalPDFSignature(path)],@"Overwrite keeps the cheap signature");
 StablePoll(d);StablePoll(d);
 Expect(d.myPDFKitView.document!=old && snapshotCount==attempts+1,@"Snapshot: same-size overwrite with restored mtime reloads");
 // Displayed from data read by the application itself.
 [base writeToFile:path atomically:YES];
 for(RecoveryView *v in @[d.myPDFKitView,d.myPDFKitView2])v.document=[[PDFDocument alloc]initWithData:base];
 NoteLoaded(d,path);old=d.myPDFKitView.document;attempts=snapshotCount;
 SetAttribute(path);StablePoll(d);StablePoll(d);
 Expect(d.myPDFKitView.document==old && snapshotCount==attempts,@"Application load: metadata-only change does not reload");
 OverwriteKeepingTimes(path,edit);StablePoll(d);StablePoll(d);
 Expect(d.myPDFKitView.document!=old && snapshotCount==attempts+1,@"Application load: same-size overwrite with restored mtime reloads");
 old=d.myPDFKitView.document;

 // Polling stats and snapshots never run on the main thread.
 mainSignatures=workerSignatures=mainSnapshots=0;attempts=snapshotCount;
 [changed writeToFile:path atomically:YES];StablePoll(d);
 Check(d.myPDFKitView.document!=old,@"Content change reloads");
 Expect(mainSignatures==0 && workerSignatures>=2 && mainSnapshots==0 && snapshotCount==attempts+1,@"File checks and snapshots run off the main thread");

 // A stalled file access leaves the main run loop responsive and checks do not pile up.
 old=d.myPDFKitView.document;[first writeToFile:path atomically:YES];
 stallChecks=YES;stallEntries=0;
 NSDate *started=[NSDate date];[d refreshPDFWindow:nil];NSTimeInterval spent=-started.timeIntervalSinceNow;
 Expect(spent<.5,[NSString stringWithFormat:@"Stalled file access blocks the main thread for %.2fs",spent]);
 __block NSUInteger ticks=0;NSTimer *tick=[NSTimer scheduledTimerWithTimeInterval:.02 repeats:YES block:^(NSTimer *t){ticks++;}];
 for(int i=0;i<5;i++){[d refreshPDFWindow:nil];Pump(.06);}
 [tick invalidate];
 Expect(ticks>=8 && stallEntries==1 && d.externalPDFCheckRunning,@"Main run loop stays responsive; one check at a time");
 stallChecks=NO;dispatch_semaphore_signal(stallRelease);WaitIdle(d);
 Check(d.myPDFKitView.document==old,@"First observation after a stall only waits for stability");
 StablePoll(d);Check(d.myPDFKitView.document!=old,@"Reload resumes after the stall");

 // Results superseded while the check was running are dropped.
 old=d.myPDFKitView.document;[changed writeToFile:path atomically:YES];Poll(d);
 attempts=snapshotCount;stallChecks=YES;[d refreshPDFWindow:nil];Pump(.05);
 NoteLoaded(d,path);
 stallChecks=NO;dispatch_semaphore_signal(stallRelease);WaitIdle(d);Pump(.1);
 Expect(snapshotCount==attempts+1 && d.myPDFKitView.document==old,@"Result superseded by an application reload is dropped");
 old=d.myPDFKitView.document;[first writeToFile:path atomically:YES];Poll(d);
 stallChecks=YES;[d refreshPDFWindow:nil];Pump(.05);
 NSTask *job=[NSTask new];job.executableURL=[NSURL fileURLWithPath:@"/bin/sleep"];job.arguments=@[@"3"];
 [job launchAndReturnError:NULL];d.texTask=job;
 stallChecks=NO;dispatch_semaphore_signal(stallRelease);WaitIdle(d);Pump(.1);
 Expect(d.myPDFKitView.document==old,@"Typesetting started during a check prevents its reload");
 [job terminate];[job waitUntilExit];d.texTask=nil;
 old=d.myPDFKitView.document;Poll(d);stallChecks=YES;[d refreshPDFWindow:nil];Pump(.05);
 [d stopExternalPDFObservation];
 stallChecks=NO;dispatch_semaphore_signal(stallRelease);WaitIdle(d);Pump(.1);
 Expect(d.myPDFKitView.document==old,@"Closed document ignores a late result");
 // A running check does not keep a released document alive.
 __weak TSDocument *weakDocument;
 @autoreleasepool {
  TSDocument *e=[TSDocument new];e.fileURL=d.fileURL;e->taskDone=YES;e.pdfKitWindow=[TestWindow new];e.documentType=isPDF;weakDocument=e;
  [e startExternalPDFObservation];[e.pdfRefreshTimer invalidate];[changed writeToFile:path atomically:YES];
  stallChecks=YES;[e refreshPDFWindow:nil];Pump(.05);[e stopExternalPDFObservation];e=nil;
 }
 Expect(weakDocument==nil,@"Background check does not retain the document");
 stallChecks=NO;dispatch_semaphore_signal(stallRelease);Pump(.2);
 [window close];
 Expect(TSTestDigests>0 && TSTestMainDigests==0,[NSString stringWithFormat:@"Content digests run off the main thread (%lu of %lu on main)",(unsigned long)TSTestMainDigests,(unsigned long)TSTestDigests]);
 if(failures) exit(1);
 printf("PASS: metadata-only changes, same-size overwrites with restored mtime, background checks and digests, stalled access, stale results\n");

 // Automatic reloading off: returning to TeXShop or to the preview checks the PDF.
 {
 TSIsolatedAppKitDefaults.values=[@{@"PdfRefresh":@NO,@"PdfFileRefresh":@YES,@"RefreshTime":@0.5} mutableCopy];
 NSString *tex=[@(argv[1]) stringByAppendingPathComponent:@"return.tex"],*pdf=[@(argv[1]) stringByAppendingPathComponent:@"return.pdf"];
 [@"" writeToFile:tex atomically:YES encoding:NSUTF8StringEncoding error:NULL];[first writeToFile:pdf atomically:YES];
 VisibleWindow *shown=[[VisibleWindow alloc] initWithContentRect:NSMakeRect(0,0,900,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 shown.releasedWhenClosed=NO;
 NSWindow *other=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,100,100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];other.releasedWhenClosed=NO;
 TSDocument *r=[TSDocument new];r.fileURL=[NSURL fileURLWithPath:tex];r->taskDone=YES;r.pdfKitWindow=[TestWindow new];r.documentType=isTeX;
 r.myPDFKitView=[[RecoveryView alloc] initWithFrame:NSMakeRect(0,0,900,600)];r.myPDFKitView2=nil;
 RecoveryView *v=r.myPDFKitView;v.myPDFWindow=r.pdfKitWindow;v.myDocument=[TestDocument new];v.myDocument.pdfKitWindow=r.pdfKitWindow;
 [shown.contentView addSubview:v];v.document=[[PDFDocument alloc]initWithData:first];v.displayMode=kPDFDisplaySinglePageContinuous;v.autoScales=NO;v.scaleFactor=1.4;
 [v goToDestination:[[PDFDestination alloc]initWithPage:[v.document pageAtIndex:6] atPoint:NSMakePoint(170,520)]];Pump(.1);
 NoteLoaded(r,pdf);
 [r configureExternalPDFObservation];
 Check(!r.pdfRefreshTimer && !r.pdfActivity,@"Off: no watching timer or activity");
 NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
 void (^Return)(id)=^(id object){[center postNotificationName:(object==NSApp?NSApplicationDidBecomeActiveNotification:NSWindowDidBecomeKeyNotification) object:object];WaitIdle(r);Pump(.05);};
 TSExternalPDFPosition kept=TSExternalPDFCapture(v);
 PDFDocument *old=v.document;[changed writeToFile:pdf atomically:YES];
 Pump(1.2);Check(v.document==old,@"Off: a rewritten PDF is not reloaded while TeXShop is not returned to");
 Return(other);Check(v.document==old,@"Off: another window becoming key does not check");
 Return(NSApp);Check(v.document!=old,@"Off: returning to TeXShop reloads at once");SamePosition(v,kept,@"return to TeXShop");
 Check(r.externalPDFFollowTimer!=nil,@"Off: a change found on returning is followed");
 Pump(4.6);Check(r.externalPDFFollowTimer==nil,@"Off: following stops after the PDF is quiet for three seconds");
 // Returning several times in a row does not shorten the three quiet seconds.
 old=v.document;[first writeToFile:pdf atomically:YES];Return(NSApp);Check(v.document!=old,@"Off: returning again reloads");
 Return(shown);Return(NSApp);Return(shown);Check(r.externalPDFFollowTimer!=nil,@"Off: returning again and again does not end following early");
 old=v.document;Pump(1.2);[changed writeToFile:pdf atomically:YES];Pump(1.6);
 Check(v.document!=old,@"Off: a pass written soon after repeated returns is loaded");
 Pump(4.6);Check(r.externalPDFFollowTimer==nil,@"Off: following stops after repeated returns");
 // A PDF still being written does not open; it is shown once complete.
 old=v.document;kept=TSExternalPDFCapture(v);NSData *third=PDF(12,3);
 [[third subdataWithRange:NSMakeRange(0,third.length/2)] writeToFile:pdf atomically:NO];
 Return(shown);Check(v.document==old,@"Off: a partly written PDF is not loaded");
 Check(r.externalPDFFollowTimer!=nil,@"Off: a partly written PDF is followed");
 Pump(1.2);[third writeToFile:pdf atomically:NO];
 Pump(2.4);Check(v.document!=old,@"Off: the completed PDF is loaded while following");SamePosition(v,kept,@"completed while following");
 // Later typesetting passes within the follow period are shown too.
 old=v.document;Pump(1.1);[first writeToFile:pdf atomically:YES];Pump(2.4);
 Check(v.document!=old,@"Off: a second pass soon after is loaded while following");
 Pump(4.6);Check(r.externalPDFFollowTimer==nil,@"Off: following stops again");
 // A writer pausing between pages: the partly written PDF stays the same for
 // longer than three seconds, and following continues until it is complete.
 old=v.document;kept=TSExternalPDFCapture(v);NSData *fourth=PDF(12,4);
 [[fourth subdataWithRange:NSMakeRange(0,fourth.length/2)] writeToFile:pdf atomically:NO];
 Return(shown);Check(v.document==old && r.externalPDFFollowTimer!=nil,@"Off: a paused writer's partial PDF is followed");
 Pump(4.6);Check(v.document==old && r.externalPDFFollowTimer!=nil,@"Off: following continues while the PDF does not open");
 [fourth writeToFile:pdf atomically:NO];Pump(2.4);
 Check(v.document!=old,@"Off: the PDF completed after a pause is loaded");SamePosition(v,kept,@"completed after a pause");
 Pump(4.6);Check(r.externalPDFFollowTimer==nil,@"Off: following stops once the completed PDF is quiet");
 // An unreadable PDF written in place with the same size and modification time
 // is not quiet either; the completed PDF written the same way is loaded.
 {
  NSData *fifth=PDF(12,5),*sixth=PDF(12,6);NSUInteger size=MAX(fifth.length,sixth.length)+64;
  [Padded(fifth,size) writeToFile:pdf atomically:YES];Return(NSApp);Check(v.document.pageCount==12,@"Off: padded PDF loaded");
  Pump(4.6);Check(r.externalPDFFollowTimer==nil,@"Off: following stops before the same-size overwrite");
  old=v.document;kept=TSExternalPDFCapture(v);
  NSMutableData *broken=[Padded(fifth,size) mutableCopy];memset((char *)broken.mutableBytes+size/3,'x',size-size/3);
  OverwriteKeepingTimes(pdf,broken);Return(shown);
  Check(v.document==old && r.externalPDFFollowTimer!=nil,@"Off: an unreadable same-size overwrite is not loaded and is followed");
  Pump(4.6);Check(v.document==old && r.externalPDFFollowTimer!=nil,@"Off: following continues while the same-size overwrite does not open");
  OverwriteKeepingTimes(pdf,Padded(sixth,size));Pump(2.4);
  Check(v.document!=old,@"Off: the completed same-size overwrite is loaded");SamePosition(v,kept,@"same-size overwrite");
  Pump(4.6);Check(r.externalPDFFollowTimer==nil,@"Off: following stops after the same-size overwrite");
 }
 // A PDF deleted while following, as some tools do before writing, is not quiet;
 // the PDF written later is loaded.
 old=v.document;kept=TSExternalPDFCapture(v);[changed writeToFile:pdf atomically:YES];Return(NSApp);
 Check(v.document!=old && r.externalPDFFollowTimer!=nil,@"Off: a change before deletion is loaded and followed");
 old=v.document;kept=TSExternalPDFCapture(v);
 [NSFileManager.defaultManager removeItemAtPath:pdf error:NULL];Return(shown);
 Pump(4.6);Check(v.document==old && r.externalPDFFollowTimer!=nil,@"Off: following continues while the PDF is missing");
 [first writeToFile:pdf atomically:YES];Pump(2.4);
 Check(v.document!=old,@"Off: the PDF written after deletion is loaded");SamePosition(v,kept,@"written after deletion");
 Pump(4.6);Check(r.externalPDFFollowTimer==nil,@"Off: following stops after the PDF is written again");
 // Following ends after two minutes even while the file keeps changing.
 [changed writeToFile:pdf atomically:YES];Return(NSApp);Check(r.externalPDFFollowTimer!=nil,@"Off: following restarts");
 r.externalPDFFollowDeadline=0;Pump(1.3);Check(r.externalPDFFollowTimer==nil,@"Off: following ends at its deadline");
 // What blocks timer reloads blocks reloads on returning.
 old=v.document;[first writeToFile:pdf atomically:YES];
 r.annotationsExist=YES;Return(NSApp);Check(v.document==old,@"Off: unsaved annotations are protected");r.annotationsExist=NO;
 NSTask *job=[NSTask new];job.executableURL=[NSURL fileURLWithPath:@"/bin/sleep"];job.arguments=@[@"3"];
 [job launchAndReturnError:NULL];r.texTask=job;Return(NSApp);Check(v.document==old,@"Off: typesetting in TeXShop blocks the reload");
 [job terminate];[job waitUntilExit];r.texTask=nil;
 [r.pdfKitWindow close];Return(NSApp);Check(v.document==old,@"Off: a closed preview is not reloaded");
 [r.pdfKitWindow orderWindow:NSWindowAbove relativeTo:0];
 // A load made by TeXShop itself is not repeated.
 NoteLoaded(r,pdf);old=v.document;Return(NSApp);Check(v.document==old,@"Off: an acknowledged load is not repeated");
 Pump(.5);[r stopFollowingExternalPDF];
 // Automatic reloading on: returning also reloads at once; the timer needs no following.
 TSIsolatedAppKitDefaults.values=[@{@"PdfRefresh":@YES,@"PdfFileRefresh":@YES,@"RefreshTime":@30} mutableCopy];
 [r startExternalPDFObservation];Check(r.pdfRefreshTimer!=nil,@"On: watching timer");
 old=v.document;[changed writeToFile:pdf atomically:YES];Return(NSApp);
 Check(v.document!=old && r.externalPDFFollowTimer==nil,@"On: returning reloads at once without following");
 [r stopExternalPDFObservation];
 old=v.document;[first writeToFile:pdf atomically:YES];Return(NSApp);Check(v.document==old,@"Closed document ignores returning");
 // PdfFileRefresh NO keeps PDFs opened by themselves as they are.
 TSIsolatedAppKitDefaults.values=[@{@"PdfRefresh":@NO,@"PdfFileRefresh":@NO} mutableCopy];
 TSDocument *q=[TSDocument new];q.fileURL=[NSURL fileURLWithPath:pdf];q->taskDone=YES;q.pdfKitWindow=[TestWindow new];q.documentType=isPDF;q.myPDFKitView=v;
 v.document=[[PDFDocument alloc]initWithData:first];NoteLoaded(q,pdf);[q configureExternalPDFObservation];
 old=v.document;[changed writeToFile:pdf atomically:YES];Return(NSApp);Check(v.document==old,@"PdfFileRefresh NO: a PDF opened by itself is not reloaded");
 [q stopExternalPDFObservation];
 [shown close];[other close];
 printf("PASS: automatic reloading off: returning to TeXShop or the preview, partly written PDFs, following later passes, blocking, PdfFileRefresh\n");
 }
}}
'''.replace('CONTROLLER',controller)
with tempfile.TemporaryDirectory(prefix='texshop-external-pdf-') as td:
 p=Path(td);(p/'home').mkdir();(p/'test.m').write_text(program)
 # Count content digests, and the ones made on the main thread.
 text=(root/'Sources/Preview/TSExternalPDFSnapshot.m').read_text()
 digest='static NSData *TSPDFDigest(NSString *path, NSString *signature, NSString *changeTime)\n{\n'
 assert text.count(digest)==1
 text=text.replace(digest,'#include <stdatomic.h>\nextern atomic_ulong TSTestDigests, TSTestMainDigests;\n'+digest+'    TSTestDigests++; if (NSThread.isMainThread) TSTestMainDigests++;\n')
 snapshot=p/'TSExternalPDFSnapshot.m';snapshot.write_text(text)
 if mutation=='ctime':
  # Put ctime back into the signature; the quoted include then resolves to this copy.
  header=(root/'Sources/Preview/TSExternalPDFReload.h').read_text()
  old='info->st_mtimespec.tv_nsec];'
  assert header.count(old)==1 and header.count('%lld:%ld", path')==1
  (p/'TSExternalPDFReload.h').write_text(header.replace(old,'info->st_mtimespec.tv_nsec, (long long)info->st_ctimespec.tv_sec, info->st_ctimespec.tv_nsec];').replace('%lld:%ld", path','%lld:%ld:%lld:%ld", path'))
 elif mutation and mutation not in mutations: raise SystemExit('unknown mutation')
 subprocess.run(['xcrun','clang','-I',str(root/'Tests'),'-w','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',*include_args(root),str(p/'test.m'),str(root/'Sources/Preview/HideView.m'),str(root/'Sources/Settings/TSPreferenceProfile.m'),str(root/'Sources/App/globals.m'),str(snapshot),str(root/'Sources/Preview/TSPreviewScrollerKeeper.m'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test'),td]+(['--ltr'] if '--ltr' in sys.argv else []),env=dict(os.environ,CFFIXED_USER_HOME=str(p/'home')),check=True)
