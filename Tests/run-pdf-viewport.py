#!/usr/bin/env python3
"""Check real PDFKit viewport restoration without launching TeXShop or loading its settings."""
import argparse
import ast
import os
import shutil
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['legacy-reload', 'legacy-second', 'skip-last-page', 'legacy-constraints', 'unconstrained'])
parser.add_argument('--artifacts', type=Path, help='Keep the generated Objective-C and executable for cross-OS testing')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/MyPDFKitView.m').read_text(encoding='latin1')
def method(signature):
    start = source.rindex(signature)
    return source[start:source.index('\n}', start) + 2]
fixture_tree = ast.parse((root / 'Tests/run-pdf-recovery.py').read_text())
fixture = max((node.value for node in ast.walk(fixture_tree)
               if isinstance(node, ast.Constant) and isinstance(node.value, str)), key=len)
fixture = fixture[:fixture.index('static void check(')]
fixture = fixture.replace('WINDOW_METHODS', '')
fixture = '#define PDF_SINGLE_PAGE_STYLE 1\n#define PDF_TWO_PAGE_STYLE 2\n' + fixture
signatures = ['- (void)reShowWithPath:', '- (void)reShowWithDocument:',
              '- (void)shareDocumentWithSecondView', '- (void)prepareSecond',
              '- (void) reShowForSecond', '- (void) initializeDisplay',
              '- (void)removeHideView1:', '- (void)removeHideView2:',
              '- (void)setDocument:(PDFDocument *)document', '- (instancetype)initWithFrame:']
methods = '\n'.join(method(signature) for signature in signatures)
if args.mutation == 'legacy-reload':
    old = 'if (viewport.valid && viewport.pageIndex < self.document.pageCount)'
    assert methods.count(old) == 1
    methods = methods.replace(old, 'if (NO)')
elif args.mutation == 'legacy-second':
    old = 'if (secondViewport.valid && secondViewport.pageIndex < self.document.pageCount)'
    assert methods.count(old) == 1
    methods = methods.replace(old, 'if (NO)')
elif args.mutation == 'skip-last-page':
    old = 'viewport.pageIndex < self.document.pageCount'
    assert methods.count(old) == 1
    methods = methods.replace(old, 'viewport.pageIndex + 1 < self.document.pageCount')
