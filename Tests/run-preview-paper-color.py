#!/usr/bin/env python3
"""The theme's Preview color is the paper of pages shown light (Issue #39).

Compiles the production drawing and paper methods of MyPDFKitView into a small PDFView
with the state they use, and the production OverView, then checks without showing a
window: the paper of light pages on screen in Light, System and dark windows, no paper
for pages shown dark, nothing added to printing, rotated and cropped pages, redrawing
only when the paper changes, and the magnifying glass. Defaults stay in memory.
"""
from pathlib import Path
import argparse, os, re, subprocess, tempfile
from source_tree import include_args

MUTATIONS = {
    'no-screen-fill': ('MyPDFKitView.m', 'TSFillPreviewPaper(NSGraphicsContext.currentContext.CGContext, page, self.displayBox, self.previewPaperColor);', ';'),
    'paper-while-dark': ('TSPreviewAppearance.h', 'return TSPreviewShouldInvert(mode, systemAppearance) ? nil : themeColor;', 'return themeColor;'),
    'inversion-keeps-paper': ('MyPDFKitView.m', '    [self updatePreviewPaperColor];\n    _updatingPreviewAppearance = NO;', '    _updatingPreviewAppearance = NO;'),
    'redraw-always': ('MyPDFKitView.m', '    if (old == paper || [old isEqual:paper]) return;\n    self.previewPaperColor = paper;', '    self.previewPaperColor = paper;'),
    'window-theme-ignored': ('MyPDFKitView.m', 'fromDictionary:(dark ? darkColors : liteColors) isWindowDark:dark];', 'fromDictionary:liteColors isWindowDark:NO];'),
    'unrotated-fill': ('TSPreviewAppearance.h', '    CGContextConcatCTM(context, [page transformForBox:box]);\n', ''),
    'lens-white': ('OverView.m', '[(self.magnifiedPaperColor ?: [NSColor whiteColor]) set];', '[[NSColor whiteColor] set];'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
texts = {name: (root/'Sources/Preview'/name).read_text(encoding='utf-8', errors='replace')
         for name in ('MyPDFKitView.m', 'TSPreviewAppearance.h', 'OverView.m')}
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert texts[name].count(old) == 1, args.mutation
    texts[name] = texts[name].replace(old, new)

# Wiring outside the compiled methods: a theme change and the magnifying glass.
color = (root/'Sources/Editor/TSDocument-Color.m').read_text(encoding='utf-8', errors='replace')
change = color[color.index('- (void) changeColorsUsingDictionary:'):color.index('- (void) changeColorsFromNotification:')]
assert '[self.myPDFKitView updatePreviewPaperColor];' in change and '[self.myPDFKitView2 updatePreviewPaperColor];' in change, 'theme changes reach both preview parts'
assert 'PreviewBackgroundColor' not in color, 'no process-wide preview color'
glass = (root/'Sources/Preview/MyPDFKitView-Magnification.m').read_text(encoding='utf-8', errors='replace')
assert '[[self overView] setMagnifiedPaperColor: self.previewPaperColor];' in glass, 'the document glass takes the paper'

def method(source, signature, after=None):
    start = source.index(signature, source.index(after) if after else 0)
    following = [i for i in (source.find('\n- (', start + 1), source.find('\n@end', start + 1)) if i > 0]
    return source[start:source.rindex('\n}', start, min(following)) + 2]

view = texts['MyPDFKitView.m']
methods = '\n'.join([
    method(view, '- (void)drawPage:(PDFPage *)page\n', after='- (void)previewBackgroundChange:'),
    method(view, '- (void)drawPage:(PDFPage *)page toContext:(CGContextRef)context'),
    method(view, '- (void)applyDarkModeInversionFilter'),
    method(view, '- (void)removeDarkModeInversionFilter'),
    method(view, '- (void)updateDarkModeInversion'),
    method(view, '- (void)updatePreviewPaperColor'),
])
overview = texts['OverView.m']
overview = overview.replace('#import "OverView.h"', '#import "OverView.h"\n#import "TSMagnifyingGlass.h"', 1) if 'TSMagnifyingGlass.h' not in overview else overview

program = r'''
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "TestAppKitIsolation.h"
#import "TSPDFScreenRendering.h"
#define MOJAVEORHIGHER 1
APPEARANCE
@interface MemoryDefaults : NSUserDefaults
@property (nonatomic, strong) NSMutableDictionary *values;
@end
@implementation MemoryDefaults
- (instancetype)init { self = [super init]; if (self) _values = [NSMutableDictionary dictionary]; return self; }
- (NSInteger)integerForKey:(NSString *)key { return [self.values[key] integerValue]; }
- (BOOL)boolForKey:(NSString *)key { return [self.values[key] boolValue]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { self.values[key] = @(value); }
@end
static MemoryDefaults *SUD;
static NSString *PdfColorMapKey = @"PdfColorMap", *InterpolationValueKey = @"InterpolationValue";
static NSColor *ImageBackgroundColor, *PreviewDirectSyncColor;
static NSDictionary *liteColors, *darkColors;
@interface TSColorSupport : NSObject
+ (instancetype)sharedInstance;
- (NSColor *)opaqueColorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark;
@end
@implementation TSColorSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
- (NSColor *)opaqueColorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark
{ return theme[key] ?: (dark ? NSColor.blackColor : NSColor.whiteColor); }
@end
@interface DocumentFixture : NSObject
@property BOOL useConTeXtSyncParser;
@property NSInteger syncWithOvals;
@end
@implementation DocumentFixture
@end
@interface MyPDFKitView : PDFView {
    BOOL _pdfViewReady, _updatingPreviewAppearance;
    NSInteger pageIndexForMark; NSRect pageBoundsForMark; BOOL drawMark, oldSync;
    NSRect syncRect[200]; int numberSyncRect;
}
@property (strong) DocumentFixture *myDocument;
@property NSInteger redraws;
@property (atomic, strong, readonly) NSColor *previewPaperColor;
- (void)updatePreviewPaperColor;
- (void)updateDarkModeInversion;
@end
@interface MyPDFKitView ()
@property (atomic, strong, readwrite) NSColor *previewPaperColor;
@end
@implementation MyPDFKitView
- (instancetype)initWithFrame:(NSRect)frame { self = [super initWithFrame:frame]; if (self) { _pdfViewReady = YES; _myDocument = [DocumentFixture new]; } return self; }
- (void)drawDotsForPage:(NSInteger)page atPoint:(NSPoint)point {}
- (BOOL)annotationDrawPage:(PDFPage *)page { return NO; }
- (void)setNeedsDisplay:(BOOL)flag { if (flag) self.redraws++; [super setNeedsDisplay:flag]; }
METHODS
@end
OVERVIEW
static int checks;
static void check(BOOL ok, NSString *message) { checks++; if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
static NSColor *orange, *purple;
// Like TeX output: a transparent page with a black mark near its lower left corner.
static PDFDocument *texDocument(NSInteger rotation, BOOL cropped) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 400, 600); CGContextRef pdf = CGPDFContextCreate(consumer, &box, NULL);
    CGPDFContextBeginPage(pdf, NULL); CGContextSetRGBFillColor(pdf, 0, 0, 0, 1); CGContextFillRect(pdf, CGRectMake(60, 60, 20, 20));
    CGPDFContextEndPage(pdf); CGPDFContextClose(pdf); CGContextRelease(pdf); CGDataConsumerRelease(consumer);
    PDFDocument *document = [[PDFDocument alloc] initWithData:data];
    PDFPage *page = [document pageAtIndex:0];
    page.rotation = rotation;
    if (cropped) [page setBounds:NSMakeRect(50, 50, 300, 400) forBox:kPDFDisplayBoxCropBox];
    return document;
}
static NSBitmapImageRep *screen(MyPDFKitView *view) {
    PDFPage *page = [view.document pageAtIndex:0];
    NSRect box = [page boundsForBox:view.displayBox];
    BOOL turned = page.rotation % 180 != 0;
    NSInteger width = turned ? NSHeight(box) : NSWidth(box), height = turned ? NSWidth(box) : NSHeight(box);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    check(context.isDrawingToScreen, @"a bitmap is drawn as the screen is");
    [view drawPage:page toContext:context.CGContext];
    return rep;
}
static BOOL same(NSColor *a, NSColor *b) {
    if (!a || !b) return a == b;
    a = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; b = [b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return a.alphaComponent > .99 && fabs(a.redComponent-b.redComponent) < .03 && fabs(a.greenComponent-b.greenComponent) < .03 && fabs(a.blueComponent-b.blueComponent) < .03;
}
static NSColor *at(NSBitmapImageRep *rep, NSInteger x, NSInteger y) { return [rep colorAtX:x y:rep.pixelsHigh - 1 - y]; }
static BOOL printedOpaque(MyPDFKitView *view) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 400, 600); CGContextRef pdf = CGPDFContextCreate(consumer, &box, NULL);
    CGPDFContextBeginPage(pdf, NULL); [view drawPage:[view.document pageAtIndex:0] toContext:pdf]; CGPDFContextEndPage(pdf);
    CGPDFContextClose(pdf); CGContextRelease(pdf); CGDataConsumerRelease(consumer);
    NSImage *image = [[NSImage alloc] initWithData:data];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:60
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [image drawInRect:NSMakeRect(0, 0, 40, 60)]; [NSGraphicsContext restoreGraphicsState];
    return [rep colorAtX:20 y:20].alphaComponent > .5;
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    SUD = [MemoryDefaults new];
    orange = [NSColor colorWithSRGBRed:1 green:.6 blue:.2 alpha:1]; purple = [NSColor colorWithSRGBRed:.5 green:.3 blue:.9 alpha:1];
    liteColors = @{@"PreviewBackground": orange}; darkColors = @{@"PreviewBackground": purple};
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    MyPDFKitView *view = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 500, 700)];
    view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    view.document = texDocument(0, NO);

    // Light pages take the theme of the window's appearance.
    [SUD setInteger:TSPreviewAppearanceLight forKey:TSPreviewAppearanceModeKey];
    NSInteger redraws = view.redraws; [view updateDarkModeInversion];
    check(same(view.previewPaperColor, orange) && view.redraws > redraws, @"Light pages: the light theme's paper, and the pages are drawn again");
    redraws = view.redraws; [view updatePreviewPaperColor]; [view updateDarkModeInversion];
    check(view.redraws == redraws, @"Pages are not drawn again while the paper stays the same");
    NSBitmapImageRep *rep = screen(view);
    check(same(at(rep, 5, 300), orange) && same(at(rep, 395, 595), orange), @"The page is filled with the paper on screen");
    check(same(at(rep, 70, 70), NSColor.blackColor), @"The page is drawn over its paper");
    check(!printedOpaque(view), @"Printing and PDF copies keep the page transparent");

    // Pages shown dark keep PDFKit's paper for the luminosity filter.
    [SUD setInteger:TSPreviewAppearanceDark forKey:TSPreviewAppearanceModeKey];
    redraws = view.redraws; [view updateDarkModeInversion];
    check(view.previewPaperColor == nil && view.redraws > redraws, @"Dark pages have no theme paper, and are drawn again");
    rep = screen(view);
    check(at(rep, 5, 300).alphaComponent < .01, @"Dark pages are not filled");

    // System follows the system's appearance; the paper follows the window's.
    [SUD setInteger:TSPreviewAppearanceSystem forKey:TSPreviewAppearanceModeKey];
    [view updateDarkModeInversion];
    check(same(view.previewPaperColor, orange), @"System in a light system: light theme's paper");
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [view updateDarkModeInversion];
    check(view.previewPaperColor == nil, @"System in a dark system: no paper");
    [SUD setInteger:TSPreviewAppearanceLight forKey:TSPreviewAppearanceModeKey];
    view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [view updateDarkModeInversion];
    check(same(view.previewPaperColor, purple), @"Light pages in a dark window: the dark theme's paper");

    // A changed theme reaches the paper.
    liteColors = @{@"PreviewBackground": NSColor.greenColor};
    view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    redraws = view.redraws; [view updatePreviewPaperColor];
    check(same(view.previewPaperColor, NSColor.greenColor) && view.redraws > redraws, @"An edited theme is drawn");

    // Rotated and cropped pages are filled exactly where they are drawn.
    view.document = texDocument(90, YES);
    rep = screen(view);
    check(rep.pixelsWide == 400 && rep.pixelsHigh == 300, @"Rotated cropped fixture");
    for (NSArray *point in @[@[@2, @2], @[@397, @2], @[@2, @297], @[@397, @297], @[@200, @150]])
        check(same(at(rep, [point[0] integerValue], [point[1] integerValue]), NSColor.greenColor), @"Rotated cropped page is filled to its corners");

    // The magnifying glass shows the same paper.
    OverView *lens = [[OverView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    [lens setDrawMagnifiedImage:YES]; [lens setSelectionRect:NSMakeRect(50, 50, 100, 100)];
    lens.magnifiedPaperColor = view.previewPaperColor;
    NSBitmapImageRep *glass = [lens bitmapImageRepForCachingDisplayInRect:lens.bounds];
    [lens cacheDisplayInRect:lens.bounds toBitmapImageRep:glass];
    check(same([glass colorAtX:glass.pixelsWide/2 y:glass.pixelsHigh/2], NSColor.greenColor), @"The lens has the preview's paper");
    printf("PASS: %d preview paper checks\n", checks);
} return 0; }
'''
program = program.replace('APPEARANCE', texts['TSPreviewAppearance.h']).replace('METHODS', methods).replace('OVERVIEW', overview)
with tempfile.TemporaryDirectory(prefix='texshop-preview-paper-') as temp:
    temp = Path(temp)
    (temp/'test.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-I', str(root/'Tests'), *include_args(root),
                    '-framework', 'Cocoa', '-framework', 'Quartz', str(temp/'test.m'), '-o', str(temp/'test')], check=True)
    (temp/'home/Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(temp/'test')], capture_output=True, text=True, timeout=60,
                            env=dict(os.environ, HOME=str(temp/'home'), CFFIXED_USER_HOME=str(temp/'home')))
    if args.mutation:
        assert result.returncode == 1 and 'FAIL:' in result.stderr, result.stdout + result.stderr
        print('PASS: detected', args.mutation)
    else:
        if result.returncode: raise SystemExit(result.stdout + result.stderr)
        print(result.stdout.strip())
