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
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['scroll-appearance'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
header = (root / 'Sources/Preview/TSPreviewAppearance.h').read_text()
if args.mutation == 'scroll-appearance':
    old = '    scrollView.appearance = nil;\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '    scrollView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];\n', 1)

program = r'''
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "TestAppKitIsolation.h"
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
        printf("PASS: %d preview window chrome checks\n", checks);
    }
    return 0;
}
'''
program = program.replace('HEADER', header)
with tempfile.TemporaryDirectory(prefix='texshop-preview-chrome-') as temp:
    temp = Path(temp)
    (temp / 'test.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-I', str(root / 'Tests'), *include_args(root),
                    '-framework', 'Cocoa', '-framework', 'Quartz', str(temp / 'test.m'), '-o', str(temp / 'test')], check=True)
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
