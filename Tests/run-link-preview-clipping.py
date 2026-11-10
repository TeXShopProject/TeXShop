#!/usr/bin/env python3
"""A link popup draws only inside its frame (#21).

The popup's image draws the whole linked page, and since macOS 14 a view may
draw outside its bounds. Issue #21 showed parts of the linked page around the
popup while the preview scrolled; the popup now clips to its frame so that
nothing outside it can be drawn. This checks that
it does, and that the page image is drawn with a clip no larger than the popup,
by drawing a popup of an all-black page into a larger transparent bitmap with a
dirty rectangle that extends past the popup, without showing any window.
"""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['no-clip', 'no-clips-to-bounds'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
preview_source = (root / 'Sources/Preview/TSLinkPreviewView.m').read_text()
mutations = {
    'no-clip': ('    NSRectClip(bounds);\n', ''),
    'no-clips-to-bounds': ('        self.clipsToBounds = YES;\n', ''),
}
if args.mutation:
    old, new = mutations[args.mutation]
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
// The clip in effect, in the popup's coordinates, when the page image is drawn.
static NSRect imageClip;
// -drawInRect:fromRect:operation:fraction:respectFlipped:hints: returns void.
static void (*originalDraw)(id, SEL, NSRect, NSRect, NSCompositingOperation, CGFloat, BOOL, NSDictionary *);
static void recordingDraw(NSImage *self, SEL sel, NSRect rect, NSRect from, NSCompositingOperation op, CGFloat fraction,
                          BOOL flipped, NSDictionary *hints) {
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    imageClip = NSRectFromCGRect(CGContextGetClipBoundingBox(context));
    originalDraw(self, sel, rect, from, op, fraction, flipped, hints);
}
static CGFloat alphaAt(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    // Bitmap rows run from the top; y is measured from the bottom here.
    return [rep colorAtX:x y:rep.pixelsHigh - 1 - y].alphaComponent;
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    NSImage *black = [[NSImage alloc] initWithSize:NSMakeSize(600, 800)];
    [black lockFocus]; [NSColor.blackColor setFill]; NSRectFill(NSMakeRect(0, 0, 600, 800)); [black unlockFocus];
    PDFPage *page = [[PDFPage alloc] initWithImage:black];
    NSSize size; CGAffineTransform transform;
    check(TSLinkPreviewPageGeometry(page, &size, &transform), "page geometry");
    NSImage *image = TSLinkPreviewImage(page, size);
    // The popup shows a small part from the middle of the page at twice its size.
    NSRect source = NSMakeRect(size.width / 2 - 50, size.height / 2 - 50, 100, 100);
    TSLinkPreviewView *preview = [[TSLinkPreviewView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200) image:image
        source:source pageSize:size page:page transform:transform];
    check(preview.clipsToBounds, "the popup clips its drawing to its frame");

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:400 pixelsHigh:400
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    NSAffineTransform *offset = [NSAffineTransform transform];
    [offset translateXBy:100 yBy:100]; [offset concat];
    Method draw = class_getInstanceMethod(NSImage.class, @selector(drawInRect:fromRect:operation:fraction:respectFlipped:hints:));
    char returnType[8] = {0};
    method_getReturnType(draw, returnType, sizeof returnType);
    check(strcmp(returnType, @encode(void)) == 0, "the replaced drawing method returns void");
    originalDraw = (void *)method_setImplementation(draw, (IMP)recordingDraw);
    // A redraw of more than the popup, as when the preview around it scrolls.
    [preview drawRect:NSMakeRect(-100, -100, 400, 400)];
    method_setImplementation(draw, (IMP)originalDraw);
    check(NSContainsRect(NSInsetRect(preview.bounds, -0.5, -0.5), imageClip) && !NSIsEmptyRect(imageClip),
          "the page image is drawn clipped to the popup");
    [context flushGraphics];
    [NSGraphicsContext restoreGraphicsState];

    check(alphaAt(rep, 200, 200) > 0.9, "the popup shows its part of the page");
    NSInteger outside = 0, inside = 0;
    for (NSInteger y = 0; y < 400; y += 4)
        for (NSInteger x = 0; x < 400; x += 4) {
            BOOL within = x >= 100 && x < 300 && y >= 100 && y < 300;
            if (!within && alphaAt(rep, x, y) > 0.01) outside++;
            if (within && alphaAt(rep, x, y) > 0.9) inside++;
        }
    check(inside > 2000, "the popup is drawn over its whole frame");
    check(outside == 0, "nothing of the linked page is drawn outside the popup");
    printf("PASS: a link popup draws only inside its frame\n");
    return 0;
}}
'''
with tempfile.TemporaryDirectory(prefix='texshop-link-clip-') as directory:
    temporary = Path(directory)
    (temporary / 'probe.m').write_text(program)
    (temporary / 'TSLinkPreviewView.m').write_text(preview_source)
    exe = temporary / 'probe'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    *include_args(root), '-I' + str(root / 'Tests'), str(temporary / 'probe.m'),
                    str(temporary / 'TSLinkPreviewView.m'), '-o', str(exe)], check=True)
    home = temporary / 'home'
    (home / 'Library/Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
    result = subprocess.run([str(exe)], env=env, capture_output=True, text=True, timeout=60)
    print(result.stdout, end='')
    if args.mutation:
        expected = {'no-clip': 'the page image is drawn clipped to the popup',
                    'no-clips-to-bounds': 'the popup clips its drawing to its frame'}[args.mutation]
        assert result.returncode == 1 and expected in result.stderr, result.stderr
        print('PASS: detected mutation ' + args.mutation)
    else:
        if result.returncode:
            print(result.stderr)
        result.check_returncode()
