#!/usr/bin/env python3
"""Check the Preview window's magnifying glass with its production methods.

doMagnifyingGlass:level: and doMagnifyingGlassElCapitanNew:level: are compiled
verbatim with the real OverView and PDFKit, in a window that is never shown.
Posted mouse events drive the tracking loop; just before the glass is removed,
what it drew is captured, so the checks look at the lens contents rather than
at coordinates alone. Defaults stay in memory.
"""
from pathlib import Path
import argparse, os, plistlib, subprocess, sys, tempfile
from production_fragments import method, verify_embedded
from source_tree import include_args

MUTATIONS = {
    'lens-in-page-units': ('                magRectWindow = [[self documentView] convertRect: lensInView fromView: self];',
                           '                magRectWindow = lensInView;'),
    'first-page-only': ('                if (pageUnder && pageUnder != myPage) {', '                if (NO) {'),
    'fixed-scale': ('            magScale = TSMagnifyingGlassScale([theEvent modifierFlags]);', ''),
    # The former limit and the former image of the whole page.
    'magnification-limit': ('- (void)doMagnifyingGlass:(NSEvent *)theEvent level: (NSInteger)level\n{\n',
                            '- (void)doMagnifyingGlass:(NSEvent *)theEvent level: (NSInteger)level\n{\n    if (self.scaleFactor > 2.5) return;\n'),
    'whole-page-image': ('                [[self overView] setMagnifiedPage: myPage];\n',
                         '                { PDFPage *p = myPage; PDFDisplayBox b = self.displayBox; NSRect r = [p boundsForBox:b];\n'
                         '                  NSSize z = p.rotation % 180 ? NSMakeSize(NSHeight(r), NSWidth(r)) : r.size;\n'
                         '                  [[self overView] setMagnifiedImage: [NSImage imageWithSize:z flipped:NO drawingHandler:^BOOL(NSRect d) {\n'
                         '                      [p drawWithBox:b toContext:NSGraphicsContext.currentContext.CGContext]; return YES; }]]; }\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root/'Sources/Preview/MyPDFKitView-Magnification.m').read_bytes().decode('latin-1')
assert '#import "TSMagnifyingGlass.h"' in source, 'The production file uses the shared glass'
fragments = []
for signature in ['- (void)doMagnifyingGlass:(NSEvent *)theEvent level: (NSInteger)level',
                  '- (void)doMagnifyingGlassElCapitanNew:(NSEvent *)theEvent level: (NSInteger)level']:
    fragments.append(('complete method:' + signature, source, method(source, signature)))
methods = '\n'.join(f[2] for f in fragments)
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert methods.count(old) == 1, args.mutation
    methods = methods.replace(old, new)

program = r'''
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import "TestAppKitIsolation.h"
#import "OverView.h"
#import "TSMagnifyingGlass.h"
#define NSAppKitVersionNumber10_10_Max 1349
static TSMemoryDefaults *defaults;
#define SUD defaults
@interface MyPDFKitView : PDFView
@property (retain) OverView *overView;
@end
@implementation MyPDFKitView
- (void)doMagnifyingGlassMavericks:(NSEvent *)event level:(NSInteger)level {}
METHODS
@end
static NSString *context = @"";
static NSUInteger checks;
static void Check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s [%s]\n", message.UTF8String, context.UTF8String); exit(1); }
}
// What the glass showed last, captured as it is removed.
static NSRect lens, shownSource; static NSBitmapImageRep *drawn; static NSUInteger glasses;
static void (*originalRemove)(id, SEL);
static void CaptureRemove(OverView *overlay, SEL selector) {
    lens = [[overlay valueForKey:@"theSelectionRect"] rectValue];
    shownSource = [[overlay valueForKey:@"magnifiedRect"] rectValue];
    drawn = [overlay bitmapImageRepForCachingDisplayInRect:lens];
    [overlay cacheDisplayInRect:lens toBitmapImageRep:drawn];
    glasses++;
    originalRemove(overlay, selector);
}
static BOOL DarkAt(NSBitmapImageRep *rep, CGFloat fx, CGFloat fy) {
    NSColor *color = [[rep colorAtX:(NSInteger)(fx * (rep.pixelsWide - 1)) y:(NSInteger)(fy * (rep.pixelsHigh - 1))]
        colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    return color.brightnessComponent < .3;
}
// A4 pages: a black "formula" near the top of page 1, a black box low on page 2.
static const NSRect Formula = {{220, 740}, {160, 30}}, Mark = {{60, 100}, {120, 60}};
static PDFDocument *Document(NSUInteger pages) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 595, 842);
    CGContextRef c = CGPDFContextCreate(consumer, &box, NULL);
    for (NSUInteger n = 0; n < pages; n++) {
        CGPDFContextBeginPage(c, NULL);
        CGContextSetRGBFillColor(c, 0, 0, 0, 1);
        CGContextFillRect(c, NSRectToCGRect(n == 0 ? Formula : Mark));
        CGPDFContextEndPage(c);
    }
    CGPDFContextClose(c); CGContextRelease(c); CGDataConsumerRelease(consumer);
    return [[PDFDocument alloc] initWithData:data];
}
static void Pump(void) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.15]]; }
static NSEvent *Mouse(NSEventType type, NSWindow *window, NSPoint point, NSInteger clicks, NSEventModifierFlags flags) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:flags timestamp:0 windowNumber:window.windowNumber
        context:nil eventNumber:0 clickCount:clicks pressure:1];
}
static void Drain(void) {
    while ([NSApp nextEventMatchingMask:NSEventMaskAny untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES]) {}
}
// Presses at one point, drags to another and releases; returns NO if no glass appeared.
static BOOL Glass(MyPDFKitView *view, NSPoint from, NSPoint to, NSInteger level, NSInteger clicks, NSEventModifierFlags flags) {
    NSWindow *window = view.window;
    NSPoint a = [view convertPoint:from toView:nil], b = [view convertPoint:to toView:nil];
    NSUInteger before = glasses;
    [NSApp postEvent:Mouse(NSEventTypeLeftMouseDragged, window, b, clicks, flags) atStart:NO];
    [NSApp postEvent:Mouse(NSEventTypeLeftMouseUp, window, b, clicks, flags) atStart:NO];
    [view doMagnifyingGlass:Mouse(NSEventTypeLeftMouseDown, window, a, clicks, flags) level:level];
    BOOL shown = glasses == before + 1;
    if (shown) Check(view.overView.superview == nil || view.overView == nil, @"Glass removed when the button is released");
    Drain();
    return shown;
}
static double FootprintMB(void) {
    task_vm_info_data_t info; mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
    return info.phys_footprint / 1048576.0;
}
static NSRect LensOnScreen(MyPDFKitView *view) { return [view convertRect:lens fromView:view.documentView]; }
static CGFloat Magnification(MyPDFKitView *view, PDFPage *page) {
    // Width on screen of what the lens shows, compared with the lens itself.
    NSRect inPage = NSRectFromCGRect(CGRectApplyAffineTransform(NSRectToCGRect(shownSource),
        CGAffineTransformInvert([page transformForBox:view.displayBox])));
    return NSWidth(LensOnScreen(view)) / NSWidth([view convertRect:inPage fromPage:page]);
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    defaults = [TSMemoryDefaults new];
    Method remove = class_getInstanceMethod(NSView.class, @selector(removeFromSuperview));
    originalRemove = (void *)method_getImplementation(remove);
    class_replaceMethod(OverView.class, @selector(removeFromSuperview), (IMP)CaptureRemove, method_getTypeEncoding(remove));
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 900) styleMask:NSWindowStyleMaskTitled
        backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    MyPDFKitView *view = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 700, 900)];
    window.contentView = view;

    // Position: the formula under the pointer, and paper away from it, for every
    // rotation, with and without boxes that start away from the origin.
    NSUInteger cases = 0;
    // offset 1: both boxes moved; offset 2: only the CropBox, as \\pdfpageattr{/CropBox [...]} makes.
    for (int offset = 0; offset < 3; offset++) for (NSInteger rotation = 0; rotation < 360; rotation += 90)
    for (NSNumber *zoom in @[@0, @0.5, @1.0, @2.0, @4.0]) {
        PDFDocument *document = Document(1); PDFPage *page = [document pageAtIndex:0];
        if (offset == 1) [page setBounds:NSMakeRect(100, 600, 400, 200) forBox:kPDFDisplayBoxMediaBox];
        if (offset) [page setBounds:offset == 1 ? NSMakeRect(100, 600, 400, 200) : NSMakeRect(150, 600, 300, 200) forBox:kPDFDisplayBoxCropBox];
        page.rotation = rotation; view.document = document;
        if (zoom.doubleValue == 0) view.autoScales = YES; else { view.autoScales = NO; view.scaleFactor = zoom.doubleValue; }
        Pump();
        [view goToRect:NSMakeRect(NSMidX(Formula) - 5, NSMidY(Formula) - 5, 10, 10) onPage:page]; Pump();
        context = [NSString stringWithFormat:@"offset %d rotation %ld zoom %.2f", offset, (long)rotation, view.scaleFactor];
        NSPoint formula = [view convertPoint:NSMakePoint(NSMidX(Formula), NSMidY(Formula)) fromPage:page];
        NSPoint paper = [view convertPoint:offset ? NSMakePoint(170, 630) : NSMakePoint(NSMidX(Formula), NSMinY(Formula) - 60) fromPage:page];
        Check(Glass(view, formula, formula, 0, 1, 0), @"Glass shown");
        Check(DarkAt(drawn, .5, .5), @"Lens centre shows the formula under the pointer");
        NSRect onScreen = LensOnScreen(view);
        Check(fabs(NSWidth(onScreen) - 150) < .5 && fabs(NSHeight(onScreen) - 100) < .5,
              [NSString stringWithFormat:@"Lens is 150x100 on screen at any zoom (%@)", NSStringFromRect(onScreen)]);
        Check(fabs(Magnification(view, page) - 1.5) < .05, [NSString stringWithFormat:@"Glass magnifies the screen 150%% (%.2f)", Magnification(view, page)]);
        if ([view mouse:paper inRect:view.visibleRect]) {
            Check(Glass(view, paper, paper, 0, 1, 0) && !DarkAt(drawn, .5, .5), @"Lens centre shows paper away from the formula");
        }
        cases++;
    }
    Check(cases >= 54, [NSString stringWithFormat:@"Enough position cases (%lu)", (unsigned long)cases]);

    // Modifier keys, larger lenses, and the largest magnification.
    context = @"keys and lenses";
    view.document = Document(1); view.autoScales = NO; view.scaleFactor = 0.7; Pump();
    PDFPage *page = [view.document pageAtIndex:0];
    [view goToRect:NSMakeRect(NSMidX(Formula) - 5, NSMidY(Formula) - 5, 10, 10) onPage:page]; Pump();
    NSPoint formula = [view convertPoint:NSMakePoint(NSMidX(Formula), NSMidY(Formula)) fromPage:page];
    NSEventModifierFlags keys[] = {NSEventModifierFlagCommand, NSEventModifierFlagOption, NSEventModifierFlagControl,
        NSEventModifierFlagShift | NSEventModifierFlagCommand, NSEventModifierFlagShift | NSEventModifierFlagOption, NSEventModifierFlagShift};
    CGFloat factors[] = {2.0, 2.5, 3.0, 1.0, 0.66666, 1.5};
    for (int k = 0; k < 6; k++) {
        Check(Glass(view, formula, formula, 0, 1, keys[k]), @"Glass with modifier keys");
        Check(fabs(Magnification(view, page) - factors[k]) < .05,
              [NSString stringWithFormat:@"Modifier keys %d: %.2f, expected %.2f", k, Magnification(view, page), factors[k]]);
    }
    Check(Glass(view, formula, formula, 0, 2, 0) && fabs(NSWidth(LensOnScreen(view)) - 380) < .5, @"Double click: large lens");
    Check(Glass(view, formula, formula, 1, 1, 0) && fabs(NSWidth(LensOnScreen(view)) - 380) < .5, @"Magnify (Large) tool: large lens");

    // An enlarged Preview: the glass works, and draws only the lens. An image of the
    // whole page at the glass's magnification took about 1 GB at 800% and 4 GB at 1600%.
    for (NSNumber *zoom in @[@8.0, @16.0]) {
        context = [NSString stringWithFormat:@"enlarged %@", zoom];
        view.scaleFactor = zoom.doubleValue; Pump();
        [view goToRect:NSMakeRect(NSMidX(Formula) - 5, NSMidY(Formula) - 5, 10, 10) onPage:page]; Pump();
        formula = [view convertPoint:NSMakePoint(NSMidX(Formula), NSMidY(Formula)) fromPage:page];
        double before = FootprintMB();
        Check(Glass(view, formula, formula, 0, 1, 0), @"Glass shown at any magnification");
        double grown = FootprintMB() - before;
        Check(DarkAt(drawn, .5, .5), @"Lens shows the formula under the pointer");
        Check(fabs(Magnification(view, page) - 1.5) < .05, @"Glass magnifies the screen 150%");
        Check(grown < 200, [NSString stringWithFormat:@"The glass draws only the lens (%.0f MB more)", grown]);
    }
    view.scaleFactor = 0.7; Pump();

    // Dragging from one page onto the next shows the next page.
    context = @"two pages";
    view.document = Document(2); view.autoScales = NO; view.scaleFactor = 0.5; Pump();
    PDFPage *first = [view.document pageAtIndex:0], *second = [view.document pageAtIndex:1];
    [view goToRect:NSMakeRect(0, 0, 595, 200) onPage:second]; Pump();
    NSPoint onFirst = [view convertPoint:NSMakePoint(300, 100) fromPage:first];
    NSPoint onMark = [view convertPoint:NSMakePoint(NSMidX(Mark), NSMidY(Mark)) fromPage:second];
    if (![view mouse:onFirst inRect:view.visibleRect]) onFirst = [view convertPoint:NSMakePoint(300, 40) fromPage:first];
    Check([view mouse:onMark inRect:view.visibleRect], @"Fixture: mark on page 2 visible");
    Check(Glass(view, onFirst, onMark, 0, 1, 0), @"Glass while dragging");
    Check(DarkAt(drawn, .5, .5), @"Lens shows page 2 after dragging onto it");
    printf("PASS: Preview window magnifying glass position, size, magnification, keys and pages (%lu checks)\n", (unsigned long)checks);
}}
'''.replace('METHODS', methods)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory(prefix='TeXShop-preview-magnifier-') as tmp:
    tmp = Path(tmp)
    app = tmp/'MagnifierTest.app'; mac = app/'Contents/MacOS'; mac.mkdir(parents=True)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.texshop.MagnifierTest.'+tmp.name,
        'CFBundleExecutable': 'MagnifierTest', 'CFBundlePackageType': 'APPL', 'LSUIElement': True}))
    (tmp/'Test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', *include_args(root), '-I'+str(root/'Tests'),
                    '-framework', 'Cocoa', '-framework', 'Quartz', str(tmp/'Test.m'), str(root/'Sources/Preview/OverView.m'),
                    '-o', str(mac/'MagnifierTest')], check=True)
    home = tmp/'Home'; (home/'Library/Preferences').mkdir(parents=True)
    try:
        result = subprocess.run([str(mac/'MagnifierTest')], env={**os.environ, 'CFFIXED_USER_HOME': str(home)},
                                capture_output=True, text=True, timeout=180)
        sys.stdout.write(result.stdout); sys.stderr.write(result.stderr)
        sys.exit(result.returncode)
    finally:
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(app)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
