#!/usr/bin/env python3
"""A pinned link popup stays at its place on its page (#56).

A pinned popup lies on a page of the preview, as the text there does. Changing the
magnification used to move it into view, away from its place, even onto another page; it now
stays at its place, growing and shrinking with the page, also when that leaves it out of view.
PDFKit keeps the place of a view in its document view on the pages at every magnification, in
every display format; this is checked here too, since the popup relies on it.

A new display format puts the pages elsewhere in the document view. The popup remembers its
place on the page under its upper left corner before the change and goes back to it after, in
every display format that shows that page; when the page is no longer shown, as in Single Page
display showing another page, it stays where it is.

A real PDFView in a window that is never shown, with pages of different sizes.
"""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile
from source_tree import include_args

MUTATIONS = {
    'no-return': ('    if (!NSEqualRects(frame, self.frame)) {\n        self.frame = frame;\n',
                  '    if (NO) {\n        self.frame = frame;\n'),
    'page-under-center': ('    NSPoint corner = NSMakePoint(NSMinX(frame), preview.isFlipped ? NSMinY(frame) : NSMaxY(frame));\n',
                          '    NSPoint corner = NSMakePoint(NSMidX(frame), NSMidY(frame));\n'),
    'page-under-lower-corner': ('    NSPoint corner = NSMakePoint(NSMinX(frame), preview.isFlipped ? NSMinY(frame) : NSMaxY(frame));\n',
                                '    NSPoint corner = NSMakePoint(NSMinX(frame), preview.isFlipped ? NSMaxY(frame) : NSMinY(frame));\n'),
    'hidden-page-placed': ('        && ![preview.visiblePages containsObject:page]) return NO;\n', ') {}\n'),
    'stale-place': ('    PDFPage *page = _placePage;\n    _placePage = nil;\n', '    PDFPage *page = _placePage;\n'),
}
EXPECTED = {
    'no-return': 'goes back to its place on its page',
    'page-under-center': 'the page under its upper left corner',
    'page-under-lower-corner': 'the page under its upper left corner',
    'hidden-page-placed': 'stays where it is when its page is not shown',
    'stale-place': 'a place is used once',
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--binary-out', help='only build the probe, for arm64 and macOS 14, to this path (to run it on other macOS versions)')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
preview_source = (root / 'Sources/Preview/TSLinkPreviewView.m').read_text()
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert preview_source.count(old) == 1, args.mutation
    preview_source = preview_source.replace(old, new)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"
#import "TSLinkPreviewGeometry.h"
#import "TSLinkPreviewView.h"
static void check(BOOL ok, const char *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static PDFPage *blankPage(NSSize size) {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, size.width, size.height)); [image unlockFocus];
    return [[PDFPage alloc] initWithImage:image];
}
static const char *modeName(PDFDisplayMode mode) {
    switch (mode) {
        case kPDFDisplaySinglePage: return "Single Page";
        case kPDFDisplaySinglePageContinuous: return "Multi-Page";
        case kPDFDisplayTwoUp: return "Double Page";
        default: return "Double Multi-Page";
    }
}
static BOOL near(NSRect a, NSRect b, CGFloat tolerance) {
    return fabs(NSMinX(a) - NSMinX(b)) < tolerance && fabs(NSMinY(a) - NSMinY(b)) < tolerance &&
           fabs(NSWidth(a) - NSWidth(b)) < tolerance && fabs(NSHeight(a) - NSHeight(b)) < tolerance;
}
// The popup's frame in the space of `page`.
static NSRect placeOn(PDFView *view, TSLinkPreviewView *popup, PDFPage *page) {
    return [view convertRect:[view convertRect:popup.frame fromView:popup.superview] toPage:page];
}
// Puts the popup at `rect` in the space of `page`.
static void put(PDFView *view, TSLinkPreviewView *popup, PDFPage *page, NSRect rect) {
    popup.frame = [view.documentView convertRect:[view convertRect:rect fromPage:page] fromView:view];
}
static void layout(PDFView *view, PDFDisplayMode mode, PDFPage *page) {
    view.displayMode = mode;
    [view layoutDocumentView];
    [view goToPage:page];
    [view layoutDocumentView];
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    PDFDocument *document = [PDFDocument new];
    // Pages of different sizes, so that the display formats put them in different places.
    NSSize sizes[] = {{612, 792}, {612, 792}, {792, 612}, {500, 700}, {612, 792}, {612, 792}, {420, 595}, {612, 792}};
    for (NSUInteger i = 0; i < sizeof sizes / sizeof sizes[0]; i++) [document insertPage:blankPage(sizes[i]) atIndex:i];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    PDFView *view = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
    window.contentView = view;
    view.document = document;
    view.autoScales = NO; view.scaleFactor = 1;
    PDFPage *second = [document pageAtIndex:1], *third = [document pageAtIndex:2], *sixth = [document pageAtIndex:5];
    NSSize size; CGAffineTransform transform;
    check(TSLinkPreviewPageGeometry(second, &size, &transform), "fixture: page geometry");
    TSLinkPreviewView *popup = [[TSLinkPreviewView alloc] initWithFrame:NSMakeRect(0, 0, 300, 90)
        image:TSLinkPreviewImage(second, size) source:NSMakeRect(0, 0, 450, 135) pageSize:size page:second transform:transform];
    popup.pinned = YES;
    NSRect place = NSMakeRect(120, 380, 300, 90);
    PDFDisplayMode modes[] = {kPDFDisplaySinglePageContinuous, kPDFDisplayTwoUpContinuous, kPDFDisplaySinglePage, kPDFDisplayTwoUp};

    // Magnification: the popup keeps its place on its page, in every display format, also
    // where it is out of view.
    for (int m = 0; m < 4; m++) {
        layout(view, modes[m], second);
        view.scaleFactor = 1;
        [popup removeFromSuperview];
        [view.documentView addSubview:popup];
        put(view, popup, second, place);
        check(near(placeOn(view, popup, second), place, 0.01), "fixture: the popup is put on its page");
        for (NSNumber *scale in @[@0.5, @1.1, @2.42, @3.52, @0.25]) {
            view.scaleFactor = scale.doubleValue;
            [view layoutDocumentView];
            if (!near(placeOn(view, popup, second), place, 0.5)) {
                fprintf(stderr, "%s at %.0f%%: %s\n", modeName(modes[m]), 100 * scale.doubleValue,
                        NSStringFromRect(placeOn(view, popup, second)).UTF8String);
                check(NO, "PDFKit keeps the place of a view on its page at every magnification");
            }
        }
        view.autoScales = YES; [view layoutDocumentView];
        check(near(placeOn(view, popup, second), place, 0.5), "PDFKit keeps the place of a view on its page when it fits the page");
        view.autoScales = NO; view.scaleFactor = 1;
    }

    // Display formats: from each one to each other one, the popup goes back to its place.
    for (int from = 0; from < 4; from++)
        for (int to = 0; to < 4; to++) {
            if (from == to) continue;
            layout(view, modes[from], second);
            [popup removeFromSuperview];
            [view.documentView addSubview:popup];
            put(view, popup, second, place);
            [popup rememberPlaceOnPage];
            layout(view, modes[to], second);
            check(popup.superview == view.documentView, "fixture: the popup stays in the document view");
            BOOL returned = [popup returnToPlaceOnPage];
            if (!returned || !near(placeOn(view, popup, second), place, 0.5)) {
                fprintf(stderr, "%s to %s: %d %s\n", modeName(modes[from]), modeName(modes[to]), returned,
                        NSStringFromRect(placeOn(view, popup, second)).UTF8String);
                check(NO, "a pinned popup goes back to its place on its page after the display format changes");
            }
        }

    // A popup across the gap between two pages belongs to the page under its upper left
    // corner: in Double Multi-Page display the next page is beside it, not below it.
    layout(view, kPDFDisplaySinglePageContinuous, second);
    [popup removeFromSuperview];
    [view.documentView addSubview:popup];
    NSRect across = NSMakeRect(150, -60, 300, 90);
    put(view, popup, second, across);
    check([view pageForPoint:[view convertPoint:NSMakePoint(NSMidX(popup.frame), NSMidY(popup.frame)) fromView:view.documentView]
                     nearest:YES] == third, "fixture: the popup's middle is on the next page");
    [popup rememberPlaceOnPage];
    layout(view, kPDFDisplayTwoUpContinuous, second);
    check([popup returnToPlaceOnPage] && near(placeOn(view, popup, second), across, 0.5),
          "a popup across two pages stays with the page under its upper left corner");

    // A page that is no longer shown: the popup stays where it is.
    layout(view, kPDFDisplaySinglePageContinuous, second);
    put(view, popup, second, place);
    [popup rememberPlaceOnPage];
    layout(view, kPDFDisplaySinglePage, sixth);
    check(![view.visiblePages containsObject:second], "fixture: the popup's page is not shown");
    NSRect before = popup.frame;
    check(![popup returnToPlaceOnPage] && NSEqualRects(popup.frame, before),
          "a pinned popup stays where it is when its page is not shown");

    // A place is used once: a later return without remembering again changes nothing.
    layout(view, kPDFDisplaySinglePageContinuous, second);
    put(view, popup, second, place);
    [popup rememberPlaceOnPage];
    check([popup returnToPlaceOnPage], "the popup goes back to its place on its page");
    put(view, popup, second, NSOffsetRect(place, 40, 40));
    before = popup.frame;
    check(![popup returnToPlaceOnPage] && NSEqualRects(popup.frame, before), "a place is used once");

    // A popup that is in no preview remembers nothing.
    [popup removeFromSuperview];
    [popup rememberPlaceOnPage];
    check(![popup returnToPlaceOnPage], "a popup in no preview has no place");
    printf("PASS: a pinned popup stays at its place on its page when the magnification changes (%s document view) "
           "and goes back to it after the display format changes\n", view.documentView.isFlipped ? "flipped" : "unflipped");
    return 0;
}}
'''
with tempfile.TemporaryDirectory(prefix='texshop-popup-on-page-') as directory:
    temporary = Path(directory)
    (temporary / 'probe.m').write_text(program)
    (temporary / 'TSLinkPreviewView.m').write_text(preview_source)
    exe = Path(args.binary_out).resolve() if args.binary_out else temporary / 'probe'
    target = ['-arch', 'arm64', '-mmacosx-version-min=14.0'] if args.binary_out else []
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', *target, '-framework', 'Cocoa', '-framework', 'PDFKit',
                    *include_args(root), '-I' + str(root / 'Tests'), str(temporary / 'probe.m'),
                    str(temporary / 'TSLinkPreviewView.m'),
                    str(root / 'Sources/Windows/TSDocumentWindowGlass.m'), '-o', str(exe)], check=True)
    if args.binary_out:
        print(f'built {exe}')
        raise SystemExit(0)
    home = temporary / 'home'
    (home / 'Library/Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
    result = subprocess.run([str(exe)], env=env, capture_output=True, text=True, timeout=60)
    print(result.stdout, end='')
    if args.mutation:
        assert result.returncode == 1 and EXPECTED[args.mutation] in result.stderr, (result.returncode, result.stderr)
        print('PASS: detected mutation ' + args.mutation)
    else:
        if result.returncode:
            print(result.stderr)
        result.check_returncode()
