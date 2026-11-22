#!/usr/bin/env python3
"""A link popup's edge and corners follow the preview's magnification (#14).

The page in a link popup grows and shrinks with the preview's magnification. Its black edge
and its rounded corners do as well: they are sized in page points. The edge is a little
under one page point, which looked heavy, and it stays at least one pixel wide on screen.
The page label keeps the size it has on screen at 100% and above, and it is never larger
than that 100% size, so a low magnification still shows it without covering the page. It
sits in the lower right corner, as far in as a three-point gap inside the black edge allows,
also along the rounded corner: the page-point corners and the edge do not cut it.

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

INSET = '            insetX = MIN(found, middleX);\n            inset = MIN(found, middleY);\n'
MUTATIONS = {
    'edge-on-screen': ('    CGFloat width = MAX(TSLinkPreviewEdgeWidth, [self unitsPerPixel]);\n',
                       '    CGFloat width = [self unitsPerScreenPoint];\n'),
    'no-pixel-floor': ('    CGFloat width = MAX(TSLinkPreviewEdgeWidth, [self unitsPerPixel]);\n',
                       '    CGFloat width = TSLinkPreviewEdgeWidth;\n'),
    'label-in-page-points': ('    CGFloat fontSize = TSLinkPreviewLabelFontSize * scale;\n',
                             '    CGFloat fontSize = TSLinkPreviewLabelFontSize;\n'),
    'label-uncapped': ('    CGFloat scale = MIN(unit, 1);\n',
                       '    CGFloat scale = unit;\n'),
    'label-in-corner': (INSET, '            insetX = inset = margin;\n'),
    'label-ignores-curve': ('    if (!(rx > 0) || !(ry > 0)) return least;\n', '    return least;\n'),
    'label-circle-corners': ('    CGFloat rx = MIN(line, (w - edge) / 2), ry = MIN(line, (h - edge) / 2);\n',
                             '    CGFloat rx = line, ry = line;\n'),
    'label-skips-endpoint': ('        NSInteger steps = (NSInteger)ceil((farthest - clear) / step);\n',
                             '        NSInteger steps = (NSInteger)floor((farthest - clear) / step + 0.5);\n'),
    'label-old-inset': (INSET, '            insetX = inset = MAX(margin, TSLinkPreviewCornerRadius + edge);\n'),
    'drops-short-label': ('        fontSize = next;\n',
                          '        return;\n'),
    'label-estimate-floor': ('        CGFloat next = fontSize * fit;\n'
                             '        if (!(next < fontSize * (CGFloat)0.99)) next = fontSize * (CGFloat)0.9;\n'
                             '        if (!(next > 0) || !(next < fontSize)) return;\n',
                             '        CGFloat next = fontSize * MIN(fit, (CGFloat)0.9);\n'
                             '        if (!(next < fontSize)) next = fontSize * (CGFloat)0.9;\n'
                             '        if (!(next > 1)) return;\n'),
    'label-ceil-page-points': ('        height = ceil(size.height / px) * px;\n'
                               '        CGFloat textWidth = ceil(size.width / px) * px;\n',
                               '        height = ceil(size.height);\n'
                               '        CGFloat textWidth = ceil(size.width);\n'),
    'label-no-screen-floor': ('        if (next < fontFloor) {\n'
                              '            if (!(fontSize > fontFloor)) return;\n'
                              '            next = fontFloor;\n'
                              '        }\n',
                              ''),
    'label-floor-page-points': ('    CGFloat fontFloor = MIN(fontSize, TSLinkPreviewLabelMinimumScreenSize * unit);\n',
                                '    CGFloat fontFloor = MIN(fontSize, TSLinkPreviewLabelMinimumScreenSize);\n'),
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
    'label-uncapped': ('the page label does not cover the page', 'the page label sits in the corner'),
    'label-in-corner': 'the page label stays clear of the frame',
    'label-ignores-curve': 'the page label stays clear of the frame',
    'label-old-inset': 'the page label sits in the corner',
    'label-skips-endpoint': 'the page label stays visible',
    'label-circle-corners': ('the page label stays visible', 'the page label keeps its size on screen', 'the page label sits in the corner'),
    'drops-short-label': 'the page label stays visible',
    'label-estimate-floor': 'the page label stays visible',
    'label-ceil-page-points': "the page label's capsule stays one size on screen",
    'label-no-screen-floor': 'the page label keeps the six-point floor',
    'label-floor-page-points': 'the page label keeps the six-point floor',
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
// The pixels per screen point the test gives the window, or 0 for its own.
static CGFloat backingOverride;
// The pixels per screen point the popup takes for its window; 0 keeps the window's own.
static CGFloat (*originalBacking)(id, SEL);
static CGFloat testBacking(NSWindow *self, SEL sel) {
    return backingOverride > 0 ? backingOverride : originalBacking(self, sel);
}
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
// The size of the popup drawn last, in page points. The bitmap is rounded up to whole pixels.
static NSSize rendered;
// The popup drawn as the screen shows it: `pixels` pixels per page point.
static NSBitmapImageRep *render(TSLinkPreviewView *popup, CGFloat pixels) {
    NSRect bounds = popup.bounds;
    rendered = bounds.size;
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
// How far, in page points, the middle of pixel (x, y) lies inside the black edge: from the
// straight part of the edge or, in a corner, from its curve. The edge is stroked along the
// rectangle half its width inside the popup, with six-point corners less half the width.
// AppKit limits each radius to half the side, so a popup lower than its corners has
// elliptical corners. The distance to the ellipse is found by trying points along it.
static CGFloat insideEdge(NSInteger x, NSInteger y, CGFloat pagePixels) {
    CGFloat edge = MAX(0.75, 1 / pagePixels), radius = 6;
    CGFloat w = rendered.width, h = rendered.height;
    CGFloat px = (x + 0.5) / pagePixels, py = (y + 0.5) / pagePixels;
    CGFloat qx = MIN(px, w - px), qy = MIN(py, h - py);
    CGFloat rx = MIN(radius - edge / 2, (w - edge) / 2), ry = MIN(radius - edge / 2, (h - edge) / 2);
    CGFloat cx = edge / 2 + rx, cy = edge / 2 + ry;
    if (qx < cx && qy < cy) {
        CGFloat least = CGFLOAT_MAX;
        for (NSInteger i = 0; i <= 2000; i++) {
            CGFloat t = M_PI_2 * i / 2000;
            least = MIN(least, hypot(cx - rx * cos(t) - qx, cy - ry * sin(t) - qy));
        }
        CGFloat ex = (cx - qx) / rx, ey = (cy - qy) / ry;
        return (ex * ex + ey * ey <= 1 ? least : -least) - edge / 2;
    }
    return MIN(qx, qy) - edge;
}
// The gray capsule, and the light and dark pixels inside it. The black edge and its
// antialiasing, out to one and a half pixels inside it, are left out: they are not the
// label. Dark pixels are the frame cutting the label; light pixels are the type.
// `clearance` is the least distance, in page points, from the capsule to the edge.
typedef struct { NSInteger minX, minY, maxX, maxY, gray, white, dark; CGFloat clearance; } LabelBox;
static LabelBox measureLabel(NSBitmapImageRep *rep, CGFloat pagePixels) {
    NSInteger w = rep.pixelsWide, h = rep.pixelsHigh;
    LabelBox box = {w, h, -1, -1, 0, 0, 0, CGFLOAT_MAX};
    for (NSInteger y = 0; y < h; y++)
        for (NSInteger x = w / 5; x < w; x++) {
            NSColor *c = pixel(rep, x, y);
            if (!(c.alphaComponent > 0.5 && luma(c) > 0.45 && luma(c) < 0.8)) continue;
            CGFloat inside = insideEdge(x, y, pagePixels);
            if (inside < 1.5 / pagePixels) continue;
            box.clearance = MIN(box.clearance, inside);
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
// The capsule in device pixels, and the light padding on its left and right.
typedef struct { CGFloat width, height, left, right; NSInteger gray, white; } Capsule;
static Capsule measureCapsule(NSBitmapImageRep *rep, CGFloat pagePixels) {
    LabelBox box = measureLabel(rep, pagePixels);
    Capsule capsule = {0, 0, 0, 0, box.gray, box.white};
    if (box.maxX < 0) return capsule;
    capsule.width = box.maxX - box.minX + 1;
    capsule.height = box.maxY - box.minY + 1;
    // The corners of the box are the page, outside the rounded capsule. The middle rows
    // run through the type, so the light pixels there are the glyphs.
    NSInteger mid = (box.minY + box.maxY) / 2;
    NSInteger minWhite = box.maxX, maxWhite = box.minX;
    for (NSInteger y = MAX(box.minY, mid - 1); y <= MIN(box.maxY, mid + 1); y++)
        for (NSInteger x = box.minX; x <= box.maxX; x++) {
            NSColor *sample = pixel(rep, x, y);
            if (!(sample.alphaComponent > 0.5 && luma(sample) > 0.92)) continue;
            if (x < minWhite) minWhite = x;
            if (x > maxWhite) maxWhite = x;
        }
    if (maxWhite >= minWhite) {
        capsule.left = minWhite - box.minX;
        capsule.right = box.maxX - maxWhite;
    }
    return capsule;
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
    // The capsule keeps three points on screen (one and a half at 50%, where three page
    // points are left) inside the edge, also along the rounded corner, and is no farther
    // in than that: the gap is the margin, give or take a pixel (#14).
    for (NSNumber *magnification in @[@0.5, @1, @2, @3, @4, @5]) {
        view.scaleFactor = magnification.doubleValue;
        CGFloat unit = [popup unitsPerScreenPoint];
        CGFloat pixels = backing / unit;
        NSBitmapImageRep *rep = render(popup, pixels);
        LabelBox box = measureLabel(rep, pixels);
        CGFloat margin = 3 * MIN(unit, 1), slack = 1 / pixels;
        printf("label %.0f%%: %.2f points on screen from the right edge and %.2f from the bottom, %.2f inside the black edge\n",
               magnification.doubleValue * 100, (rendered.width * pixels - 1 - box.maxX) / backing, box.minY / backing,
               box.clearance / unit);
        check(box.gray > 20 && box.white > 10 && box.dark == 0, "the page label stays clear of the frame");
        check(box.clearance >= margin - slack, "the page label stays clear of the frame");
        check(box.clearance <= margin + slack, "the page label sits in the corner");
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
    // At 50% the unshrunk label is already under six points on screen, so a tall popup
    // still shows it and a short one leaves it out instead of shrinking it further. With
    // the label in the corner, the popup of a link near the bottom of the page still has
    // room for it; one a third shorter again has not.
    view.scaleFactor = 0.5;
    for (NSNumber *height in @[@80, @(80.0 / 3.0)]) {
        popup.frame = NSMakeRect(20, 20, productWidth, height.doubleValue);
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        LabelBox box = measureLabel(render(popup, pixels), pixels);
        check(box.gray > 8 && box.white > 0, "the page label stays visible");
    }
    popup.frame = NSMakeRect(20, 20, productWidth, 80.0 / 3.0 * 2.0 / 3.0);
    {
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        LabelBox box = measureLabel(render(popup, pixels), pixels);
        check(box.gray == 0, "the page label keeps the six-point floor");
    }

    // The narrowest popup is 120 points wide on screen. A label that fits at six points
    // is drawn at least that large. One that does not fit at six points is left out.
    popup.pageLabel = @"Page 180";
    popup.frame = NSMakeRect(20, 20, 200, 50);
    view.scaleFactor = 1;
    CGFloat referenceHeight;
    {
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        LabelBox box = measureLabel(render(popup, pixels), pixels);
        referenceHeight = box.maxY - box.minY + 1;
        check(referenceHeight > 10, "fixture: the eleven-point label has a height");
    }
    popup.frame = NSMakeRect(20, 20, 120, 40);
    for (NSNumber *length in @[@24, @40, @80]) {
        NSMutableString *longLabel = [@"Page " mutableCopy];
        while ((NSInteger)longLabel.length < length.integerValue) [longLabel appendString:@"9"];
        popup.pageLabel = longLabel;
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        LabelBox box = measureLabel(render(popup, pixels), pixels);
        if (length.integerValue == 24) {
            check(box.gray > 8 && box.white > 0, "the page label stays visible");
            CGFloat screen = 11 * (box.maxY - box.minY + 1) / referenceHeight;
            printf("label 100%% length 24 is %.2f points on screen\n", screen);
            check(screen >= 6, "the page label stays at least six points on screen");
        } else {
            printf("label 100%% length %ld is %s\n", (long)length.integerValue, box.gray ? "drawn" : "left out");
            check(box.gray == 0, "the page label keeps the six-point floor");
        }
    }
    popup.pageLabel = @"Page 180";

    // The capsule is rounded to screen pixels, so 1000% and 2000% stay the size measured
    // at 100%. The frames are wide enough that the eleven-point label is not shrunk.
    popup.pageLabel = @"Page 180";
    popup.frame = NSMakeRect(20, 20, 160, 50);
    view.scaleFactor = 1;
    Capsule base;
    {
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        base = measureCapsule(render(popup, pixels), pixels);
        check(base.gray > 20 && base.white > 10, "the page label's capsule stays one size on screen");
    }
    for (NSNumber *magnification in @[@10, @20]) {
        view.scaleFactor = magnification.doubleValue;
        popup.frame = NSMakeRect(20, 20, 48, 28);
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        Capsule got = measureCapsule(render(popup, pixels), pixels);
        check(got.gray > 20 && got.white > 10, "the page label's capsule stays one size on screen");
        check(fabs(got.width - base.width) <= 2 && fabs(got.height - base.height) <= 2
              && fabs(got.left - base.left) <= 3 && fabs(got.right - base.right) <= 3,
              "the page label's capsule stays one size on screen");
    }

    // At 500% the short popup is 46 by 20 page points. Fifty characters still fit at six
    // points on screen. Fifty-two, fifty-six and sixty fit only below that, so they are
    // left out. A twelve-character label at 1000% in a 20-point-wide popup fits
    // between six and ten points; guessing the next size must not skip it.
    popup.frame = NSMakeRect(20, 20, 46, 20);
    view.scaleFactor = 5;
    for (NSNumber *length in @[@50, @52, @56, @60]) {
        NSMutableString *longLabel = [@"Page " mutableCopy];
        while ((NSInteger)longLabel.length < length.integerValue) [longLabel appendString:@"9"];
        popup.pageLabel = longLabel;
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        LabelBox box = measureLabel(render(popup, pixels), pixels);
        if (length.integerValue == 50) {
            check(box.gray > 8 && box.white > 0, "the page label stays visible");
            CGFloat screen = 11 * (box.maxY - box.minY + 1) / referenceHeight;
            printf("label 500%% length 50 is %.2f points on screen\n", screen);
            check(screen >= 6, "the page label stays at least six points on screen");
        } else {
            printf("label 500%% length %ld is %s\n", (long)length.integerValue, box.gray ? "drawn" : "left out");
            check(box.gray == 0, "the page label keeps the six-point floor");
        }
    }
    popup.frame = NSMakeRect(20, 20, 20, 20);
    view.scaleFactor = 10;
    {
        NSMutableString *longLabel = [@"Page " mutableCopy];
        while (longLabel.length < 12) [longLabel appendString:@"9"];
        popup.pageLabel = longLabel;
        CGFloat pixels = backing / [popup unitsPerScreenPoint];
        LabelBox box = measureLabel(render(popup, pixels), pixels);
        check(box.gray > 8 && box.white > 0, "the page label stays visible");
        CGFloat screen = 11 * (box.maxY - box.minY + 1) / referenceHeight;
        printf("label 1000%% length 12 is %.2f points on screen\n", screen);
        check(screen >= 6, "the page label stays at least six points on screen");
    }
    // A pinned popup dragged to 250 by a few dozen points on screen at 800% to 2000% is lower
    // than its corners, which are then elliptical. The label goes by the corners as drawn:
    // eleven points where they leave room, smaller where they leave less, and left out where
    // even six points do not fit, at one and two pixels per point (#14).
    Method backingMethod = class_getInstanceMethod(NSWindow.class, @selector(backingScaleFactor));
    originalBacking = (void *)method_setImplementation(backingMethod, (IMP)testBacking);
    popup.pageLabel = @"Page 2";
    for (NSNumber *density in @[@1, @2]) {
        backingOverride = density.doubleValue;
        view.scaleFactor = 1;
        popup.frame = NSMakeRect(20, 20, 200, 50);
        CGFloat reference;
        {
            CGFloat pixels = backingOverride / [popup unitsPerScreenPoint];
            LabelBox box = measureLabel(render(popup, pixels), pixels);
            reference = box.maxY - box.minY + 1;
            check(box.gray > 8 && reference > 5, "fixture: the eleven-point label has a height");
        }
        // Heights on screen: the label fits at eleven points, fits smaller, does not fit.
        NSDictionary<NSNumber *, NSArray<NSNumber *> *> *cases = @{
            @8: @[@48, @28, @22], @10: @[@48, @31, @26], @20: @[@56, @48, @40]};
        for (NSNumber *magnification in @[@8, @10, @20]) {
            NSArray<NSNumber *> *heights = cases[magnification];
            for (NSUInteger kind = 0; kind < 3; kind++) {
                CGFloat mag = magnification.doubleValue;
                view.scaleFactor = mag;
                popup.frame = NSMakeRect(20, 20, 250 / mag, heights[kind].doubleValue / mag);
                CGFloat unit = [popup unitsPerScreenPoint];
                CGFloat pixels = backingOverride / unit;
                LabelBox box = measureLabel(render(popup, pixels), pixels);
                CGFloat screen = box.gray ? 11 * (box.maxY - box.minY + 1) / reference : 0;
                printf("label %.0f%% at %.0fx in 250 by %.0f points: %s, %.2f points on screen, %.2f inside the black edge\n",
                       mag * 100, backingOverride, heights[kind].doubleValue, box.gray ? "drawn" : "left out", screen,
                       box.gray ? box.clearance / unit : 0.0);
                if (kind == 2) {
                    check(box.gray == 0, "the page label keeps the six-point floor");
                    continue;
                }
                check(box.gray > 8 && box.white > 0, "the page label stays visible");
                check(box.dark == 0 && box.clearance >= 3 * unit - 1 / pixels, "the page label stays clear of the frame");
                check(box.clearance <= 3 * unit + 1 / pixels, "the page label sits in the corner");
                if (kind == 0) check(screen > 10, "the page label keeps its size on screen");
                else check(screen >= 6 && screen < 10, "the page label stays at least six points on screen");
            }
        }
    }
    // Resizing a pinned popup point by point at 2000%, 45 points high, and one at 1900%,
    // 132 by 43: the place found is at the end of the search, where the room is largest.
    // However little is left for the last step, it is tried (#14).
    for (NSNumber *density in @[@1, @2]) {
        backingOverride = density.doubleValue;
        NSArray *sizes = @[@[@20, @128, @45, @"Page 127"], @[@20, @129, @45, @"Page 127"], @[@20, @130, @45, @"Page 127"],
                           @[@20, @131, @45, @"Page 127"], @[@20, @132, @45, @"Page 127"], @[@19, @132, @43, @"Page 2"]];
        for (NSArray *size in sizes) {
            CGFloat mag = [size[0] doubleValue];
            view.scaleFactor = mag;
            popup.pageLabel = size[3];
            popup.frame = NSMakeRect(20, 20, [size[1] doubleValue] / mag, [size[2] doubleValue] / mag);
            CGFloat unit = [popup unitsPerScreenPoint];
            CGFloat pixels = backingOverride / unit;
            LabelBox box = measureLabel(render(popup, pixels), pixels);
            printf("label %.0f%% at %.0fx in %.0f by %.0f points: %s, %.2f inside the black edge\n", mag * 100,
                   backingOverride, [size[1] doubleValue], [size[2] doubleValue], box.gray ? "drawn" : "left out",
                   box.gray ? box.clearance / unit : 0.0);
            check(box.gray > 8 && box.white > 0, "the page label stays visible");
            check(box.dark == 0 && box.clearance >= 3 * unit - 1 / pixels, "the page label stays clear of the frame");
            check(box.clearance <= 3 * unit + 1 / pixels, "the page label sits in the corner");
        }
    }
    backingOverride = 0;
    method_setImplementation(backingMethod, (IMP)originalBacking);
    popup.pageLabel = @"Page 180";

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
        expected = EXPECTED[args.mutation]
        if isinstance(expected, str): expected = (expected,)
        assert result.returncode == 1 and any(message in result.stderr for message in expected), (result.returncode, result.stderr)
        print('PASS: detected mutation ' + args.mutation)
    else:
        if result.returncode:
            print(result.stderr)
        result.check_returncode()
