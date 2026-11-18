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
parser.add_argument('--mutation', choices=['scroll-appearance', 'late-scroller', 'display-mode', 'late-page', 'late-direction'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
header = (root / 'Sources/Preview/TSPreviewAppearance.h').read_text()
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
view_methods = [method(view_source, signature) for signature in (
    '- (void)setScaleFactor:(CGFloat)scale', '- (void)setFrameSize:(NSSize)newSize',
    '- (void)setDisplayMode:(PDFDisplayMode)mode', '- (void)setDisplayDirection:(PDFDisplayDirection)direction',
    '- (void)keepHorizontalPositionDuring:(void (NS_NOESCAPE ^)(void))navigation',
    '- (BOOL)scrollingKeepsPage', '- (BOOL)isPageTurnFromScrolling:(SEL)selector',
    '- (void)goToNextPage:(id)sender',
    '- (NSMenu *)menuForEvent:(NSEvent *)theEvent',
    '- (MyPDFKitView *)previewPartForMenuEvent: (NSEvent *)theEvent',
    '- (PDFDestination *)internalLinkDestinationAtPoint: (NSPoint)viewPoint')]
fragments = [('complete method: ' + item.split('\n', 1)[0], view_source, item) for item in view_methods]
reapply = '    TSReapplyPreviewInversion(self.documentView.enclosingScrollView);\n'
def strip_reapply(index):
    assert view_methods[index].count(reapply) == 1, args.mutation
    view_methods[index] = view_methods[index].replace(reapply, '')
if args.mutation == 'scroll-appearance':
    old = '    scrollView.appearance = nil;\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '    scrollView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];\n', 1)
elif args.mutation == 'late-scroller':
    strip_reapply(0)
    strip_reapply(1)
elif args.mutation == 'display-mode':
    strip_reapply(2)
elif args.mutation == 'late-direction':
    strip_reapply(3)
elif args.mutation == 'late-page':
    strip_reapply(4)
view_text = '\n'.join(view_methods)

program = r'''
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "TestAppKitIsolation.h"
#import "TSContentZoom.h"
#import "TSPreviewHorizontalPosition.h"
#import "TSPreviewScrollerKeeper.h"
#import "TSScrollPageTurn.h"
@interface NSObject (ChromeDocumentMessages)
- (void)updatePreviewLayoutControls;
- (NSMenu *)getContextMenu;
@end
#define SUD NSUserDefaults.standardUserDefaults
#define NoScrollPageTurnKey @"NoScrollPageTurn"
#define NEW_PDF_FIT_TO_NONE 2
#define NEW_PDF_FIT_TO_CONTENT_WIDTH 6
#define PDF_SINGLE_PAGE_STYLE 1
#define PDF_TWO_PAGE_STYLE 2
#define PDF_MULTI_PAGE_STYLE 3
#define PDF_DOUBLE_MULTI_PAGE_STYLE 4
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
@interface MyPDFKitView : PDFView {
    BOOL _fittingContentWidth;
    NSInteger resizeOption;
    NSInteger pageStyle;
    NSPoint menuPoint;
}
@property (nonatomic, strong) id myDocument;
- (void)fitContentWidthKeepingTop:(TSContentTop)top;
@end
@implementation MyPDFKitView
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
static PDFDocument *PagesOfWidths(CGFloat first, CGFloat second) {
    PDFDocument *document = [PDFDocument new];
    CGFloat widths[2] = {first, second};
    for (int i = 0; i < 2; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(widths[i], 380)];
        [image lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, widths[i], 380));
        [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return document;
}
static MyPDFKitView *SpreadPreview(PDFDocument *document, PDFDisplayMode mode) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 550)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    window.toolbarStyle = NSWindowToolbarStyleExpanded;
    window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"TSPreviewChromeSpread"];
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    MyPDFKitView *pdf = [[MyPDFKitView alloc] initWithFrame:window.contentView.bounds];
    pdf.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    pdf.autoScales = NO;
    pdf.displayMode = mode;
    pdf.document = document;
    [window.contentView addSubview:pdf];
    [window layoutIfNeeded];
    [pdf layoutSubtreeIfNeeded];
    pdf.scaleFactor = 1;
    [pdf goToFirstPage:nil];
    return pdf;
}
static void ChooseTwoPages(PDFView *pdf) {
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSMakePoint(200, 240)
        modifierFlags:0 timestamp:0 windowNumber:pdf.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    NSMenu *menu = [pdf menuForEvent:event];
    NSMenuItem *item = nil;
    for (NSMenuItem *candidate in menu.itemArray)
        if ([candidate.title isEqualToString:@"Two Pages"]) item = candidate;
    check(item != nil && item.action == NSSelectorFromString(@"_setDoublePage:"), @"the context menu offers Two Pages");
    [NSApp sendAction:item.action to:item.target ?: pdf from:item];
}
static MyPDFKitView *LatePreview(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 750, 550)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    window.toolbarStyle = NSWindowToolbarStyleExpanded;
    window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"TSPreviewChromeLate"];
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    MyPDFKitView *pdf = [[MyPDFKitView alloc] initWithFrame:window.contentView.bounds];
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
        MyPDFKitView *magnified = LatePreview();
        TSApplyPreviewInversion(magnified.documentView.enclosingScrollView, YES);
        check(!magnified.documentView.enclosingScrollView.hasHorizontalScroller, @"magnifying starts without a horizontal scroller");
        magnified.scaleFactor = 4;
        CheckLateBar(magnified, YES, @"magnifying the document preview");
        MyPDFKitView *narrowed = LatePreview();
        narrowed.scaleFactor = 1;
        TSApplyPreviewInversion(narrowed.documentView.enclosingScrollView, YES);
        check(!narrowed.documentView.enclosingScrollView.hasHorizontalScroller, @"narrowing starts without a horizontal scroller");
        [narrowed setFrameSize:NSMakeSize(120, 550)];
        CheckLateBar(narrowed, YES, @"narrowing the document preview");
        MyPDFKitView *plain = LatePreview();
        TSApplyPreviewInversion(plain.documentView.enclosingScrollView, NO);
        plain.scaleFactor = 4;
        CheckLateBar(plain, NO, @"magnifying a light document preview");
        MyPDFKitView *twoUp = SpreadPreview(PagesOfWidths(410, 410), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(twoUp.documentView.enclosingScrollView, YES);
        NSScrollView *twoScroll = twoUp.documentView.enclosingScrollView;
        NSView *twoClip = twoScroll.contentView;
        NSView *twoGutter = nil;
        for (NSView *subview in twoScroll.subviews)
            if ([NSStringFromClass(subview.class) containsString:@"Background"]) twoGutter = subview;
        check(twoClip != nil && twoGutter != nil && !twoScroll.hasHorizontalScroller, @"Two Pages starts without a horizontal scroller");
        ChooseTwoPages(twoUp);
        BOOL sameGutter = NO;
        for (NSView *subview in twoUp.documentView.enclosingScrollView.subviews)
            if (subview == twoGutter) sameGutter = YES;
        check(twoUp.documentView.enclosingScrollView.contentView == twoClip && sameGutter, @"Two Pages keeps the clip view and the area around the pages");
        CheckLateBar(twoUp, YES, @"choosing Two Pages from the document context menu");
        MyPDFKitView *twoUpPlain = SpreadPreview(PagesOfWidths(410, 410), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(twoUpPlain.documentView.enclosingScrollView, NO);
        ChooseTwoPages(twoUpPlain);
        CheckLateBar(twoUpPlain, NO, @"choosing Two Pages on a light document preview");
        MyPDFKitView *turned = SpreadPreview(PagesOfWidths(410, 1100), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(turned.documentView.enclosingScrollView, YES);
        check(!turned.documentView.enclosingScrollView.hasHorizontalScroller, @"the next page starts without a horizontal scroller");
        [turned goToNextPage:nil];
        CheckLateBar(turned, YES, @"turning to a wider page");
        MyPDFKitView *across = SpreadPreview(PagesOfWidths(410, 410), kPDFDisplaySinglePageContinuous);
        TSApplyPreviewInversion(across.documentView.enclosingScrollView, YES);
        check(!across.documentView.enclosingScrollView.hasHorizontalScroller, @"a vertical row starts without a horizontal scroller");
        across.displayDirection = kPDFDisplayDirectionHorizontal;
        CheckLateBar(across, YES, @"laying the pages in a row");
        printf("PASS: %d preview window chrome checks\n", checks);
    }
    return 0;
}
'''
program = program.replace('HEADER', header).replace('VIEWMETHODS', view_text)
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
