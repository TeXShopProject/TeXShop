#!/usr/bin/env python3
"""Terada: Exercise production PDF reload methods with real PDFKit views in isolation."""
from pathlib import Path
import ast, os, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
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
s=(root/'Sources/TSDocument.m').read_text()
controller='\n'.join(method(s,x) for x in ['- (NSString *)externalPDFPath','- (void)startExternalPDFObservation','- (void)notePDFLoadedAtPath:', '- (void)refreshPDFWindow:'])
program=fixture+r'''
#import "TSExternalPDFReload.h"
#define PdfRefreshKey @"PdfRefresh"
#define PdfFileRefreshKey @"PdfFileRefresh"
#define isPDF 2
@interface TSDocument:NSObject { @public BOOL taskDone,_externalEditor,PDFfromKit; }
@property NSURL *fileURL;
@property RecoveryView *myPDFKitView,*myPDFKitView2;
@property TestWindow *pdfKitWindow;
@property NSTask *texTask;
@property BOOL annotationsExist;
@property NSInteger documentType;
@property NSString *externalPDFLoadedSignature,*externalPDFPendingSignature;
@property NSTimer *pdfRefreshTimer;
@property NSDate *pdfLastModDate;
- (void)refreshPDFWindow:(NSTimer*)timer;
@end
@implementation TSDocument
CONTROLLER
@end
static void Check(BOOL ok,NSString *message){if(!ok){NSLog(@"FAIL: %@",message);exit(1);}}
static void Pump(double seconds){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];while(end.timeIntervalSinceNow>0)[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
static NSData *PDF(NSInteger pages,NSInteger revision) {
 NSMutableData *data=[NSMutableData data]; CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
 CGRect box=CGRectMake(0,0,612,792);CGContextRef context=CGPDFContextCreate(consumer,&box,NULL);
 for(NSInteger i=0;i<pages;i++) {CGPDFContextBeginPage(context,NULL);CGContextSetRGBFillColor(context,1,1,1,1);CGContextFillRect(context,box);CGContextSetRGBFillColor(context,.2,.4,.6,1);CGContextFillRect(context,CGRectMake(40,100+i*10,100+revision*10,30));CGPDFContextEndPage(context);}
 CGPDFContextClose(context);CGContextRelease(context);CGDataConsumerRelease(consumer);return data;
}
static void StablePoll(TSDocument *d){[d refreshPDFWindow:nil];[d refreshPDFWindow:nil];Pump(.15);}
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
 [d startExternalPDFObservation];Check([[d externalPDFPath]isEqualToString:path],@"Uppercase PDF path");
 [d.pdfRefreshTimer invalidate];
 TSExternalPDFPosition one=TSExternalPDFCapture(d.myPDFKitView),two=TSExternalPDFCapture(d.myPDFKitView2);
 PDFDocument *old=d.myPDFKitView.document;
 [changed writeToFile:path atomically:YES];[d refreshPDFWindow:nil];Check(d.myPDFKitView.document==old,@"Wait for stable observation");
 [d refreshPDFWindow:nil];Pump(.15);Check(d.myPDFKitView.document!=old,@"Atomic replacement reload");SamePosition(d.myPDFKitView,one,@"primary");SamePosition(d.myPDFKitView2,two,@"secondary");
 old=d.myPDFKitView.document;[[changed subdataWithRange:NSMakeRange(0,changed.length/2)]writeToFile:path atomically:NO];StablePoll(d);Check(d.myPDFKitView.document==old,@"Partial PDF retains good display");
 [first writeToFile:path atomically:NO];StablePoll(d);Check(d.myPDFKitView.document!=old,@"Partial to valid recovery");SamePosition(d.myPDFKitView,one,@"recovered");
 old=d.myPDFKitView.document;[[NSFileManager defaultManager]removeItemAtPath:path error:NULL];StablePoll(d);Check(d.myPDFKitView.document==old,@"Deleted PDF retains display");[changed writeToFile:path atomically:YES];StablePoll(d);Check(d.myPDFKitView.document!=old,@"Recreation reload");
 old=d.myPDFKitView.document;d.annotationsExist=YES;[first writeToFile:path atomically:YES];StablePoll(d);Check(d.myPDFKitView.document==old,@"Protect annotations");d.annotationsExist=NO;
 d->taskDone=NO;StablePoll(d);Check(d.myPDFKitView.document==old,@"Defer during typesetting");d->taskDone=YES;
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
 [window close];printf("PASS autoScale=%d mode=%ld: viewport, zoom, atomic save, partial/deleted/recreated PDF, annotations, typesetting, independent writer + timer\n",fit.boolValue,(long)mode.integerValue);
 }
}}
'''.replace('CONTROLLER',controller)
with tempfile.TemporaryDirectory(prefix='texshop-external-pdf-') as td:
 p=Path(td);(p/'home').mkdir();(p/'test.m').write_text(program)
 subprocess.run(['xcrun','clang','-w','-fobjc-arc','-framework','Cocoa','-framework','PDFKit','-I',str(root/'Sources'),str(p/'test.m'),str(root/'Sources/HideView.m'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test'),td],env=dict(os.environ,CFFIXED_USER_HOME=str(p/'home')),check=True)
