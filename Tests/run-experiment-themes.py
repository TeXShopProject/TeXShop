#!/usr/bin/env python3
"""Exercise Experiment theme hooks and the actual PDFKit toolbar without showing windows.

The PDF view is compiled from its complete production implementation. The source view's
new lifecycle/theme methods run on NSTextView; legacy completion dependencies are omitted.
Defaults stay in memory, and no window uses frame autosaving, including failing mutations.
"""
from pathlib import Path
import argparse, os, subprocess, tempfile
from source_tree import include_args
from experiment_preview_source import prelude as experiment_preview_prelude, sources as experiment_preview_sources
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['source-hook', 'pdf-hook', 'defaults-hook', 'reload-hook', 'menu-validation', 'filter-gamma', 'source-alpha', 'preview-alpha', 'paper-invert', 'paper-print', 'paper-lens', 'scroll-appearance', 'bar-appearance', 'bar-filters', 'document-filters', 'page-hook'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root/'Sources/Editor/ScrapTextView.m').read_text(encoding='latin1')
source = source[source.index('- (void)updateExperimentColors:'):source.index('- (void)awakeFromNib')]
pdf = (root/'Sources/Preview/ScrapPDFKitView.m').read_text()
for header in ['globals.h', 'TSDocument.h', 'TSEncodingSupport.h']:
    pdf = pdf.replace(f'#import "{header}"', '')
if args.mutation == 'source-hook':
    source = source.replace('[self updateExperimentColors:nil];', '')
if args.mutation == 'pdf-hook':
    pdf = pdf.replace('[self updateExperimentColors:nil];', '')
if args.mutation == 'defaults-hook':
    old = '[center addObserver:self selector:@selector(experimentDefaultsChanged:)\n        name:NSUserDefaultsDidChangeNotification object:SUD];'
    assert pdf.count(old) == 1, 'defaults-hook'
    pdf = pdf.replace(old, '')
if args.mutation == 'reload-hook':
    start, end = pdf.index('- (void)setDocument:'), pdf.index('- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowed')
    pdf = pdf[:start] + '- (void)setDocument:(PDFDocument *)document { [super setDocument:document]; }\n' + pdf[end:]
if args.mutation == 'menu-validation':
    pdf = pdf.replace('return [super validateMenuItem:item];', 'return YES;')
if args.mutation == 'source-alpha':
    source = source.replace('self.window.alphaValue = TSThemeWindowAlpha(theme, TSThemeSourceAlphaKey);', '')
if args.mutation == 'preview-alpha':
    pdf = pdf.replace('self.window.alphaValue = TSThemeWindowAlpha(theme, TSThemePreviewAlphaKey);', '')
appearance = (root/'Sources/Preview/TSPreviewAppearance.h').read_text()
if args.mutation == 'filter-gamma':
    appearance = appearance.replace('numberWithDouble:1.6', 'numberWithDouble:1.0')
if args.mutation == 'paper-invert':
    appearance = appearance.replace('return TSPreviewShouldInvert(mode, systemAppearance) ? nil : themeColor;', 'return themeColor;')
if args.mutation == 'paper-print':
    pdf = pdf.replace('if (screen) TSFillPreviewPaper(', 'TSFillPreviewPaper(')
if args.mutation == 'paper-lens':
    pdf = pdf.replace('overlay.magnifiedPaperColor = self.previewPaperColor;', '')
if args.mutation == 'scroll-appearance':
    old = '    scrollView.appearance = nil;\n'
    assert appearance.count(old) == 1, args.mutation
    appearance = appearance.replace(old, '    scrollView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];\n', 1)
elif args.mutation == 'bar-appearance':
    old = '            subview.appearance = nil;\n'
    assert appearance.count(old) == 1, args.mutation
    appearance = appearance.replace(old, '            subview.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];\n', 1)
elif args.mutation == 'bar-filters':
    old = '            subview.contentFilters = @[];\n'
    assert appearance.count(old) == 1, args.mutation
    appearance = appearance.replace(old, '            subview.contentFilters = TSPreviewInversionFilters();\n', 1)
elif args.mutation == 'document-filters':
    old = '    documentView.contentFilters = filters;\n'
    assert appearance.count(old) == 1, args.mutation
    appearance = appearance.replace(old, '    documentView.contentFilters = @[];\n', 1)
elif args.mutation == 'page-hook':
    old = '                TSLightenPreviewPageView(subview);\n        });'
    assert appearance.count(old) == 1, args.mutation
    appearance = appearance.replace(old, '                (void)subview;\n        });', 1)
