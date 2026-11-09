#!/usr/bin/env python3
"""Exercise production page-navigation actions in isolated, hidden PDFKit views."""
import argparse
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['native-corners', 'raw-page-delta', 'continuous-restore', 'always-restore'])
parser.add_argument('--artifacts', type=Path, help='Keep the generated Objective-C and executable for cross-OS testing')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
def method(signature):
    start = source.rindex(signature)
    return source[start:source.index('\n}', start) + 2]
methods = '\n'.join(method(signature) for signature in (
    '- (void)stepPageForward:', '- (void) previousPage:', '- (void) nextPage:'))
if args.mutation == 'native-corners':
    methods = methods.replace('TSExternalPDFRestore(self, viewport);', '')
elif args.mutation == 'raw-page-delta':
    methods = methods.replace('if (self.displayMode == kPDFDisplayTwoUp) {', 'if (NO) {')
elif args.mutation == 'continuous-restore':
    methods = methods.replace('if (self.displayMode == kPDFDisplaySinglePage || self.displayMode == kPDFDisplayTwoUp) {', 'if (YES) {')
elif args.mutation == 'always-restore':
    methods = methods.replace('if (actual.valid && actual.pageIndex == viewport.pageIndex &&', 'if (NO && actual.valid && actual.pageIndex == viewport.pageIndex &&')