program = fixture.replace('METHODS', methods.replace('MyPDFKitView *weakSelf', 'RecoveryView *weakSelf')) + r'''
static NSString *context;
static void check(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr,"FAIL: %s [%s]\n",message.UTF8String,context.UTF8String); exit(1); }
}
static void pump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
}
static PDFDocument *document(NSData *bytes, NSUInteger count, NSInteger rotation) {
    PDFDocument *pdf = [[PDFDocument alloc] initWithData:bytes];
    while (pdf.pageCount > count) [pdf removePageAtIndex:pdf.pageCount - 1];
    for (NSUInteger n=0;n<pdf.pageCount;n++) [pdf pageAtIndex:n].rotation=rotation;
    return pdf;
}
static void sameViewport(TSExternalPDFPosition expected, PDFView *view, NSString *message) {
    TSExternalPDFPosition actual = TSExternalPDFCapture(view);
    CGFloat distance = hypot(actual.pagePoint.x - expected.pagePoint.x,
                             actual.pagePoint.y - expected.pagePoint.y);
    if (!(actual.valid && actual.pageIndex == expected.pageIndex && distance < 1.1))
        fprintf(stderr,"viewport: page %lu -> %lu, point %s -> %s\n",
                expected.pageIndex,actual.pageIndex,NSStringFromPoint(expected.pagePoint).UTF8String,
                NSStringFromPoint(actual.pagePoint).UTF8String);
    check(actual.valid && actual.pageIndex == expected.pageIndex && distance < 1.1, message);
}
// Stand-in for macOS 26: with content insets, -[NSClipView constrainBoundsRect:]
// moved an origin that was already inside the scrollable range by about 13.5
// points. Reproduce that on other systems so the restoration is checked there too.
#import <objc/runtime.h>
static NSClipView *shiftingClip;
static NSRect (*nativeConstrain)(id, SEL, NSRect);
static NSRect shiftingConstrain(NSClipView *self, SEL _cmd, NSRect proposed) {
    NSRect result = nativeConstrain(self, _cmd, proposed);
    if (self != shiftingClip) return result;
    NSRect far = proposed; far.origin.y = NSMaxY(self.documentRect) + 1e5;
    CGFloat top = nativeConstrain(self, _cmd, far).origin.y;
    far.origin.y = NSMinY(self.documentRect) - 1e5;
    CGFloat bottom = nativeConstrain(self, _cmd, far).origin.y;
    if (result.origin.y > bottom + .5 && result.origin.y < top - .5)
        result.origin.y = fmin(result.origin.y + 13.5, top);
    return result;
}
static void installShiftingClip(void) {
    Method method = class_getInstanceMethod(NSClipView.class, @selector(constrainBoundsRect:));
    nativeConstrain = (void *)method_setImplementation(method, (IMP)shiftingConstrain);
}
@interface ViewportToolbar : NSObject <NSToolbarDelegate> @end
@implementation ViewportToolbar
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return @[@"item"]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return @[@"item"]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)insert {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label=@"Test"; item.view=[NSButton buttonWithTitle:@"Test" target:nil action:nil]; return item;
}
@end
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    [SUD setVolatileDomain:@{@"flash":@NO} forName:NSArgumentDomain];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600,800)];
    [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,600,800)); [image unlockFocus];
    PDFDocument *pdf = [PDFDocument new];
    for (NSUInteger n=0;n<8;n++) [pdf insertPage:[[PDFPage alloc] initWithImage:image] atIndex:n];
    NSData *bytes = pdf.dataRepresentation;
    for (NSInteger direction=0;direction<2;direction++)
    for (NSInteger mode=0;mode<4;mode++) for (NSNumber *rotation in @[@0,@90])
    for (NSNumber *scale in @[@1.25,@2.0]) {
        context=[NSString stringWithFormat:@"direction=%ld mode=%ld rotation=%@ scale=%@",direction,mode,rotation,scale];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,500)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        RecoveryView *view = [[RecoveryView alloc] initWithFrame:window.contentView.bounds];
        [window.contentView addSubview:view];
        view.myPDFWindow=[TestWindow new]; view.myDocument=[TestDocument new];
        view.myDocument.pdfKitWindow=view.myPDFWindow;
        view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        view.document=document(bytes,6,rotation.integerValue); view.displayMode=mode;
        view.displayDirection=direction; view.displaysAsBook=direction; view.displaysRTL=direction;
        view.scaleFactor=scale.doubleValue; [view goToPage:[view.document pageAtIndex:1]]; pump();
        NSClipView *clip=view.documentView.enclosingScrollView.contentView;
        NSRect bounds=clip.bounds; bounds.origin.x+=60; bounds.origin.y+=80;
        [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin]; pump();
        TSExternalPDFPosition before=TSExternalPDFCapture(view);
        check(before.valid,@"capture page viewport");
        // Appending/deleting later pages must not move the current page.
        for (NSNumber *count in @[@6,@8,@4]) {
            [view reShowWithDocument:document(bytes,count.unsignedIntegerValue,rotation.integerValue)]; pump();
            sameViewport(before,view,[NSString stringWithFormat:@"reload preserves viewport with page count %@",count]);
            check(fabs(view.scaleFactor-scale.doubleValue)<.001,@"reload preserves zoom");
        }
        // Exercise the first reload after zooming, before and after AppKit settles.
        for (NSNumber *settle in @[@NO, @YES]) {
            view.scaleFactor = scale.doubleValue / 2;
            pump();
            view.scaleFactor = scale.doubleValue;
            if (settle.boolValue) pump();
            TSExternalPDFPosition zoomed = TSExternalPDFCapture(view);
            for (NSUInteger reload=0; reload<2; reload++) {
                [view reShowWithDocument:document(bytes,4,rotation.integerValue)]; pump();
                TSExternalPDFPosition actual = TSExternalPDFCapture(view);
                CGFloat screenDrift = hypot(actual.pagePoint.x-zoomed.pagePoint.x,
                                             actual.pagePoint.y-zoomed.pagePoint.y) * view.scaleFactor;
                check(actual.pageIndex == zoomed.pageIndex && screenDrift < .75,
                      [NSString stringWithFormat:@"zoom reload %lu (settled=%@) drift %.3f screen points",reload,settle,screenDrift]);
            }
        }
        // Reload after the window changes size must preserve its new viewport.
        [window setContentSize:NSMakeSize(650,420)]; pump();
        TSExternalPDFPosition resized=TSExternalPDFCapture(view);
        [view reShowWithDocument:document(bytes,4,rotation.integerValue)]; pump();
        sameViewport(resized,view,@"reload preserves viewport after resizing the window");
        // Fit-to-window pages stay centered rather than acquiring an offset.
        view.displayMode=kPDFDisplaySinglePage; view.autoScales=YES;
        [view goToPage:[view.document pageAtIndex:0]]; pump();
        TSExternalPDFPosition fitted=TSExternalPDFCapture(view);
        [view reShowWithDocument:document(bytes,4,rotation.integerValue)]; pump();
        sameViewport(fitted,view,@"fit page remains centered");
        // If the old page vanished, use the established last-page fallback.
        view.autoScales=NO; view.scaleFactor=1.25; [view goToPage:[view.document pageAtIndex:3]];
        [view reShowWithDocument:document(bytes,2,rotation.integerValue)]; pump();
        check([view.document indexForPage:view.currentPage]==1,@"removed current page falls back to last page");
        view.document=nil; [view removeFromSuperview]; [window close];
    }
    // A toolbar extending into the content produces the insets associated with
    // repeated upward drift even when the PDF has exactly the same pages.
    ViewportToolbar *toolbarDelegate = [ViewportToolbar new];
    for (NSNumber *style in @[@(NSScrollerStyleLegacy), @(NSScrollerStyleOverlay)])
    for (NSInteger mode=0;mode<4;mode++) {
        context=[NSString stringWithFormat:@"insets style=%@ mode=%ld",style,mode];
        NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,500)
            styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskFullSizeContentView
            backing:NSBackingStoreBuffered defer:NO]; window.releasedWhenClosed=NO;
        NSToolbar *toolbar=[[NSToolbar alloc] initWithIdentifier:@"ViewportTest"];
        toolbar.delegate=toolbarDelegate; window.toolbar=toolbar;
        window.toolbarStyle=NSWindowToolbarStyleExpanded;
        RecoveryView *view=[[RecoveryView alloc] initWithFrame:window.contentView.bounds];
        [window.contentView addSubview:view];
        view.myPDFWindow=[TestWindow new]; view.myDocument=[TestDocument new];
        view.myDocument.pdfKitWindow=view.myPDFWindow;
        view.document=document(bytes,4,0); view.displayMode=mode;
        view.documentView.enclosingScrollView.scrollerStyle=style.integerValue;
        view.scaleFactor=1.25;
        [view goToPage:[view.document pageAtIndex:3]]; pump();
        NSScrollView *scroll=view.documentView.enclosingScrollView;
        check(scroll.contentInsets.top>0,@"toolbar test actually has a top inset");
        NSClipView *clip=scroll.contentView; NSRect bounds=clip.bounds;
        bounds.origin.x+=40; bounds.origin.y+=(mode==0||mode==2)?80:-100;
        [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];pump();
        TSExternalPDFPosition before=TSExternalPDFCapture(view);
        if (mode==kPDFDisplaySinglePage) check(before.pageIndex==3,@"last-page viewport captured");
        for (NSUInteger n=0;n<3;n++) {
            [view reShowWithDocument:document(bytes,4,0)];pump();
            sameViewport(before,view,@"same PDF reload retains inset viewport on final page");
        }
        [view reShowWithDocument:document(bytes,6,0)];pump();
        sameViewport(before,view,@"appending pages retains formerly final page viewport");
        view.document=nil;[view removeFromSuperview];[window close];
    }
    installShiftingClip();
    for (NSInteger mode=0;mode<4;mode++) for (NSNumber *scale in @[@1.25,@2]) {
        context=[NSString stringWithFormat:@"shifting clip mode=%ld scale=%@",mode,scale];
        NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,500,500)
            styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskFullSizeContentView
            backing:NSBackingStoreBuffered defer:NO]; window.releasedWhenClosed=NO;
        NSToolbar *toolbar=[[NSToolbar alloc] initWithIdentifier:@"ViewportShift"];
        toolbar.delegate=toolbarDelegate; window.toolbar=toolbar;
        window.toolbarStyle=NSWindowToolbarStyleExpanded;
        RecoveryView *view=[[RecoveryView alloc] initWithFrame:window.contentView.bounds];
        [window.contentView addSubview:view];
        view.myPDFWindow=[TestWindow new]; view.myDocument=[TestDocument new];
        view.myDocument.pdfKitWindow=view.myPDFWindow;
        view.document=document(bytes,4,0); view.displayMode=mode;
        view.documentView.enclosingScrollView.scrollerStyle=NSScrollerStyleOverlay;
        view.scaleFactor=scale.doubleValue;
        [view goToPage:[view.document pageAtIndex:1]]; pump();
        NSClipView *clip=view.documentView.enclosingScrollView.contentView;
        NSRect bounds=clip.bounds; bounds.origin.x+=40; bounds.origin.y+=60;
        [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];pump();
        shiftingClip=clip;
        TSExternalPDFPosition before=TSExternalPDFCapture(view);
        for (NSUInteger n=0;n<3;n++) {
            [view reShowWithDocument:document(bytes,4,0)];pump();
            sameViewport(before,view,@"reload keeps an interior viewport when constraints shift it");
        }
        // Positions beyond the scrollable range must still follow the native limits.
        TSExternalPDFPosition far={YES,NO,3,NSMakePoint(590,10),scale.doubleValue};
        TSExternalPDFRestore(view,far);pump();
        NSRect limited=[clip constrainBoundsRect:NSMakeRect(1e5,1e5,clip.bounds.size.width,clip.bounds.size.height)];
        if (clip.isFlipped) check(fabs(clip.bounds.origin.y-limited.origin.y)<.5,@"far restoration stops at the native lower limit");
        shiftingClip=nil;
        view.document=nil;[view removeFromSuperview];[window close];
    }
    method_setImplementation(class_getInstanceMethod(NSClipView.class, @selector(constrainBoundsRect:)),
                             (IMP)nativeConstrain);
    // A new typeset PDF may use smaller paper. Keeping the old page coordinates
    // must not scroll the entire replacement page out of view.
    for (NSInteger mode=0;mode<4;mode++) {
        context=[NSString stringWithFormat:@"smaller paper mode=%ld",mode];
        NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,400,400)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed=NO;
        RecoveryView *view=[[RecoveryView alloc] initWithFrame:window.contentView.bounds];
        [window.contentView addSubview:view];
        view.myPDFWindow=[TestWindow new]; view.myDocument=[TestDocument new];
        view.myDocument.pdfKitWindow=view.myPDFWindow;
        view.document=document(bytes,4,0); view.displayMode=mode; view.scaleFactor=2;
        TSExternalPDFPosition start={YES,NO,0,NSMakePoint(500,700),2};
        TSExternalPDFRestore(view,start); pump();
        PDFDocument *smaller=document(bytes,4,0);
        for (NSUInteger n=0;n<smaller.pageCount;n++) {
            PDFPage *page=[smaller pageAtIndex:n];
            [page setBounds:NSMakeRect(0,0,150,200) forBox:kPDFDisplayBoxMediaBox];
            [page setBounds:NSMakeRect(0,0,150,200) forBox:kPDFDisplayBoxCropBox];
        }
        [view reShowWithDocument:smaller]; pump();
        NSClipView *clip=view.documentView.enclosingScrollView.contentView;
        NSRect visible=[view convertRect:clip.bounds fromView:clip];
        PDFPage *page=[smaller pageAtIndex:0];
        NSRect pageRect=[view convertRect:[page boundsForBox:view.displayBox] fromPage:page];
        check(!NSIsEmptyRect(NSIntersectionRect(visible,pageRect)),
              @"smaller replacement paper remains visible after clamping");
        view.document=nil; [view removeFromSuperview]; [window close];
    }
    // Follow the actual typesetting sequence, including the separately saved
    // lower pane rather than only the first view's document replacement.
    for (NSInteger mode=0;mode<4;mode++) for (NSNumber *scale in @[@1.25,@2]) {
        context=[NSString stringWithFormat:@"split mode=%ld scale=%@",mode,scale];
        NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,900)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];window.releasedWhenClosed=NO;
        RecoveryView *top=[[RecoveryView alloc]initWithFrame:NSMakeRect(0,450,600,450)];
        RecoveryView *bottom=[[RecoveryView alloc]initWithFrame:NSMakeRect(0,0,600,450)];
        TestWindow *tw=[TestWindow new];tw.windowIsSplit=YES;
        TestDocument *td=[TestDocument new];td.pdfKitWindow=tw;td.myPDFKitView2=bottom;
        for (RecoveryView *view in @[top,bottom]) {
            [window.contentView addSubview:view];view.myPDFWindow=tw;view.myDocument=td;
        }
        top.document=document(bytes,6,0);bottom.document=top.document;
        for (RecoveryView *view in @[top,bottom]) {view.displayMode=mode;view.scaleFactor=scale.doubleValue;}
        [top goToPage:[top.document pageAtIndex:1]];[bottom goToPage:[bottom.document pageAtIndex:2]];pump();
        for (RecoveryView *view in @[top,bottom]) {
            NSClipView *clip=view.documentView.enclosingScrollView.contentView;NSRect bounds=clip.bounds;
            bounds.origin.x+=50;bounds.origin.y+=(mode==0||mode==2)?100:-120;
            [clip scrollToPoint:[clip constrainBoundsRect:bounds].origin];
        }
        pump();TSExternalPDFPosition first=TSExternalPDFCapture(top),second=TSExternalPDFCapture(bottom);
        for (NSNumber *count in @[@6,@8,@4]) {
            [bottom prepareSecond];[top reShowWithDocument:document(bytes,count.unsignedIntegerValue,0)];
            bottom.document=top.document;[bottom reShowForSecond];pump();
            sameViewport(first,top,@"split top pane keeps viewport");
            sameViewport(second,bottom,@"split bottom pane keeps viewport");
        }
        top.document=nil;bottom.document=nil;[top removeFromSuperview];[bottom removeFromSuperview];[window close];
    }
    puts("PASS: four display modes, changed page counts, zoom, rotation, horizontal/vertical, book/RTL, resize, auto fit, last-page fallback, both scroller styles with insets, smaller paper, retained last page, split panes");
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix='texshop-viewport-') as directory:
    temp = Path(directory)
    (temp / 'test.m').write_text(program)
    if args.mutation in ('legacy-constraints', 'unconstrained'):
        header = (root / 'Sources/TSExternalPDFReload.h').read_text()
        start = header.index('    // On macOS 26, NSClipView')
        end = header.index('    [clip scrollToPoint:target.origin];', start)
        replacement = ('    target = [clip constrainBoundsRect:target];\n'
                       if args.mutation == 'legacy-constraints' else '')
        (temp/'TSExternalPDFReload.h').write_text(header[:start] + replacement + header[end:])
    subprocess.run(['xcrun', 'clang', '-I', str(root/'Tests'), '-mmacosx-version-min=14.6', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    '-I'+str(root/'Sources'), str(temp/'test.m'), str(root/'Sources/HideView.m'),
                    str(root/'Sources/TSExternalPDFSnapshot.m'), '-o', str(temp/'test')], check=True)
    home = temp / 'home'
    (home/'Library'/'Preferences').mkdir(parents=True)
    environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
    if args.artifacts:
        args.artifacts.mkdir(parents=True, exist_ok=True)
        shutil.copy2(temp/'test.m', args.artifacts/'test.m')
        shutil.copy2(temp/'test', args.artifacts/'test')
        if (temp/'TSExternalPDFReload.h').exists():
            shutil.copy2(temp/'TSExternalPDFReload.h', args.artifacts/'TSExternalPDFReload.h')
    subprocess.run([str(temp/'test')], check=True, timeout=120, env=environment)
