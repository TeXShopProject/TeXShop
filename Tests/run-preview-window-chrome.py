#!/usr/bin/env python3
"""The preview's appearance applies to the pages, not to the window frame.

On macOS 26 and later the preview runs under the toolbar. Forcing the PDF scroll
view to the light appearance used to make AppKit draw the title bar and the
toolbar light as well. The pages, and the area around them, are still drawn
light (and inverted for a dark preview). The scroll view and the pocket under
the toolbar keep the system's appearance, so the window frame does too.

The windows are never ordered on screen. Defaults stay in memory.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path
from production_fragments import method, verify_embedded
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['scroll-appearance', 'late-scroller'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
header = (root / 'Sources/Preview/TSPreviewAppearance.h').read_text()
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
view_methods = [method(view_source, signature) for signature in (
    '- (void)setScaleFactor:(CGFloat)scale', '- (void)setFrameSize:(NSSize)newSize')]
view_text = '\n'.join(view_methods)
if args.mutation == 'scroll-appearance':
    old = '    scrollView.appearance = nil;\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '    scrollView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];\n', 1)
elif args.mutation == 'late-scroller':
    old = '    TSReapplyPreviewInversion(self.documentView.enclosingScrollView);\n'
    assert view_text.count(old) == 2, args.mutation
    view_text = view_text.replace(old, '')

program = r'''
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "TestAppKitIsolation.h"
#import "TSContentZoom.h"
#import "TSPreviewScrollerKeeper.h"
#define NEW_PDF_FIT_TO_NONE 2
#define NEW_PDF_FIT_TO_CONTENT_WIDTH 6
HEADER
static int checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSString *Match(NSAppearance *appearance) {
    return [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
}
static NSView *FindClass(NSView *view, NSString *name) {
    if ([NSStringFromClass(view.class) isEqualToString:name]) return view;
    for (NSView *subview in view.subviews) {
        NSView *found = FindClass(subview, name);
        if (found) return found;
    }
    return nil;
}
static void Pump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
}
static PDFDocument *Document(void) {
    PDFDocument *document = [PDFDocument new];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(300, 400)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 300, 400));
    [image unlockFocus];
    [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:0];
    return document;
}
static void CheckChrome(NSWindow *window, PDFView *pdf, NSString *systemName, BOOL inverted) {
    Pump();
    [window layoutIfNeeded];
    [pdf layoutSubtreeIfNeeded];
    NSView *titlebar = FindClass(window.contentView.superview, @"NSTitlebarView");
    check(titlebar != nil, @"the window has a title bar");
    check([Match(window.effectiveAppearance) isEqual:systemName], @"the window follows the system");
    check([Match(titlebar.effectiveAppearance) isEqual:systemName], @"the title bar follows the system, not the preview");
    NSScrollView *scroll = pdf.documentView.enclosingScrollView;
    check(scroll.appearance == nil && scroll.contentFilters.count == 0, @"the scroll view keeps the system's appearance and does not invert the pocket");
    check([Match(scroll.contentView.effectiveAppearance) isEqual:NSAppearanceNameAqua], @"the pages are drawn light");
    check(scroll.contentView.contentFilters.count == (inverted ? 3 : 0), @"the inversion filters apply to the pages");
    BOOL pocket = NO, around = NO;
    for (NSView *subview in scroll.subviews) {
        if (TSPreviewSubviewIsToolbarPocket(subview)) {
            pocket = YES;
            check(subview.appearance == nil && subview.contentFilters.count == 0, @"the pocket under the toolbar is left alone");
            check([Match(subview.effectiveAppearance) isEqual:systemName], @"the pocket follows the system");
        } else if (subview != scroll.contentView && ![subview isKindOfClass:NSScroller.class]
                   && NSHeight(subview.frame) > NSHeight(scroll.bounds) * 0.5) {
            around = YES;
            check([Match(subview.effectiveAppearance) isEqual:NSAppearanceNameAqua], @"the area around the pages follows the preview");
            check(subview.contentFilters.count == (inverted ? 3 : 0), @"the area around the pages is inverted with them");
        }
    }
    check(pocket && around, @"the pocket and the area around the pages are both present");
}
@interface ChromeDocumentPreview : PDFView {
    BOOL _fittingContentWidth;
    NSInteger resizeOption;
}
- (void)fitContentWidthKeepingTop:(TSContentTop)top;
@end
@implementation ChromeDocumentPreview
- (void)fitContentWidthKeepingTop:(TSContentTop)top {}
VIEWMETHODS
@end
static void CheckLateBar(PDFView *pdf, BOOL inverted, NSString *what) {
    [pdf layoutSubtreeIfNeeded];
    NSScrollView *scroll = pdf.documentView.enclosingScrollView;
    NSScroller *bar = scroll.horizontalScroller;
    check(scroll.hasHorizontalScroller && bar != nil, [what stringByAppendingString:@": the horizontal scroller is present"]);
    check(bar.contentFilters.count == (inverted ? 3 : 0), [what stringByAppendingString:@": the new scroller has the preview's filters"]);
    check(bar.appearance == [NSAppearance appearanceNamed:NSAppearanceNameAqua], [what stringByAppendingString:@": the new scroller is light"]);
    check(scroll.appearance == nil && scroll.contentFilters.count == 0, [what stringByAppendingString:@": the scroll view stays with the system"]);
    check(scroll.contentView.contentFilters.count == (inverted ? 3 : 0), [what stringByAppendingString:@": the pages keep their filters"]);
    for (NSView *subview in scroll.subviews)
        if (TSPreviewSubviewIsToolbarPocket(subview))
            check(subview.appearance == nil && subview.contentFilters.count == 0, [what stringByAppendingString:@": the pocket stays untouched"]);
    NSView *titlebar = FindClass(pdf.window.contentView.superview, @"NSTitlebarView");
    check([Match(titlebar.effectiveAppearance) isEqual:NSAppearanceNameDarkAqua], [what stringByAppendingString:@": the title bar stays dark"]);
}
static ChromeDocumentPreview *LatePreview(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 750, 550)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    window.toolbarStyle = NSWindowToolbarStyleExpanded;
    window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"TSPreviewChromeLate"];
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    ChromeDocumentPreview *pdf = [[ChromeDocumentPreview alloc] initWithFrame:window.contentView.bounds];
    pdf.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    pdf.autoScales = NO;
    pdf.displayMode = kPDFDisplaySinglePage;
    pdf.document = Document();
    [window.contentView addSubview:pdf];
    [window layoutIfNeeded];
    [pdf layoutSubtreeIfNeeded];
    pdf.scaleFactor = 0.5;
    return pdf;
}
int main(void) {
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 520)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
            backing:NSBackingStoreBuffered defer:NO];
        window.toolbarStyle = NSWindowToolbarStyleExpanded;
        window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"TSPreviewChromeTest"];
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
        PDFView *pdf = [[PDFView alloc] initWithFrame:window.contentView.bounds];
        pdf.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        pdf.autoScales = YES;
        pdf.document = Document();
        [window.contentView addSubview:pdf];
        [window layoutIfNeeded];
        [pdf layoutSubtreeIfNeeded];
        NSScrollView *scroll = pdf.documentView.enclosingScrollView;

        TSApplyPreviewInversion(scroll, NO);
        CheckChrome(window, pdf, NSAppearanceNameDarkAqua, NO);
        NSBitmapImageRep *rep = [pdf bitmapImageRepForCachingDisplayInRect:pdf.bounds];
        [pdf cacheDisplayInRect:pdf.bounds toBitmapImageRep:rep];
        NSColor *gutter = [[rep colorAtX:2 y:rep.pixelsHigh / 2] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        check(gutter.redComponent > 0.7, @"a light preview keeps a light area around the page in a dark window");

        TSApplyPreviewInversion(scroll, YES);
        CheckChrome(window, pdf, NSAppearanceNameDarkAqua, YES);

        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        TSApplyPreviewInversion(scroll, YES);
        CheckChrome(window, pdf, NSAppearanceNameAqua, YES);
        TSApplyPreviewInversion(scroll, NO);
        CheckChrome(window, pdf, NSAppearanceNameAqua, NO);

        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        ChromeDocumentPreview *magnified = LatePreview();
        TSApplyPreviewInversion(magnified.documentView.enclosingScrollView, YES);
        check(!magnified.documentView.enclosingScrollView.hasHorizontalScroller, @"magnifying starts without a horizontal scroller");
        magnified.scaleFactor = 4;
        CheckLateBar(magnified, YES, @"magnifying the document preview");
        ChromeDocumentPreview *narrowed = LatePreview();
        narrowed.scaleFactor = 1;
        TSApplyPreviewInversion(narrowed.documentView.enclosingScrollView, YES);
        check(!narrowed.documentView.enclosingScrollView.hasHorizontalScroller, @"narrowing starts without a horizontal scroller");
        [narrowed setFrameSize:NSMakeSize(120, 550)];
        CheckLateBar(narrowed, YES, @"narrowing the document preview");
        ChromeDocumentPreview *plain = LatePreview();
        TSApplyPreviewInversion(plain.documentView.enclosingScrollView, NO);
        plain.scaleFactor = 4;
        CheckLateBar(plain, NO, @"magnifying a light document preview");
        printf("PASS: %d preview window chrome checks\n", checks);
    }
    return 0;
}
'''
program = program.replace('HEADER', header).replace('VIEWMETHODS', view_text)
fragments = [('complete method: ' + item.split('\n', 1)[0], view_source, item) for item in view_methods]
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory(prefix='texshop-preview-chrome-') as temp:
    temp = Path(temp)
    (temp / 'test.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-I', str(root / 'Tests'), *include_args(root),
                    '-framework', 'Cocoa', '-framework', 'Quartz', str(temp / 'test.m'),
                    str(root / 'Sources/Preview/TSPreviewScrollerKeeper.m'), '-o', str(temp / 'test')], check=True)
    (temp / 'home/Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(temp / 'test')], capture_output=True, text=True, timeout=60,
                            env=dict(os.environ, HOME=str(temp / 'home'), CFFIXED_USER_HOME=str(temp / 'home')))
    if args.mutation:
        assert result.returncode == 1 and 'FAIL:' in result.stderr, result.stdout + result.stderr
        print('PASS: detected', args.mutation)
    elif result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    else:
        print(result.stdout, end='')