pdf = pdf.replace('#import "TSPreviewAppearance.h"', appearance)
pdf = experiment_preview_prelude(root) + pdf
prefix = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import <Quartz/Quartz.h>
#import "TSColorSupport.h"
#import "TSExperimentTheme.h"
static NSDictionary *liteColors, *darkColors;
@interface ExperimentMemoryDefaults : NSUserDefaults
@property (nonatomic, strong) NSMutableDictionary *values;
@end
@implementation ExperimentMemoryDefaults
- (instancetype)init { self = [super init]; if (self) _values = [NSMutableDictionary dictionary]; return self; }
- (NSInteger)integerForKey:(NSString *)key { return [self.values[key] integerValue]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key {
    self.values[key] = @(value);
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}
@end
static ExperimentMemoryDefaults *testDefaults;
#define SUD testDefaults
#define SourceColorChangedNotification @"SourceColorChanged"
@implementation TSColorSupport
+ (id)sharedInstance { static id instance; if (!instance) instance = [self new]; return instance; }
- (NSColor *)opaqueColorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark
{ return theme[key] ?: (dark ? NSColor.blackColor : NSColor.whiteColor); }
@end
@interface ExperimentSourceFixture : NSTextView
@end
@implementation ExperimentSourceFixture
SOURCE
@end
'''.replace('SOURCE', source)
tests = r'''
static int checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void pump(void) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:.1];
    while (end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
static void settle(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.55]];
}
static PDFDocument *manyPages(int count) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef sink = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 400, 420);
    CGContextRef pdf = CGPDFContextCreate(sink, &box, NULL);
    for (int i = 0; i < count; i++) {
        CGPDFContextBeginPage(pdf, NULL);
        CGContextSetRGBFillColor(pdf, 0, 0, 0, 1);
        CGContextFillRect(pdf, CGRectMake(12, 14, 9, 9));
        CGPDFContextEndPage(pdf);
    }
    CGPDFContextClose(pdf); CGContextRelease(pdf); CGDataConsumerRelease(sink);
    return [[PDFDocument alloc] initWithData:data];
}
static NSSet *pagePointers(PDFView *view) {
    NSMutableSet *set = [NSMutableSet set];
    for (NSView *child in view.documentView.subviews)
        if ([NSStringFromClass(child.class) containsString:@"Page"])
            [set addObject:[NSValue valueWithPointer:(__bridge void *)child]];
    return set;
}
static NSView *frontPage(PDFView *view) {
    NSView *found = nil;
    CGFloat best = 0;
    for (NSView *child in view.documentView.subviews) {
        if (![NSStringFromClass(child.class) containsString:@"Page"]) continue;
        NSRect coverage = NSIntersectionRect([view convertRect:child.bounds fromView:child], view.bounds);
        CGFloat area = coverage.size.width * coverage.size.height;
        if (area > best) { best = area; found = child; }
    }
    return found;
}
static void turnWheel(PDFView *view) {
    NSView *hit = frontPage(view);
    check(hit != nil, @"the wheel hits a page in the Experiment");
    for (int i = 0; i < 12; i++) {
        CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, -10);
        NSEvent *wheel = [NSEvent eventWithCGEvent:event];
        [hit scrollWheel:wheel];
        CFRelease(event);
        hit = frontPage(view) ?: hit;
    }
}
static NSWindow *window(NSView *view) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,480)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    w.contentView = view;
    return w;
}
static PDFDocument *document(void) {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(400,600)];
    [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,400,600));
    [@"Experiment" drawAtPoint:NSMakePoint(20,500) withAttributes:@{NSForegroundColorAttributeName:NSColor.blackColor}];
    [image unlockFocus];
    PDFDocument *doc = [PDFDocument new];
    [doc insertPage:[[PDFPage alloc] initWithImage:image] atIndex:0];
    return doc;
}
static NSString *Match(NSAppearance *appearance) {
    return [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
}
static BOOL inverted(ScrapPDFKitView *view) {
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    if (scroll.appearance != nil || scroll.contentFilters.count != 0) return NO;
    if (scroll.contentView.appearance != nil || scroll.contentView.contentFilters.count != 0) return NO;
    if (scroll.documentView.appearance != nil || scroll.documentView.contentFilters.count != 3) return NO;
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    NSString *system = Match(NSApp.effectiveAppearance);
    BOOL page = NO, gutter = NO, scroller = NO;
    for (NSView *child in scroll.documentView.subviews) {
        if ([NSStringFromClass(child.class) containsString:@"Page"]) page = YES;
        if (child.appearance != light || child.contentFilters.count != 0) return NO;
    }
    for (NSView *subview in scroll.subviews) {
        if ([subview isKindOfClass:NSScroller.class]) {
            scroller = YES;
            if (subview.appearance != nil || subview.contentFilters.count != 0) return NO;
            if (![Match(subview.effectiveAppearance) isEqual:system]) return NO;
        } else if ([NSStringFromClass(subview.class) containsString:@"Background"] &&
                   ![NSStringFromClass(subview.class) containsString:@"Pocket"]) {
            gutter = YES;
            if (subview.appearance != light || subview.contentFilters.count != 3) return NO;
        }
    }
    return page && gutter && scroller;
}
static void checkPages(NSScrollView *scroll, NSUInteger filters, NSString *what) {
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    BOOL page = NO;
    check(scroll.documentView.appearance == nil && scroll.documentView.contentFilters.count == filters,
          [what stringByAppendingString:@": the document view carries the preview's filters"]);
    for (NSView *child in scroll.documentView.subviews) {
        if ([NSStringFromClass(child.class) containsString:@"Page"]) page = YES;
        check(child.appearance == light && child.contentFilters.count == 0,
              [what stringByAppendingString:@": the page keeps the preview appearance"]);
    }
    check(page, [what stringByAppendingString:@": a page view is present"]);
}
static void checkSystemScroller(NSScrollView *scroll, NSString *what) {
    NSString *system = Match(NSApp.effectiveAppearance);
    BOOL found = NO;
    for (NSView *subview in scroll.subviews) {
        if (![subview isKindOfClass:NSScroller.class]) continue;
        found = YES;
        check(subview.appearance == nil && subview.contentFilters.count == 0,
              [what stringByAppendingString:@": the scroller is window chrome"]);
        check([Match(subview.effectiveAppearance) isEqual:system],
              [what stringByAppendingString:@": the scroller follows the system"]);
    }
    check(found, [what stringByAppendingString:@": a scroller is present"]);
}
static NSArray *pageInversionFilters(NSScrollView *scroll) {
    return scroll.documentView.contentFilters;
}
// Page views that PDFKit adds after a new document are light from the moment they exist,
// however late they come: checked every 10 ms for a second, not once at a set time.
static void checkPagesAsTheyCome(PDFView *view, NSUInteger filters, NSString *what) {
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    BOOL page = NO, ok = YES, filtered = YES;
    for (int i = 0; i < 100; i++) {
        if (view.documentView.contentFilters.count != filters) filtered = NO;
        for (NSView *child in view.documentView.subviews) {
            if ([NSStringFromClass(child.class) containsString:@"Page"]) page = YES;
            if (child.appearance != light || child.contentFilters.count) ok = NO;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    check(page, [what stringByAppendingString:@": page views come"]);
    check(filtered, [what stringByAppendingString:@": the document view has the filters from the start"]);
    check(ok, [what stringByAppendingString:@": every page view is light as soon as it exists"]);
}
// A page like TeX output: transparent, with a little black mark near a corner.
static PDFDocument *transparentDocument(void) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0,0,400,600); CGContextRef pdf = CGPDFContextCreate(consumer, &box, NULL);
    CGPDFContextBeginPage(pdf, NULL); CGContextSetRGBFillColor(pdf,0,0,0,1); CGContextFillRect(pdf, CGRectMake(10,10,20,20));
    CGPDFContextEndPage(pdf); CGPDFContextClose(pdf); CGContextRelease(pdf); CGDataConsumerRelease(consumer);
    return [[PDFDocument alloc] initWithData:data];
}
// The page as the view draws it on screen (a bitmap) and in a PDF, as in printing.
static NSColor *screenPaper(ScrapPDFKitView *view) {
    PDFPage *page = [view.document pageAtIndex:0];
    NSRect box = [page boundsForBox:view.displayBox];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, NSWidth(box), NSHeight(box), 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    [view drawPage:page toContext:context];
    unsigned char *pixel = (unsigned char *)CGBitmapContextGetData(context) + (CGBitmapContextGetHeight(context)/2)*CGBitmapContextGetBytesPerRow(context) + 4*4;
    NSColor *color = pixel[3] ? [NSColor colorWithSRGBRed:pixel[0]/255. green:pixel[1]/255. blue:pixel[2]/255. alpha:1] : nil;
    CGContextRelease(context);
    return color;
}
static BOOL printedWithPaper(ScrapPDFKitView *view) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0,0,400,600); CGContextRef pdf = CGPDFContextCreate(consumer, &box, NULL);
    CGPDFContextBeginPage(pdf, NULL); [view drawPage:[view.document pageAtIndex:0] toContext:pdf]; CGPDFContextEndPage(pdf);
    CGPDFContextClose(pdf); CGContextRelease(pdf); CGDataConsumerRelease(consumer);
    PDFDocument *printed = [[PDFDocument alloc] initWithData:data];
    NSImage *image = [[NSImage alloc] initWithData:[[printed pageAtIndex:0] dataRepresentation]];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:60 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [image drawInRect:NSMakeRect(0,0,40,60)]; [NSGraphicsContext restoreGraphicsState];
    // The page is transparent, so a print with the paper is opaque at its edge.
    return [rep colorAtX:1 y:30].alphaComponent > .5;
}
static BOOL same(NSColor *a, NSColor *b) {
    if (!a || !b) return a == b;
    a = [a colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; b = [b colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return fabs(a.redComponent-b.redComponent)<.02 && fabs(a.greenComponent-b.greenComponent)<.02 && fabs(a.blueComponent-b.blueComponent)<.02;
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    testDefaults = [ExperimentMemoryDefaults new];
    liteColors = @{@"EditorBackground":NSColor.whiteColor, @"EditorText":NSColor.blackColor,
        @"EditorInsertionPoint":NSColor.blueColor, @"PreviewBackground":NSColor.grayColor,
        @"SourceAlpha":@[@0,@0,@0,@.92], @"PreviewAlpha":@[@0,@0,@0,@.93]};
    darkColors = @{@"EditorBackground":NSColor.blackColor, @"EditorText":NSColor.whiteColor,
        @"EditorInsertionPoint":NSColor.cyanColor, @"PreviewBackground":NSColor.darkGrayColor,
        @"SourceAlpha":@[@0,@0,@0,@.82], @"PreviewAlpha":@[@0,@0,@0,@.83]};
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    ExperimentSourceFixture *editor = [[ExperimentSourceFixture alloc] initWithFrame:NSMakeRect(0,0,600,480)];
    editor.string = @"source text";
    NSWindow *sourceWindow = window(editor);
    ScrapPDFKitView *pdf = [[ScrapPDFKitView alloc] initWithFrame:NSMakeRect(0,0,600,480)];
    NSWindow *pdfWindow = window(pdf);
    pdf.document = document(); pump();
    check([editor.backgroundColor isEqual:NSColor.whiteColor], @"initial source theme");
    check([editor.insertionPointColor isEqual:NSColor.blueColor], @"initial insertion color");
    check([pdf.previewPaperColor isEqual:NSColor.grayColor] && ![pdf.backgroundColor isEqual:NSColor.grayColor], @"initial preview theme is the paper of light pages, not the area around them");
    check(fabs(sourceWindow.alphaValue-.92)<.001 && fabs(pdfWindow.alphaValue-.93)<.001, @"initial source/PDF transparency");
    check(!inverted(pdf), @"system light pages");
    NSMenuItem *next = [[NSMenuItem alloc] initWithTitle:@"Next" action:@selector(goToNextPage:) keyEquivalent:@""];
    NSMenuItem *previous = [[NSMenuItem alloc] initWithTitle:@"Previous" action:@selector(goToPreviousPage:) keyEquivalent:@""];
    check(![pdf validateMenuItem:next] && ![pdf validateMenuItem:previous], @"single page navigation stays disabled");
    PDFDocument *twoPages = document();
    [twoPages insertPage:[document() pageAtIndex:0] atIndex:1];
    pdf.document = twoPages; pump();
    check([pdf validateMenuItem:next] && ![pdf validateMenuItem:previous], @"first page navigation uses PDFKit validation");
    [pdf goToLastPage:nil]; pump();
    check(![pdf validateMenuItem:next] && [pdf validateMenuItem:previous], @"last page navigation uses PDFKit validation");
    pdf.document = document(); pump();
    NSMenuToolbarItem *appearance = nil;
    for (NSToolbarItem *item in pdfWindow.toolbar.items)
        if ([item.itemIdentifier isEqual:TSPreviewAppearanceToolbarID]) appearance=(id)item;
    check(appearance.menu.numberOfItems == 3, @"actual toolbar contains three choices");
    for (NSMenuItem *choice in appearance.menu.itemArray) {
        check(choice.target == pdf && choice.action == @selector(changePreviewAppearance:), @"menu wiring");
    }
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; pump();
    check([editor.backgroundColor isEqual:NSColor.blackColor] && [editor.textColor isEqual:NSColor.whiteColor], @"source follows system dark");
    check([[editor.textStorage attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:NSColor.whiteColor], @"existing source text recolored");
    check([editor.insertionPointColor isEqual:NSColor.cyanColor], @"dark insertion color");
    check(pdf.previewPaperColor == nil, @"pages shown dark keep PDFKit's paper");
    check(fabs(sourceWindow.alphaValue-.82)<.001 && fabs(pdfWindow.alphaValue-.83)<.001, @"dark transparency");
    // PDFKit creates the page view when the magnification changes.
    if (pdf.documentView.subviews.count == 0) pdf.scaleFactor = MAX(pdf.scaleFactor, 1) * 1.1;
    pump();
    check(inverted(pdf), @"system dark pages are drawn light and then inverted, without the scroll view taking that appearance");
    NSArray *filters = pageInversionFilters(pdf.documentView.enclosingScrollView);
    check([[(CIFilter *)filters[0] name] isEqualToString:@"CIGammaAdjust"] &&
          [[(CIFilter *)filters[1] name] isEqualToString:@"CIColorMatrix"] &&
          [[(CIFilter *)filters[2] name] isEqualToString:@"CIGammaAdjust"], @"inversion filter order");
    check(fabs([[filters[0] valueForKey:@"inputPower"] doubleValue]-.625)<1e-6 &&
          fabs([[filters[2] valueForKey:@"inputPower"] doubleValue]-1.6)<1e-6, @"inversion gamma contract");
    CGFloat factor = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast ? 1.9337 : 1.8972;
    NSArray *vectors = @[@"inputRVector", @"inputGVector", @"inputBVector"];
    CGFloat weights[] = {.2126, .7152, .0722};
    for (NSUInteger row=0; row<3; row++) {
        CIVector *v = [filters[1] valueForKey:vectors[row]];
        for (NSUInteger column=0; column<4; column++) {
            CGFloat expected = column==3 ? 0 : (row==column ? 1 : 0)-weights[column]*factor;
            check(fabs([v valueAtIndex:column]-expected)<1e-6, @"inversion matrix contract");
        }
    }
    CIVector *bias = [filters[1] valueForKey:@"inputBiasVector"];
    CIVector *alpha = [filters[1] valueForKey:@"inputAVector"];
    check(bias.X==1 && bias.Y==1 && bias.Z==1 && bias.W==0 &&
          alpha.X==0 && alpha.Y==0 && alpha.Z==0 && alpha.W==1, @"inversion preserves page alpha");
    [appearance.menu performActionForItemAtIndex:1]; pump();
    check([testDefaults integerForKey:TSPreviewAppearanceModeKey] == 1 && !inverted(pdf), @"Light choice persists and overrides dark system");
    check([pdf.previewPaperColor isEqual:NSColor.darkGrayColor], @"light pages in a dark window take the paper of the dark theme");
    for (NSMenuItem *choice in appearance.menu.itemArray) {
        [pdf validateMenuItem:choice];
        check(choice.state == (choice.tag==1 ? NSControlStateValueOn : NSControlStateValueOff), @"selected choice checkmark");
    }
    [appearance.menu performActionForItemAtIndex:2]; pump();
    check(inverted(pdf) && pdf.previewPaperColor == nil, @"Dark choice leaves the paper to PDFKit");
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua]; pump();
    check(inverted(pdf) && pdf.previewPaperColor == nil, @"dark PDF independent of light window theme");
    // A normal preview writes this same key; Experiment must respond without a local action.
    [testDefaults setInteger:1 forKey:TSPreviewAppearanceModeKey]; pump();
    check(!inverted(pdf) && [pdf.previewPaperColor isEqual:NSColor.grayColor], @"external shared setting change");
    pdf.document = transparentDocument(); pump();
    check(same(screenPaper(pdf), NSColor.grayColor), @"screen drawing fills the page with the paper");
    check(!printedWithPaper(pdf), @"printing and PDF copies keep the page transparent");
    [pdf layoutDocumentView];
    PDFPage *lensPage = [pdf.document pageAtIndex:0];
    NSPoint onPage = [pdf convertPoint:NSMakePoint(200,300) fromPage:lensPage];
    check([pdf pageForPoint:onPage nearest:YES] == lensPage, @"the magnifying glass fixture points at the page");
    [pdf showExperimentMagnifierAt:onPage level:1 modifiers:0];
    check([pdf.experimentOverlayView.magnifiedPaperColor isEqual:NSColor.grayColor], @"the magnifying glass shows the same paper");
    [pdf hideExperimentMagnifier];
    [testDefaults setInteger:2 forKey:TSPreviewAppearanceModeKey]; pump();
    check(inverted(pdf), @"external dark shared setting change");
    check(screenPaper(pdf) == nil, @"pages shown dark are not filled with the theme's paper");
    NSScrollView *replaced = pdf.documentView.enclosingScrollView;
    for (NSView *subview in replaced.subviews)
        if ([NSStringFromClass(subview.class) containsString:@"Background"] &&
            ![NSStringFromClass(subview.class) containsString:@"Pocket"])
            subview.contentFilters = @[];
    pdf.document = document(); pump();
    BOOL gutterRestored = NO;
    replaced = pdf.documentView.enclosingScrollView;
    for (NSView *subview in replaced.subviews)
        if ([NSStringFromClass(subview.class) containsString:@"Background"] &&
            ![NSStringFromClass(subview.class) containsString:@"Pocket"])
            gutterRestored = subview.contentFilters.count == 3 && subview.appearance == [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    check(gutterRestored && replaced.appearance == nil && replaced.contentView.appearance == nil,
          @"page appearance reapplied after document replacement");
    if (pdf.documentView.subviews.count == 0) pdf.scaleFactor = MAX(pdf.scaleFactor, 1) * 1.1;
    pump();
    check(inverted(pdf), @"the new document's pages take the preview appearance");
    [testDefaults setInteger:1 forKey:TSPreviewAppearanceModeKey]; pump();
    NSDictionary *custom = @{@"EditorBackground":NSColor.yellowColor, @"EditorText":NSColor.purpleColor,
        @"EditorInsertionPoint":NSColor.redColor, @"PreviewBackground":NSColor.orangeColor,
        @"SourceAlpha":@[@0,@0,@0,@.7], @"PreviewAlpha":@[@0,@0,@0,@.8]};
    [NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:nil userInfo:custom];
    check([editor.backgroundColor isEqual:NSColor.yellowColor] && [editor.textColor isEqual:NSColor.purpleColor], @"live source theme edit");
    check([pdf.previewPaperColor isEqual:NSColor.orangeColor], @"live preview theme edit");
    check(fabs(sourceWindow.alphaValue-.7)<.001 && fabs(pdfWindow.alphaValue-.8)<.001, @"live transparency edit");
    [NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:nil];
    check([editor.backgroundColor isEqual:NSColor.whiteColor] && [pdf.previewPaperColor isEqual:NSColor.grayColor], @"theme cancel restores saved colors");
    [testDefaults setInteger:2 forKey:TSPreviewAppearanceModeKey]; pump();
    for(id invalid in @[@"bad",NSNull.null,@[@0],@[@0,@0,@0,@"0.5"],@[@0,@0,@0,@(-0.1)],@[@0,@0,@0,@1.1],@[@0,@0,@0,@(NAN)],@[@0,@0,@0,@(INFINITY)]]){
        NSMutableDictionary *bad=[custom mutableCopy];bad[@"SourceAlpha"]=invalid;bad[@"PreviewAlpha"]=invalid;
        [NSNotificationCenter.defaultCenter postNotificationName:SourceColorChangedNotification object:nil userInfo:bad];
        check(sourceWindow.alphaValue==1 && pdfWindow.alphaValue==1,@"invalid source and preview opacity uses the common opaque fallback");
    }
    // A later Experiment must adopt the persisted preference and theme immediately.
    ScrapPDFKitView *secondPDF = [[ScrapPDFKitView alloc] initWithFrame:NSMakeRect(0,0,600,480)];
    NSWindow *secondWindow = window(secondPDF); secondPDF.document=document(); pump();
    if (secondPDF.documentView.subviews.count == 0) secondPDF.scaleFactor = MAX(secondPDF.scaleFactor, 1) * 1.1;
    pump();
    check(inverted(secondPDF), @"new preview inherits shared appearance");
    [appearance.menu performActionForItemAtIndex:0]; pump();
    check(!inverted(pdf) && !inverted(secondPDF), @"System choice propagates to all Experiment previews");
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]; pump();
    check(inverted(pdf) && inverted(secondPDF), @"System choice follows later system change");
    // A horizontal scroller PDFKit creates only after the appearance was chosen.
    {
        ScrapPDFKitView *zoom = [[ScrapPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 750, 550)];
        NSWindow *zoomWindow = window(zoom);
        zoom.displayMode = kPDFDisplaySinglePage;
        zoom.autoScales = NO;
        zoom.document = document();
        zoom.scaleFactor = 0.5;
        pump();
        [testDefaults setInteger:2 forKey:TSPreviewAppearanceModeKey];
        pump();
        NSScrollView *scroll = zoom.documentView.enclosingScrollView;
        check(!scroll.hasHorizontalScroller, @"Experiment starts without a horizontal scroller");
        zoom.scaleFactor = 4;
        checkPages(scroll, 3, @"magnifying the inverted Experiment");
        pump();
        check(scroll.hasHorizontalScroller, @"a horizontal scroller appears while the Experiment is inverted");
        checkSystemScroller(scroll, @"magnifying the inverted Experiment");
        checkPages(scroll, 3, @"magnifying the inverted Experiment");
        check(scroll.appearance == nil && scroll.contentFilters.count == 0, @"the new scroller does not put the appearance on the scroll view");
        for (NSView *subview in scroll.subviews)
            if (TSPreviewSubviewIsToolbarPocket(subview))
                check(subview.appearance == nil && subview.contentFilters.count == 0, @"the pocket stays untouched when the scroller appears");
        [zoomWindow setContentSize:NSMakeSize(160, 480)];
        pump();
        checkSystemScroller(scroll, @"narrowing the inverted Experiment");
        checkPages(scroll, 3, @"narrowing the inverted Experiment");
        ScrapPDFKitView *plain = [[ScrapPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 750, 550)];
        NSWindow *plainWindow = window(plain);
        plain.displayMode = kPDFDisplaySinglePage;
        plain.autoScales = NO;
        plain.document = document();
        plain.scaleFactor = 0.5;
        pump();
        [testDefaults setInteger:1 forKey:TSPreviewAppearanceModeKey];
        pump();
        plain.scaleFactor = 4;
        NSScrollView *plainScroll = plain.documentView.enclosingScrollView;
        checkPages(plainScroll, 0, @"magnifying a light Experiment");
        pump();
        check(plainScroll.hasHorizontalScroller, @"a horizontal scroller appears on a light Experiment");
        checkSystemScroller(plainScroll, @"magnifying a light Experiment");
        checkPages(plainScroll, 0, @"magnifying a light Experiment");
        [zoomWindow close];
        [plainWindow close];
        NSWindow *spreadWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 550)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
            backing:NSBackingStoreBuffered defer:NO];
        spreadWindow.releasedWhenClosed = NO;
        spreadWindow.toolbarStyle = NSWindowToolbarStyleExpanded;
        spreadWindow.toolbar = [[NSToolbar alloc] initWithIdentifier:@"experiment-spread"];
        ScrapPDFKitView *spread = [[ScrapPDFKitView alloc] initWithFrame:spreadWindow.contentView.bounds];
        spread.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        spread.autoScales = NO;
        spread.displayMode = kPDFDisplaySinglePage;
        PDFDocument *pair = [PDFDocument new];
        for (int i = 0; i < 2; i++) {
            NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(410, 380)];
            [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, 410, 380)); [image unlockFocus];
            [pair insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
        }
        [spreadWindow.contentView addSubview:spread];
        spread.document = pair;
        spread.scaleFactor = 1;
        [testDefaults setInteger:2 forKey:TSPreviewAppearanceModeKey];
        pump();
        NSScrollView *spreadScroll = spread.documentView.enclosingScrollView;
        NSView *spreadClip = spreadScroll.contentView;
        check(!spreadScroll.hasHorizontalScroller, @"Experiment Two Pages starts without a horizontal scroller");
        NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSMakePoint(350, 300)
            modifierFlags:0 timestamp:0 windowNumber:spreadWindow.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
        NSMenu *spreadMenu = [spread menuForEvent:click];
        NSMenuItem *twoPages = nil;
        for (NSMenuItem *item in spreadMenu.itemArray)
            if ([item.title isEqualToString:@"Two Pages"]) twoPages = item;
        check(twoPages.action == NSSelectorFromString(@"_setDoublePage:"), @"the Experiment context menu offers Two Pages");
        [NSApp sendAction:twoPages.action to:twoPages.target ?: spread from:twoPages];
        checkPages(spreadScroll, 3, @"Two Pages from the Experiment context menu");
        pump();
        check(spread.documentView.enclosingScrollView.contentView == spreadClip, @"Two Pages keeps the Experiment clip view");
        check(spreadScroll.hasHorizontalScroller, @"Two Pages from the Experiment context menu shows a horizontal scroller");
        checkSystemScroller(spreadScroll, @"Two Pages from the Experiment context menu");
        checkPages(spreadScroll, 3, @"Two Pages from the Experiment context menu");
        ScrapPDFKitView *wide = [[ScrapPDFKitView alloc] initWithFrame:spreadWindow.contentView.bounds];
        wide.autoScales = NO;
        wide.displayMode = kPDFDisplaySinglePage;
        PDFDocument *steps = [PDFDocument new];
        CGFloat widths[2] = {410, 1100};
        for (int i = 0; i < 2; i++) {
            NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(widths[i], 380)];
            [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, widths[i], 380)); [image unlockFocus];
            [steps insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
        }
        [spreadWindow.contentView addSubview:wide];
        wide.document = steps;
        wide.scaleFactor = 1;
        [wide goToFirstPage:nil];
        pump();
        check(!wide.documentView.enclosingScrollView.hasHorizontalScroller, @"the Experiment next page starts without a horizontal scroller");
        [wide goToNextPage:nil];
        checkPages(wide.documentView.enclosingScrollView, 3, @"turning to a wider Experiment page");
        pump();
        checkSystemScroller(wide.documentView.enclosingScrollView, @"turning to a wider Experiment page");
        checkPages(wide.documentView.enclosingScrollView, 3, @"turning to a wider Experiment page");
        ScrapPDFKitView *row = [[ScrapPDFKitView alloc] initWithFrame:spreadWindow.contentView.bounds];
        row.autoScales = NO;
        row.displayMode = kPDFDisplaySinglePageContinuous;
        row.document = pair;
        row.scaleFactor = 1;
        [spreadWindow.contentView addSubview:row];
        pump();
        check(!row.documentView.enclosingScrollView.hasHorizontalScroller, @"a vertical Experiment row starts without a horizontal scroller");
        row.displayDirection = kPDFDisplayDirectionHorizontal;
        checkPages(row.documentView.enclosingScrollView, 3, @"laying Experiment pages in a row");
        pump();
        checkSystemScroller(row.documentView.enclosingScrollView, @"laying Experiment pages in a row");
        checkPages(row.documentView.enclosingScrollView, 3, @"laying Experiment pages in a row");
        NSData *stepData = steps.dataRepresentation;
        PDFDocument *destDoc = [[PDFDocument alloc] initWithData:stepData];
        PDFDestination *widePoint = [[PDFDestination alloc] initWithPage:[destDoc pageAtIndex:1] atPoint:NSMakePoint(30, 45)];
        ScrapPDFKitView *dest = [[ScrapPDFKitView alloc] initWithFrame:spreadWindow.contentView.bounds];
        dest.autoScales = NO;
        dest.displayMode = kPDFDisplaySinglePage;
        [spreadWindow.contentView addSubview:dest];
        dest.document = destDoc;
        dest.scaleFactor = 1;
        [dest goToFirstPage:nil];
        pump();
        check(!dest.documentView.enclosingScrollView.hasHorizontalScroller, @"the Experiment destination starts without a horizontal scroller");
        [dest goToDestination:widePoint];
        checkPages(dest.documentView.enclosingScrollView, 3, @"an Experiment destination on a wider page");
        pump();
        checkSystemScroller(dest.documentView.enclosingScrollView, @"an Experiment destination on a wider page");
        checkPages(dest.documentView.enclosingScrollView, 3, @"an Experiment destination on a wider page");
        check(dest.canGoBack, @"the Experiment destination is in the back history");
        [dest goBack:nil];
        [dest goForward:nil];
        pump();
        checkSystemScroller(dest.documentView.enclosingScrollView, @"going forward in the Experiment");
        checkPages(dest.documentView.enclosingScrollView, 3, @"going forward in the Experiment");
        PDFDocument *linkDoc = [[PDFDocument alloc] initWithData:stepData];
        PDFDestination *linkPoint = [[PDFDestination alloc] initWithPage:[linkDoc pageAtIndex:1] atPoint:NSMakePoint(30, 45)];
        ScrapPDFKitView *linked = [[ScrapPDFKitView alloc] initWithFrame:spreadWindow.contentView.bounds];
        linked.autoScales = NO;
        linked.displayMode = kPDFDisplaySinglePage;
        [spreadWindow.contentView addSubview:linked];
        linked.document = linkDoc;
        linked.scaleFactor = 1;
        [linked goToFirstPage:nil];
        pump();
        PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(10, 10, 60, 20) forType:PDFAnnotationSubtypeLink withProperties:nil];
        link.action = [[PDFActionGoTo alloc] initWithDestination:linkPoint];
        [[linkDoc pageAtIndex:0] addAnnotation:link];
        [linked performAction:link.action];
        pump();
        checkSystemScroller(linked.documentView.enclosingScrollView, @"an Experiment internal link");
        checkPages(linked.documentView.enclosingScrollView, 3, @"an Experiment internal link");
        PDFDocument *boxDoc = [[PDFDocument alloc] initWithData:stepData];
        ScrapPDFKitView *box = [[ScrapPDFKitView alloc] initWithFrame:spreadWindow.contentView.bounds];
        box.autoScales = NO;
        box.displayMode = kPDFDisplaySinglePage;
        [spreadWindow.contentView addSubview:box];
        box.document = boxDoc;
        box.scaleFactor = 1;
        [box goToFirstPage:nil];
        pump();
        [box goToRect:NSMakeRect(40, 35, 70, 10) onPage:[boxDoc pageAtIndex:1]];
        pump();
        checkSystemScroller(box.documentView.enclosingScrollView, @"an Experiment rectangle jump");
        checkPages(box.documentView.enclosingScrollView, 3, @"an Experiment rectangle jump");
        NSMutableData *textPDF = [NSMutableData data];
        CGDataConsumerRef sink = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)textPDF);
        CGRect media = CGRectMake(0, 0, 410, 380);
        CGContextRef drawn = CGPDFContextCreate(sink, &media, NULL);
        for (int i = 0; i < 2; i++) {
            CGRect pageBox = CGRectMake(0, 0, i ? 1100 : 410, 380);
            NSDictionary *info = @{(__bridge NSString *)kCGPDFContextMediaBox: [NSData dataWithBytes:&pageBox length:sizeof(pageBox)]};
            CGPDFContextBeginPage(drawn, (__bridge CFDictionaryRef)info);
            CGContextSelectFont(drawn, "Helvetica", 18, kCGEncodingMacRoman);
            CGContextSetRGBFillColor(drawn, 0, 0, 0, 1);
            CGContextShowTextAtPoint(drawn, 40, 40, "Wide page", 9);
            CGPDFContextEndPage(drawn);
        }
        CGPDFContextClose(drawn); CGContextRelease(drawn); CGDataConsumerRelease(sink);
        PDFDocument *words = [[PDFDocument alloc] initWithData:textPDF];
        ScrapPDFKitView *picked = [[ScrapPDFKitView alloc] initWithFrame:spreadWindow.contentView.bounds];
        picked.autoScales = NO;
        picked.displayMode = kPDFDisplaySinglePage;
        [spreadWindow.contentView addSubview:picked];
        picked.document = words;
        picked.scaleFactor = 1;
        [picked goToFirstPage:nil];
        pump();
        PDFSelection *selection = [[words pageAtIndex:1] selectionForRange:NSMakeRange(0, 4)];
        check(selection.string.length > 0, @"the Experiment wider page has text to select");
        [picked goToSelection:selection];
        pump();
        checkSystemScroller(picked.documentView.enclosingScrollView, @"an Experiment selection jump");
        checkPages(picked.documentView.enclosingScrollView, 3, @"an Experiment selection jump");
        [testDefaults setInteger:1 forKey:TSPreviewAppearanceModeKey];
        pump();
        PDFDocument *plainDoc = [[PDFDocument alloc] initWithData:stepData];
        PDFDestination *plainPoint = [[PDFDestination alloc] initWithPage:[plainDoc pageAtIndex:1] atPoint:NSMakePoint(30, 45)];
        PDFAnnotation *plainLink = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(10, 10, 60, 20) forType:PDFAnnotationSubtypeLink withProperties:nil];
        plainLink.action = [[PDFActionGoTo alloc] initWithDestination:plainPoint];
        [[plainDoc pageAtIndex:0] addAnnotation:plainLink];
        ScrapPDFKitView *linkedPlain = [[ScrapPDFKitView alloc] initWithFrame:spreadWindow.contentView.bounds];
        linkedPlain.autoScales = NO;
        linkedPlain.displayMode = kPDFDisplaySinglePage;
        [spreadWindow.contentView addSubview:linkedPlain];
        linkedPlain.document = plainDoc;
        linkedPlain.scaleFactor = 1;
        [linkedPlain goToFirstPage:nil];
        pump();
        [linkedPlain performAction:plainLink.action];
        pump();
        checkSystemScroller(linkedPlain.documentView.enclosingScrollView, @"an Experiment internal link on a light preview");
        checkPages(linkedPlain.documentView.enclosingScrollView, 0, @"an Experiment internal link on a light preview");
        [spreadWindow close];
    }
    [testDefaults setInteger:2 forKey:TSPreviewAppearanceModeKey];
    pump();
    pdf.displayMode = kPDFDisplaySinglePageContinuous;
    pdf.document = manyPages(12);
    pdf.scaleFactor = 1;
    [pdf goToFirstPage:nil];
    if (pdf.documentView.subviews.count == 0) pdf.scaleFactor = 1.1;
    settle();
    check(inverted(pdf), @"the Experiment's first pages are inverted");
    NSSet *seen = pagePointers(pdf);
    turnWheel(pdf);
    settle();
    BOOL created = NO;
    for (NSView *child in pdf.documentView.subviews)
        if ([NSStringFromClass(child.class) containsString:@"Page"] &&
            ![seen containsObject:[NSValue valueWithPointer:(__bridge void *)child]]) created = YES;
    check(created, @"scrolling the Experiment creates a page view");
    settle();
    check(inverted(pdf), @"scrolling the Experiment keeps the preview appearance");
    checkSystemScroller(pdf.documentView.enclosingScrollView, @"scrolling the Experiment");
    NSString *typesetPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"texshop-experiment-reload.pdf"];
    NSData *typesetData = [manyPages(8) dataRepresentation];
    check([typesetData writeToFile:typesetPath atomically:YES], @"the Experiment typeset PDF is written");
    [pdf reShowWithPath:typesetPath];
    checkPagesAsTheyCome(pdf, 3, @"reloading the Experiment after typesetting");
    check(pdf.document.pageCount == 8 && inverted(pdf), @"reloading the Experiment after typesetting keeps the preview appearance");
    checkSystemScroller(pdf.documentView.enclosingScrollView, @"reloading the Experiment after typesetting");
    [testDefaults setInteger:1 forKey:TSPreviewAppearanceModeKey];
    pump();
    pdf.document = manyPages(8);
    checkPagesAsTheyCome(pdf, 0, @"replacing the Experiment with a light PDF");
    checkPages(pdf.documentView.enclosingScrollView, 0, @"replacing the Experiment with a light PDF");
    checkSystemScroller(pdf.documentView.enclosingScrollView, @"replacing the Experiment with a light PDF");
    check(TSThemeWindowAlpha(@{}, @"SourceAlpha")==1, @"missing alpha stays opaque");
    check(TSThemeWindowAlpha(@{@"SourceAlpha":@[@0]}, @"SourceAlpha")==1, @"malformed alpha stays opaque");
    check(!sourceWindow.isVisible && !pdfWindow.isVisible && !secondWindow.isVisible, @"no windows displayed");
    [sourceWindow close]; [pdfWindow close]; [secondWindow close];
    printf("PASS: %d Experiment theme and PDF appearance checks\n", checks);
} return 0; }
'''
with tempfile.TemporaryDirectory(prefix='texshop-experiment-themes-') as tmp:
    src, exe = Path(tmp)/'test.m', Path(tmp)/'test'
    src.write_text(prefix + pdf + tests)
    subprocess.run(['xcrun','clang','-I',str(root/'Tests'),'-w','-fobjc-arc','-framework','Cocoa','-framework','Quartz',
        *include_args(root),str(src),*experiment_preview_sources(root),'-o',str(exe)], check=True)
    (Path(tmp)/'home/Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(exe)],env=dict(os.environ,HOME=str(Path(tmp)/'home'),CFFIXED_USER_HOME=str(Path(tmp)/'home')),capture_output=True,text=True,timeout=60)
    if args.mutation:
        assert result.returncode == 1 and 'FAIL:' in result.stderr, result.stdout + result.stderr
        print('PASS: detected', args.mutation)
    else:
        if result.returncode: raise SystemExit(result.stdout + result.stderr)
        print(result.stdout.strip())
