#!/usr/bin/env python3
"""Exercise production source-click routing with real AppKit text layout.

The document is a recording double; no TeXShop settings or windows are opened.
"""
from pathlib import Path
import os
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['live-menu-pointer'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Editor/TSTextView.m').read_text(encoding='latin1')
a = source.index('- (void)doSyncForMenu:')
b = source.index('- (void)mouseUp:', a)
methods = source[a:b]
a = source.index('- (NSMenu *)menuForEvent:')
menu_method = source[a:source.index('\n}', a) + 2]
if args.mutation == 'live-menu-pointer':
    old = '[theEvent.window convertPointToScreen:theEvent.locationInWindow]'
    assert old in menu_method
    menu_method = menu_method.replace(old, '[NSEvent mouseLocation]', 1)
methods += '\n' + menu_method
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
// Keep the live pointer deliberately away from every recorded click.
@interface NSEvent (TestPointer)
@end
@implementation NSEvent (TestPointer)
+ (NSPoint)mouseLocation { return NSMakePoint(-10000,-10000); }
@end
static NSPoint menuPoint;
enum { RootForPdfSync = 1 };
@class TSTextView;
@interface RecordingDocument : NSObject
@property NSTextView *textView;
@property NSUInteger characterIndex, pdfSyncLine, calls;
@property NSInteger receivedLine;
@property id receivedView;
@property BOOL master, root, textSelectionYellow;
- (BOOL)checkMasterFile:(NSString *)text forTask:(NSInteger)task;
- (BOOL)checkRootFile_forTask:(NSInteger)task;
- (void)doPreviewSyncWithFilename:(NSString *)file andLine:(NSInteger)line andCharacterIndex:(NSUInteger)index andTextView:(id)view;
@end
@implementation RecordingDocument
- (BOOL)checkMasterFile:(NSString *)text forTask:(NSInteger)task { return self.master; }
- (BOOL)checkRootFile_forTask:(NSInteger)task { return self.root; }
- (void)doPreviewSyncWithFilename:(NSString *)file andLine:(NSInteger)line andCharacterIndex:(NSUInteger)index andTextView:(id)view {
 self.calls++; self.receivedLine=line; self.receivedView=view;
}
@end
@interface OrdinaryTextView : NSTextView
@property NSUInteger ordinaryClicks;
@end
@implementation OrdinaryTextView
- (void)mouseDown:(NSEvent *)event { self.ordinaryClicks++; }
@end
@interface TSTextView : OrdinaryTextView { BOOL _alternateDown; }
@property RecordingDocument *document;
- (void)doSyncFinal:(NSPoint)point;
@end
@implementation TSTextView
METHODS
@end
static NSUInteger failures, checks;
static void check(BOOL ok, const char *label) {
 checks++; if(!ok){ failures++; fprintf(stderr,"FAIL: %s\n", label); }
}
static NSPoint pointForIndex(TSTextView *view, NSUInteger index) {
 NSLayoutManager *layout=view.layoutManager;
 [layout ensureLayoutForTextContainer:view.textContainer];
 NSUInteger glyph=[layout glyphIndexForCharacterAtIndex:index];
 NSRect rect=[layout boundingRectForGlyphRange:NSMakeRange(glyph,1) inTextContainer:view.textContainer];
 return NSMakePoint(NSMinX(rect)+view.textContainerOrigin.x+0.1,NSMidY(rect)+view.textContainerOrigin.y);
}
static NSPoint screenPoint(TSTextView *view, NSPoint point) {
 return [view.window convertPointToScreen:[view convertPoint:point toView:nil]];
}
static NSEvent *click(TSTextView *view, NSPoint point, NSEventModifierFlags flags) {
 return [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:[view convertPoint:point toView:nil]
  modifierFlags:flags timestamp:1 windowNumber:view.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
}
int main() { @autoreleasepool {
 TSInstallAppKitIsolation(); [NSApplication sharedApplication];
 NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(170,200,700,600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
 window.releasedWhenClosed=NO;
 RecordingDocument *doc=[RecordingDocument new];
 TSTextView *view=[[TSTextView alloc] initWithFrame:NSMakeRect(0,0,320,1600)];
 NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(30,40,320,180)];
 scroll.documentView=view; [window.contentView addSubview:scroll];
 view.document=doc; doc.textView=view;
 view.font=[NSFont fontWithName:@"Menlo" size:15];
 for(NSString *newline in @[@"\n",@"\r\n",@"\r"]) {
  view.string=[@[@"first",@"second",@"third"] componentsJoinedByString:newline];
  NSUInteger second=5+newline.length;
  NSPoint point=pointForIndex(view,second);
  [view doSyncFinal:screenPoint(view,point)];
  check(doc.receivedLine==2,"first character of a line belongs to that line");
  NSUInteger before=doc.calls;
  [view mouseDown:click(view,point,NSEventModifierFlagCommand)];
  check(doc.calls==before+1 && doc.receivedLine==2,"Command-click uses recorded event position, not the current pointer");
 }
 NSUInteger before=doc.calls;
 NSPoint point=pointForIndex(view,2);
 [view mouseDown:click(view,point,0)];
 [view mouseDown:click(view,point,NSEventModifierFlagCommand|NSEventModifierFlagOption)];
 check(doc.calls==before && view.ordinaryClicks==2,"plain and Option-Command clicks preserve ordinary handling");
 [view mouseDown:click(view,point,NSEventModifierFlagCommand|NSEventModifierFlagShift)];
 check(doc.calls==before+1,"Shift does not suppress Command-click sync");
 doc.master=YES; before=doc.calls; [view doSyncFinal:screenPoint(view,point)];
 check(doc.calls==before,"master document handles redirected sync"); doc.master=NO;
 doc.root=YES; [view doSyncFinal:screenPoint(view,point)];
 check(doc.calls==before,"root document handles redirected sync"); doc.root=NO;
 // Use the production menuForEvent: and its actual Sync item, not a fabricated menuPoint.
 point=pointForIndex(view,6); // Second source line, distinct from the far-away live pointer.
 NSEvent *menuEvent=[NSEvent mouseEventWithType:NSEventTypeRightMouseDown
  location:[view convertPoint:point toView:nil] modifierFlags:0 timestamp:2
  windowNumber:window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:1];
 NSMenu *menu=[view menuForEvent:menuEvent];
 check(menu != nil && menu.numberOfItems >= 3,"production context menu is constructed");
 NSMenuItem *syncItem=menu.numberOfItems ? [menu itemAtIndex:0] : nil;
 check(syncItem.action == @selector(doSyncForMenu:),"context menu exposes the Sync action");
 [NSApp sendAction:syncItem.action to:view from:syncItem];
 check(doc.calls==before+1 && doc.receivedLine==2,"context-menu sync uses the right-click event position");
 TSTextView *second=[[TSTextView alloc] initWithFrame:NSMakeRect(380,40,280,500)];
 [window.contentView addSubview:second]; second.document=doc;
 // Each split pane has its own layout manager over the same text storage.
 [second.layoutManager replaceTextStorage:view.textStorage];
 [second doSyncFinal:screenPoint(second,pointForIndex(second,2))];
 check(doc.receivedView==second,"sync forwards the clicked split pane");
 NSMutableString *longText=[NSMutableString new];
 for(int i=0;i<100;i++) [longText appendFormat:@"row %d 日本語 text\n",i];
 view.string=longText;
 NSRange target=[view.string rangeOfString:@"row 60"];
 point=pointForIndex(view,target.location+2);
 [scroll.contentView scrollToPoint:NSMakePoint(0,point.y-40)];
 [view mouseDown:click(view,point,NSEventModifierFlagCommand)];
 check(doc.receivedLine==61,"scrolled source uses text coordinates");
 view.string=@"first\nsecond";
 point=pointForIndex(view,view.string.length-1); point.x+=12;
 [view doSyncFinal:screenPoint(view,point)];
 check(doc.receivedLine==2,"end-of-document insertion point keeps the last line");
 view.string=[@"word " stringByPaddingToLength:400 withString:@"word " startingAtIndex:0];
 point=pointForIndex(view,160);
 [view mouseDown:click(view,point,NSEventModifierFlagCommand)];
 check(doc.receivedLine==1,"soft-wrapped text keeps its source line number");
 view.string=@""; before=doc.calls;
 [view doSyncFinal:screenPoint(view,NSMakePoint(10,10))];
 check(doc.calls==before,"empty text does not dispatch sync");
 printf("%lu checks, %lu failures\n",checks,failures);
 return failures ? 1 : 0;
} }
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-source-sync-') as tmp:
    src, exe = Path(tmp)/'test.m', Path(tmp)/'test'
    src.write_text(program)
    subprocess.run(['xcrun','clang','-I',str(root/'Tests'),'-w','-fobjc-arc','-framework','Cocoa',str(src),'-o',str(exe)],check=True)
    (Path(tmp)/'home/Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(exe)],env=dict(os.environ,HOME=str(Path(tmp)/'home'),CFFIXED_USER_HOME=str(Path(tmp)/'home')),capture_output=True,text=True,timeout=30)
    print(result.stdout + result.stderr, end='')
    if args.mutation:
        assert result.returncode == 1 and 'FAIL: context-menu sync uses the right-click event position' in result.stderr
        print('PASS: detected', args.mutation)
    else:
        raise SystemExit(result.returncode)
