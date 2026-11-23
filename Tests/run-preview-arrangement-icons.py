#!/usr/bin/env python3
"""Check the icons of the Two-Page Arrangement menu in the Preview toolbar.

Each icon shows what its choice displays, with the other choice as it is now, as PDFKit arranges
the pages: Left to right is [1|2], or [2|3] while the first page is a cover; Right to left is [2|1]
or [3|2]; the cover is page 1 alone in the middle above the next spread, [2|3] or [3|2] by the
direction. Restore Document Settings has no icon. The test draws each icon and compares it with
the pages drawn from the expected numbers, checks the cover's page is in the middle, that the
icons are template images of the Page Layout icons' size, that the menu shows them also on
macOS 27, and that validating the menu gives each choice the icon of the current arrangement."""
from pathlib import Path
import argparse
import subprocess
import sys
import tempfile
from source_tree import include_args

LAYOUT = 'Sources/Preview/TSPreviewLayout.h'
TOOLBAR = 'Sources/Windows/TSToolbarController.m'
MUTATIONS = {
    # Left to right shows [1|2] also while the first page is a cover.
    'ltr-ignores-cover': (LAYOUT, 'tag == 1 ? (cover ? @[@"2", @"3"] : @[@"1", @"2"])', 'tag == 1 ? @[@"1", @"2"]'),
    # Right to left shows the pages of left to right.
    'rtl-as-ltr': (LAYOUT, ': tag == 2 ? (cover ? @[@"3", @"2"] : @[@"2", @"1"])', ': tag == 2 ? (cover ? @[@"2", @"3"] : @[@"1", @"2"])'),
    # The cover's spread does not follow the direction.
    'cover-ignores-direction': (LAYOUT, ': (rightToLeft ? @[@"3", @"2"] : @[@"2", @"3"]);', ': @[@"2", @"3"];'),
    # The cover without page 1 above the spread.
    'cover-without-page-one': (LAYOUT, '            TSPreviewDrawPages(NSMakeRect(NSMidX(rect) - pageWidth / 2, bottom + pageHeight + gap, pageWidth, pageHeight), @[@"1"], 1.0, 6.5);\n', ''),
    # Page 1 of the cover at the right, as a recto page; PDFKit puts it in the middle.
    'cover-page-at-right': (LAYOUT, 'NSMakeRect(NSMidX(rect) - pageWidth / 2, bottom + pageHeight + gap', 'NSMakeRect(NSMidX(rect), bottom + pageHeight + gap'),
    # Restore Document Settings gets an icon.
    'restore-has-icon': (LAYOUT, 'if (tag < 1 || tag > 3) return nil;', 'if (tag < 1 || tag > 4) return nil;'),
    'not-template': (LAYOUT, '    image.template = YES;\n    images[key] = image;', '    images[key] = image;'),
    # The menu hides the icons on macOS 27.
    'icons-hidden-on-27': (LAYOUT, '        if (choice.image) {\n            if (@available(macOS 27.0, *)) choice.preferredImageVisibility = NSMenuItemImageVisibilityVisible;\n        }\n', ''),
    # Validating the menu leaves the icons of the first arrangement.
    'validation-keeps-icons': (TOOLBAR, '        if (item.image != image) item.image = image;\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--sdk', help='SDK to compile with, for example a path to an older macOS SDK')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
sources = {name: (root / name).read_text() for name in (LAYOUT, TOOLBAR)}
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert sources[name].count(old) == 1, args.mutation
    sources[name] = sources[name].replace(old, new)

# Validating a menu item of the arrangement gives it the icon of the current arrangement.
toolbar = sources[TOOLBAR]
start = toolbar.index('- (BOOL)validatePreviewLayoutItem:(NSMenuItem *)item')
validation = toolbar[start:toolbar.index('\n}\n', start)]
if not ('TSPreviewArrangementImage(item.tag, self.previewDisplaysRTL, self.previewDisplaysAsBook)' in validation
        and 'item.image = image;' in validation):
    print('FAIL: validating an arrangement choice gives it the icon of the current arrangement', file=sys.stderr)
    sys.exit(1)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSPreviewLayout.h"
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSInteger const W = 88, H = 80;
// The ink of an image drawn at 4 times its size, as 0 or 1 per pixel, rows from the top.
static NSData *inkOf(NSImage *image) {
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
// The pages drawn from the expected numbers, in the frames of the icons.
static NSImage *expected(NSArray<NSString *> *spread, BOOL cover) {
    NSImage *image = [NSImage imageWithSize:NSMakeSize(22, 20) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [NSColor.blackColor setStroke];
        if (cover) {
            CGFloat gap = 1.4, pageWidth = 8.5, pageHeight = (20 - gap - 1) / 2, bottom = (20 - (2 * pageHeight + gap)) / 2;
            TSPreviewDrawPages(NSMakeRect(11 - pageWidth / 2, bottom + pageHeight + gap, pageWidth, pageHeight), @[@"1"], 1.0, 6.5);
            TSPreviewDrawPages(NSMakeRect(11 - pageWidth, bottom, 2 * pageWidth, pageHeight), spread, 1.0, 6.5);
        } else
            TSPreviewDrawPages(NSMakeRect(1.5, 3.5, 19, 13), spread, 1.2, 8.5);
        return YES;
    }];
    return image;
}
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSDictionary *names = @{@1: @"Left to right", @2: @"Right to left", @3: @"Cover"};
    for (NSInteger rtl = 0; rtl <= 1; rtl++) for (NSInteger cover = 0; cover <= 1; cover++) {
        NSArray *spreads = @[cover ? @[@"2", @"3"] : @[@"1", @"2"], cover ? @[@"3", @"2"] : @[@"2", @"1"], rtl ? @[@"3", @"2"] : @[@"2", @"3"]];
        for (NSInteger tag = 1; tag <= 3; tag++) {
            NSImage *image = TSPreviewArrangementImage(tag, rtl, cover);
            NSString *state = [NSString stringWithFormat:@"%@ (%@, cover %@)", names[@(tag)], rtl ? @"right to left" : @"left to right", cover ? @"on" : @"off"];
            check(image.template && NSEqualSizes(image.size, NSMakeSize(22, 20)), [state stringByAppendingString:@": a template image of 22 x 20"]);
            NSData *ink = inkOf(image);
            check(count(ink) > 300, [state stringByAppendingFormat:@": drawn (%lu)", (unsigned long)count(ink)]);
            check([ink isEqualToData:inkOf(expected(spreads[tag - 1], tag == 3))],
                  [state stringByAppendingFormat:@": shows %@%@", tag == 3 ? @"[1] above " : @"", [spreads[tag - 1] componentsJoinedByString:@"|"]]);
        }
    }
    check(TSPreviewArrangementImage(4, NO, NO) == nil && TSPreviewArrangementImage(4, YES, YES) == nil, @"Restore Document Settings has no icon");
    // The four spreads differ from each other.
    NSArray *four = @[TSPreviewArrangementImage(1, NO, NO), TSPreviewArrangementImage(2, NO, NO), TSPreviewArrangementImage(1, NO, YES), TSPreviewArrangementImage(2, NO, YES)];
    for (NSUInteger a = 0; a < 4; a++) for (NSUInteger b = a + 1; b < 4; b++)
        check(![inkOf(four[a]) isEqualToData:inkOf(four[b])], [NSString stringWithFormat:@"spreads %lu and %lu differ", (unsigned long)a, (unsigned long)b]);
    // Page 1 of the cover is in the middle, as PDFKit shows it: the ink of the upper half is centered.
    for (NSInteger rtl = 0; rtl <= 1; rtl++) {
        const unsigned char *b = inkOf(TSPreviewArrangementImage(3, rtl, NO)).bytes;
        NSInteger left = W, right = -1;
        for (NSInteger y = 0; y < H / 2 - 4; y++) for (NSInteger x = 0; x < W; x++) if (b[y * W + x]) { left = MIN(left, x); right = MAX(right, x); }
        check(right > left && ABS((left + right + 1) - W) <= 2, [NSString stringWithFormat:@"the cover's page 1 is in the middle (%ld to %ld)", (long)left, (long)right]);
    }
    // The menu shows the icons of the first arrangement, also on macOS 27; Restore has none.
    NSMenuToolbarItem *item = TSPreviewLayoutItem(nil, TSPreviewArrangementToolbarID);
    for (NSMenuItem *choice in item.menu.itemArray) {
        if (choice.isSeparatorItem) continue;
        if (choice.tag == 4) { check(choice.image == nil, @"Restore Document Settings in the menu has no icon"); continue; }
        check(choice.image && [inkOf(choice.image) isEqualToData:inkOf(TSPreviewArrangementImage(choice.tag, NO, NO))],
              [NSString stringWithFormat:@"menu item %ld shows its icon", (long)choice.tag]);
#if defined(MAC_OS_VERSION_27_0)
        if (@available(macOS 27.0, *))
            check(choice.preferredImageVisibility == NSMenuItemImageVisibilityVisible,
                  [NSString stringWithFormat:@"menu item %ld keeps its icon visible on macOS 27", (long)choice.tag]);
#endif
    }
    printf("PASS: %lu checks of the arrangement icons\n", (unsigned long)checks + 1);
    return 0;
}}
'''
with tempfile.TemporaryDirectory(prefix='TeXShop-arrangement-icons-') as tmp:
    tmp = Path(tmp)
    (tmp / 'TSPreviewLayout.h').write_text(sources[LAYOUT])
    (tmp / 'test.m').write_text(program)
    subprocess.run(['xcrun', *(['--sdk', args.sdk] if args.sdk else []), 'clang', '-fobjc-arc', '-I', str(tmp), *include_args(root), '-framework', 'Cocoa', '-framework', 'PDFKit',
                    str(tmp / 'test.m'), '-o', str(tmp / 'test')], check=True)
    result = subprocess.run([str(tmp / 'test')], capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    print(output)
    sys.exit(result.returncode)
