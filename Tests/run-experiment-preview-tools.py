#!/usr/bin/env python3
"""Check the Experiment preview's tools with its complete production source.

Real PDFKit and AppKit toolbars run in windows that are never shown. Defaults
stay in memory, and the general pasteboard is replaced by a private one, so the
user's clipboard is not touched. Mouse tracking loops receive posted events.
"""
from pathlib import Path
import argparse, os, plistlib, subprocess, sys, tempfile
from source_tree import include_args
from experiment_preview_source import prelude, sources

MUTATIONS = {
    'shared-mode': ('    [SUD setInteger:TSExperimentToolModes[index] forKey:ExperimentMouseModeKey];',
                    '    [SUD setInteger:TSExperimentToolModes[index] forKey:PdfKitMouseModeKey];'),
    'keep-band-on-zoom': ('    // The rubber band is drawn at the old scale; select again after zooming.\n    [self clearExperimentSelection];',
                          '    // The rubber band is drawn at the old scale; select again after zooming.'),
    'pdf-as-bitmap': ('    if (type == IMAGE_TYPE_PDF) {', '    if (NO) {'),
    'ink-upside-down': ('NSMinY(bounds) + (height - 1 - maxY) / resolution', 'NSMinY(bounds) + minY / resolution'),
    'scroll-backwards': ('    target.origin.x = origin.x - delta.width * unit;', '    target.origin.x = origin.x + delta.width * unit;'),
    'folded-tools': ('labels:labels target:self action:@selector(changeExperimentTool:)];\n    // Kept as separate buttons: AppKit would size them by their labels and fold them into a menu.\n    group.controlRepresentation = NSToolbarItemGroupControlRepresentationExpanded;\n',
                     'labels:labels target:self action:@selector(changeExperimentTool:)];\n'),
    'glass-in-page-units': ('    [overlay setSelectionRect:[self.documentView convertRect:onScreen fromView:self]];',
                            '    [overlay setSelectionRect:onScreen];'),
    'lens-page-coordinates': ('    [overlay setMagnifiedRect:drawn];',
                              '    [overlay setMagnifiedRect:[self convertRect:NSInsetRect(onScreen, NSWidth(onScreen) / 6, NSHeight(onScreen) / 6) toPage:page]];'),
    'no-tool-sync': ('    [self updateExperimentAppearance:notification];\n    [self syncExperimentToolSelection];',
                     '    [self updateExperimentAppearance:notification];'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
pdf = (root/'Sources/Preview/ScrapPDFKitView.m').read_text()
if args.mutation:
    old, new = MUTATIONS[args.mutation]
    assert pdf.count(old) == 1, args.mutation
    pdf = pdf.replace(old, new)
for header in ['globals.h', 'TSDocument.h', 'TSEncodingSupport.h']:
    pdf = pdf.replace(f'#import "{header}"', '')
pdf = pdf.replace('#import "TSPreviewAppearance.h"', (root/'Sources/Preview/TSPreviewAppearance.h').read_text())
pdf = prelude(root) + pdf

program = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import <Quartz/Quartz.h>
#import "TSColorSupport.h"
#import "TSExperimentTheme.h"
static NSDictionary *liteColors, *darkColors;
@interface NotifyingDefaults : TSMemoryDefaults
@end
@implementation NotifyingDefaults
- (void)setObject:(id)value forKey:(NSString *)key {
    [super setObject:value forKey:key];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}
@end
static NotifyingDefaults *testDefaults;
#define SUD testDefaults
#define SourceColorChangedNotification @"SourceColorChanged"
@implementation TSColorSupport
+ (id)sharedInstance { static id instance; if (!instance) instance = [self new]; return instance; }
- (NSColor *)colorForKey:(NSString *)key fromDictionary:(NSDictionary *)theme isWindowDark:(BOOL)dark { return NSColor.grayColor; }
@end
PDFSOURCE
static NSPasteboard *privateBoard;
static id PrivateGeneralPasteboard(id receiver, SEL selector) { return privateBoard; }
static NSString *context = @"";
static NSUInteger checks;
static void Check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s [%s]\n", message.UTF8String, context.UTF8String); exit(1); }
}
static void Pump(void) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:.1];
    while (end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
// A4; a black "formula" box near the top of page 1 at (220,740)-(380,770).
static const NSRect Formula = {{220, 740}, {160, 30}};
static PDFDocument *Document(NSUInteger pages) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 595, 842);
    CGContextRef c = CGPDFContextCreate(consumer, &box, NULL);
    for (NSUInteger n = 0; n < pages; n++) {
        CGPDFContextBeginPage(c, NULL);
        CGContextSetRGBFillColor(c, 0, 0, 0, 1);
        if (n == 0) CGContextFillRect(c, NSRectToCGRect(Formula));
        CGPDFContextEndPage(c);
    }
    CGPDFContextClose(c); CGContextRelease(c); CGDataConsumerRelease(consumer);
    return [[PDFDocument alloc] initWithData:data];
}
static NSPanel *Panel(NSSize size, ScrapPDFKitView **view) {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(272, 172, size.width, size.height)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskUtilityWindow
        backing:NSBackingStoreBuffered defer:NO];
    panel.releasedWhenClosed = NO;
    ScrapPDFKitView *pdf = [[ScrapPDFKitView alloc] initWithFrame:NSMakeRect(0, -10, size.width, size.height + 10)];
    pdf.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    [panel.contentView addSubview:pdf];
    pdf.document = Document(1); Pump();
    [panel makeKeyAndOrderFront:nil]; Pump();
    *view = pdf;
    return panel;
}
static NSToolbarItemGroup *Group(NSWindow *window, NSString *identifier) {
    for (NSToolbarItem *item in window.toolbar.items)
        if ([item.itemIdentifier isEqualToString:identifier]) return (id)item;
    return nil;
}
static NSClipView *Clip(PDFView *view) { return view.documentView.enclosingScrollView.contentView; }
// The page rectangle visible on screen, in page 1 coordinates.
static NSRect SeenOnPage(ScrapPDFKitView *view) {
    NSRect area = [view experimentVisibleArea];
    NSRect inView = [view convertRect:area fromView:Clip(view)];
    return [view convertRect:inView toPage:[view.document pageAtIndex:0]];
}
static NSPoint ViewPointOfPage(ScrapPDFKitView *view, NSPoint pagePoint) {
    return [view convertPoint:pagePoint fromPage:[view.document pageAtIndex:0]];
}
static NSEvent *Mouse(NSEventType type, NSWindow *window, NSPoint inWindow, NSInteger clicks, NSEventModifierFlags flags) {
    return [NSEvent mouseEventWithType:type location:inWindow modifierFlags:flags timestamp:NSProcessInfo.processInfo.systemUptime
        windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:clicks pressure:1];
}
static void Post(NSEvent *event) { [NSApp postEvent:event atStart:NO]; }
static NSBitmapImageRep *Bitmap(NSData *data) { return [[NSBitmapImageRep alloc] initWithData:data]; }
static BOOL DarkAt(NSBitmapImageRep *rep, CGFloat fx, CGFloat fy) {
    NSColor *color = [[rep colorAtX:(NSInteger)(fx * (rep.pixelsWide - 1)) y:(NSInteger)(fy * (rep.pixelsHigh - 1))]
        colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    return color.brightnessComponent < .3;
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    privateBoard = [NSPasteboard pasteboardWithUniqueName];
    method_setImplementation(class_getClassMethod(NSPasteboard.class, @selector(generalPasteboard)), (IMP)PrivateGeneralPasteboard);
    Check(NSPasteboard.generalPasteboard == privateBoard, @"The user's clipboard is not used");
    testDefaults = [NotifyingDefaults new];

    // Toolbar: four tools, three zoom buttons, the appearance menu; the row keeps its height.
    context = @"toolbar";
    ScrapPDFKitView *view; NSPanel *panel = Panel(NSMakeSize(276, 378), &view);
    Check([[view toolbarDefaultItemIdentifiers:panel.toolbar] isEqual:(@[@"TSExperimentTools", @"TSExperimentZoom",
        NSToolbarFlexibleSpaceItemIdentifier, TSPreviewAppearanceToolbarID])], @"Toolbar order");
    NSToolbarItemGroup *tools = Group(panel, @"TSExperimentTools"), *zoom = Group(panel, @"TSExperimentZoom");
    Check(tools.subitems.count == 4 && tools.selectionMode == NSToolbarItemGroupSelectionModeSelectOne, @"Four selectable tools");
    Check(zoom.subitems.count == 3 && zoom.selectionMode == NSToolbarItemGroupSelectionModeMomentary, @"Three zoom buttons");
    // Labels would otherwise widen the buttons and fold the tools into a menu at the default width.
    Check(tools.controlRepresentation == NSToolbarItemGroupControlRepresentationExpanded &&
          zoom.controlRepresentation == NSToolbarItemGroupControlRepresentationExpanded, @"Groups stay separate buttons");
    NSArray *toolNames = @[@"Scroll", @"Select Text", @"Magnify", @"Select PDF"];
    for (NSUInteger i = 0; i < 4; i++)
        Check([tools.subitems[i].label isEqual:toolNames[i]] && [tools.subitems[i].toolTip isEqual:toolNames[i]] && tools.subitems[i].image, @"Tool names and icons");
    NSArray *zoomNames = @[@"Zoom Out", @"Zoom In", @"Zoom to Content"];
    for (NSUInteger i = 0; i < 3; i++) Check([zoom.subitems[i].toolTip isEqual:zoomNames[i]] && zoom.subitems[i].image, @"Zoom names and icons");
    Check(tools.selectedIndex == 1 && view.experimentMouseMode == NEW_MOUSE_MODE_SELECT_TEXT, @"Text selection by default");
    CGFloat withTools = NSHeight(panel.frame) - NSHeight([panel contentRectForFrameRect:panel.frame]);
    // 53pt is the title bar and toolbar of beta-6's Experiment preview, which had only the appearance menu.
    Check(withTools > 0 && withTools <= 53.5, [NSString stringWithFormat:@"Title bar and toolbar stay %.1f <= 53pt", withTools]);

    // Choices: kept apart from the document preview's mouse mode; invalid values fall back.
    context = @"tool choice";
    tools.selectedIndex = 3; [view changeExperimentTool:tools];
    Check([testDefaults integerForKey:ExperimentMouseModeKey] == NEW_MOUSE_MODE_SELECT_PDF, @"Choice saved");
    Check([testDefaults objectForKey:PdfKitMouseModeKey] == nil, @"Document preview mode untouched");
    [view changeExperimentTool:tools.subitems[0]];
    Check(view.experimentMouseMode == NEW_MOUSE_MODE_SCROLL, @"An item of the group as sender");
    for (NSNumber *bad in @[@4, @0, @99]) {
        [testDefaults setInteger:bad.integerValue forKey:ExperimentMouseModeKey];
        Check(view.experimentMouseMode == NEW_MOUSE_MODE_SELECT_TEXT, @"Large glass and unknown values fall back to text");
    }
    ScrapPDFKitView *other; NSPanel *otherPanel = Panel(NSMakeSize(300, 378), &other);
    tools.selectedIndex = 2; [view changeExperimentTool:tools]; Pump();
    Check(Group(otherPanel, @"TSExperimentTools").selectedIndex == 2, @"Another Experiment window follows the choice");
    Check(view.experimentToolCursor == NSCursor.arrowCursor, @"Magnifier cursor");
    [testDefaults setInteger:NEW_MOUSE_MODE_SCROLL forKey:ExperimentMouseModeKey];
    Check(view.experimentToolCursor == NSCursor.openHandCursor, @"Hand cursor");
    [testDefaults setInteger:NEW_MOUSE_MODE_SELECT_PDF forKey:ExperimentMouseModeKey];
    Check(view.experimentToolCursor == NSCursor.crosshairCursor, @"Selection cursor");
    [testDefaults setInteger:NEW_MOUSE_MODE_SELECT_TEXT forKey:ExperimentMouseModeKey];
    Check(view.experimentToolCursor == nil, @"Text keeps PDFKit's cursors");
    [otherPanel close];

    // Ink bounds and zoom to content.
    context = @"zoom";
    PDFPage *first = [view.document pageAtIndex:0];
    NSRect ink = TSExperimentInkBounds(first, kPDFDisplayBoxCropBox);
    Check(fabs(NSMinX(ink) - 220) < 1.5 && fabs(NSMinY(ink) - 740) < 1.5 && fabs(NSMaxX(ink) - 380) < 1.5 && fabs(NSMaxY(ink) - 770) < 1.5,
          [NSString stringWithFormat:@"Ink bounds %@", NSStringFromRect(ink)]);
    Check(NSIsEmptyRect(TSExperimentInkBounds([Document(2) pageAtIndex:1], kPDFDisplayBoxCropBox)), @"Blank page has no ink");
    CGFloat fitted = view.scaleFactor;
    zoom.selectedIndex = 1; [view experimentZoom:zoom]; Pump();
    Check(view.scaleFactor > fitted * 1.05, @"Zoom in");
    CGFloat larger = view.scaleFactor;
    [view experimentZoom:zoom.subitems[0]]; Pump();
    Check(view.scaleFactor < larger * 0.95, @"Zoom out");
    zoom.selectedIndex = 2; [view experimentZoom:zoom]; Pump();
    NSRect seen = SeenOnPage(view);
    Check(!view.autoScales && view.scaleFactor > fitted * 1.3, @"Content enlarged");
    Check(NSContainsRect(NSInsetRect(seen, -1, -1), Formula), [NSString stringWithFormat:@"Whole formula visible %@", NSStringFromRect(seen)]);
    Check(NSWidth(seen) < NSWidth(Formula) + 60 || NSHeight(seen) < NSHeight(Formula) + 60, @"Formula fills one direction");
    // Centred, unless that would scroll past the top of the document.
    Check(fabs(NSMidX(seen) - NSMidX(Formula)) < 10, [NSString stringWithFormat:@"Formula centred across %@", NSStringFromRect(seen)]);
    Check(fabs(NSMidY(seen) - NSMidY(Formula)) < 10 || NSMaxY(seen) >= 842 - 1, [NSString stringWithFormat:@"Formula centred or page top shown %@", NSStringFromRect(seen)]);

    // Hand: the page point under the pointer follows the pointer.
    context = @"hand";
    view.autoScales = YES; Pump(); view.scaleFactor = view.scaleFactor * 2; Pump();
    NSPoint origin = Clip(view).bounds.origin;
    NSPoint windowPoint = [view convertPoint:NSMakePoint(NSMidX(view.bounds), NSMidY(view.bounds)) toView:nil];
    NSPoint under = [view convertPoint:[view convertPoint:windowPoint fromView:nil] toPage:first];
    [view scrollExperimentFromOrigin:origin byDelta:NSMakeSize(-30, 40)];
    NSPoint moved = NSMakePoint(windowPoint.x - 30, windowPoint.y + 40);
    NSPoint after = [view convertPoint:[view convertPoint:moved fromView:nil] toPage:first];
    Check(hypot(after.x - under.x, after.y - under.y) * view.scaleFactor < 1.5, @"Dragged page follows the pointer");

    // Rectangle selection, copied in each Copy Format type.
    context = @"selection";
    view.autoScales = YES; Pump();
    [testDefaults setInteger:NEW_MOUSE_MODE_SELECT_PDF forKey:ExperimentMouseModeKey];
    NSRect wanted = NSMakeRect(200, 720, 200, 70);   // around the formula, in page coordinates
    NSPoint a = [view.documentView convertPoint:ViewPointOfPage(view, wanted.origin) fromView:view];
    NSPoint b = [view.documentView convertPoint:ViewPointOfPage(view, NSMakePoint(NSMaxX(wanted), NSMaxY(wanted))) fromView:view];
    [view setExperimentSelectionFrom:a to:b square:NO];
    Check(view.hasExperimentSelection && view.selectionPage == first, @"Selection on page 1");
    Check(fabs(NSMinX(view.selectionPageRect) - 200) < 2 && fabs(NSMinY(view.selectionPageRect) - 720) < 2 &&
          fabs(NSWidth(view.selectionPageRect) - 200) < 2 && fabs(NSHeight(view.selectionPageRect) - 70) < 2,
          [NSString stringWithFormat:@"Selection in page coordinates %@", NSStringFromRect(view.selectionPageRect)]);
    Check(view.experimentOverlay.superview == view.documentView, @"Rubber band shown");
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
    Check([view validateMenuItem:copyItem], @"Copy enabled with a selection");
    struct { NSInteger type; NSPasteboardType kind; } formats[] = {
        {IMAGE_TYPE_PDF, NSPasteboardTypePDF}, {IMAGE_TYPE_TIFF_NC, NSPasteboardTypeTIFF}, {IMAGE_TYPE_TIFF_LZW, NSPasteboardTypeTIFF},
        {IMAGE_TYPE_TIFF_PB, NSPasteboardTypeTIFF}, {IMAGE_TYPE_JPEG_HIGH, @"public.jpeg"}, {IMAGE_TYPE_JPEG_MEDIUM, @"public.jpeg"},
        {IMAGE_TYPE_JPEG_LOW, @"public.jpeg"}, {IMAGE_TYPE_PNG, NSPasteboardTypePNG}, {IMAGE_TYPE_EPS, NSPasteboardTypePNG}};
    for (NSUInteger f = 0; f < sizeof formats / sizeof formats[0]; f++) {
        context = [NSString stringWithFormat:@"copy type %ld", (long)formats[f].type];
        [privateBoard clearContents];
        [testDefaults setInteger:formats[f].type forKey:PdfCopyTypeKey];
        [view copy:nil];
        NSData *data = [privateBoard dataForType:formats[f].kind];
        Check(data.length > 0, [NSString stringWithFormat:@"Data of the chosen type (%@)", privateBoard.types]);
        if (formats[f].type == IMAGE_TYPE_PDF) {
            PDFDocument *copied = [[PDFDocument alloc] initWithData:data];
            NSRect box = [[copied pageAtIndex:0] boundsForBox:kPDFDisplayBoxCropBox];
            Check(copied.pageCount == 1 && fabs(NSWidth(box) - 200) < 2 && fabs(NSHeight(box) - 70) < 2, @"PDF of the selection");
            Check(NSEqualRects(NSIntegralRect(TSExperimentInkBounds([copied pageAtIndex:0], kPDFDisplayBoxCropBox)),
                  NSIntegralRect(NSIntersectionRect(Formula, box))) || NSWidth(TSExperimentInkBounds([copied pageAtIndex:0], kPDFDisplayBoxCropBox)) > 150,
                  @"PDF keeps the formula");
        } else {
            NSBitmapImageRep *rep = Bitmap(data);
            CGFloat expected = 200 * MAX(1.0, view.scaleFactor * (panel.backingScaleFactor > 0 ? panel.backingScaleFactor : 2));
            Check(rep && fabs(rep.pixelsWide - expected) <= 2 && fabs(rep.size.width - 200) < 1 && fabs(rep.size.height - 70) < 1,
                  [NSString stringWithFormat:@"Image size %ldx%ld (%.0f)", (long)rep.pixelsWide, (long)rep.pixelsHigh, expected]);
            // The formula covers the middle; the corners are white.
            Check(DarkAt(rep, .5, .4) && !DarkAt(rep, .02, .05) && !DarkAt(rep, .98, .95), @"Image shows the formula on white");
        }
    }
    context = @"selection lifetime";
    [testDefaults setInteger:NEW_MOUSE_MODE_SELECT_TEXT forKey:ExperimentMouseModeKey];
    [privateBoard clearContents]; [privateBoard setString:@"before" forType:NSPasteboardTypeString];
    [view copy:nil];
    Check([[privateBoard stringForType:NSPasteboardTypeString] isEqual:@"before"] || [privateBoard dataForType:NSPasteboardTypePNG] == nil,
          @"Text mode does not copy the rectangle as an image");
    Check([privateBoard dataForType:NSPasteboardTypePNG] == nil && [privateBoard dataForType:NSPasteboardTypePDF] == nil, @"No image in text mode");
    [testDefaults setInteger:NEW_MOUSE_MODE_SELECT_PDF forKey:ExperimentMouseModeKey];
    [view setExperimentSelectionFrom:a to:NSMakePoint(a.x + 40, a.y + 10) square:YES];
    NSRect band = view.selectionPageRect;
    Check(fabs(NSWidth(band) - NSHeight(band)) < 1, @"Shift makes a square");
    [view zoomIn:nil]; Pump();
    Check(!view.hasExperimentSelection && view.experimentOverlay == nil, @"Zooming clears the rectangle");
    [view setExperimentSelectionFrom:a to:b square:NO];
    tools.selectedIndex = 0; [view changeExperimentTool:tools];
    Check(!view.hasExperimentSelection && view.experimentOverlay == nil, @"Changing tool clears the rectangle");
    [testDefaults setInteger:NEW_MOUSE_MODE_SELECT_PDF forKey:ExperimentMouseModeKey];
    [view setExperimentSelectionFrom:a to:b square:NO];
    view.document = Document(1); Pump();
    Check(!view.hasExperimentSelection && view.experimentOverlay == nil, @"A new output clears the rectangle");
    Check(![view validateMenuItem:copyItem], @"Copy disabled without a rectangle in this mode");

    // Magnifying glass: lens size by clicks, magnification by modifier keys, page image under the pointer.
    context = @"magnifier";
    first = [view.document pageAtIndex:0];
    view.autoScales = YES; Pump();
    NSPoint over = ViewPointOfPage(view, NSMakePoint(NSMidX(Formula), NSMidY(Formula)));
    [view showExperimentMagnifierAt:over level:1 modifiers:0];
    OverView *lens = view.experimentOverlay;
    Check(lens.superview == view.documentView && lens.magnifiedPage == first, @"Glass shown");
    Check(view.scaleFactor < 0.6, @"Fixture: the Experiment panel shows the page reduced");
    // Lens size in points on screen, and magnification of what the screen shows.
    NSRect lensRect = [view convertRect:[[lens valueForKey:@"theSelectionRect"] rectValue] fromView:view.documentView];
    NSRect source = [[lens valueForKey:@"magnifiedRect"] rectValue];
    Check(fabs(NSWidth(lensRect) - 150) < .5 && fabs(NSHeight(lensRect) - 100) < .5,
          [NSString stringWithFormat:@"Small lens on screen %@", NSStringFromRect(lensRect)]);
    Check(fabs(NSMidX(source) - NSMidX(Formula)) < 2 && fabs(NSMidY(source) - NSMidY(Formula)) < 2, @"Lens shows the page under the pointer");
    CGFloat shown = NSWidth(source) * view.scaleFactor;   // width of the source as the screen shows it
    // The same glass as the Preview window: 150%, Command 200%, Option 250%, Control 300% of the screen.
    Check(fabs(NSWidth(lensRect) / shown - 1.5) < .05, [NSString stringWithFormat:@"Glass magnifies 150%% (%.2f)", NSWidth(lensRect) / shown]);
    NSEventModifierFlags keys[] = {NSEventModifierFlagCommand, NSEventModifierFlagOption, NSEventModifierFlagControl};
    CGFloat factors[] = {2.0, 2.5, 3.0};
    for (int k = 0; k < 3; k++) {
        [view showExperimentMagnifierAt:over level:1 modifiers:keys[k]];
        source = [[lens valueForKey:@"magnifiedRect"] rectValue];
        Check(fabs(150 / (NSWidth(source) * view.scaleFactor) - factors[k]) < .05, @"Modifier keys magnify as in the Preview window");
    }
    [view showExperimentMagnifierAt:over level:2 modifiers:0];
    lensRect = [view convertRect:[[lens valueForKey:@"theSelectionRect"] rectValue] fromView:view.documentView];
    Check(fabs(NSWidth(lensRect) - 380) < .5, @"Double click gives the large lens");
    [view hideExperimentMagnifier];
    Check(view.experimentOverlay == nil, @"Glass removed");
    // What the lens actually draws: the formula under the pointer, for rotated pages and
    // for a page whose boxes do not start at the origin.
    NSUInteger lensCases = 0;
    for (NSInteger rotation = 0; rotation < 360; rotation += 90) for (int offset = 0; offset < 2; offset++) {
        context = [NSString stringWithFormat:@"lens rotation %ld offset %d", (long)rotation, offset];
        PDFDocument *turned = Document(1);
        PDFPage *page = [turned pageAtIndex:0];
        if (offset) {
            [page setBounds:NSMakeRect(100, 600, 400, 200) forBox:kPDFDisplayBoxMediaBox];
            [page setBounds:NSMakeRect(100, 600, 400, 200) forBox:kPDFDisplayBoxCropBox];
        }
        page.rotation = rotation;
        view.document = turned; view.autoScales = YES; Pump();
        // The lens centre shows what lies under the pointer: the formula, then plain paper.
        NSPoint spots[] = {NSMakePoint(NSMidX(Formula), NSMidY(Formula)), offset ? NSMakePoint(140, 630) : NSMakePoint(120, 300)};
        for (int k = 0; k < 2; k++) {
            NSPoint target = [view convertPoint:spots[k] fromPage:page];
            [view showExperimentMagnifierAt:target level:1 modifiers:0];
            OverView *glass = view.experimentOverlay;
            NSRect shownLens = [[glass valueForKey:@"theSelectionRect"] rectValue];
            NSBitmapImageRep *drawn = [glass bitmapImageRepForCachingDisplayInRect:shownLens];
            [glass cacheDisplayInRect:shownLens toBitmapImageRep:drawn];
            Check(DarkAt(drawn, .5, .5) == (k == 0), k == 0 ? @"Lens centre shows the formula" : @"Lens centre shows paper away from it");
            [view hideExperimentMagnifier];
        }
        lensCases++;
    }
    Check(lensCases == 8, @"All rotations with and without a box offset");
    context = @"magnifier";
    view.document = Document(1); Pump();

    // Mouse tracking loops with posted events.
    context = @"tracking";
    NSPoint start = [view convertPoint:ViewPointOfPage(view, NSMakePoint(200, 720)) toView:nil];
    NSPoint end = [view convertPoint:ViewPointOfPage(view, NSMakePoint(400, 790)) toView:nil];
    [testDefaults setInteger:NEW_MOUSE_MODE_SELECT_PDF forKey:ExperimentMouseModeKey];
    Post(Mouse(NSEventTypeLeftMouseDragged, panel, end, 1, 0));
    Post(Mouse(NSEventTypeLeftMouseUp, panel, end, 1, 0));
    [view mouseDown:Mouse(NSEventTypeLeftMouseDown, panel, start, 1, 0)];
    Check(view.hasExperimentSelection && fabs(NSWidth(view.selectionPageRect) - 200) < 3, @"Dragging selects a rectangle");
    Post(Mouse(NSEventTypeLeftMouseUp, panel, start, 1, 0));
    [view mouseDown:Mouse(NSEventTypeLeftMouseDown, panel, start, 1, 0)];
    Check(!view.hasExperimentSelection && view.experimentOverlay == nil, @"A click without dragging clears it");
    [testDefaults setInteger:NEW_MOUSE_MODE_MAG_GLASS forKey:ExperimentMouseModeKey];
    Post(Mouse(NSEventTypeLeftMouseDragged, panel, end, 1, 0));
    Post(Mouse(NSEventTypeLeftMouseUp, panel, end, 1, 0));
    [view mouseDown:Mouse(NSEventTypeLeftMouseDown, panel, start, 1, 0)];
    Check(view.experimentOverlay == nil, @"Glass gone after the button is released");
    // The glass works at any magnification, and draws only the lens.
    view.autoScales = NO; view.scaleFactor = 16; Pump();
    [view goToRect:NSMakeRect(NSMidX(Formula) - 5, NSMidY(Formula) - 5, 10, 10) onPage:[view.document pageAtIndex:0]]; Pump();
    NSPoint enlarged = ViewPointOfPage(view, NSMakePoint(NSMidX(Formula), NSMidY(Formula)));
    [view showExperimentMagnifierAt:enlarged level:1 modifiers:0];
    {
        OverView *glass = view.experimentOverlay;
        NSRect shownLens = [[glass valueForKey:@"theSelectionRect"] rectValue];
        NSBitmapImageRep *drawn = [glass bitmapImageRepForCachingDisplayInRect:shownLens];
        [glass cacheDisplayInRect:shownLens toBitmapImageRep:drawn];
        Check(DarkAt(drawn, .5, .5), @"An enlarged page shows the formula in the glass");
    }
    [view hideExperimentMagnifier];
    Post(Mouse(NSEventTypeLeftMouseUp, panel, start, 1, 0));
    [view mouseDown:Mouse(NSEventTypeLeftMouseDown, panel, start, 1, 0)];
    NSEvent *left = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseUp untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES];
    Check(left == nil && view.experimentOverlay == nil, @"The glass tool works on an enlarged page");
    view.scaleFactor = 2; Pump();
    [testDefaults setInteger:NEW_MOUSE_MODE_SCROLL forKey:ExperimentMouseModeKey];
    NSPoint beforeDrag = Clip(view).bounds.origin;
    Post(Mouse(NSEventTypeLeftMouseDragged, panel, NSMakePoint(start.x, start.y + 60), 1, 0));
    Post(Mouse(NSEventTypeLeftMouseUp, panel, NSMakePoint(start.x, start.y + 60), 1, 0));
    [view mouseDown:Mouse(NSEventTypeLeftMouseDown, panel, start, 1, 0)];
    Check(!NSEqualPoints(beforeDrag, Clip(view).bounds.origin), @"Hand drag scrolls");
    [panel close];
    printf("PASS: Experiment preview tools, zoom, copy formats and tracking (%lu checks)\n", (unsigned long)checks);
}}
'''.replace('PDFSOURCE', pdf)
with tempfile.TemporaryDirectory(prefix='TeXShop-experiment-tools-') as tmp:
    tmp = Path(tmp)
    app = tmp/'ExperimentToolsTest.app'; mac = app/'Contents/MacOS'; mac.mkdir(parents=True)
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.texshop.ExperimentToolsTest.'+tmp.name,
        'CFBundleExecutable': 'ExperimentToolsTest', 'CFBundlePackageType': 'APPL', 'LSUIElement': True}))
    res = app/'Contents/Resources/en.lproj'; res.mkdir(parents=True)
    (res/'ToolbarItems.strings').write_bytes((root/'Resources/Interfaces/en.lproj/ToolbarItems.strings').read_bytes())
    (tmp/'Test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', *include_args(root), '-I'+str(root/'Tests'),
                    '-framework', 'Cocoa', '-framework', 'Quartz', str(tmp/'Test.m'), *sources(root),
                    '-o', str(mac/'ExperimentToolsTest')], check=True)
    home = tmp/'Home'; (home/'Library/Preferences').mkdir(parents=True)
    try:
        result = subprocess.run([str(mac/'ExperimentToolsTest'), '-AppleLanguages', '(en)'], env={**os.environ, 'CFFIXED_USER_HOME': str(home)},
                                capture_output=True, text=True, timeout=120)
        sys.stdout.write(result.stdout); sys.stderr.write(result.stderr)
        sys.exit(result.returncode)
    finally:
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', '-u', str(app)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
