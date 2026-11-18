#!/usr/bin/env python3
"""A link popup's edge and corners follow the preview's magnification (#14).

The page in a link popup grows and shrinks with the preview's magnification. Its black edge
and its rounded corners do as well: they are sized in page points. The edge is a little
under one page point, which looked heavy, and it stays at least one pixel wide on screen.
The page label keeps the size it has on screen at 100% and above, and it is never larger
than that 100% size, so a low magnification still shows it without covering the page. It
sits on the straight part of the frame: the page-point corners and the edge do not cut it.

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
    'label-in-page-points': ('    CGFloat fontSize = TSLinkPreviewLabelFontSize * scale;\n',
                             '    CGFloat fontSize = TSLinkPreviewLabelFontSize;\n'),
    'label-uncapped': ('    CGFloat scale = MIN(unit, 1);\n',
                       '    CGFloat scale = unit;\n'),
    'label-in-corner': ('    CGFloat inset = MAX(margin, TSLinkPreviewCornerRadius + edge);\n',
                        '    CGFloat inset = margin;\n'),
    'drops-short-label': ('        fontSize = next;\n',
                          '        return;\n'),
    'corner-on-screen': ('    CGFloat radius = TSLinkPreviewCornerRadius;\n',
                         '    CGFloat radius = TSLinkPreviewCornerRadius * [self unitsPerScreenPoint];\n'),
    'no-redraw': ('            [weakSelf setNeedsDisplay:YES];\n', ''),
    'keeps-old-preview': ('    if (_scaleObserver) [NSNotificationCenter.defaultCenter removeObserver:_scaleObserver];\n    _scaleObserver = nil;\n    _magnifiedView = preview;\n',
                          '    _magnifiedView = preview;\n'),
}
EXPECTED = {
    'edge-on-screen': 'the edge grows with the magnification',
    'no-pixel-floor': 'the edge stays at least one pixel wide',
    'label-in-page-points': 'the page label keeps its size on screen',
    'label-uncapped': 'the page label does not cover the page',
    'label-in-corner': 'the page label stays clear of the frame',
    'drops-short-label': 'the page label stays visible',
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
// Width of the gray page label, in pixels. The page around it is white. This is the capsule
// itself, not the gap out to the edge: that gap is the corner clearance and grows on screen.
static NSInteger labelWidth(NSBitmapImageRep *rep) {
    NSInteger best = 0, limit = MIN(rep.pixelsHigh, 160);
    for (NSInteger y = 0; y < limit; y++) {
        NSInteger span = 0, run = 0;
        for (NSInteger x = rep.pixelsWide / 3; x < rep.pixelsWide; x++) {
            NSColor *c = pixel(rep, x, y);
            BOOL gray = c.alphaComponent > 0.5 && luma(c) > 0.45 && luma(c) < 0.8;
            if (gray) { span++; run = MAX(run, span); }
            else span = 0;
        }
        if (run > best && run < rep.pixelsWide / 2) best = run;
    }
    return best;
}
// The gray capsule, and the light and dark pixels inside it. The outer four page points
// are left out: that is the black edge and its antialiasing, not the label. A label that
// sits in the corner falls in that band and is not counted. Dark pixels are the frame
// cutting the label; light pixels are the type.
typedef struct { NSInteger minX, minY, maxX, maxY, gray, white, dark; } LabelBox;
static LabelBox measureLabel(NSBitmapImageRep *rep, CGFloat pagePixels) {
    NSInteger w = rep.pixelsWide, h = rep.pixelsHigh;
    NSInteger band = MAX((NSInteger)ceil(pagePixels * 4), 1);
    LabelBox box = {w, h, -1, -1, 0, 0, 0};
    for (NSInteger y = band; y < h - band; y++)
        for (NSInteger x = MAX(w / 5, band); x < w - band; x++) {
            NSColor *c = pixel(rep, x, y);
            if (!(c.alphaComponent > 0.5 && luma(c) > 0.45 && luma(c) < 0.8)) continue;
            box.gray++;
            if (x < box.minX) box.minX = x;
            if (y < box.minY) box.minY = y;
            if (x > box.maxX) box.maxX = x;
            if (y > box.maxY) box.maxY = y;
        }
    if (box.maxX < 0) return box;
    for (NSInteger y = box.minY + 1; y < box.maxY; y++)
        for (NSInteger x = box.minX + 1; x < box.maxX; x++) {
            NSColor *c = pixel(rep, x, y);
            if (c.alphaComponent < 0.5) continue;
            CGFloat l = luma(c);
            if (l < 0.3) box.dark++;
            else if (l > 0.92) box.white++;
        }
    return box;
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

    CGFloat edges[4]; NSInteger labels[4]; NSInteger i = 0;
    for (NSNumber *magnification in @[@0.25, @1, @2, @3]) {
        view.scaleFactor = magnification.doubleValue;
        CGFloat unitsPerPoint = [popup unitsPerScreenPoint];
        check(fabs(unitsPerPoint * magnification.doubleValue - 1) < 0.01, "fixture: page points follow the magnification");
        CGFloat pixels = backing / unitsPerPoint;
        NSBitmapImageRep *rep = render(popup, pixels);
        edges[i] = edgeCoverage(rep) / pixels;
        labels[i] = labelWidth(rep);
        CGFloat corner = pixel(rep, (NSInteger)(1.2 * pixels), (NSInteger)(1.2 * pixels)).alphaComponent;
        if (magnification.doubleValue >= 1)
            check(corner < 0.1, "the corners grow with the magnification");
        if (magnification.doubleValue < 1)
            check(edgeCoverage(rep) > 0.85, "the edge stays at least one pixel wide");
        i++;
    }
    // In page points the edge is 0.75 wide at 100% and above, so it grows on screen.
    // The label keeps the same size in pixels, the size it has on screen (#14).
    check(labels[1] > 40, "the page label keeps its size on screen");
    for (NSInteger k = 1; k < 4; k++) {
        check(fabs(edges[k] - 0.75) < 0.15, "the edge grows with the magnification");
        check(labs(labels[k] - labels[1]) * 5 <= labels[1], "the page label keeps its size on screen");
    }

    // A usual popup is about 266.67 by 80 page points, and one whose link sits near the
    // bottom of the page is about 26.67 page points tall (TSLinkPreviewRects at 2/3 scale).
    CGFloat productWidth = 800.0 / 3.0;
    popup.frame = NSMakeRect(20, 20, productWidth, 80);
    for (NSNumber *magnification in @[@3, @4, @5]) {
        view.scaleFactor = magnification.doubleValue;
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        NSBitmapImageRep *rep = render(popup, pixels);
        LabelBox box = measureLabel(rep, pixels);
        check(box.gray > 20 && box.white > 10 && box.dark == 0, "the page label stays clear of the frame");
        check((rep.pixelsWide - 1 - box.maxX) / pixels > 5.5 && box.minY / pixels > 5.5,
              "the page label stays clear of the frame");
    }
    for (NSNumber *magnification in @[@0.2, @0.25, @0.3]) {
        view.scaleFactor = magnification.doubleValue;
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        NSBitmapImageRep *rep = render(popup, pixels);
        LabelBox box = measureLabel(rep, pixels);
        check(box.gray > 8 && box.white > 0, "the page label stays visible");
        check(box.maxY >= box.minY && (box.maxY - box.minY + 1) / pixels < 20,
              "the page label does not cover the page");
    }
    popup.frame = NSMakeRect(20, 20, productWidth, 80.0 / 3.0);
    view.scaleFactor = 0.5;
    {
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        NSBitmapImageRep *rep = render(popup, pixels);
        LabelBox box = measureLabel(rep, pixels);
        check(box.gray > 8 && box.white > 0, "the page label stays visible");
        check(box.maxY >= box.minY && (box.maxY - box.minY + 1) / pixels < 20,
              "the page label does not cover the page");
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
    printf("PASS: a link popup's edge and corners follow the magnification, its page label keeps its size on screen, and it draws itself again\n");
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