# Count only restoration requested by the production action, not native simulation.
methods = methods.replace('TSExternalPDFRestore(self, viewport);', 'CountedRestore(self, viewport);')
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import <PDFKit/PDFKit.h>
#import "TSExternalPDFReload.h"
static NSUInteger restorationCount;
static void CountedRestore(PDFView *view, TSExternalPDFPosition position) {
 restorationCount++; TSExternalPDFRestore(view, position);
}
#define PDF_SINGLE_PAGE_STYLE 1
#define PDF_TWO_PAGE_STYLE 2
@interface NavigationView:PDFView { NSInteger pageStyle; }
-(void)cleanupMarquee:(BOOL)b;
-(void)stepPageForward:(BOOL)forward sender:(id)sender;
-(void)previousPage:(id)sender;
-(void)nextPage:(id)sender;
@end
@implementation NavigationView
-(void)cleanupMarquee:(BOOL)b {}
METHODS
@end
// PDFKit may identify either member of a visible spread as currentPage.
// Force that valid ambiguity without changing its native navigation itself.
@interface ReportedPageView : NavigationView
@property BOOL reportAlternate, reportRight;
@end
@implementation ReportedPageView
-(PDFPage *)currentPage {
 PDFPage *page=[super currentPage];
 if(!self.reportAlternate || !page) return page;
 NSUInteger index=[self.document indexForPage:page];
 NSUInteger target=index/2*2+(self.reportRight?1:0);
 return [self.document pageAtIndex:MIN(target,self.document.pageCount-1)];
}
-(void)goToNextPage:(id)sender {
 self.reportAlternate=NO;[super goToNextPage:sender];self.reportRight=NO;self.reportAlternate=YES;
}
-(void)goToPreviousPage:(id)sender {
 self.reportAlternate=NO;[super goToPreviousPage:sender];self.reportRight=YES;self.reportAlternate=YES;
}
@end
// Model a future PDFKit that retains the page-relative position itself.
@interface FixedNativeView : NavigationView
@property CGFloat nativeDrift;
@end
@implementation FixedNativeView
-(void)simulateNativeStep:(BOOL)forward sender:(id)sender {
 TSExternalPDFPosition position=TSExternalPDFCapture(self);
 if(forward) [super goToNextPage:sender]; else [super goToPreviousPage:sender];
 NSInteger stride=self.displayMode==kPDFDisplayTwoUp?2:1;
 position.pageIndex=(NSUInteger)((NSInteger)position.pageIndex+(forward?stride:-stride));
 position.pagePoint.y+=self.nativeDrift;
 TSExternalPDFRestore(self,position);
}
-(void)goToNextPage:(id)sender { [self simulateNativeStep:YES sender:sender]; }
-(void)goToPreviousPage:(id)sender { [self simulateNativeStep:NO sender:sender]; }
@end
static NSString *context;
static void check(BOOL ok, NSString *message) { if(!ok){fprintf(stderr,"FAIL: %s [%s]\n",message.UTF8String,context.UTF8String);exit(1);} }
static void pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.015]]; }
static void equal(TSExternalPDFPosition expected, PDFView *view, NSString *message) {
 TSExternalPDFPosition actual=TSExternalPDFCapture(view);
 CGFloat distance=hypot(actual.pagePoint.x-expected.pagePoint.x,actual.pagePoint.y-expected.pagePoint.y);
 if(actual.pageIndex!=expected.pageIndex||distance>=1.5) fprintf(stderr,"%s p%lu %s -> p%lu %s\n",message.UTF8String,expected.pageIndex,NSStringFromPoint(expected.pagePoint).UTF8String,actual.pageIndex,NSStringFromPoint(actual.pagePoint).UTF8String);
 check(actual.valid&&actual.pageIndex==expected.pageIndex&&distance<1.5,message);
}
static PDFDocument *makePDF(BOOL varied, NSInteger rotation, NSUInteger count) {
 PDFDocument *pdf=[PDFDocument new];
 for(NSUInteger n=0;n<count;n++) {
  NSSize size=NSMakeSize(varied?600+20*(n%3):600,varied?800+30*(n%2):800);
  NSImage *image=[[NSImage alloc]initWithSize:size];[image lockFocus];[NSColor.whiteColor setFill];NSRectFill(NSMakeRect(0,0,size.width,size.height));[image unlockFocus];
  PDFPage *p=[[PDFPage alloc]initWithImage:image];p.rotation=rotation;[pdf insertPage:p atIndex:n];
 }return pdf;
}
int main(void) { @autoreleasepool {
 TSInstallAppKitIsolation(); [NSApplication sharedApplication];
 BOOL workaroundOS=NO; if (@available(macOS 27.0,*)) workaroundOS=YES;
 NSArray *documents=@[makePDF(NO,0,8),makePDF(NO,90,8),makePDF(YES,0,8),makePDF(YES,90,8)];
 for(NSInteger mode=0;mode<4;mode++)for(NSInteger style=0;style<2;style++)
 for(NSInteger book=0;book<2;book++)for(NSInteger rtl=0;rtl<2;rtl++)
 for(NSNumber *rotation in @[@0,@90])for(NSNumber *varied in @[@NO,@YES]) {
  context=[NSString stringWithFormat:@"mode=%ld style=%ld book=%ld rtl=%ld rotation=%@ varied=%@",mode,style,book,rtl,rotation,varied];
  NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,500,500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];w.releasedWhenClosed=NO;
  NavigationView *view=[[NavigationView alloc]initWithFrame:w.contentView.bounds];
  PDFView *control=[[PDFView alloc]initWithFrame:w.contentView.bounds];
  [w.contentView addSubview:view];[w.contentView addSubview:control];
  PDFDocument *doc=documents[(varied.boolValue?2:0)+(rotation.integerValue?1:0)];
  for(PDFView *v in @[view,control]) {
   v.document=doc;v.displayMode=mode;v.displaysAsBook=book;v.displaysRTL=rtl;v.scaleFactor=2;
   v.documentView.enclosingScrollView.scrollerStyle=style;
   TSExternalPDFPosition start={YES,NO,book?3:4,NSMakePoint(300,400),2};TSExternalPDFRestore(v,start);
  }pump();
  TSExternalPDFPosition before=TSExternalPDFCapture(view);
  [view nextPage:nil];[control goToNextPage:nil];pump();
  BOOL paginated=mode==kPDFDisplaySinglePage||mode==kPDFDisplayTwoUp;
  if(paginated && workaroundOS) {
   TSExternalPDFPosition expected=before;expected.pageIndex+=(mode==kPDFDisplayTwoUp?2:1);
   equal(expected,view,@"next page retains relative viewport");
   check(fabs(view.scaleFactor-2)<.001,@"navigation preserves fixed zoom");
  } else equal(TSExternalPDFCapture(control),view,@"continuous next matches unmodified PDFKit");
  [view previousPage:nil];[control goToPreviousPage:nil];pump();
  if(paginated && workaroundOS) equal(before,view,@"previous spread retains original viewport");
  else equal(TSExternalPDFCapture(control),view,@"continuous previous matches unmodified PDFKit");
  // Both ends are safe and must not jump to a different page.
  if(paginated && workaroundOS) {
   TSExternalPDFPosition first={YES,NO,0,NSMakePoint(300,400),2};TSExternalPDFRestore(view,first);pump();
   first=TSExternalPDFCapture(view);[view previousPage:nil];pump();equal(first,view,@"first-page boundary");
   TSExternalPDFPosition last={YES,NO,7,NSMakePoint(300,400),2};TSExternalPDFRestore(view,last);pump();
   last=TSExternalPDFCapture(view);[view nextPage:nil];pump();equal(last,view,@"last-page boundary");
  }
  view.document=[PDFDocument new];[view nextPage:nil];[view previousPage:nil];
  view.document=nil;control.document=nil;[view nextPage:nil];[view previousPage:nil];
  [view removeFromSuperview];[control removeFromSuperview];[w close];
 }
 // A native fix must bypass restoration, while a visible drift still needs it.
 if(workaroundOS) for(NSNumber *mode in @[@(kPDFDisplaySinglePage),@(kPDFDisplayTwoUp)])
 for(NSInteger style=0;style<2;style++) for(NSNumber *drift in @[@0,@0.1,@10]) {
  context=[NSString stringWithFormat:@"future native fix mode=%@ style=%ld drift=%@",mode,style,drift];
  NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,500,500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];w.releasedWhenClosed=NO;
  FixedNativeView *v=[[FixedNativeView alloc]initWithFrame:w.contentView.bounds];[w.contentView addSubview:v];
  v.document=documents[0];v.displayMode=mode.integerValue;v.scaleFactor=2;v.nativeDrift=drift.doubleValue;
  v.documentView.enclosingScrollView.scrollerStyle=style;
  TSExternalPDFPosition start={YES,NO,2,NSMakePoint(300,400),2};TSExternalPDFRestore(v,start);pump();
  for(NSNumber *forward in @[@YES,@NO]) {
   TSExternalPDFPosition expected=TSExternalPDFCapture(v);
   expected.pageIndex+=(forward.boolValue?1:-1)*(mode.integerValue==kPDFDisplayTwoUp?2:1);
   restorationCount=0;
   [v stepPageForward:forward.boolValue sender:nil];pump();
   equal(expected,v,@"native fix or workaround retains position");
   check(restorationCount==(drift.doubleValue>1?1:0),@"skip redundant restoration but correct visible drift");
  }
  v.document=nil;[v removeFromSuperview];[w close];
 }
 // Native currentPage can name the right page while the viewport is on
 // the left. This is why raw currentPage index differences are not enough.
 if (workaroundOS) for(NSInteger style=0;style<2;style++) {
  context=[NSString stringWithFormat:@"currentPage differs from viewport page, style=%ld",style];
  NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,500,500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];w.releasedWhenClosed=NO;
  ReportedPageView *v=[[ReportedPageView alloc]initWithFrame:w.contentView.bounds];[w.contentView addSubview:v];
  v.document=documents[0];v.displayMode=kPDFDisplayTwoUp;v.scaleFactor=2;
  v.documentView.enclosingScrollView.scrollerStyle=style;
  [v goToPage:[v.document pageAtIndex:1]];pump();
  NSClipView *c=v.documentView.enclosingScrollView.contentView;NSRect bounds=c.bounds;
  bounds.origin.x+=50;bounds.origin.y+=80;[c scrollToPoint:[c constrainBoundsRect:bounds].origin];pump();
  v.reportAlternate=YES;v.reportRight=YES;
  TSExternalPDFPosition before=TSExternalPDFCapture(v),next=before;next.pageIndex+=2;
  check(before.pageIndex==0,@"left page is visible while native selection names the right page");
  [v nextPage:nil];pump();equal(next,v,@"right currentPage does not shift target by one page");
  [v previousPage:nil];pump();equal(before,v,@"previous spread retains the left-page viewport");
  v.document=nil;[v removeFromSuperview];[w close];
 }
 // Returning from either page of the first full book spread must show
 // the cover rather than accidentally selecting page 1 again.
 if (workaroundOS) for (NSInteger rtl=0;rtl<2;rtl++) for(NSUInteger startPage=1;startPage<=2;startPage++) {
  context=[NSString stringWithFormat:@"book cover rtl=%ld startPage=%lu",rtl,startPage];
  NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,500,500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];w.releasedWhenClosed=NO;
  NavigationView *v=[[NavigationView alloc]initWithFrame:w.contentView.bounds];[w.contentView addSubview:v];
  v.document=documents[0];v.displayMode=kPDFDisplayTwoUp;v.displaysAsBook=YES;v.displaysRTL=rtl;v.scaleFactor=2;
  TSExternalPDFPosition start={YES,NO,startPage,NSMakePoint(300,400),2};TSExternalPDFRestore(v,start);pump();
  TSExternalPDFPosition before=TSExternalPDFCapture(v);check(before.pageIndex==startPage,@"capture selected member of book spread");
  [v previousPage:nil];pump();before.pageIndex=0;equal(before,v,@"previous spread reaches cover from either member");
  v.document=nil;[v removeFromSuperview];[w close];
 }
 // Auto-fit and an odd final spread should remain valid and in range.
 for(NSInteger book=0;book<2;book++) {
  context=[NSString stringWithFormat:@"auto-fit book=%ld",book];
  NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,700,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];w.releasedWhenClosed=NO;
  NavigationView *v=[[NavigationView alloc]initWithFrame:w.contentView.bounds];[w.contentView addSubview:v];
  v.document=makePDF(YES,0,5);v.displayMode=kPDFDisplayTwoUp;v.displaysAsBook=book;v.autoScales=YES;
  [v goToPage:[v.document pageAtIndex:2]];pump();[v nextPage:nil];pump();
  check(v.autoScales,@"auto-fit remains enabled");check([v.document indexForPage:v.currentPage]<5,@"odd final spread remains valid");
  [v previousPage:nil];pump();check(v.autoScales,@"auto-fit remains enabled on return");
  v.document=nil;[v removeFromSuperview];[w close];
 }
 puts("PASS: native page-navigation actions; single/two-up; book/RTL; legacy/overlay; rotation; page sizes; boundaries; future native fix and restoration count; nil document; auto-fit; continuous native behavior");
}return 0;}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-navigation-') as directory:
    temp=Path(directory)
    (temp/'home'/'Library'/'Preferences').mkdir(parents=True)
    (temp/'test.m').write_text(program)
    subprocess.run(['xcrun','clang', '-I', str(root/'Tests'),'-mmacosx-version-min=14.6','-w','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',
                    *include_args(root),str(temp/'test.m'),'-o',str(temp/'test')],check=True)
    if args.artifacts:
        args.artifacts.mkdir(parents=True, exist_ok=True)
        shutil.copy2(temp/'test.m', args.artifacts/'test.m')
        shutil.copy2(temp/'test', args.artifacts/'test')
    subprocess.run([str(temp/'test')],check=True,timeout=180,
                   env=dict(os.environ,HOME=str(temp/'home'),CFFIXED_USER_HOME=str(temp/'home')))
