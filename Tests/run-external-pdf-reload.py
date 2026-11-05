#!/usr/bin/env python3
"""Exercise production PDF reload methods with real PDFKit views in isolation."""
from pathlib import Path
import ast, os, shutil, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
# --mutation=NAME reverts one behaviour in memory to show that its checks fail.
mutation = next((a.split('=',1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
# Reuse only the inert view/window fixtures, not the old method-selection logic.
tree = ast.parse((root/'Tests/run-pdf-recovery.py').read_text())
fixture = max((n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value,str)),key=len)
fixture = fixture[:fixture.index('static void check(')]
fixture = fixture.replace('-(void)reShowWithPath:(NSString*)path;', '-(void)reShowWithPath:(NSString*)path;\n-(void)reShowWithDocument:(PDFDocument*)document;')
s=(root/'Sources/MyPDFKitView.m').read_text(encoding='latin1')
def method(s, signature):
    a=s.rindex(signature); return s[a:s.index('\n}',a)+2]
methods='\n'.join(method(s,x) for x in ['- (void)reShowWithPath:', '- (void)reShowWithDocument:', '- (void)prepareSecond', '- (void) reShowForSecond', '- (void) initializeDisplay', '- (void)removeHideView1:', '- (void)removeHideView2:'])
fixture=fixture.replace('METHODS',methods)
fixture=fixture.replace('@implementation TestWindow', '@implementation TestWindow\n- (void)setRepresentedFilename:(NSString *)s {}\n- (void)setTitle:(NSString *)s {}\n- (BOOL)isVisible { return YES; }\n- (void)makeKeyAndOrderFront:(id)sender {}')
s=(root/'Sources/TSDocument.m').read_text()
controller='\n'.join(method(s,x) for x in ['- (NSString *)externalPDFPath','- (BOOL)externalPDFObservationEnabled', '- (void)externalPDFSettingsChanged:', '- (void)configureExternalPDFObservation','- (void)stopExternalPDFObservation','- (void)startExternalPDFObservation','- (void)notePDFLoadedAtPath:', '- (BOOL)externalPDFReloadBlocked'])
# Count and optionally stall the file checks made by the polling path only.
controller+='\n'+method(s,'- (void)refreshPDFWindow:').replace('TSExternalPDFSignature(', 'CheckedSignature(')
controller+='\n'+'\n'.join(method(s,x) for x in ['- (void)finishExternalPDFCheck:', '- (void)applyExternalPDFPath:'])
controller=controller.replace('TSExternalPDFSnapshot(', 'CountedSnapshot(')
mutations={
 'inline': ('dispatch_async(self.externalPDFQueue, ^{', 'RunInline(^{'),
 'generation': ('generation == self.externalPDFGeneration && ', ''),
 'taskdone': ('return ![self externalPDFObservationEnabled] || ', 'return ![self externalPDFObservationEnabled] || !taskDone || '),
}
if mutation in mutations:
    old,new=mutations[mutation]; assert old in controller; controller=controller.replace(old,new)
program=fixture+r'''
#import "TSExternalPDFReload.h"
#include <stdatomic.h>
#include <sys/xattr.h>
static atomic_ulong snapshotCount, mainSnapshots, mainSignatures, workerSignatures, stallEntries;
static atomic_bool stallChecks;
static dispatch_semaphore_t stallRelease;
static PDFDocument *CountedSnapshot(NSString *p, NSString *s) { snapshotCount++; if(NSThread.isMainThread) mainSnapshots++; return TSExternalPDFSnapshot(p,s); }
// Simulates a stalled network volume or an online-only file being fetched.
static NSString *CheckedSignature(NSString *p) {
 if(NSThread.isMainThread) mainSignatures++; else workerSignatures++;
 if(stallChecks){stallEntries++;dispatch_semaphore_wait(stallRelease,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC));}
 return TSExternalPDFSignature(p);
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
@property NSString *externalPDFLoadedSignature,*externalPDFPendingSignature;
@property NSTimer *pdfRefreshTimer;
@property NSDate *pdfLastModDate;
@property id pdfActivity;
@property NSString *externalPDFFailedSignature;
@property NSTimeInterval externalPDFFailedRetryTime;
@property BOOL externalPDFObservationClosed;
@property (strong) dispatch_queue_t externalPDFQueue;
@property NSUInteger externalPDFGeneration;
@property BOOL externalPDFCheckRunning;
- (void)refreshPDFWindow:(NSTimer*)timer;
@end
@implementation TSDocument
- (void)allocateSyncScanner {}
- (void)allocateSyncScannerOld {}
- (void)fillLogWindowIfVisible {}
CONTROLLER
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
 [NSApplication sharedApplication];
 [SUD setVolatileDomain:@{@"PdfRefresh":@YES,@"PdfFileRefresh":@YES,@"RefreshTime":@0.5} forName:NSArgumentDomain];
 NSString *path=[@(argv[1]) stringByAppendingPathComponent:@"test.PDF"];
 NSData *first=PDF(12,1),*changed=PDF(12,2);
 for(NSNumber *fit in @[@NO,@YES]) for(NSNumber *mode in @[@(kPDFDisplaySinglePage),@(kPDFDisplaySinglePageContinuous),@(kPDFDisplayTwoUp),@(kPDFDisplayTwoUpContinuous)]) {
 [first writeToFile:path atomically:YES];
 NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 window.releasedWhenClosed=NO;
 TSDocument *d=[TSDocument new];d.fileURL=[NSURL fileURLWithPath:path];d->taskDone=YES;d.pdfKitWindow=[TestWindow new];
 d.myPDFKitView=[[RecoveryView alloc] initWithFrame:NSMakeRect(0,0,450,600)];d.myPDFKitView2=[[RecoveryView alloc] initWithFrame:NSMakeRect(450,0,450,600)];
 for(RecoveryView *v in @[d.myPDFKitView,d.myPDFKitView2]) {
 v.myPDFWindow=d.pdfKitWindow;v.myDocument=[TestDocument new];v.myDocument.pdfKitWindow=d.pdfKitWindow;
 [window.contentView addSubview:v];v.document=[[PDFDocument alloc]initWithData:first];v.displayMode=mode.integerValue;v.autoScales=fit.boolValue;if(!fit.boolValue)v.scaleFactor=1.6;
 [v goToDestination:[[PDFDestination alloc]initWithPage:[v.document pageAtIndex:(v==d.myPDFKitView?4:8)] atPoint:NSMakePoint(170,520)]];
 }
 Pump(.1);
 [SUD setVolatileDomain:@{@"PdfRefresh":@NO} forName:NSArgumentDomain];
 [d startExternalPDFObservation];Check(d.pdfRefreshTimer==nil && d.pdfActivity==nil,@"Disabled observation has no timer/activity");
 [SUD setVolatileDomain:@{@"PdfRefresh":@YES,@"PdfFileRefresh":@NO,@"RefreshTime":@0.5} forName:NSArgumentDomain];
 d.documentType=isPDF; [d configureExternalPDFObservation];
 Check(!d.pdfRefreshTimer && !d.pdfActivity,@"PDF-only opt-out prevents startup");
 d.documentType=3;[d configureExternalPDFObservation];[d startExternalPDFObservation];
 Check(!d.pdfRefreshTimer && !d.pdfActivity,@"Image document cannot observe a sibling PDF");
 d.documentType=isPDF;
 [SUD setVolatileDomain:@{@"PdfRefresh":@YES,@"PdfFileRefresh":@YES,@"RefreshTime":@0.5} forName:NSArgumentDomain];
 [d startExternalPDFObservation];Check([[d externalPDFPath]isEqualToString:path],@"Uppercase PDF path");
 [d.pdfRefreshTimer invalidate];
 TSExternalPDFPosition one=TSExternalPDFCapture(d.myPDFKitView),two=TSExternalPDFCapture(d.myPDFKitView2);
 PDFDocument *old=d.myPDFKitView.document;
 [changed writeToFile:path atomically:YES];Poll(d);Check(d.myPDFKitView.document==old,@"Wait for stable observation");
 Poll(d);Pump(.15);Check(d.myPDFKitView.document!=old,@"Atomic replacement reload");SamePosition(d.myPDFKitView,one,@"primary");SamePosition(d.myPDFKitView2,two,@"secondary");
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
 d.pdfKitWindow.previewClosed=YES;StablePoll(d);Check(d.myPDFKitView.document==old,@"Do not reopen preview");d.pdfKitWindow.previewClosed=NO;StablePoll(d);Check(d.myPDFKitView.document!=old,@"Resume after gates");
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
 Check([d.myPDFKitView.document indexForPage:d.myPDFKitView.visiblePages.firstObject]<=1,@"Short-to-long PDF keeps original first spread visible within scroll bounds");
 old=d.myPDFKitView.document;[d notePDFLoadedAtPath:path signature:TSExternalPDFSignature(path)];
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
 v.myPDFWindow=d.pdfKitWindow;v.myDocument=[TestDocument new];v.myDocument.pdfKitWindow=d.pdfKitWindow;
 [window.contentView addSubview:v];v.document=[[PDFDocument alloc]initWithData:first];
 }
 [d startExternalPDFObservation];[d.pdfRefreshTimer invalidate];
 PDFDocument *old=d.myPDFKitView.document;

 // Sync clients and Finder set extended attributes after typesetting; only ctime changes.
 struct stat before,after;Check(stat(path.fileSystemRepresentation,&before)==0,@"stat");usleep(20000);
 uint8_t used[16]={1,2,3};Check(setxattr(path.fileSystemRepresentation,"com.apple.lastuseddate#PS",used,sizeof used,0,0)==0,@"Set extended attribute");
 Check(stat(path.fileSystemRepresentation,&after)==0 && (after.st_ctimespec.tv_sec!=before.st_ctimespec.tv_sec || after.st_ctimespec.tv_nsec!=before.st_ctimespec.tv_nsec) &&
  after.st_mtimespec.tv_sec==before.st_mtimespec.tv_sec && after.st_mtimespec.tv_nsec==before.st_mtimespec.tv_nsec,@"Extended attribute changes ctime but not mtime");
 NSUInteger attempts=snapshotCount;StablePoll(d);StablePoll(d);
 Expect(d.myPDFKitView.document==old && snapshotCount==attempts,@"Metadata-only change does not reload the PDF");

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
 [d notePDFLoadedAtPath:path signature:TSExternalPDFSignature(path)];
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
 if(failures) exit(1);
 printf("PASS: metadata-only changes, background checks, stalled access, stale results\n");
}}
'''.replace('CONTROLLER',controller)
with tempfile.TemporaryDirectory(prefix='texshop-external-pdf-') as td:
 p=Path(td);(p/'home').mkdir();(p/'test.m').write_text(program)
 snapshot=root/'Sources/TSExternalPDFSnapshot.m'
 if mutation=='ctime':
  # The quoted include resolves beside each source file, so copy both.
  header=(root/'Sources/TSExternalPDFReload.h').read_text()
  old='info.st_mtimespec.tv_nsec];'
  assert old in header
  (p/'TSExternalPDFReload.h').write_text(header.replace(old,'info.st_mtimespec.tv_nsec, (long long)info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec];').replace('%lld:%ld", path','%lld:%ld:%lld:%ld", path'))
  snapshot=shutil.copy(snapshot,p)
 subprocess.run(['xcrun','clang','-w','-fobjc-arc','-framework','Cocoa','-framework','PDFKit','-I',str(root/'Sources'),str(p/'test.m'),str(root/'Sources/HideView.m'),str(snapshot),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test'),td],env=dict(os.environ,CFFIXED_USER_HOME=str(p/'home')),check=True)
