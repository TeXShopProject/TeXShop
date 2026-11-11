#!/usr/bin/env python3
"""Check "Do not turn pages by scrolling" with the production methods in hidden PDFKit views:
scrolling stops at the edge of the page in single and double page display, while keys,
menus and the page buttons still turn pages."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['ignore-setting', 'no-delayed-guard', 'no-event-guard', 'all-modes'])
parser.add_argument('--artifacts', type=Path, help='Keep the generated Objective-C and executable for other macOS versions')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='utf-8')
def method(signature):
    start = source.rindex(signature)
    return source[start:source.index('\n}', start) + 2]
methods = '\n'.join(method(signature) for signature in (
    '- (void)keepHorizontalPositionDuring:', '- (BOOL)scrollingKeepsPage', '- (BOOL)isPageTurnFromScrolling:',
    '- (void)performSelector:(SEL)selector withObject:(id)argument afterDelay:(NSTimeInterval)delay\n{',
    '- (void)performSelector:(SEL)selector withObject:(id)argument afterDelay:(NSTimeInterval)delay\n                inModes:',
    '- (void)goToNextPage:', '- (void)goToPreviousPage:'))
def mutate(old, new, count=1):
    global methods
    assert methods.count(old) == count, old
    methods = methods.replace(old, new)
if args.mutation == 'ignore-setting':
    mutate('return [SUD boolForKey:NoScrollPageTurnKey] &&', 'return YES &&')
elif args.mutation == 'no-delayed-guard':
    mutate('    if ([self isPageTurnFromScrolling:selector])\n        return;\n', '', 2)
elif args.mutation == 'no-event-guard':
    mutate('if (NSApp.currentEvent.type == NSEventTypeScrollWheel && [self isPageTurnFromScrolling:_cmd])', 'if (NO)', 2)
elif args.mutation == 'all-modes':
    mutate('(self.displayMode == kPDFDisplaySinglePage || self.displayMode == kPDFDisplayTwoUp)', 'YES', 2)

program = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import <PDFKit/PDFKit.h>
#import "TSExternalPDFReload.h"
#import "TSPreviewHorizontalPosition.h"
#define SUD NSUserDefaults.standardUserDefaults
#define NoScrollPageTurnKey @"NoScrollPageTurn"
static NSString *context;
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
 checks++;
 if(!ok) { fprintf(stderr,"FAIL: %s [%s]\n",message.UTF8String,context.UTF8String); exit(1); }
}
static void pump(double seconds) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
// The event AppKit is handling; set by the test to model a scroll in progress.
static NSEvent *current;
static NSEvent *CurrentEvent(id self, SEL _cmd) { return current; }
@interface PreviewView:PDFView
-(BOOL)scrollingKeepsPage;
@end
@implementation PreviewView
METHODS
@end
static PDFDocument *makePDF(void) {
 PDFDocument *pdf=[PDFDocument new];
 for(NSUInteger n=0;n<8;n++) {
  NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(600,800)];[image lockFocus];[NSColor.whiteColor setFill];NSRectFill(NSMakeRect(0,0,600,800));[image unlockFocus];
  [pdf insertPage:[[PDFPage alloc]initWithImage:image] atIndex:n];
 }
 return pdf;
}
static NSEvent *wheel(int dy) {
 CGEventRef e=CGEventCreateScrollWheelEvent(NULL,kCGScrollEventUnitPixel,1,dy);
 NSEvent *event=[NSEvent eventWithCGEvent:e];CFRelease(e);return event;
}
static NSEvent *key(unichar k, NSEventModifierFlags flags) {
 NSString *s=[NSString stringWithCharacters:&k length:1];
 if(k!=' ') flags|=NSEventModifierFlagFunction;
 return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil characters:s charactersIgnoringModifiers:s isARepeat:NO keyCode:0];
}
static NSUInteger pageOf(PDFView *v) { return [v.document indexForPage:v.currentPage]; }
// Scrolls with the wheel past the bottom (or top) of page 4, as a person turning the wheel.
static NSUInteger wheelPastEdge(PDFView *v, BOOL down) {
 TSExternalPDFPosition start={YES,NO,4,NSMakePoint(300,down?150:650),2};TSExternalPDFRestore(v,start);pump(.05);
 for(int i=0;i<8;i++){ NSEvent *e=wheel(down?-60:60); current=e; [v.documentView.enclosingScrollView scrollWheel:e]; current=nil; pump(.12); }
 return pageOf(v);
}
static PDFView *makeView(Class cls, PDFDocument *doc, PDFDisplayMode mode, NSWindow **window) {
 NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,500,500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 w.releasedWhenClosed=NO;*window=w;
 PDFView *v=[[cls alloc]initWithFrame:w.contentView.bounds];[w.contentView addSubview:v];
 v.document=doc;v.displayMode=mode;v.scaleFactor=2;pump(.05);return v;
}
int main(void) { @autoreleasepool {
 TSInstallAppKitIsolation(); [NSApplication sharedApplication];
 Method m=class_getInstanceMethod(NSApplication.class,@selector(currentEvent));
 method_setImplementation(m,(IMP)CurrentEvent);
 PDFDocument *doc=makePDF();
 NSUInteger nativeTurns=0;
 for(NSNumber *mode in @[@(kPDFDisplaySinglePage),@(kPDFDisplayTwoUp),@(kPDFDisplaySinglePageContinuous),@(kPDFDisplayTwoUpContinuous)])
 for(NSNumber *down in @[@YES,@NO]) {
  BOOL paginated=mode.integerValue==kPDFDisplaySinglePage||mode.integerValue==kPDFDisplayTwoUp;
  NSWindow *w,*cw;
  PDFView *v=makeView(PreviewView.class,doc,mode.integerValue,&w), *control=makeView(PDFView.class,doc,mode.integerValue,&cw);
  // Off (the default): the same as PDFKit alone.
  context=[NSString stringWithFormat:@"setting off, mode=%@ down=%@",mode,down];
  [SUD removeObjectForKey:NoScrollPageTurnKey];
  NSUInteger page=wheelPastEdge(v,down.boolValue), native=wheelPastEdge(control,down.boolValue);
  // In double page display either page of a spread may be current.
  NSUInteger unit=(mode.integerValue==kPDFDisplayTwoUp||mode.integerValue==kPDFDisplayTwoUpContinuous)?2:1;
  check(page/unit==native/unit,@"the wheel behaves as in PDFKit alone");
  if(paginated) { check(native!=4,@"Fixture: PDFKit turns the page when the wheel passes the edge"); nativeTurns++; }
  // On: the wheel stops at the edge in single and double page display.
  context=[NSString stringWithFormat:@"setting on, mode=%@ down=%@",mode,down];
  [SUD setBool:YES forKey:NoScrollPageTurnKey];
  check(((PreviewView *)v).scrollingKeepsPage==paginated,@"the setting applies to single and double page display only");
  page=wheelPastEdge(v,down.boolValue);
  if(paginated) check(page==4,@"the wheel stops at the edge of the page");
  else check(page/unit==native/unit,@"continuous display scrolls on as in PDFKit alone");
  // A page turn made while a scroll is being handled is a scroll's, as on a trackpad.
  if(paginated) {
   TSExternalPDFRestore(v,(TSExternalPDFPosition){YES,NO,4,NSMakePoint(300,400),2});pump(.05);
   current=wheel(-60);[v goToNextPage:v];current=nil;
   check(pageOf(v)==4,@"no next page while a scroll is handled");
   current=wheel(60);[v goToPreviousPage:v];current=nil;
   check(pageOf(v)==4,@"no previous page while a scroll is handled");
  }
  // Keys, menus and the page buttons still turn pages.
  TSExternalPDFRestore(v,(TSExternalPDFPosition){YES,NO,4,NSMakePoint(300,400),2});pump(.05);
  current=key(NSRightArrowFunctionKey,NSEventModifierFlagCommand);[v goToNextPage:nil];current=nil;pump(.05);
  check(pageOf(v)==4+(mode.integerValue==kPDFDisplayTwoUp||mode.integerValue==kPDFDisplayTwoUpContinuous?2:1),@"the next page command turns the page");
  current=key(NSLeftArrowFunctionKey,NSEventModifierFlagCommand);[v goToPreviousPage:nil];current=nil;pump(.05);
  check(pageOf(v)==4,@"the previous page command turns the page");
  if(paginated) {
   TSExternalPDFRestore(v,(TSExternalPDFPosition){YES,NO,4,NSMakePoint(300,150),2});pump(.05);
   for(int i=0;i<6&&pageOf(v)==4;i++){ NSEvent *e=key(NSDownArrowFunctionKey,NSEventModifierFlagOption); current=e; [v keyDown:e]; current=nil; pump(.05); }
   check(pageOf(v)!=4,@"Option-Down still moves on to the next page");
   current=key(NSEndFunctionKey,0);[v keyDown:current];current=nil;pump(.05);
   check(pageOf(v)>=6,@"End still goes to the last page");
  }
  [SUD removeObjectForKey:NoScrollPageTurnKey];
  v.document=nil;control.document=nil;[w close];[cw close];
 }
 check(nativeTurns==4,@"PDFKit turned the page from the wheel in every paginated case");
 printf("PASS: scrolling page turn off by default; on: the wheel stops at the page edge in single and double page display, continuous display and keys unchanged (%lu checks)\n",(unsigned long)checks);
}return 0;}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-scroll-page-turn-') as directory:
    temp = Path(directory)
    (temp / 'home' / 'Library' / 'Preferences').mkdir(parents=True)
    (temp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-I', str(root / 'Tests'), '-mmacosx-version-min=14.6', '-w', '-fobjc-arc',
                    '-framework', 'Cocoa', '-framework', 'PDFKit', *include_args(root), str(temp / 'test.m'),
                    '-o', str(temp / 'test')], check=True)
    if args.artifacts:
        args.artifacts.mkdir(parents=True, exist_ok=True)
        shutil.copy2(temp / 'test.m', args.artifacts / 'test.m')
        shutil.copy2(temp / 'test', args.artifacts / 'test')
    subprocess.run([str(temp / 'test')], check=True, timeout=300,
                   env=dict(os.environ, HOME=str(temp / 'home'), CFFIXED_USER_HOME=str(temp / 'home')))
