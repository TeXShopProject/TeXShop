#!/usr/bin/env python3
"""Check production vertical-arrow handling in real PDFKit views, without user settings."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['delegate-at-edge', 'all-modes', 'ignore-modifiers', 'ignore-annotation', 'visible-scroller'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/MyPDFKitView.m').read_text(encoding='latin1')
def method(signature):
    start = source.rindex(signature)
    return source[start:source.index('\n}', start) + 2]
methods = '\n'.join(method(signature) for signature in (
    '- (BOOL)scrollVerticalArrowWithinPage:', '- (void)keyDown:'))
if args.mutation == 'delegate-at-edge':
    methods = methods.replace('[clip scrollToPoint:origin];', 'if (origin.y == bounds.origin.y) return NO;\n    [clip scrollToPoint:origin];')
elif args.mutation == 'all-modes':
    methods = methods.replace('if (self.displayMode != kPDFDisplaySinglePage && self.displayMode != kPDFDisplayTwoUp)', 'if (NO)')
elif args.mutation == 'ignore-modifiers':
    methods = methods.replace('if (event.modifierFlags &', 'if (0 & event.modifierFlags &')
elif args.mutation == 'ignore-annotation':
    methods = methods.replace('if ([self annotationKeyDown: theEvent])', 'if (NO)')
elif args.mutation == 'visible-scroller':
    methods = methods.replace('NSClipView *clip = scroll.contentView;', 'if (scroll.verticalScroller.hidden) return NO;\n    NSClipView *clip = scroll.contentView;')
program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSExternalPDFReload.h"
#define SUD NSUserDefaults.standardUserDefaults
#define LeftRightArrowsAlwaysPageKey @"LeftRightArrowsAlwaysPage"
static NSString *context;
static void check(BOOL ok, NSString *message) {
 if(!ok) { fprintf(stderr,"FAIL: %s [%s]\n",message.UTF8String,context.UTF8String); exit(1); }
}
static void pump(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]]; }
@interface TrackingPDFView:PDFView
@property NSUInteger delegated, previousCalls, nextCalls;
@property BOOL handlesAnnotation;
@end
@implementation TrackingPDFView
// Track delegation without invoking PDFKit's selection/page commands in routing tests.
-(void)keyDown:(NSEvent *)event { self.delegated++; }
-(void)previousPage:(id)sender { self.previousCalls++; }
-(void)nextPage:(id)sender { self.nextCalls++; }
-(BOOL)annotationKeyDown:(NSEvent *)event { return self.handlesAnnotation; }
@end
@interface ArrowView:TrackingPDFView
-(BOOL)scrollVerticalArrowWithinPage:(NSEvent *)event;
@end
@implementation ArrowView
METHODS
@end
static NSEvent *key(unichar character, NSEventModifierFlags flags, BOOL repeat) {
 NSString *s=[NSString stringWithCharacters:&character length:1];
 return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags
 timestamp:0 windowNumber:0 context:nil characters:s charactersIgnoringModifiers:s isARepeat:repeat keyCode:0];
}
static PDFDocument *document(NSInteger rotation) {
 PDFDocument *doc=[PDFDocument new];
 for(NSUInteger i=0;i<8;i++) {
  NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(600,800)];
  [image lockFocus];[NSColor.whiteColor setFill];NSRectFill(NSMakeRect(0,0,600,800));[image unlockFocus];
  PDFPage *p=[[PDFPage alloc]initWithImage:image];p.rotation=rotation;[doc insertPage:p atIndex:i];
 }
 return doc;
}
int main(void) { @autoreleasepool {
 [NSApplication sharedApplication];
 NSArray *documents=@[document(0),document(90),document(180),document(270)];
 for(NSInteger mode=0;mode<4;mode++) for(NSInteger style=0;style<2;style++)
 for(NSInteger book=0;book<2;book++) for(NSInteger rtl=0;rtl<2;rtl++) for(NSInteger rotation=0;rotation<4;rotation++) {
  context=[NSString stringWithFormat:@"mode=%ld style=%ld book=%ld rtl=%ld rotation=%ld",mode,style,book,rtl,rotation*90];
  NSWindow *w=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,500,500) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];w.releasedWhenClosed=NO;
  ArrowView *v=[[ArrowView alloc]initWithFrame:w.contentView.bounds];[w.contentView addSubview:v];
  v.document=documents[rotation];v.displayMode=mode;v.displaysAsBook=book;v.displaysRTL=rtl;v.scaleFactor=2;
  NSScrollView *scroll=v.documentView.enclosingScrollView;scroll.scrollerStyle=style;scroll.verticalLineScroll=32;
  TSExternalPDFPosition start={YES,NO,3,NSMakePoint(300,400),2};TSExternalPDFRestore(v,start);pump();
  NSClipView *clip=scroll.contentView;
  // Overlay bars may be hidden until a gesture. Visibility must not determine routing.
  if(style==NSScrollerStyleOverlay) scroll.verticalScroller.hidden=YES;
  BOOL paginated=mode==kPDFDisplaySinglePage||mode==kPDFDisplayTwoUp;
  for(NSNumber *character in @[@(NSDownArrowFunctionKey),@(NSUpArrowFunctionKey)]) {
   NSPoint before=clip.bounds.origin;PDFPage *page=v.currentPage;v.delegated=0;
   [v keyDown:key(character.unsignedShortValue,NSEventModifierFlagFunction|NSEventModifierFlagNumericPad,NO)];
   if(!paginated) { check(v.delegated==1,@"continuous views delegate to PDFKit"); continue; }
   CGFloat sign=character.unsignedShortValue==NSDownArrowFunctionKey?1:-1;if(!clip.isFlipped)sign=-sign;
   check((clip.bounds.origin.y-before.y)*sign>0,@"arrow moves visibly in requested direction");
   check(fabs(clip.bounds.origin.x-before.x)<.01,@"vertical arrows preserve horizontal position");
   for(NSUInteger i=0;i<100;i++) [v keyDown:key(character.unsignedShortValue,0,YES)];
   NSPoint end=clip.bounds.origin;
   for(NSUInteger i=0;i<5;i++) [v keyDown:key(character.unsignedShortValue,0,YES)];
   check(fabs(clip.bounds.origin.y-end.y)<.01,@"key repeat stops at page edge");
   check(v.delegated==0&&v.currentPage==page,@"edge does not delegate or turn page");
  }
  // Modified arrows, annotations and explicit page navigation retain their routes.
  for(NSNumber *flags in @[@(NSEventModifierFlagCommand),@(NSEventModifierFlagOption),@(NSEventModifierFlagControl),@(NSEventModifierFlagShift)]) {
   v.delegated=0;[v keyDown:key(NSDownArrowFunctionKey,flags.unsignedLongLongValue,NO)];
   check(v.delegated==1,@"modified arrows delegate");
  }
  NSPoint before=clip.bounds.origin;v.handlesAnnotation=YES;v.delegated=0;
  [v keyDown:key(NSDownArrowFunctionKey,0,NO)];
  check(NSEqualPoints(before,clip.bounds.origin)&&v.delegated==0,@"annotation handler has priority");v.handlesAnnotation=NO;
  [v keyDown:key(NSLeftArrowFunctionKey,NSEventModifierFlagCommand,NO)];
  [v keyDown:key(NSRightArrowFunctionKey,NSEventModifierFlagCommand,NO)];
  check(v.previousCalls==1&&v.nextCalls==1,@"command arrows still navigate pages");
  [SUD setBool:YES forKey:LeftRightArrowsAlwaysPageKey];
  [v keyDown:key(NSLeftArrowFunctionKey,0,NO)];[v keyDown:key(NSRightArrowFunctionKey,0,NO)];
  check(v.previousCalls==2&&v.nextCalls==2,@"left/right preference still works");
  [SUD setBool:NO forKey:LeftRightArrowsAlwaysPageKey];
  if(paginated) {
   v.scaleFactor=.2;[v layoutDocumentView];[v layoutSubtreeIfNeeded];pump();
   v.delegated=0;[v keyDown:key(NSDownArrowFunctionKey,0,NO)];
   check(v.delegated==1,@"fully visible page delegates to native navigation");
  }
  v.document=nil;v.delegated=0;[v keyDown:key(NSUpArrowFunctionKey,0,NO)];
  check(v.delegated==1,@"no document delegates safely");
  [v removeFromSuperview];[w close];
 }
 puts("PASS: vertical arrows; four modes; legacy/hidden overlay; book/RTL; rotations; both edges and repeat; fit page; modifiers; annotation priority; explicit page commands");
}return 0;}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-vertical-arrows-') as directory:
    temp = Path(directory)
    (temp/'home').mkdir()
    (temp/'test.m').write_text(program)
    subprocess.run(['xcrun','clang','-mmacosx-version-min=14.6','-w','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',
                    '-I'+str(root/'Sources'),str(temp/'test.m'),'-o',str(temp/'test')],check=True)
    subprocess.run([str(temp/'test')],check=True,timeout=180,
                   env=dict(os.environ,CFFIXED_USER_HOME=str(temp/'home')))
