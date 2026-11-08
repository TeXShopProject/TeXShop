#!/usr/bin/env python3
"""Exercise the production combined-window transition without showing any UI."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/TSDocument.m').read_text()
start = source.index('- (void) doMove: (id)sender;')
method = source[start:source.index('\n}', start) + 2]
program = r'''
#import <Cocoa/Cocoa.h>
@interface Node : NSObject
@property NSString *string;
@property NSInteger state, showCount, removeCount;
@property NSRect frame;
@property id parentWindow, window, child;
@property Node *pdfKitSplitView;
@property BOOL previewClosed, hidden;
- (NSRect)bounds;
- (void)addSubview:(id)view;
- (void)removeFromSuperview;
- (void)toggle:(id)sender;
- (void)close;
- (void)showWindow:(id)sender;
- (void)orderOut:(id)sender;
- (void)setFrameFromString:(NSString *)value;
@end
@implementation Node
- (NSRect)bounds { return NSMakeRect(0,0,500,600); }
- (void)addSubview:(id)view { self.child=view; }
- (void)removeFromSuperview { self.removeCount++; }
- (void)toggle:(id)sender {}
- (void)close {}
- (void)showWindow:(id)sender { self.showCount++; }
- (void)orderOut:(id)sender { self.hidden=YES; }
- (void)setFrameFromString:(NSString *)value {}
@end
@interface Defaults : NSObject
@property BOOL interchange;
- (BOOL)boolForKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;
@end
@implementation Defaults
- (BOOL)boolForKey:(NSString *)key { return self.interchange; }
- (NSString *)stringForKey:(NSString *)key { return @""; }
@end
static Defaults *defaults;
#define SUD defaults
#define SwitchSidesKey @"SwitchSides"
#define DocumentSplitWindowPositionKey @"DocumentSplitWindowPosition"
@interface Document : NSObject {
 @public BOOL useFullSplitWindow, fileIsTex, _externalEditor;
 Node *textView1, *myDrawer, *splitView, *rightView, *leftView, *fullSplitWindow, *textWindow;
}
@property NSURL *fileURL;
@property id rootDocument;
@property Node *pdfKitWindow, *splitController;
- (void)addWindowController:(id)controller;
- (void)doMove:(id)sender;
@end
@implementation Document
- (void)addWindowController:(id)controller {}
METHOD
@end
static void check(BOOL ok, NSString *message) {
 if(!ok) { NSLog(@"FAIL: %@",message); exit(1); }
}
static Document *document(NSURL *url) {
 Document *d=[Document new];d.fileURL=url;d->fileIsTex=YES;
 d->textView1=[Node new];d->textView1.string=@"sample";
 d->myDrawer=[Node new];d->splitView=[Node new];
 d->rightView=[Node new];d->leftView=[Node new];
 d->fullSplitWindow=[Node new];d->textWindow=[Node new];
 d.pdfKitWindow=[Node new];d.pdfKitWindow.pdfKitSplitView=[Node new];
 d.pdfKitWindow.previewClosed=YES;d.splitController=[Node new];
 return d;
}
int main(int argc, char **argv) { @autoreleasepool {
 defaults=[Defaults new];
 NSURL *url=[NSURL fileURLWithPath:[@(argv[1]) stringByAppendingPathComponent:@"sample.tex"]];
 NSURL *pdf=[[url URLByDeletingPathExtension] URLByAppendingPathExtension:@"pdf"];
 check([[@"sample" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:pdf atomically:YES],@"Prepare fixture");
 for(NSNumber *side in @[@NO,@YES]) {
  defaults.interchange=side.boolValue;
  Document *d=document(url);[d doMove:nil];
  check(d->useFullSplitWindow && !d.pdfKitWindow.previewClosed,@"Combined preview is no longer closed");
  check(d.splitController.showCount==1 && d.pdfKitWindow.hidden,@"Combined window replaces separate preview");
  Node *destination=side.boolValue?d->leftView:d->rightView;
  check(destination.child==d.pdfKitWindow.pdfKitSplitView,@"PDF is moved into the visible combined window");
  [d doMove:nil];check(d.splitController.showCount==1,@"Already combined is a no-op");
 }
 for(NSNumber *kind in @[@0,@1,@2,@3]) {
  Document *d=document(url);
  if(kind.intValue==0) d.rootDocument=[NSObject new];
  if(kind.intValue==1) d->_externalEditor=YES;
  if(kind.intValue==2) d->fileIsTex=NO;
  if(kind.intValue==3) d->textView1.string=@"%!TEX root = root.tex";
  [d doMove:nil];check(d.pdfKitWindow.previewClosed && !d->useFullSplitWindow,@"Rejected transition retains closed state");
 }
 [[NSFileManager defaultManager] removeItemAtURL:pdf error:NULL];
 Document *d=document(url);[d doMove:nil];
 check(d.pdfKitWindow.previewClosed && !d->useFullSplitWindow,@"Missing PDF retains closed state");
 puts("PASS: production combined-window transition clears closed state, both sides, rejected transitions preserve state");
}}
'''.replace('METHOD', method)

with tempfile.TemporaryDirectory(prefix='texshop-preview-combine-') as td:
    path = Path(td)
    (path / 'home').mkdir()
    (path / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa',
                    str(path / 'test.m'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test'), td], check=True,
                   env=dict(os.environ, CFFIXED_USER_HOME=str(path / 'home')))
