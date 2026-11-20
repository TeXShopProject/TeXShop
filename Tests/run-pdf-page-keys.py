#!/usr/bin/env python3
"""Page Up and Page Down in the Preview, as Preview.app does on macOS 15 and 26, checked in real PDFKit
views without user settings and without showing a window.

Single page and two pages display: a page or spread that fits turns by one page or spread; a zoomed one
scrolls by a screen, and from its bottom Page Down shows the next page or spread from its top, from its
top Page Up shows the previous one from its bottom. The first and last pages keep the key. Continuous
display is left to PDFKit. All of it also with a top content inset as under the toolbar, where PDFKit on
macOS 27 does neither on its own. Modified keys are left to PDFKit.

  --mutation NAME   break one rule; the test must then fail"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
from source_tree import include_args

MUTATIONS = {
    'not-handled': ('    if ([self pageKeyInPaginatedView:theEvent])\n        return;\n', ''),
    'no-scroll-first': ('    if ([self paginatedScrollMinimum:&minimum maximum:&maximum]) {\n        // The end of the page', '    if (NO) {\n        // The end of the page'),
    'keeps-position': ('    [self layoutDocumentView];\n    if ([self paginatedScrollMinimum:&minimum maximum:&maximum]) {\n        // The next page from its top', '    if (NO) {\n        // The next page from its top'),
    'continuous-too': ('    if (self.displayMode != kPDFDisplaySinglePage && self.displayMode != kPDFDisplayTwoUp)\n        return NO;\n    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption |\n                               NSEventModifierFlagControl | NSEventModifierFlagShift))\n        return NO;\n    NSString *characters = event.charactersIgnoringModifiers;\n    if (characters.length != 1) return NO;\n    unichar key = [characters characterAtIndex:0];\n    if (key != NSPageUpFunctionKey',
                       '    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption |\n                               NSEventModifierFlagControl | NSEventModifierFlagShift))\n        return NO;\n    NSString *characters = event.charactersIgnoringModifiers;\n    if (characters.length != 1) return NO;\n    unichar key = [characters characterAtIndex:0];\n    if (key != NSPageUpFunctionKey'),
    'screen-and-a-half': ('CGFloat step = visible - overlap > 0 ? visible - overlap : visible;', 'CGFloat step = 1.5 * visible;'),
    'no-overlap': ('CGFloat step = visible - overlap > 0 ? visible - overlap : visible;', 'CGFloat step = visible;'),
    'insets-ignored': ('CGFloat visible = NSHeight(clip.bounds) - (fabs(insets.top) + fabs(insets.bottom)) / magnification;', 'CGFloat visible = NSHeight(clip.bounds);'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--build-only', type=Path, help='write the test program to this path instead of running it')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')


def method(signature):
    start = source.rindex(signature)
    return source[start:source.index('\n}', start) + 2]


methods = '\n'.join(method(signature) for signature in (
    '- (BOOL)paginatedScrollMinimum:', '- (BOOL)scrollVerticalArrowWithinPage:', '- (BOOL)pageKeyInPaginatedView:', '- (void)keyDown:'))
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert methods.count(old) == 1, args.mutation
    methods = methods.replace(old, new)
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import <PDFKit/PDFKit.h>
#define SUD NSUserDefaults.standardUserDefaults
#define LeftRightArrowsAlwaysPageKey @"LeftRightArrowsAlwaysPage"
static NSString *context;
static int failures; static NSUInteger measuredSteps;
static void check(BOOL ok, NSString *message) {
 if(!ok) { fprintf(stderr,"FAIL: %s [%s]\n",message.UTF8String,context.UTF8String); failures++; }
}
static void pump(void) { for(int i=0;i<3;i++) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]]; }
@interface KeyView:PDFView
-(BOOL)paginatedScrollMinimum:(CGFloat *)minimum maximum:(CGFloat *)maximum;
-(BOOL)pageKeyInPaginatedView:(NSEvent *)event;
@end
@implementation KeyView
-(BOOL)annotationKeyDown:(NSEvent *)event { return NO; }
// TeXShop's page commands, as the Preview's menu items call them.
-(void)previousPage:(id)sender { [self goToPreviousPage:sender]; }
-(void)nextPage:(id)sender { [self goToNextPage:sender]; }
METHODS
@end
static NSEvent *key(unichar character, NSEventModifierFlags flags) {
 NSString *s=[NSString stringWithCharacters:&character length:1];
 return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags|NSEventModifierFlagFunction
 timestamp:0 windowNumber:0 context:nil characters:s charactersIgnoringModifiers:s isARepeat:NO keyCode:character==NSPageDownFunctionKey?121:116];
}
static PDFDocument *document(void) {
 PDFDocument *doc=[PDFDocument new];
 for(NSUInteger i=0;i<9;i++) {
  NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(600,800)];
  [image lockFocus];[NSColor.whiteColor setFill];NSRectFill(NSMakeRect(0,0,600,800));[image unlockFocus];
  [doc insertPage:[[PDFPage alloc]initWithImage:image] atIndex:i];
 }
 return doc;
}
// The shown page and how far down it the top of the visible area is: 0 at its top, 1 at the bottom of
// the scroll range (the page's bottom in view).
// One press moves the page by the visible height on screen less the part that stays in view, as AppKit
// pages a scroll view: measured in screen points, away from the ends where the move is cut short.
static CGFloat ExpectedStep(PDFView *v) {
 NSScrollView *scroll=v.documentView.enclosingScrollView;
 return NSHeight(scroll.contentView.frame)-scroll.contentInsets.top-scroll.contentInsets.bottom-scroll.verticalPageScroll;
}
static void CheckStep(PDFView *v, CGFloat before, NSString *what) {
 NSScrollView *scroll=v.documentView.enclosingScrollView;
 CGFloat minimum,maximum,y=scroll.contentView.bounds.origin.y,m=scroll.magnification;
 if(![(id)v paginatedScrollMinimum:&minimum maximum:&maximum]) return;
 if((y-minimum)*m<0.5||(maximum-y)*m<0.5) return; // cut short at an end
 measuredSteps++;
 CGFloat moved=fabs(y-before)*m, expected=ExpectedStep(v);
 check(fabs(moved-expected)<=1,[NSString stringWithFormat:@"%@ moves %.1f points on screen, the visible height less the overlap (%.1f)",what,moved,expected]);
}
static NSUInteger ShownPage(PDFView *v) { return [v.document indexForPage:v.currentPage]; }
static double ShownFraction(PDFView *v) {
 CGFloat minimum, maximum;
 if(![(id)v paginatedScrollMinimum:&minimum maximum:&maximum]) return -1;
 NSClipView *clip=v.documentView.enclosingScrollView.contentView;
 double f=(clip.bounds.origin.y-minimum)/(maximum-minimum);
 return clip.isFlipped ? f : 1-f;
}
int main(void) { @autoreleasepool {
 TSInstallAppKitIsolation(); [NSApplication sharedApplication];
 PDFDocument *doc=document();
 printf("%s\n", NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);
 for(NSNumber *inset in @[@0,@82]) for(NSInteger mode=0;mode<4;mode++) for(NSNumber *scale in @[@0,@2.5]) {
  BOOL paginated=mode==kPDFDisplaySinglePage||mode==kPDFDisplayTwoUp, zoomed=scale.doubleValue>0;
  NSUInteger stride=mode==kPDFDisplayTwoUp?2:1;
  context=[NSString stringWithFormat:@"mode=%ld %@ inset=%@",(long)mode,zoomed?@"zoomed":@"fits",inset];
  NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,700,560) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];w.releasedWhenClosed=NO;
  KeyView *v=[[KeyView alloc]initWithFrame:w.contentView.bounds];[w.contentView addSubview:v];
  v.document=doc;v.displayMode=mode;
  if(zoomed){v.autoScales=NO;v.scaleFactor=scale.doubleValue;}else v.autoScales=YES;
  NSScrollView *scroll=v.documentView.enclosingScrollView;
  if(inset.doubleValue>0){scroll.automaticallyAdjustsContentInsets=NO;scroll.contentInsets=NSEdgeInsetsMake(inset.doubleValue,0,0,0);}
  [v goToPage:[doc pageAtIndex:4]];[v layoutDocumentView];pump();
  if(zoomed) check(scroll.verticalPageScroll>0,@"the scroll view keeps part of the screen in view");
  if(!paginated) {
   check(![v pageKeyInPaginatedView:key(NSPageDownFunctionKey,0)] && ![v pageKeyInPaginatedView:key(NSPageUpFunctionKey,0)],@"continuous display is left to PDFKit");
   [v removeFromSuperview];[w close];continue;
  }
  for(NSNumber *flags in @[@(NSEventModifierFlagCommand),@(NSEventModifierFlagOption),@(NSEventModifierFlagControl),@(NSEventModifierFlagShift)])
   check(![v pageKeyInPaginatedView:key(NSPageDownFunctionKey,flags.unsignedLongLongValue)],@"modified Page Down is left to PDFKit");
  if(!zoomed) {
   check(ShownFraction(v)<0,@"the page fits");
   NSUInteger start=ShownPage(v);
   [v keyDown:key(NSPageDownFunctionKey,0)];pump();
   check(ShownPage(v)==start+stride,@"Page Down turns a page that fits");
   [v keyDown:key(NSPageDownFunctionKey,0)];pump();
   check(ShownPage(v)==start+2*stride,@"and again");
   [v keyDown:key(NSPageUpFunctionKey,0)];pump();
   check(ShownPage(v)==start+stride,@"Page Up turns back");
  } else {
   // From the top of a page: Page Down scrolls by screens to its bottom, then shows the next page from its top.
   NSClipView *clip=scroll.contentView;
   NSPoint origin=clip.bounds.origin;CGFloat minimum,maximum;
   check([v paginatedScrollMinimum:&minimum maximum:&maximum],@"the zoomed page scrolls");
   origin.y=clip.isFlipped?minimum:maximum;[clip scrollToPoint:origin];[scroll reflectScrolledClipView:clip];
   NSUInteger start=ShownPage(v);
   double last=ShownFraction(v);check(last<0.01,@"starts at the top");
   int presses=0;
   while(ShownFraction(v)>-1 && ShownFraction(v)<0.99 && ShownPage(v)==start && presses<20){
    CGFloat before=clip.bounds.origin.y;
    [v keyDown:key(NSPageDownFunctionKey,0)];pump();presses++;
    if(ShownPage(v)==start) CheckStep(v,before,@"Page Down");
    double f=ShownFraction(v);
    if(ShownPage(v)==start){ check(f>last+0.05,@"Page Down scrolls down the page"); last=f; }
   }
   check(ShownPage(v)==start && presses>=1 && presses<20,@"Page Down reaches the bottom of the page");
   double overlapCheck=ShownFraction(v);check(overlapCheck>0.99,@"at the bottom");
   [v keyDown:key(NSPageDownFunctionKey,0)];pump();
   check(ShownPage(v)==start+stride && ShownFraction(v)<0.01,@"from the bottom, Page Down shows the next page from its top");
   [v keyDown:key(NSPageUpFunctionKey,0)];pump();
   check(ShownPage(v)==start && ShownFraction(v)>0.99,@"from the top, Page Up shows the previous page from its bottom");
   CGFloat before=clip.bounds.origin.y;
   [v keyDown:key(NSPageUpFunctionKey,0)];pump();
   check(ShownPage(v)==start && ShownFraction(v)<0.99 && ShownFraction(v)>-1,@"Page Up scrolls up the page");
   NSUInteger measuredBefore=measuredSteps; CheckStep(v,before,@"Page Up");
   check(measuredSteps==measuredBefore+1,@"Page Up from the bottom is measured away from the top");
  }
  // The first and last pages keep the key.
  [v goToFirstPage:nil];[v layoutDocumentView];pump();
  if(zoomed){NSClipView *clip=scroll.contentView;CGFloat minimum,maximum;[v paginatedScrollMinimum:&minimum maximum:&maximum];NSPoint o=clip.bounds.origin;o.y=clip.isFlipped?minimum:maximum;[clip scrollToPoint:o];[scroll reflectScrolledClipView:clip];}
  NSPoint before=scroll.contentView.bounds.origin;
  check([v pageKeyInPaginatedView:key(NSPageUpFunctionKey,0)] && ShownPage(v)==0 && NSEqualPoints(before,scroll.contentView.bounds.origin),@"Page Up at the top of the first page keeps the key");
  [v removeFromSuperview];[w close];
 }
 check(measuredSteps>=8,[NSString stringWithFormat:@"moves away from the ends were measured (%lu)",(unsigned long)measuredSteps]);
 if(!failures) puts("PASS: Page Up and Page Down in four display modes, fitting and zoomed, with and without a top inset");
 return failures?1:0;
}}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-page-keys-') as directory:
    temp = Path(directory)
    (temp/'home'/'Library'/'Preferences').mkdir(parents=True)
    (temp/'test.m').write_text(program)
    binary = args.build_only or temp/'TeXShopPageKeysTest'
    subprocess.run(['xcrun','clang','-I',str(root/'Tests'),'-arch','arm64','-mmacosx-version-min=14.0','-w','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',
                    *include_args(root),str(temp/'test.m'),'-o',str(binary)],check=True)
    if not args.build_only:
        result = subprocess.run([str(binary)],timeout=240,env=dict(os.environ,HOME=str(temp/'home'),CFFIXED_USER_HOME=str(temp/'home')))
        raise SystemExit(result.returncode)
