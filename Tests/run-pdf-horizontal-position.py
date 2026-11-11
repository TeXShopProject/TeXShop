#!/usr/bin/env python3
"""Check that the Preview keeps its horizontal position when it changes pages or shows
a SyncTeX or Find result (#9), with the production methods in hidden PDFKit views."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['no-keep', 'no-go-to-page', 'selection-native', 'selection-always-keep'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
def method(signature):
    start = source.rindex(signature)
    return source[start:source.index('\n}', start) + 2]
methods = '\n'.join(method(signature) for signature in (
    '- (void)keepHorizontalPositionDuring:', '- (void)goToPage:(PDFPage *)page', '- (void)goToNextPage:',
    '- (void)goToPreviousPage:', '- (void)goToFirstPage:', '- (void)goToLastPage:',
    '- (void)scrollSelectionToVisible:', '- (void)stepPageForward:', '- (void) previousPage:', '- (void) nextPage:',
    '- (BOOL)scrollVerticalArrowWithinPage:', '- (void)keyDown:'))
def mutate(old, new):
    global methods
    assert old in methods, old
    methods = methods.replace(old, new)
if args.mutation == 'no-keep':
    mutate('keep = (self.displayMode == kPDFDisplaySinglePage', 'keep = NO && (self.displayMode == kPDFDisplaySinglePage')
elif args.mutation == 'no-go-to-page':
    mutate('[self keepHorizontalPositionDuring:^{ [super goToPage:page]; }];', '[super goToPage:page];')
elif args.mutation == 'selection-native':
    mutate('    if (!keep) return;\n    clip = self', '    return;\n    clip = self')
elif args.mutation == 'selection-always-keep':
    mutate('    if (!isnan(target))\n', '    target = x;\n')

program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import <PDFKit/PDFKit.h>
#import "TSExternalPDFReload.h"
#import "TSPreviewHorizontalPosition.h"
#define SUD NSUserDefaults.standardUserDefaults
#define LeftRightArrowsAlwaysPageKey @"LeftRightArrowsAlwaysPage"
#define PDF_SINGLE_PAGE_STYLE 1
#define PDF_TWO_PAGE_STYLE 2
static NSString *context;
static void check(BOOL ok, NSString *message) {
 if(!ok) { fprintf(stderr,"FAIL: %s [%s]\n",message.UTF8String,context.UTF8String); exit(1); }
}
static void pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]]; }
@interface PreviewView:PDFView { NSInteger pageStyle; }
-(void)stepPageForward:(BOOL)forward sender:(id)sender;
-(void)previousPage:(id)sender;
-(void)nextPage:(id)sender;
-(BOOL)scrollVerticalArrowWithinPage:(NSEvent *)event;
@end
@implementation PreviewView
-(void)cleanupMarquee:(BOOL)b {}
-(BOOL)annotationKeyDown:(NSEvent *)event { return NO; }
METHODS
@end

// Pages of text whose column alternates between the left and the right, as in a
// two-sided document; the page width varies when asked.
static PDFDocument *makePDF(BOOL varied) {
 NSMutableData *data=[NSMutableData data];
 CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
 CGContextRef pdf=CGPDFContextCreate(consumer,NULL,NULL);
 NSDictionary *attributes=@{NSFontAttributeName:[NSFont fontWithName:@"Helvetica" size:12]};
 for(NSInteger n=0;n<9;n++) {
  CGRect box=CGRectMake(0,0,varied&&n%3==2?520:600,800);
  CGContextBeginPage(pdf,&box);
  [NSGraphicsContext saveGraphicsState];
  NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithCGContext:pdf flipped:NO];
  CGFloat left=n%2?150:60;
  for(NSInteger line=0;line<40;line++)
   [[NSString stringWithFormat:@"Line %02ld of page %ld runs across the text column here",line,n+1]
     drawAtPoint:NSMakePoint(left,740-18*line) withAttributes:attributes];
  [@"far" drawAtPoint:NSMakePoint(box.size.width-40,400) withAttributes:attributes];
  [NSGraphicsContext restoreGraphicsState];
  CGContextEndPage(pdf);
 }
 CGPDFContextClose(pdf);CGContextRelease(pdf);CGDataConsumerRelease(consumer);
 return [[PDFDocument alloc] initWithData:data];
}
static NSEvent *key(unichar k, NSEventModifierFlags flags) {
 NSString *s=[NSString stringWithCharacters:&k length:1];
 if(k!=' ') flags|=NSEventModifierFlagFunction|(k==NSUpArrowFunctionKey||k==NSDownArrowFunctionKey||k==NSLeftArrowFunctionKey||k==NSRightArrowFunctionKey?NSEventModifierFlagNumericPad:0);
 return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil characters:s charactersIgnoringModifiers:s isARepeat:NO keyCode:0];
}
static NSClipView *clipOf(PDFView *v) { return v.documentView.enclosingScrollView.contentView; }
static CGFloat xOf(PDFView *v) { return NSMinX(clipOf(v).bounds); }
static NSUInteger pageOf(PDFView *v) { return TSExternalPDFCapture(v).pageIndex; }
static CGFloat clampX(PDFView *v, CGFloat x) {
 CGFloat lo,hi;TSPreviewHorizontalLimits(v.documentView.enclosingScrollView,&lo,&hi);return fmin(fmax(x,lo),hi);
}
static void sameX(PDFView *v, CGFloat x, NSString *message) {
 CGFloat expected=clampX(v,x);
 if(fabs(xOf(v)-expected)>0.5) fprintf(stderr,"%s: x %.1f, expected %.1f\n",message.UTF8String,xOf(v),expected);
 check(fabs(xOf(v)-expected)<=0.5,message);
}
static NSWindow *window(void) {
 NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,500,500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 w.releasedWhenClosed=NO;return w;
}
static PDFView *setUp(PDFView *v, NSWindow *w, PDFDocument *doc, PDFDisplayMode mode, BOOL book, NSInteger style) {
 [w.contentView addSubview:v];v.document=doc;v.displayMode=mode;v.displaysAsBook=book;v.scaleFactor=2;
 v.documentView.enclosingScrollView.scrollerStyle=style;pump();
 TSExternalPDFPosition start={YES,NO,4,NSMakePoint(330,400),2};TSExternalPDFRestore(v,start);pump();
 return v;
}
// Show a line as SyncTeX and Find do: go to the page, select, scroll the selection into view.
static PDFSelection *showResult(PDFView *v, NSUInteger index, NSRect rect) {
 PDFPage *page=[v.document pageAtIndex:index];
 PDFSelection *selection=[page selectionForRect:rect];
 [v goToPage:page];[v setCurrentSelection:selection];[v scrollSelectionToVisible:nil];[v setCurrentSelection:nil];pump();
 return selection;
}
static NSRect shown(PDFView *v, PDFSelection *selection) {
 PDFPage *page=selection.pages.firstObject;
 return [clipOf(v) convertRect:[v convertRect:[selection boundsForPage:page] fromPage:page] fromView:v];
}

int main(void) { @autoreleasepool {
 TSInstallAppKitIsolation(); [NSApplication sharedApplication];
 [SUD setBool:NO forKey:LeftRightArrowsAlwaysPageKey];
 BOOL macOS27=NO; if (@available(macOS 27.0,*)) macOS27=YES;
 PDFDocument *plain=makePDF(NO), *varied=makePDF(YES);
 check(plain.pageCount==9 && [[plain pageAtIndex:4].string containsString:@"Line 00 of page 5"],@"test document has text");

 // The pure rule for search and SyncTeX results.
 context=@"rule";
 check(TSPreviewHorizontalOriginShowing(120,180,100,200,10)==100,@"a result in view keeps the position");
 check(TSPreviewHorizontalOriginShowing(40,80,100,200,10)==30,@"a result to the left comes just into view");
 check(TSPreviewHorizontalOriginShowing(350,380,100,200,10)==190,@"a result to the right comes just into view");
 check(TSPreviewHorizontalOriginShowing(0,190,100,200,10)==-5,@"the spare room shrinks for a wide result");
 check(TSPreviewHorizontalOriginShowing(50,600,100,200,10)==100,@"a result wider than the view keeps the position while in view");
 check(isnan(TSPreviewHorizontalOriginShowing(400,900,100,200,10)),@"a wide result out of view is left to PDFKit");

 NSUInteger paginatedRuns=0,keptLines=0,nativeMoves=0;
 for(NSNumber *mode in @[@(kPDFDisplaySinglePage),@(kPDFDisplayTwoUp),@(kPDFDisplaySinglePageContinuous),@(kPDFDisplayTwoUpContinuous)])
 for(NSInteger book=0;book<2;book++) for(NSInteger style=0;style<2;style++) for(NSNumber *variedPages in @[@NO,@YES]) {
  BOOL twoUp=mode.integerValue==kPDFDisplayTwoUp||mode.integerValue==kPDFDisplayTwoUpContinuous;
  if(book&&!twoUp) continue;
  BOOL paginated=mode.integerValue==kPDFDisplaySinglePage||mode.integerValue==kPDFDisplayTwoUp;
  PDFDocument *doc=variedPages.boolValue?varied:plain;
  context=[NSString stringWithFormat:@"mode=%@ book=%ld style=%ld varied=%@",mode,book,style,variedPages];
  // Keys, the page commands and goToPage: (the page number field).
  struct { const char *name; unichar k; NSEventModifierFlags flags; NSInteger repeat; } keys[]={
   {"Option-Down",NSDownArrowFunctionKey,NSEventModifierFlagOption,6},{"Option-Up",NSUpArrowFunctionKey,NSEventModifierFlagOption,6},
   {"Space",' ',0,6},{"Shift-Space",' ',NSEventModifierFlagShift,6},
   {"Command-Down",NSDownArrowFunctionKey,NSEventModifierFlagCommand,1},{"Command-Up",NSUpArrowFunctionKey,NSEventModifierFlagCommand,1},
   {"End",NSEndFunctionKey,0,1},{"Home",NSHomeFunctionKey,0,1},{"goToPage",0,0,1}};
  for(size_t i=0;i<sizeof keys/sizeof keys[0];i++) {
   NSWindow *w=window(),*cw=window();
   PDFView *v=setUp([[PreviewView alloc]initWithFrame:NSMakeRect(0,0,500,500)],w,doc,mode.integerValue,book,style);
   PDFView *control=setUp([[PDFView alloc]initWithFrame:NSMakeRect(0,0,500,500)],cw,doc,mode.integerValue,book,style);
   CGFloat x=xOf(v);NSUInteger page=pageOf(v);
   CGFloat lo,hi;TSPreviewHorizontalLimits(v.documentView.enclosingScrollView,&lo,&hi);
   check(x>lo+20&&x<hi-20,@"the test starts away from the page edges");
   for(NSInteger r=0;r<keys[i].repeat&&pageOf(v)==page;r++) {
    if(keys[i].k) { [v keyDown:key(keys[i].k,keys[i].flags)];[control keyDown:key(keys[i].k,keys[i].flags)]; }
    else { [v goToPage:[doc pageAtIndex:7]];[control goToPage:[doc pageAtIndex:7]]; }
    pump();
   }
   NSString *name=@(keys[i].name);
   check(pageOf(v)!=page,[name stringByAppendingString:@" changes the page"]);
   if(paginated&&macOS27) {
    paginatedRuns++;
    sameX(v,x,[name stringByAppendingString:@" keeps the horizontal position"]);
    if(!variedPages.boolValue) check(fabs(xOf(control)-x)>20,[name stringByAppendingString:@": PDFKit alone moves sideways (the case being fixed)"]);
   } else {
    check(fabs(xOf(v)-xOf(control))<=0.5&&fabs(NSMinY(clipOf(v).bounds)-NSMinY(clipOf(control).bounds))<=0.5,
          [name stringByAppendingString:@" is left to PDFKit"]);
   }
   check([doc indexForPage:v.currentPage]==[doc indexForPage:control.currentPage],[name stringByAppendingString:@" reaches the same page as PDFKit"]);
   v.document=nil;control.document=nil;[w close];[cw close];
  }
  // Command-Right and Command-Left keep the place on the page, as before.
  {
   NSWindow *w=window();PDFView *v=setUp([[PreviewView alloc]initWithFrame:NSMakeRect(0,0,500,500)],w,plain,mode.integerValue,book,style);
   TSExternalPDFPosition before=TSExternalPDFCapture(v);
   [v keyDown:key(NSRightArrowFunctionKey,NSEventModifierFlagCommand)];pump();
   TSExternalPDFPosition after=TSExternalPDFCapture(v);
   if(paginated&&macOS27) {
    check(after.pageIndex==before.pageIndex+(twoUp?2:1),@"Command-Right moves to the next page or spread");
    check(hypot(after.pagePoint.x-before.pagePoint.x,after.pagePoint.y-before.pagePoint.y)<1.5,@"Command-Right keeps the place on the page");
   }
   // A bare Left arrow still scrolls sideways.
   CGFloat x=xOf(v);[v keyDown:key(NSLeftArrowFunctionKey,0)];pump();
   check(xOf(v)<x-1,@"Left arrow still scrolls sideways");
   v.document=nil;[w close];
  }
  // SyncTeX and Find: a line on either kind of page keeps the margins in view.
  for(NSUInteger target=5;target<=6;target++) {
   NSWindow *w=window(),*cw=window();
   PDFView *v=setUp([[PreviewView alloc]initWithFrame:NSMakeRect(0,0,500,500)],w,doc,mode.integerValue,book,style);
   PDFView *control=setUp([[PDFView alloc]initWithFrame:NSMakeRect(0,0,500,500)],cw,doc,mode.integerValue,book,style);
   CGFloat x=xOf(v);
   NSRect line=NSMakeRect(0,740-18*20-2,600,16);
   PDFSelection *selection=showResult(v,target,line);showResult(control,target,line);
   NSRect visible=clipOf(v).bounds,result=shown(v,selection);
   check(NSMinY(result)>=NSMinY(visible)-0.5&&NSMaxY(result)<=NSMaxY(visible)+0.5,@"the line comes into view vertically");
   check(NSMaxX(result)>NSMinX(visible)&&NSMinX(result)<NSMaxX(visible),@"part of the line is in view");
   BOOL inView=NSMaxX(result)>x&&NSMinX(result)<x+NSWidth(visible);
   if(macOS27&&!twoUp) check(inView,@"a single page line overlaps the view sideways");
   if(macOS27&&inView) {
    sameX(v,x,[NSString stringWithFormat:@"a line on page %lu keeps the margins",target+1]);keptLines++;
    if(fabs(xOf(control)-x)>20) nativeMoves++;
   }
   v.document=nil;control.document=nil;[w close];[cw close];
  }
  // A short result out of view sideways comes just into view, with a little room.
  if(macOS27) {
   NSWindow *w=window();PDFView *v=setUp([[PreviewView alloc]initWithFrame:NSMakeRect(0,0,500,500)],w,doc,mode.integerValue,book,style);
   NSUInteger target=4;PDFPage *page=[doc pageAtIndex:target];
   NSRect far=NSMakeRect(NSWidth([page boundsForBox:kPDFDisplayBoxMediaBox])-42,396,40,16);
   NSClipView *clip=clipOf(v);NSRect bounds=clip.bounds;bounds.origin.x=clampX(v,0);
   [clip scrollToPoint:bounds.origin];[v.documentView.enclosingScrollView reflectScrolledClipView:clip];pump();
   PDFSelection *selection=showResult(v,target,far);
   NSRect visible=clipOf(v).bounds,result=shown(v,selection);
   CGFloat unit=NSWidth(visible)/NSWidth(clipOf(v).frame);
   check(NSMinX(result)>=NSMinX(visible)-0.5&&NSMaxX(result)<=NSMaxX(visible)+0.5,@"a short result off to the side comes into view");
   check(NSMaxX(visible)-NSMaxX(result)<=10*unit+0.5||xOf(v)>=clampX(v,1e9)-0.5,@"it moves just far enough, with ten points to spare");
   v.document=nil;[w close];
  }
 }
 if(macOS27) {
  check(paginatedRuns==12*9,@"all paginated cases ran");
  // Lines keep the margins in every view; PDFKit alone moves them in most.
  check(keptLines>=24,@"lines in view sideways were checked (all single page lines, some spreads)");
  check(nativeMoves>=24,@"PDFKit alone moves sideways for lines");
 }
 puts(macOS27?"PASS: horizontal position kept by Option/Command arrows, Space, Home, End and goToPage in single and double page display; Command-Left/Right and Left arrow unchanged; SyncTeX/Find results keep the margins or come just into view; continuous display left to PDFKit":
      "PASS: earlier macOS, all navigation left to PDFKit");
}return 0;}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-horizontal-') as directory:
    temp = Path(directory)
    (temp / 'home' / 'Library' / 'Preferences').mkdir(parents=True)
    (temp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-I', str(root / 'Tests'), '-mmacosx-version-min=14.6', '-w', '-fobjc-arc',
                    '-framework', 'Cocoa', '-framework', 'PDFKit', *include_args(root), str(temp / 'test.m'),
                    '-o', str(temp / 'test')], check=True)
    subprocess.run([str(temp / 'test')], check=True, timeout=300,
                   env=dict(os.environ, HOME=str(temp / 'home'), CFFIXED_USER_HOME=str(temp / 'home')))
