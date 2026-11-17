#!/usr/bin/env python3
"""A link popup's edge, page label and corners follow the preview's magnification (#14).

The page in a link popup grows and shrinks with the preview's magnification. Its black edge,
its page label and its rounded corners now do as well: they are sized in page points, so a
popup made at one magnification looks the same as one made at another. The edge stays at
least one pixel wide on screen.

AppKit magnifies what a view inside the preview drew before and does not draw it again when
the magnification changes, so a popup made at a small magnification was blurred and its edge
and label were sized for the earlier magnification. The popup now draws itself again when the
magnification of the preview it is in changes, also after it has moved to another preview.

The popup is drawn into bitmaps at the pixels per page point the screen would have, without
showing any window.
"""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile
from source_tree import include_args

MUTATIONS = {
    'edge-on-screen': ('    CGFloat width = MAX(TSLinkPreviewEdgeWidth, [self unitsPerPixel]);\n',
                       '    CGFloat width = [self unitsPerScreenPoint];\n'),
    'no-pixel-floor': ('    CGFloat width = MAX(TSLinkPreviewEdgeWidth, [self unitsPerPixel]);\n',
                       '    CGFloat width = TSLinkPreviewEdgeWidth;\n'),
    'label-on-screen': ('[NSFont boldSystemFontOfSize:TSLinkPreviewLabelFontSize]',
                        '[NSFont boldSystemFontOfSize:TSLinkPreviewLabelFontSize * [self unitsPerScreenPoint]]'),
    'corner-on-screen': ('    CGFloat radius = TSLinkPreviewCornerRadius;\n',
                         '    CGFloat radius = TSLinkPreviewCornerRadius * [self unitsPerScreenPoint];\n'),
    'no-redraw': ('            [weakSelf setNeedsDisplay:YES];\n', ''),
    'keeps-old-preview': ('    if (_scaleObserver) [NSNotificationCenter.defaultCenter removeObserver:_scaleObserver];\n    _scaleObserver = nil;\n    _magnifiedView = preview;\n',
                          '    _magnifiedView = preview;\n'),
}
EXPECTED = {
    'edge-on-screen': 'the edge grows with the magnification',
    'no-pixel-floor': 'the edge stays at least one pixel wide',
    'label-on-screen': 'the page label grows with the magnification',
    'corner-on-screen': 'the corners grow with the magnification',
    'no-redraw': 'the popup draws itself again when the magnification changes',
    'keeps-old-preview': 'a moved popup follows only the preview it is in',
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
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
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSLinkPreviewGeometry.h"
#import "TSLinkPreviewView.h"
static void check(BOOL ok, const char *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
// A window that is not shown keeps no record of what needs drawing, so the requests to draw
// the popup again are counted instead.
static NSInteger redraws;
static void (*originalSetNeedsDisplay)(id, SEL, BOOL);
static void countingSetNeedsDisplay(NSView *self, SEL sel, BOOL flag) {
    if (flag && [self isKindOfClass:[TSLinkPreviewView class]]) redraws++;
    originalSetNeedsDisplay(self, sel, flag);
}
@interface TSLinkPreviewView (Probe)
- (CGFloat)unitsPerScreenPoint;
@end
static NSWindow *window(void) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700) styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    return w;
}
static PDFView *preview(NSWindow *w, PDFDocument *document) {
    PDFView *view = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
    w.contentView = view;
    view.document = document; view.autoScales = NO; view.scaleFactor = 1;
    return view;
}
// The popup drawn as the screen shows it: `pixels` pixels per page point.
static NSBitmapImageRep *render(TSLinkPreviewView *popup, CGFloat pixels) {
    NSRect bounds = popup.bounds;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:(NSInteger)ceil(NSWidth(bounds) * pixels) pixelsHigh:(NSInteger)ceil(NSHeight(bounds) * pixels)
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    NSAffineTransform *scale = [NSAffineTransform transform]; [scale scaleBy:pixels]; [scale concat];
    [popup drawRect:bounds];
    [NSGraphicsContext.currentContext flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}
// Pixel (x, y) with y from the bottom.
static NSColor *pixel(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    return [[rep colorAtX:x y:rep.pixelsHigh - 1 - y] colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
}
static CGFloat luma(NSColor *c) { return (c.redComponent + c.greenComponent + c.blueComponent) / 3; }
// How many pixels of black the edge covers on the left, along the middle row.
static CGFloat edgeCoverage(NSBitmapImageRep *rep) {
    NSInteger y = rep.pixelsHigh / 2; CGFloat covered = 0;
    for (NSInteger x = 0; x < MIN(rep.pixelsWide, 40); x++) {
        NSColor *c = pixel(rep, x, y);
        if (c.alphaComponent > 0.5 && luma(c) > 0.97) break;
        covered += c.alphaComponent * (1 - luma(c));
    }
    return covered;
}
// The width of the gray page label, in pixels, along a row through its middle: from its
// leftmost gray pixel to the right side. The page around it is white.
static NSInteger labelWidth(NSBitmapImageRep *rep, CGFloat pixels) {
    NSInteger y = (NSInteger)round(9 * pixels), left = -1;
    for (NSInteger x = (NSInteger)(10 * pixels); x < rep.pixelsWide; x++) {
        NSColor *c = pixel(rep, x, y);
        if (c.alphaComponent > 0.5 && luma(c) > 0.45 && luma(c) < 0.8) { left = x; break; }
    }
    return left < 0 ? 0 : rep.pixelsWide - left;
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    NSImage *white = [[NSImage alloc] initWithSize:NSMakeSize(612, 792)];
    [white lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, 612, 792)); [white unlockFocus];
    PDFPage *page = [[PDFPage alloc] initWithImage:white];
    PDFDocument *document = [PDFDocument new]; [document insertPage:page atIndex:0];
    NSSize size; CGAffineTransform transform;
    check(TSLinkPreviewPageGeometry(page, &size, &transform), "fixture: page geometry");
    NSWindow *w = window();
    PDFView *view = preview(w, document);
    CGFloat backing = w.backingScaleFactor > 0 ? w.backingScaleFactor : 1;
    TSLinkPreviewView *popup = [[TSLinkPreviewView alloc] initWithFrame:NSMakeRect(20, 20, 400, 200)
        image:TSLinkPreviewImage(page, size) source:NSMakeRect(0, 0, 400, 200) pageSize:size page:page transform:transform];
    popup.pageLabel = @"Page 180";
    [view.documentView addSubview:popup];

    CGFloat edges[4], labels[4]; NSInteger i = 0;
    for (NSNumber *magnification in @[@0.25, @1, @2, @3]) {
        view.scaleFactor = magnification.doubleValue;
        CGFloat unitsPerPoint = [popup unitsPerScreenPoint];
        check(fabs(unitsPerPoint * magnification.doubleValue - 1) < 0.01, "fixture: page points follow the magnification");
        CGFloat pixels = backing / unitsPerPoint;
        NSBitmapImageRep *rep = render(popup, pixels);
        edges[i] = edgeCoverage(rep) / pixels;
        labels[i] = labelWidth(rep, pixels) / pixels;
        CGFloat corner = pixel(rep, (NSInteger)(1.2 * pixels), (NSInteger)(1.2 * pixels)).alphaComponent;
        if (magnification.doubleValue >= 1)
            check(corner < 0.1, "the corners grow with the magnification");
        if (magnification.doubleValue < 1)
            check(edgeCoverage(rep) > 0.85, "the edge stays at least one pixel wide");
        i++;
    }
    // In page points the edge is 1 wide at 100% and above, and the label keeps its size.
    for (NSInteger k = 1; k < 4; k++) {
        check(fabs(edges[k] - 1) < 0.5, "the edge grows with the magnification");
        check(fabs(labels[k] - labels[1]) < 2 && labels[1] > 30, "the page label grows with the magnification");
    }

    Method setNeedsDisplay = class_getInstanceMethod(NSView.class, @selector(setNeedsDisplay:));
    originalSetNeedsDisplay = (void *)method_setImplementation(setNeedsDisplay, (IMP)countingSetNeedsDisplay);
    // Drawn, then magnified: the popup has to be drawn again.
    view.scaleFactor = 1; redraws = 0;
    view.scaleFactor = 2;
    check(redraws > 0, "the popup draws itself again when the magnification changes");

    // A popup moved to the other part of a split preview follows that part only.
    NSWindow *otherWindow = window();
    PDFView *other = preview(otherWindow, document);
    [popup removeFromSuperview];
    [other.documentView addSubview:popup];
    redraws = 0; view.scaleFactor = 3;
    check(redraws == 0, "a moved popup follows only the preview it is in");
    other.scaleFactor = 2;
    check(redraws > 0, "the popup draws itself again when the magnification changes");
    [popup removeFromSuperview];
    redraws = 0; other.scaleFactor = 1; view.scaleFactor = 1;
    check(redraws == 0, "a moved popup follows only the preview it is in");
    method_setImplementation(setNeedsDisplay, (IMP)originalSetNeedsDisplay);
    printf("PASS: a link popup's edge, page label and corners follow the magnification and it draws itself again\n");
    return 0;
}}
'''
with tempfile.TemporaryDirectory(prefix='texshop-link-magnification-') as directory:
    temporary = Path(directory)
    (temporary / 'probe.m').write_text(program)
    (temporary / 'TSLinkPreviewView.m').write_text(preview_source)
    exe = temporary / 'probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    *include_args(root), '-I' + str(root / 'Tests'), str(temporary / 'probe.m'),
                    str(temporary / 'TSLinkPreviewView.m'),
                    str(root / 'Sources/Windows/TSDocumentWindowGlass.m'), '-o', str(exe)], check=True)
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
