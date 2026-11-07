#!/usr/bin/env python3
"""Check real PDFKit viewport restoration without launching TeXShop or loading its settings."""
import argparse
import ast
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['legacy-reload'])
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
program = fixture.replace('METHODS', methods.replace('MyPDFKitView *weakSelf', 'RecoveryView *weakSelf')) + r'''
static void check(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
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
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    [SUD setVolatileDomain:@{@"flash":@NO} forName:NSArgumentDomain];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600,800)];
    [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,600,800)); [image unlockFocus];
    PDFDocument *pdf = [PDFDocument new];
    for (NSUInteger n=0;n<8;n++) [pdf insertPage:[[PDFPage alloc] initWithImage:image] atIndex:n];
    NSData *bytes = pdf.dataRepresentation;
    for (NSInteger direction=0;direction<2;direction++)
    for (NSInteger mode=0;mode<4;mode++) for (NSNumber *rotation in @[@0,@90])
    for (NSNumber *scale in @[@1.25,@2.0]) {
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
            sameViewport(before,view,@"reload preserves viewport with changed page count");
            check(fabs(view.scaleFactor-scale.doubleValue)<.001,@"reload preserves zoom");
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
    puts("PASS: four display modes, changed page counts, zoom, rotation, horizontal/vertical, book/RTL, resize, auto fit, last-page fallback");
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix='texshop-viewport-') as directory:
    temp = Path(directory)
    (temp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    '-I'+str(root/'Sources'), str(temp/'test.m'), str(root/'Sources/HideView.m'),
                    str(root/'Sources/TSExternalPDFSnapshot.m'), '-o', str(temp/'test')], check=True)
    subprocess.run([str(temp/'test')], check=True, timeout=60)
