#!/usr/bin/env python3
"""Check the line along the active part of a split Preview window.

Compiles the production TSPreviewActivePartLine class and the TSPreviewWindow
methods that show it with a stand-in window and two PDF views. The active part has
a 2-point line in the accent color along its inside edges while the window is split
and key; the other part, an unsplit window and a window that is not key show none.
The line follows the active part, the window's key state and the part's size, stays
above the part's own subviews and lets clicks through. Nothing is shown on screen
and no user settings are read.
"""
import argparse, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['no-key-check', 'no-split-check', 'line-below', 'no-resign-observer', 'fixed-size'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root/'Sources/Windows/TSPreviewWindow.m').read_text()
header = (root/'Sources/Windows/TSPreviewWindow.h').read_text()

fragments = []
def span(first, last):
    start = source.index(first); end = source.index(last, start) + len(last)
    fragment = source[start:end]
    fragments.append(('statements:' + first, source, fragment))
    return fragment

line_class = span('@interface TSPreviewActivePartLine : NSView', '''    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

@end''')
methods = span('- (void)setActiveView:(PDFView *)activeView', '''            TSActivePartLineInView(self, view).shown = shown;
    }
}''')

# The properties keep their names; the setters show the line.
assert '@property (nonatomic)   BOOL            windowIsSplit;' in header
assert '@property (nonatomic, retain) PDFView   *activeView;' in header
assert source.index('@interface TSPreviewActivePartLine') < source.index('@implementation TSPreviewWindow\n')

if args.mutation == 'no-key-check':
    old = 'view == self.activeView && view.window.isKeyWindow;'
    assert methods.count(old) == 1
    methods = methods.replace(old, 'view == self.activeView;')
elif args.mutation == 'no-split-check':
    old = 'BOOL shown = self.windowIsSplit && view == self.activeView'
    assert methods.count(old) == 1
    methods = methods.replace(old, 'BOOL shown = view == self.activeView')
elif args.mutation == 'line-below':
    old = '    } else if (view.subviews.lastObject != line)\n        [view addSubview: line positioned: NSWindowAbove relativeTo: nil];'
    assert methods.count(old) == 1
    methods = methods.replace(old, '    }')
elif args.mutation == 'no-resign-observer':
    old = '@[NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification]'
    assert line_class.count(old) == 1
    line_class = line_class.replace(old, '@[NSWindowDidBecomeKeyNotification]')
elif args.mutation == 'fixed-size':
    old = '            [line.bottomAnchor constraintEqualToAnchor: view.bottomAnchor]]];'
    assert methods.count(old) == 1
    methods = methods.replace(old, '            [line.widthAnchor constraintEqualToConstant: NSWidth(view.bounds)], [line.heightAnchor constraintEqualToConstant: NSHeight(view.bounds)]]];')

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"

@interface TSPreviewWindow : NSWindow
@property (nonatomic) BOOL windowIsSplit;
@property (nonatomic, retain) PDFView *activeView;
@property (retain) PDFView *myPDFKitView;
@property (retain) PDFView *myPDFKitView2;
@property BOOL testKey;
- (void)showActivePart;
@end

LINECLASS

@implementation TSPreviewWindow
- (BOOL)isKeyWindow { return self.testKey; }
METHODS
@end

