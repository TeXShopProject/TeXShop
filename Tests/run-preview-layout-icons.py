#!/usr/bin/env python3
"""Check the icons of the display formats in the Page Layout item of the Preview toolbar (#65).

Single Page is a sheet with text, Two Pages an open book with lines of text, MultiPage a scroll and
Double MultiPage the open book above an arrow down. The books are drawn from SVG path data; the
test reads that data with the production parser and checks every point against the SVG, checks
that each icon is that drawing, that the four differ from each other, and that they are template
images of the toolbar's size."""
from pathlib import Path
import argparse
import subprocess
import sys
import tempfile
from source_tree import include_args

MUTATIONS = {
    # Relative curves read as absolute ones.
    'relative-curves-absolute': ('NSPoint base = relative ? current : NSZeroPoint;', 'NSPoint base = NSZeroPoint;'),
    # Further pairs after a move are not read as lines.
    'move-pairs-not-lines': ("command = relative ? 'l' : 'L';   // further pairs are lines", ''),
    'not-template': ('    image.template = YES;\n    return image;', '    return image;'),
    'book-without-lines': ('    for (NSUInteger i = 0; i < 4; i++) {\n        NSBezierPath *line', '    for (NSUInteger i = 4; i < 4; i++) {\n        NSBezierPath *line'),
    'multipage-not-scroll': ('else if (style == 3 && scroll) TSPreviewDrawSymbol(scroll, rect);', 'else if (style == 3 && scroll) TSPreviewDrawSymbol(sheet, rect);'),
    'double-multipage-without-arrow': ('            [arrow stroke];\n', ''),
    # The arrow points up (#65 audit).
    'arrow-up': ('@"M11,14.6V19.2M9.3,17.5L11,19.2L12.7,17.5"', '@"M11,14.6V19.2M9.3,16.3L11,14.6L12.7,16.3"'),
    # A carriage return is not a separator (#65 audit).
    # The menu items show their images also on macOS 27, where AppKit usually hides them.
    'menu-images-hidden-on-27': ('if (@available(macOS 27.0, *)) choice.preferredImageVisibility = NSMenuItemImageVisibilityVisible;', ''),
    'menu-without-images': ('            choice.image = TSPreviewLayoutImage(tag);\n', ''),
    'cr-not-separator': ('@" ,\\n\\r\\t\\f"', '@" ,\\n\\t"'),
    # Command letters read together: a close followed at once by a move is lost (#65 audit).
    'commands-read-together': ('        unichar next = [data characterAtIndex:scanner.scanLocation];\n        if ([commands characterIsMember:next]) {\n            command = next;\n            scanner.scanLocation += 1;',
        '        unichar next = [data characterAtIndex:scanner.scanLocation];\n        NSString *letters = nil;\n        if ([scanner scanCharactersFromSet:commands intoString:&letters]) {\n            command = [letters characterAtIndex:letters.length - 1];'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
header = (root / 'Sources/Preview/TSPreviewLayout.h').read_text()
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, new)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSPreviewLayout.h"
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
// The points of a path: for each element, its type and its points.
static NSString *pointsOf(NSBezierPath *path) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSInteger i = 0; i < path.elementCount; i++) {
        NSPoint p[3];
        NSBezierPathElement e = [path elementAtIndex:i associatedPoints:p];
        NSUInteger n = e == NSBezierPathElementCubicCurveTo ? 3 : e == NSBezierPathElementClosePath ? 0 : 1;
        NSMutableString *s = [NSMutableString stringWithString:@[@"M", @"L", @"C", @"Z"][e == NSBezierPathElementMoveTo ? 0 : e == NSBezierPathElementLineTo ? 1 : e == NSBezierPathElementCubicCurveTo ? 2 : 3]];
        for (NSUInteger k = 0; k < n; k++) [s appendFormat:@"%.2f,%.2f%@", p[k].x, p[k].y, k + 1 < n ? @" " : @""];
        [parts addObject:s];
    }
    return [parts componentsJoinedByString:@" "];
}
// The ink of an image drawn at 4 times its size, as 0 or 1 per pixel.
static NSData *inkOf(NSImage *image) {
    NSInteger W = 88, H = 80;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [image drawInRect:NSMakeRect(0, 0, W, H)];
    [NSGraphicsContext restoreGraphicsState];
    NSMutableData *ink = [NSMutableData dataWithLength:W * H];
    unsigned char *o = ink.mutableBytes;
    for (NSInteger y = 0; y < H; y++) for (NSInteger x = 0; x < W; x++)
        o[y * W + x] = rep.bitmapData[y * rep.bytesPerRow + x * 4 + 3] > 127;
    return ink;
}
static NSUInteger count(NSData *ink) { NSUInteger n = 0; const unsigned char *b = ink.bytes; for (NSUInteger i = 0; i < ink.length; i++) n += b[i]; return n; }
// Intersection over union of the ink of two images.
static double overlap(NSData *a, NSData *b) {
    const unsigned char *p = a.bytes, *q = b.bytes; NSUInteger both = 0, either = 0;
    for (NSUInteger i = 0; i < a.length; i++) { both += p[i] && q[i]; either += p[i] || q[i]; }
    return either ? (double)both / either : 0;
}
// A sheet of the image's size with only `draw` in it.
static NSImage *drawn(void (^draw)(NSRect)) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(22, 20) flipped:YES drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor setStroke]; draw(rect); return YES; }];
    image.template = YES;
    return image;
}
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    // The SVG of the open book (Issue65 SVG), as absolute points.
    NSArray *expected = @[
        @"M2.20,17.20 L2.20,3.30 C5.01,2.10 8.19,2.10 11.00,3.30 L11.00,17.20 C8.19,16.00 5.01,16.00 2.20,17.20",
        @"M11.00,17.20 L11.00,3.30 C13.81,2.10 16.99,2.10 19.80,3.30 L19.80,17.20 C16.99,16.00 13.81,16.00 11.00,17.20"];
    for (NSUInteger i = 0; i < 2; i++)
        check([pointsOf(TSPreviewPathFromSVG(TSPreviewBookPages[i])) isEqualToString:expected[i]],
              [NSString stringWithFormat:@"page %lu follows its SVG path (%@)", (unsigned long)i, pointsOf(TSPreviewPathFromSVG(TSPreviewBookPages[i]))]);
    NSArray *lines = @[@"M3.78,5.47 C5.61,4.84 7.59,4.84 9.42,5.47", @"M3.78,7.85 C5.01,7.25 6.40,7.15 7.73,7.40",
                       @"M12.58,5.47 C14.41,4.84 16.39,4.84 18.22,5.47", @"M12.58,7.85 C13.81,7.25 15.27,7.14 16.57,7.44"];
    for (NSUInteger i = 0; i < 4; i++)
        check([pointsOf(TSPreviewPathFromSVG(TSPreviewBookLines[i])) isEqualToString:lines[i]],
              [NSString stringWithFormat:@"line %lu follows its SVG path (%@)", (unsigned long)i, pointsOf(TSPreviewPathFromSVG(TSPreviewBookLines[i]))]);
    check([pointsOf(TSPreviewPathFromSVG(@"M1,2 3,4 5,6Z m1,1 2,0")) isEqualToString:@"M1.00,2.00 L3.00,4.00 L5.00,6.00 Z M2.00,3.00 L4.00,3.00"],
          [NSString stringWithFormat:@"pairs after a move are lines, also relative ones after a close (%@)", pointsOf(TSPreviewPathFromSVG(@"M1,2 3,4 5,6Z m1,1 2,0"))]);
    check([pointsOf(TSPreviewPathFromSVG(@"M1,1H4h1V3v-1")) isEqualToString:@"M1.00,1.00 L4.00,1.00 L5.00,1.00 L5.00,3.00 L5.00,2.00"],
          @"horizontal and vertical lines, absolute and relative");
    // Without spaces between the commands, the same path (#65 audit).
    NSString *spaced = pointsOf(TSPreviewPathFromSVG(@"M1,1L5,1L5,5Z m2,0 l1,0")), *packed = pointsOf(TSPreviewPathFromSVG(@"M1,1L5,1L5,5Zm2,0l1,0"));
    check([spaced isEqualToString:@"M1.00,1.00 L5.00,1.00 L5.00,5.00 Z M3.00,1.00 L4.00,1.00"] && [packed isEqualToString:spaced],
          [NSString stringWithFormat:@"a close followed at once by the next command (%@ / %@)", spaced, packed]);
    // Line breaks of any kind separate commands as a space does (#65 audit).
    for (NSString *br in @[@"\n", @"\r", @"\r\n", @"\t", @"\f"]) {
        NSString *broken = pointsOf(TSPreviewPathFromSVG([NSString stringWithFormat:@"M1,1L5,1L5,5Z%@m2,0%@l1,0", br, br]));
        check([broken isEqualToString:spaced], [NSString stringWithFormat:@"a line break between commands (%lu characters): %@", (unsigned long)br.length, broken]);
    }

    NSData *ink[5];
    for (NSInteger style = 1; style <= 4; style++) {
        NSImage *image = TSPreviewLayoutImage(style);
        check(image.template && NSEqualSizes(image.size, NSMakeSize(22, 20)),
              [NSString stringWithFormat:@"display format %ld: a template image of 22 x 20", (long)style]);
        ink[style] = inkOf(image);
        check(count(ink[style]) > 400, [NSString stringWithFormat:@"display format %ld: drawn (%lu)", (long)style, (unsigned long)count(ink[style])]);
    }
    for (NSInteger a = 1; a <= 4; a++) for (NSInteger b = a + 1; b <= 4; b++)
        check(overlap(ink[a], ink[b]) < 0.6, [NSString stringWithFormat:@"display formats %ld and %ld look different (%.2f)", (long)a, (long)b, overlap(ink[a], ink[b])]);
    // The symbols: a sheet with text for Single Page, a scroll for MultiPage.
    NSImage *sheet = [NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:nil];
    NSImage *scroll = [NSImage imageWithSystemSymbolName:@"scroll" accessibilityDescription:nil];
    check(sheet && scroll, @"the symbols are there");
    check([ink[1] isEqualToData:inkOf(drawn(^(NSRect r) { TSPreviewDrawSymbol(sheet, r); }))], @"Single Page is the sheet with text");
    check([ink[3] isEqualToData:inkOf(drawn(^(NSRect r) { TSPreviewDrawSymbol(scroll, r); }))], @"MultiPage is the scroll");
    // The books: Two Pages as in the SVG, Double MultiPage the same book, smaller, above an arrow.
    check([ink[2] isEqualToData:inkOf(drawn(^(NSRect r) { TSPreviewDrawBook(nil, 1.35, 0.95); }))], @"Two Pages is the open book");
    NSAffineTransform *smaller = [NSAffineTransform transform];
    [smaller translateXBy:11 * 0.2 yBy:1.5 - 2.4 * 0.8]; [smaller scaleBy:0.8];
    NSData *bookOnly = inkOf(drawn(^(NSRect r) { TSPreviewDrawBook(smaller, 1.15, 0.81); }));
    const unsigned char *b4 = bookOnly.bytes, *i4 = ink[4].bytes; BOOL contains = YES;
    for (NSUInteger i = 0; i < bookOnly.length; i++) if (b4[i] && !i4[i]) contains = NO;
    check(contains && count(ink[4]) > count(bookOnly) + 30, @"Double MultiPage is the open book at 0.8 of its size with more below");
    NSData *lineless = inkOf(drawn(^(NSRect r) {
        for (NSUInteger i = 0; i < 2; i++) { NSBezierPath *p = TSPreviewPathFromSVG(TSPreviewBookPages[i]); p.lineWidth = 1.35; [p stroke]; } }));
    check(count(ink[2]) > count(lineless) + 60, [NSString stringWithFormat:@"Two Pages shows lines of text (%lu, %lu)", (unsigned long)count(ink[2]), (unsigned long)count(lineless)]);
    // Rows from the top: below the book (whose spine ends at 13.3), around the middle.
    NSUInteger below = 0; const unsigned char *d4 = ink[4].bytes;
    for (NSInteger y = 60; y < 80; y++) for (NSInteger x = 36; x < 52; x++) below += d4[y * 88 + x];
    check(below > 30, [NSString stringWithFormat:@"Double MultiPage has the arrow below the book (%lu)", (unsigned long)below]);
    // The arrow points down: all of the arrow, as in the SVG, is in the icon (#65 audit).
    NSData *arrow = inkOf(drawn(^(NSRect r) {
        NSBezierPath *a = TSPreviewPathFromSVG(@"M11,14.6V19.2M9.3,17.5L11,19.2L12.7,17.5");
        a.lineWidth = 0.95; a.lineCapStyle = NSLineCapStyleRound; a.lineJoinStyle = NSLineJoinStyleRound; [a stroke]; }));
    const unsigned char *ar = arrow.bytes; NSUInteger missing = 0;
    for (NSUInteger i = 0; i < arrow.length; i++) if (ar[i] && !i4[i]) missing++;
    check(count(arrow) > 30 && missing == 0, [NSString stringWithFormat:@"Double MultiPage has the arrow pointing down (%lu of %lu missing)", (unsigned long)missing, (unsigned long)count(arrow)]);
    // The Page Layout menu shows the icon of each display format, also on macOS 27 and later.
    NSMenuToolbarItem *item = TSPreviewLayoutItem(nil, TSPreviewLayoutToolbarID);
    NSArray<NSMenuItem *> *choices = item.menu.itemArray;
    check(choices.count == 4, @"the Page Layout menu has the four display formats");
    for (NSMenuItem *choice in choices) {
        check(choice.image && [inkOf(choice.image) isEqualToData:ink[choice.tag]],
            [NSString stringWithFormat:@"menu item %ld shows the icon of its display format", (long)choice.tag]);
        if (@available(macOS 27.0, *))
            check(choice.preferredImageVisibility == NSMenuItemImageVisibilityVisible,
                [NSString stringWithFormat:@"menu item %ld keeps its icon visible on macOS 27", (long)choice.tag]);
    }
    printf("PASS: %lu checks of the display format icons\n", (unsigned long)checks);
    return 0;
}}
'''
with tempfile.TemporaryDirectory(prefix='TeXShop-layout-icons-') as tmp:
    tmp = Path(tmp)
    (tmp / 'TSPreviewLayout.h').write_text(header)
    (tmp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-I', str(tmp), *include_args(root), '-framework', 'Cocoa', '-framework', 'PDFKit',
                    str(tmp / 'test.m'), '-o', str(tmp / 'test')], check=True)
    result = subprocess.run([str(tmp / 'test')], capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.splitlines()[-1])
    else:
        print(output)
        sys.exit(result.returncode)