static NSUInteger checks;
static void Check(BOOL ok, NSString *message) { checks++; if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
static TSPreviewActivePartLine *Line(PDFView *view) {
    for (NSView *subview in view.subviews) if ([subview isKindOfClass:[TSPreviewActivePartLine class]]) return (TSPreviewActivePartLine *)subview;
    return nil;
}
static BOOL Shown(PDFView *view) { return Line(view).shown; }
static NSBitmapImageRep *Drawn(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    return rep;
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    TSPreviewWindow *w = [[TSPreviewWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 800) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
    [w.contentView addSubview:split];
    PDFView *top = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)], *bottom = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    for (PDFView *v in @[top, bottom]) { v.autoresizesSubviews = NO; } // as in TSDocument.nib
    [split addSubview:top];
    w.myPDFKitView = top; w.myPDFKitView2 = bottom; w.activeView = top; w.testKey = YES;

    // Not split: no line anywhere.
    Check(!Shown(top) && !Shown(bottom), @"No line in an unsplit window");
    Check(!Line(top) && !Line(bottom), @"No line view before the first split");

    // Split: the active part has the line.
    [split addSubview:bottom]; [split adjustSubviews];
    w.windowIsSplit = YES;
    Check(Shown(top) && !Shown(bottom), @"Split: the line is on the active (top) part");
    [split layoutSubtreeIfNeeded];
    Check(NSEqualRects(Line(top).frame, top.bounds), [NSString stringWithFormat:@"The line covers the part: %@ in %@", NSStringFromRect(Line(top).frame), NSStringFromRect(top.bounds)]);
    Check(top.subviews.lastObject == Line(top), @"The line is above the part's own subviews");
    Check([Line(top) hitTest:NSMakePoint(10, 10)] == nil && [top hitTest:[top convertPoint:NSMakePoint(10, 10) toView:top.superview]] != Line(top), @"Clicks go through the line");

    // The line: 2 points in the accent color at the edges, nothing inside.
    NSBitmapImageRep *rep = Drawn(Line(top));
    NSColor *edge = [[rep colorAtX:0 y:rep.pixelsHigh / 2] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSColor *inner = [rep colorAtX:rep.pixelsWide / 2 y:rep.pixelsHigh / 2];
    NSColor *beyond = [rep colorAtX:(NSInteger)(3 * rep.pixelsWide / NSWidth(Line(top).bounds)) y:rep.pixelsHigh / 2];
    __block NSColor *accent = nil;
    [Line(top).effectiveAppearance performAsCurrentDrawingAppearance:^{
        NSBitmapImageRep *one = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:1 pixelsHigh:1 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        one = [one bitmapImageRepByRetaggingWithColorSpace:rep.colorSpace];
        [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:one];
        [NSColor.controlAccentColor setFill]; NSRectFill(NSMakeRect(0, 0, 1, 1)); [NSGraphicsContext restoreGraphicsState];
        accent = [[one colorAtX:0 y:0] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    }];
    Check(edge.alphaComponent > 0.9 && fabs(edge.redComponent - accent.redComponent) < 0.05 && fabs(edge.greenComponent - accent.greenComponent) < 0.05 && fabs(edge.blueComponent - accent.blueComponent) < 0.05,
          [NSString stringWithFormat:@"Accent line at the edge: %@ for %@", edge, accent]);
    Check(inner.alphaComponent < 0.01 && beyond.alphaComponent < 0.01, @"Nothing drawn inside the line");
    for (NSValue *corner in @[[NSValue valueWithPoint:NSMakePoint(0, 0)], [NSValue valueWithPoint:NSMakePoint(rep.pixelsWide - 1, rep.pixelsHigh - 1)]])
        Check([rep colorAtX:corner.pointValue.x y:corner.pointValue.y].alphaComponent > 0.9, @"All four edges");

    // The active part changes.
    w.activeView = bottom;
    Check(!Shown(top) && Shown(bottom), @"The line follows the active part");
    [split layoutSubtreeIfNeeded];
    Check(NSEqualRects(Line(bottom).frame, bottom.bounds), @"The line covers the bottom part");
    // The part's own subviews come later; the line goes back on top.
    [bottom addSubview:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)]];
    w.activeView = bottom;
    Check(bottom.subviews.lastObject == Line(bottom), @"The line stays above subviews added later");
    // The part changes its size.
    [split setPosition:250 ofDividerAtIndex:0]; [split layoutSubtreeIfNeeded];
    Check(NSEqualRects(Line(bottom).frame, bottom.bounds) && NSEqualRects(Line(top).frame, top.bounds),
          [NSString stringWithFormat:@"The line follows the part's size: %@ in %@", NSStringFromRect(Line(bottom).frame), NSStringFromRect(bottom.bounds)]);

    // The window stops being key, and becomes key again.
    w.testKey = NO; [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidResignKeyNotification object:w];
    Check(!Shown(top) && !Shown(bottom), @"No line while the window is not key");
    w.testKey = YES; [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidBecomeKeyNotification object:w];
    Check(Shown(bottom) && !Shown(top), @"The line comes back when the window is key");
    // Another window's key changes do not matter.
    NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 10, 10) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    other.releasedWhenClosed = NO;
    w.testKey = NO; [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidBecomeKeyNotification object:other];
    Check(Shown(bottom), @"Only the window's own key changes are followed");
    w.testKey = YES; [w showActivePart];

    // Unsplit: no line.
    w.activeView = top; [bottom removeFromSuperview]; w.windowIsSplit = NO;
    Check(!Shown(top) && !Shown(bottom), @"No line after unsplitting");
    // Split again with the bottom part active, in a window that is not key.
    w.testKey = NO; [split addSubview:bottom]; w.windowIsSplit = YES; w.activeView = bottom;
    Check(!Shown(top) && !Shown(bottom), @"Split in a window that is not key: no line");
    w.testKey = YES; [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidBecomeKeyNotification object:w];
    Check(Shown(bottom) && !Shown(top), @"Becoming key shows the line on the active part");
    // A part moved to another window (the single window) follows that window.
    NSWindow *single = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 800) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    single.releasedWhenClosed = NO;
    [single.contentView addSubview:split];
    Check(!Shown(bottom), @"In a window that is not key, the moved parts show no line");
    [w close]; [single close]; [other close];
    printf("PASS: %lu checks\n", (unsigned long)checks);
    return 0;
}}
'''
program = program.replace('LINECLASS', line_class).replace('METHODS', methods)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    (temp/'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit', '-I', str(root/'Tests'),
                    *include_args(root), str(temp/'test.m'), '-o', str(temp/'test')], check=True)
    result = subprocess.run([str(temp/'test')], capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.splitlines()[-1])
    else:
        print(output)
        sys.exit(result.returncode)
