#!/usr/bin/env python3
"""The preview's appearance applies to the pages, not to the window frame.

On macOS 26 and later the preview runs under the toolbar. Forcing the PDF scroll
view to the light appearance used to make AppKit draw the title bar and the
toolbar light as well. Scroll bars are part of that frame: they keep the system's
appearance and are not inverted. On macOS 27 an overlay scroller copies the clip
view and the document view, so those take no appearance. The pages and the area
around them are still drawn light. For a dark preview the pages are inverted as
they are drawn, and the PDF view carries that choice; no view PDFKit magnifies (the
clip, the document view, a page view) carries a filter, since a filter there blurs
the pages when zoomed in. Each page view is made light as PDFKit adds it to the
document view, and a view TeXShop puts over the pages gets the filters at once.

The windows are never ordered on screen. Defaults stay in memory.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path
from production_fragments import method, verify_embedded
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['scroll-appearance', 'bar-appearance', 'bar-filters', 'document-filters', 'page-hook', 'hook-original', 'ancestor-mark', 'page-state', 'overlay-filters', 'paper-layers', 'tile-layers', 'selection-blend', 'selection-inner', 'own-filters'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
header = (root / 'Sources/Preview/TSPreviewAppearance.h').read_text()
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
view_methods = [method(view_source, signature) for signature in (
    '- (void)setScaleFactor:(CGFloat)scale', '- (void)setFrameSize:(NSSize)newSize',
    '- (void)setDisplayMode:(PDFDisplayMode)mode',
    '- (void)keepHorizontalPositionDuring:(void (NS_NOESCAPE ^)(void))navigation',
    '- (BOOL)scrollingKeepsPage', '- (BOOL)isPageTurnFromScrolling:(SEL)selector',
    '- (void)goToNextPage:(id)sender',
    '- (NSMenu *)menuForEvent:(NSEvent *)theEvent',
    '- (MyPDFKitView *)previewPartForMenuEvent: (NSEvent *)theEvent',
    '- (PDFDestination *)internalLinkDestinationAtPoint: (NSPoint)viewPoint',
    '- (IBAction) takeDestinationFromOutline: (id) sender',
    '- (void) rotateClockwise:sender',
    '- (void) rotateCounterclockwise:sender',
    '- (void) goBack:sender',
    '- (void) goForward: sender')]
fragments = [('complete method: ' + item.split('\n', 1)[0], view_source, item) for item in view_methods]
# The document preview and the Experiment preview call the hook right after PDFKit's -setDocument:.
set_document = method(view_source, '- (void)setDocument:(PDFDocument *)document')
assert '    TSPreviewSetDocument(self, ^{ [super setDocument:document]; });\n' in set_document, 'MyPDFKitView -setDocument: goes through TSPreviewSetDocument'
scrap_source = (root / 'Sources/Preview/ScrapPDFKitView.m').read_text(encoding='latin1')
assert '    TSPreviewSetDocument(self, ^{ [super setDocument:document]; });\n' in method(scrap_source, '- (void)setDocument:(PDFDocument *)document'), 'ScrapPDFKitView -setDocument: goes through TSPreviewSetDocument'
if args.mutation == 'scroll-appearance':
    old = '    scrollView.appearance = nil;\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '    scrollView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];\n', 1)
elif args.mutation == 'bar-appearance':
    old = '            subview.appearance = nil;\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '            subview.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];\n', 1)
elif args.mutation == 'bar-filters':
    old = '            subview.contentFilters = @[];\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '            subview.contentFilters = TSPreviewInversionFilters();\n', 1)
elif args.mutation == 'document-filters':
    # The 6.00 beta 4 filters on the document view: views there are magnified, and the pages blur.
    old = '    documentView.contentFilters = @[];\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '    documentView.contentFilters = filters;\n', 1)
elif args.mutation == 'page-state':
    # The PDF view is not told to draw its pages inverted.
    old = '        objc_setAssociatedObject(pdfView, TSPreviewPagesInvertedKey, @(invert), OBJC_ASSOCIATION_RETAIN);\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '', 1)
elif args.mutation == 'overlay-filters':
    # A view over the pages, such as a link popup, is no longer inverted.
    old = '    NSArray *wanted = page ? @[] : filters;\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '    NSArray *wanted = @[];\n', 1)
elif args.mutation == 'paper-layers':
    # The paper behind the tiles stays white: a page flashes white while it is drawn.
    old = '        if (invert && paper && !layer.filters.count) {\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '        if (0) {\n', 1)
elif args.mutation == 'tile-layers':
    # Every layer without sublayers is taken for paper, also the layer that will hold the tiles.
    old = '        BOOL paper = !tiles && layer.sublayers.count == 0 && (layer.backgroundColor || layer.contents);\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '        BOOL paper = !tiles && layer.sublayers.count == 0;\n', 1)
elif args.mutation == 'selection-blend':
    # The selection stays multiplied over a dark page.
    old = '            if (![sublayer.compositingFilter isEqual:@"screenBlendMode"]) sublayer.compositingFilter = @"screenBlendMode";\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '', 1)
elif args.mutation == 'selection-inner':
    # The 5f284339 way: the layers inside the effect are changed, and PDFKit sets them back on a zoom.
    old = '                sublayer.filters = filters;\n'
    old2 = '            if (![sublayer.compositingFilter isEqual:@"screenBlendMode"]) sublayer.compositingFilter = @"screenBlendMode";\n'
    assert header.count(old) == 1 and header.count(old2) == 1, args.mutation
    header = header.replace(old, '', 1).replace(old2, '            for (CALayer *blend in sublayer.sublayers) { blend.filters = filters; blend.compositingFilter = @"screenBlendMode"; }\n', 1)
elif args.mutation == 'own-filters':
    # The 8f71aa48 way: a light preview takes every filter off the effect layer.
    old = '            if (added) {\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '            if (added || kept) {\n', 1)
elif args.mutation == 'page-hook':
    old = '                TSLightenPreviewPageView(subview, invert.boolValue ? TSPreviewInversionFilters() : @[]);\n        });'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '                (void)subview; (void)invert;\n        });', 1)
elif args.mutation == 'hook-original':
    old = '            ((void (*)(__unsafe_unretained id, SEL, NSView *))original)(view, sel, subview);\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '            (void)original;\n')
elif args.mutation == 'ancestor-mark':
    # The round-9 finding: leave a class alone when any ancestor is hooked, whatever it inherits.
    old = '        if (!own && [hooks containsObject:[NSValue valueWithPointer:(const void *)original]]) return;\n'
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '        if (!own) for (Class up = class_getSuperclass(cls); up && up != NSView.class; up = class_getSuperclass(up))\n            if (objc_getAssociatedObject(up, @selector(tsPreviewPageHook))) return;\n')
view_text = '\n'.join(view_methods)

program = r'''
#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "TestAppKitIsolation.h"
#import "TSContentZoom.h"
#import "TSPreviewHorizontalPosition.h"
#import "TSPreviewScrollerKeeper.h"
#import "TSScrollPageTurn.h"
@interface NSObject (ChromeDocumentMessages)
- (void)updatePreviewLayoutControls;
- (NSMenu *)getContextMenu;
@end
#define SUD NSUserDefaults.standardUserDefaults
#define NoScrollPageTurnKey @"NoScrollPageTurn"
#define NEW_PDF_FIT_TO_NONE 2
#define NEW_PDF_FIT_TO_CONTENT_WIDTH 6
#define PDF_SINGLE_PAGE_STYLE 1
#define PDF_TWO_PAGE_STYLE 2
#define PDF_MULTI_PAGE_STYLE 3
#define PDF_DOUBLE_MULTI_PAGE_STYLE 4
HEADER
static int checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSString *Match(NSAppearance *appearance) {
    return [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
}
static NSView *FindClass(NSView *view, NSString *name) {
    if ([NSStringFromClass(view.class) isEqualToString:name]) return view;
    for (NSView *subview in view.subviews) {
        NSView *found = FindClass(subview, name);
        if (found) return found;
    }
    return nil;
}
static void Pump(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
}
static PDFDocument *Document(void) {
    PDFDocument *document = [PDFDocument new];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(300, 400)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 300, 400));
    [image unlockFocus];
    [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:0];
    return document;
}
static void CheckScrollersFollowSystem(NSScrollView *scroll, NSString *systemName, NSString *what) {
    BOOL found = NO;
    for (NSView *subview in scroll.subviews) {
        if (![subview isKindOfClass:NSScroller.class]) continue;
        found = YES;
        check(subview.appearance == nil, [what stringByAppendingString:@": the scroller has no explicit appearance"]);
        check(subview.contentFilters.count == 0, [what stringByAppendingString:@": the scroller is not inverted"]);
        check([Match(subview.effectiveAppearance) isEqual:systemName], [what stringByAppendingString:@": the scroller follows the system"]);
    }
    check(found, [what stringByAppendingString:@": a scroller is present"]);
}
static void CheckPageViews(NSScrollView *scroll, NSString *systemName, BOOL inverted, NSString *what) {
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    check(scroll.contentView.appearance == nil && scroll.contentView.contentFilters.count == 0,
          [what stringByAppendingString:@": the clip stays with the system"]);
    check([Match(scroll.contentView.effectiveAppearance) isEqual:systemName],
          [what stringByAppendingString:@": the clip follows the system"]);
    check(scroll.documentView.appearance == nil,
          [what stringByAppendingString:@": the document view takes no appearance"]);
    check(scroll.documentView.contentFilters.count == 0,
          [what stringByAppendingString:@": the document view, magnified by PDFKit, carries no filters"]);
    NSView *pdfView = scroll.superview;
    while (pdfView && ![pdfView isKindOfClass:PDFView.class]) pdfView = pdfView.superview;
    check(pdfView && TSPreviewPagesInverted(pdfView) == inverted,
          [what stringByAppendingString:@": the PDF view draws its pages inverted for a dark preview only"]);
    BOOL page = NO;
    for (NSView *child in scroll.documentView.subviews) {
        BOOL isPage = [NSStringFromClass(child.class) containsString:@"Page"];
        if (isPage) page = YES;
        check(child.appearance == light, [what stringByAppendingString:@": the page is drawn light"]);
        check(child.contentFilters.count == (isPage || !inverted ? 0 : 3),
              [what stringByAppendingString:@": a page carries no filters; a view over the pages is inverted"]);
    }
    check(page, [what stringByAppendingString:@": a page view is present"]);
}
static void CheckChrome(NSWindow *window, PDFView *pdf, NSString *systemName, BOOL inverted) {
    Pump();
    [window layoutIfNeeded];
    [pdf layoutSubtreeIfNeeded];
    NSView *titlebar = FindClass(window.contentView.superview, @"NSTitlebarView");
    check(titlebar != nil, @"the window has a title bar");
    check([Match(window.effectiveAppearance) isEqual:systemName], @"the window follows the system");
    check([Match(titlebar.effectiveAppearance) isEqual:systemName], @"the title bar follows the system, not the preview");
    NSScrollView *scroll = pdf.documentView.enclosingScrollView;
    check(scroll.appearance == nil && scroll.contentFilters.count == 0, @"the scroll view keeps the system's appearance and does not invert the pocket");
    CheckPageViews(scroll, systemName, inverted, @"the preview");
    CheckScrollersFollowSystem(scroll, systemName, @"the preview");
    BOOL pocket = NO, around = NO;
    for (NSView *subview in scroll.subviews) {
        if (TSPreviewSubviewIsToolbarPocket(subview)) {
            pocket = YES;
            check(subview.appearance == nil && subview.contentFilters.count == 0, @"the pocket under the toolbar is left alone");
            check([Match(subview.effectiveAppearance) isEqual:systemName], @"the pocket follows the system");
        } else if (subview != scroll.contentView && ![subview isKindOfClass:NSScroller.class]
                   && NSHeight(subview.frame) > NSHeight(scroll.bounds) * 0.5) {
            around = YES;
            check([Match(subview.effectiveAppearance) isEqual:NSAppearanceNameAqua], @"the area around the pages follows the preview");
            check(subview.contentFilters.count == (inverted ? 3 : 0), @"the area around the pages is inverted with them");
        }
    }
    check(pocket && around, @"the pocket and the area around the pages are both present");
}
@interface TSPreviewWindow : NSObject
@property (nonatomic, weak) PDFView *pdf;
- (void)fixAfterRotation:(BOOL)clockwise;
@end
@interface MyPDFKitView : PDFView {
    BOOL _fittingContentWidth;
    NSInteger resizeOption;
    NSInteger pageStyle;
    NSPoint menuPoint;
}
@property (nonatomic, strong) id myDocument;
@property (nonatomic, strong) TSPreviewWindow *myPDFWindow;
- (void)fitContentWidthKeepingTop:(TSContentTop)top;
- (void)cleanupMarquee:(BOOL)terminate;
- (BOOL)beginKeepingPinnedLinkPreviewOnPage;
- (void)endKeepingPinnedLinkPreviewOnPage:(BOOL)began;
@end
@implementation MyPDFKitView
- (void)fitContentWidthKeepingTop:(TSContentTop)top {}
- (void)closePinnedLinkPreview {}
- (void)cleanupMarquee:(BOOL)terminate {}
- (void)cleanupMarqueeKeepingPinnedLinkPreview {}
- (BOOL)beginKeepingPinnedLinkPreviewOnPage { return NO; }
- (void)endKeepingPinnedLinkPreviewOnPage:(BOOL)began {}
// The production -setDocument: does more; the part this test needs is checked in its source above.
- (void)setDocument:(PDFDocument *)document { TSPreviewSetDocument(self, ^{ [super setDocument:document]; }); }
VIEWMETHODS
@end
@implementation TSPreviewWindow
- (void)fixAfterRotation:(BOOL)clockwise {
    PDFView *pdf = self.pdf;
    if (!pdf.document.pageCount) return;
    NSInteger delta = clockwise ? 90 : -90;
    for (NSUInteger i = 0; i < pdf.document.pageCount; i++) {
        PDFPage *page = [pdf.document pageAtIndex:i];
        page.rotation = (page.rotation + delta + 360) % 360;
    }
    [pdf layoutDocumentView];
    [pdf layoutSubtreeIfNeeded];
}
@end
@interface OutlineSource : NSObject <NSOutlineViewDataSource>
@property (nonatomic, strong) PDFOutline *item;
@end
@implementation OutlineSource
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item { return item ? 0 : 1; }
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item { return self.item; }
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item { return NO; }
@end
static void CheckLateBar(PDFView *pdf, BOOL inverted, NSString *what) {
    [pdf layoutSubtreeIfNeeded];
    NSScrollView *scroll = pdf.documentView.enclosingScrollView;
    NSScroller *bar = scroll.horizontalScroller;
    check(scroll.hasHorizontalScroller && bar != nil, [what stringByAppendingString:@": the horizontal scroller is present"]);
    check(bar.appearance == nil && bar.contentFilters.count == 0, [what stringByAppendingString:@": the new scroller is window chrome"]);
    check([Match(bar.effectiveAppearance) isEqual:NSAppearanceNameDarkAqua], [what stringByAppendingString:@": the new scroller follows the dark system"]);
    check(scroll.appearance == nil && scroll.contentFilters.count == 0, [what stringByAppendingString:@": the scroll view stays with the system"]);
    CheckPageViews(scroll, NSAppearanceNameDarkAqua, inverted, what);
    for (NSView *subview in scroll.subviews)
        if (TSPreviewSubviewIsToolbarPocket(subview))
            check(subview.appearance == nil && subview.contentFilters.count == 0, [what stringByAppendingString:@": the pocket stays untouched"]);
    NSView *titlebar = FindClass(pdf.window.contentView.superview, @"NSTitlebarView");
    check([Match(titlebar.effectiveAppearance) isEqual:NSAppearanceNameDarkAqua], [what stringByAppendingString:@": the title bar stays dark"]);
}
static PDFDocument *TallPage(void) {
    PDFDocument *document = [PDFDocument new];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(410, 1100)];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 410, 1100));
    [image unlockFocus];
    [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:0];
    return document;
}
static PDFDocument *PagesOfWidths(CGFloat first, CGFloat second) {
    PDFDocument *document = [PDFDocument new];
    CGFloat widths[2] = {first, second};
    for (int i = 0; i < 2; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(widths[i], 380)];
        [image lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, widths[i], 380));
        [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return document;
}
static MyPDFKitView *SpreadPreview(PDFDocument *document, PDFDisplayMode mode) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 550)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    window.toolbarStyle = NSWindowToolbarStyleExpanded;
    window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"TSPreviewChromeSpread"];
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    MyPDFKitView *pdf = [[MyPDFKitView alloc] initWithFrame:window.contentView.bounds];
    pdf.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    pdf.autoScales = NO;
    pdf.displayMode = mode;
    pdf.document = document;
    [window.contentView addSubview:pdf];
    [window layoutIfNeeded];
    [pdf layoutSubtreeIfNeeded];
    pdf.scaleFactor = 1;
    [pdf goToFirstPage:nil];
    return pdf;
}
static PDFDestination *WideDestination(PDFView *pdf) {
    return [[PDFDestination alloc] initWithPage:[pdf.document pageAtIndex:1] atPoint:NSMakePoint(30, 45)];
}
static void ChooseOutline(MyPDFKitView *pdf) {
    PDFOutline *root = [PDFOutline new];
    PDFOutline *child = [PDFOutline new];
    child.label = @"wide";
    child.destination = WideDestination(pdf);
    [root insertChild:child atIndex:0];
    pdf.document.outlineRoot = root;
    NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"outline"];
    [outline addTableColumn:column];
    outline.outlineTableColumn = column;
    OutlineSource *source = [OutlineSource new];
    source.item = child;
    outline.dataSource = source;
    [outline reloadData];
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    check([outline itemAtRow:outline.selectedRow] == child, @"the outline row is the wider page");
    [pdf takeDestinationFromOutline:outline];
}
static void FollowLink(PDFView *pdf) {
    PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(10, 10, 60, 20) forType:PDFAnnotationSubtypeLink withProperties:nil];
    link.action = [[PDFActionGoTo alloc] initWithDestination:WideDestination(pdf)];
    [[pdf.document pageAtIndex:0] addAnnotation:link];
    [pdf performAction:link.action];
}
static PDFDocument *TextPages(void) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef sink = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect media = CGRectMake(0, 0, 410, 380);
    CGContextRef pdf = CGPDFContextCreate(sink, &media, NULL);
    CGFloat widths[2] = {410, 1100};
    for (int i = 0; i < 2; i++) {
        CGRect box = CGRectMake(0, 0, widths[i], 380);
        NSDictionary *info = @{(__bridge NSString *)kCGPDFContextMediaBox: [NSData dataWithBytes:&box length:sizeof(box)]};
        CGPDFContextBeginPage(pdf, (__bridge CFDictionaryRef)info);
        CGContextSelectFont(pdf, "Helvetica", 18, kCGEncodingMacRoman);
        CGContextSetRGBFillColor(pdf, 0, 0, 0, 1);
        CGContextShowTextAtPoint(pdf, 40, 40, "Wide page", 9);
        CGPDFContextEndPage(pdf);
    }
    CGPDFContextClose(pdf);
    CGContextRelease(pdf);
    CGDataConsumerRelease(sink);
    return [[PDFDocument alloc] initWithData:data];
}
static void ChooseTwoPages(PDFView *pdf) {
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSMakePoint(200, 240)
        modifierFlags:0 timestamp:0 windowNumber:pdf.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    NSMenu *menu = [pdf menuForEvent:event];
    NSMenuItem *item = nil;
    for (NSMenuItem *candidate in menu.itemArray)
        if ([candidate.title isEqualToString:@"Two Pages"]) item = candidate;
    check(item != nil && item.action == NSSelectorFromString(@"_setDoublePage:"), @"the context menu offers Two Pages");
    [NSApp sendAction:item.action to:item.target ?: pdf from:item];
}
static MyPDFKitView *LatePreview(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 750, 550)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    window.toolbarStyle = NSWindowToolbarStyleExpanded;
    window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"TSPreviewChromeLate"];
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    MyPDFKitView *pdf = [[MyPDFKitView alloc] initWithFrame:window.contentView.bounds];
    pdf.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    pdf.autoScales = NO;
    pdf.displayMode = kPDFDisplaySinglePage;
    pdf.document = Document();
    [window.contentView addSubview:pdf];
    [window layoutIfNeeded];
    [pdf layoutSubtreeIfNeeded];
    return pdf;
}
static PDFDocument *ManyPages(void) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef sink = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 410, 380);
    CGContextRef pdf = CGPDFContextCreate(sink, &box, NULL);
    for (int i = 0; i < 12; i++) {
        CGPDFContextBeginPage(pdf, NULL);
        CGContextSetRGBFillColor(pdf, 0, 0, 0, 1);
        CGContextFillRect(pdf, CGRectMake(12, 14, 9, 9));
        CGPDFContextEndPage(pdf);
    }
    CGPDFContextClose(pdf);
    CGContextRelease(pdf);
    CGDataConsumerRelease(sink);
    return [[PDFDocument alloc] initWithData:data];
}
static void Settle(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.55]];
}
static NSSet *PagePointers(PDFView *pdf) {
    NSMutableSet *set = [NSMutableSet set];
    for (NSView *child in pdf.documentView.subviews)
        if ([NSStringFromClass(child.class) containsString:@"Page"])
            [set addObject:[NSValue valueWithPointer:(__bridge void *)child]];
    return set;
}
static NSView *FrontPage(PDFView *pdf) {
    NSView *found = nil;
    CGFloat best = 0;
    for (NSView *child in pdf.documentView.subviews) {
        if (![NSStringFromClass(child.class) containsString:@"Page"]) continue;
        NSRect coverage = NSIntersectionRect([pdf convertRect:child.bounds fromView:child], pdf.bounds);
        CGFloat area = coverage.size.width * coverage.size.height;
        if (area > best) { best = area; found = child; }
    }
    return found;
}
static void TurnWheel(PDFView *pdf) {
    NSView *hit = FrontPage(pdf);
    check(hit != nil, @"the wheel hits a page in the preview");
    for (int i = 0; i < 12; i++) {
        CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, -10);
        NSEvent *wheel = [NSEvent eventWithCGEvent:event];
        [hit scrollWheel:wheel];
        CFRelease(event);
        hit = FrontPage(pdf) ?: hit;
    }
}
@interface TSHookParent : NSView
@property int calls;
@end
@implementation TSHookParent
- (void)didAddSubview:(NSView *)subview { self.calls++; }
@end
@interface TSHookChild : TSHookParent @end
@implementation TSHookChild @end
@interface TSHookOwnChild : TSHookParent
@property int ownCalls;
@end
@implementation TSHookOwnChild
- (void)didAddSubview:(NSView *)subview { self.ownCalls++; [super didAddSubview:subview]; }
@end
@interface TSHookParentB : NSView
@property int calls;
@end
@implementation TSHookParentB
- (void)didAddSubview:(NSView *)subview { self.calls++; }
@end
@interface TSHookChildB : TSHookParentB @end
@implementation TSHookChildB @end
// A <- B <- C: B overrides and turns the new view dark; C only inherits B's method.
@interface TSHookBaseC : NSView
@property int calls;
@end
@implementation TSHookBaseC
- (void)didAddSubview:(NSView *)subview { self.calls++; }
@end
@interface TSHookMiddleC : TSHookBaseC
@property int middleCalls;
@end
@implementation TSHookMiddleC
- (void)didAddSubview:(NSView *)subview {
    self.middleCalls++; [super didAddSubview:subview];
    subview.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}
@end
@interface TSHookLeafC : TSHookMiddleC @end
@implementation TSHookLeafC @end
@interface TSHookMiddleD : NSView
@property int middleCalls;
@end
@implementation TSHookMiddleD
- (void)didAddSubview:(NSView *)subview {
    self.middleCalls++; subview.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}
@end
@interface TSHookLeafD : TSHookMiddleD @end
@implementation TSHookLeafD @end
// A superclass and its subclasses, hooked in either order, each reach their own original
// exactly once; only views in a preview are made light.
static void CheckHookClasses(void) {
    NSRect frame = NSMakeRect(0, 0, 10, 10);
    TSHookParent *parent = [[TSHookParent alloc] initWithFrame:frame];
    TSHookChild *child = [[TSHookChild alloc] initWithFrame:frame];
    TSHookOwnChild *own = [[TSHookOwnChild alloc] initWithFrame:frame];
    TSInstallPreviewPageHook(parent);
    TSInstallPreviewPageHook(child);
    TSInstallPreviewPageHook(own);
    [child addSubview:[[NSView alloc] initWithFrame:frame]];
    check(child.calls == 1, @"a subclass of a hooked class reaches the original once");
    [own addSubview:[[NSView alloc] initWithFrame:frame]];
    check(own.ownCalls == 1 && own.calls == 1, @"a subclass with its own method and its superclass each run once");
    [parent addSubview:[[NSView alloc] initWithFrame:frame]];
    check(parent.calls == 1, @"the hooked superclass reaches its original once");
    TSHookParentB *parentB = [[TSHookParentB alloc] initWithFrame:frame];
    TSHookChildB *childB = [[TSHookChildB alloc] initWithFrame:frame];
    TSInstallPreviewPageHook(childB);
    TSInstallPreviewPageHook(parentB);
    NSView *plain = [[NSView alloc] initWithFrame:frame];
    [childB addSubview:plain];
    check(childB.calls == 1, @"a subclass hooked before its superclass reaches the original once");
    [parentB addSubview:[[NSView alloc] initWithFrame:frame]];
    check(parentB.calls == 1, @"a superclass hooked after its subclass reaches the original once");
    check(plain.appearance == nil, @"a view outside a preview is left alone");
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    TSHookChild *page = [[TSHookChild alloc] initWithFrame:frame];
    scroll.documentView = page;
    TSApplyPreviewInversion(scroll, YES);
    NSView *added = [[NSView alloc] initWithFrame:frame];
    [page addSubview:added];
    check(added.appearance == [NSAppearance appearanceNamed:NSAppearanceNameAqua] && page.calls == 1,
          @"in a preview the new view is made light after the original ran");
    // The ancestor is hooked first; the leaf inherits an override that sets the new view dark.
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    TSHookBaseC *base = [[TSHookBaseC alloc] initWithFrame:frame];
    TSInstallPreviewPageHook(base);
    NSScrollView *leafScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    TSHookLeafC *leaf = [[TSHookLeafC alloc] initWithFrame:frame];
    leafScroll.documentView = leaf;
    TSApplyPreviewInversion(leafScroll, YES);
    NSView *leafChild = [[NSView alloc] initWithFrame:frame];
    [leaf addSubview:leafChild];
    check(leafChild.appearance == light && leaf.middleCalls == 1 && leaf.calls == 1,
          @"an override between a hooked ancestor and the leaf runs once, and the view is light after it");
    NSScrollView *dScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    TSHookMiddleD *middleD = [[TSHookMiddleD alloc] initWithFrame:frame];
    TSInstallPreviewPageHook(middleD);
    TSHookLeafD *leafD = [[TSHookLeafD alloc] initWithFrame:frame];
    dScroll.documentView = leafD;
    TSApplyPreviewInversion(dScroll, YES);
    NSView *dChild = [[NSView alloc] initWithFrame:frame];
    [leafD addSubview:dChild];
    check(dChild.appearance == light && leafD.middleCalls == 1,
          @"a leaf that inherits a hooked override runs it once and the view is light");
}
static void CheckWatchCloses(void) {
    @autoreleasepool {
        MyPDFKitView *view = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 220, 180)];
        PDFDocument *document = [PDFDocument new];
        [document insertPage:[[PDFPage alloc] init] atIndex:0];
        view.document = document;
        NSScrollView *scroll = view.documentView.enclosingScrollView;
        check(scroll != nil, @"a preview has a scroll view");
        TSApplyPreviewInversion(scroll, NO);
        Class documentClass = [view.documentView class];
        check(objc_getAssociatedObject(documentClass, @selector(tsPreviewPageHook)) != nil,
              @"the document view's class has the page hook");
        NSView *added = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [view.documentView addSubview:added];
        check(added.superview == view.documentView && added.appearance == [NSAppearance appearanceNamed:NSAppearanceNameAqua],
              @"a view added to a preview's document view is added and made light");
        [added removeFromSuperview];
        NSView *plainHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        NSView *plainChild = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 5, 5)];
        [plainHost addSubview:plainChild];
        check(plainChild.appearance == nil, @"other views are left alone");
        TSApplyPreviewInversion(scroll, YES);
        IMP installed = class_getMethodImplementation(documentClass, @selector(didAddSubview:));
        MyPDFKitView *other = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 220, 180)];
        other.document = document;
        check(class_getMethodImplementation(documentClass, @selector(didAddSubview:)) == installed,
              @"the hook is added to the class once");
        NSView *first = view.documentView;
        PDFDocument *next = [PDFDocument new];
        [next insertPage:[[PDFPage alloc] init] atIndex:0];
        view.document = next;
        check(view.documentView != first, @"a new document comes with a new document view");
        check(view.documentView.contentFilters.count == 0, @"the new document view carries no filters");
        check(TSPreviewPagesInverted(view), @"the PDF view still draws its pages inverted after a new document");
        NSView *late = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [view.documentView addSubview:late];
        check(late.appearance == [NSAppearance appearanceNamed:NSAppearanceNameAqua] && late.contentFilters.count == 3,
              @"a view put over the pages of the new document view is light and inverted at once");
        [late removeFromSuperview];
        TSApplyPreviewInversion(view.documentView.enclosingScrollView, NO);
        check(!TSPreviewPagesInverted(view), @"a light preview draws its pages as they are");
    }
    NSHashTable *views = [NSHashTable weakObjectsHashTable];
    for (int i = 0; i < 24; i++) {
        @autoreleasepool {
            PDFView *view = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 220, 180)];
            PDFDocument *document = [PDFDocument new];
            [document insertPage:[[PDFPage alloc] init] atIndex:0];
            view.document = document;
            NSScrollView *scroll = view.documentView.enclosingScrollView;
            if (!scroll) { check(NO, @"a closing preview has a scroll view"); return; }
            TSApplyPreviewInversion(scroll, NO);
            [views addObject:view];
        }
    }
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    check(views.allObjects.count == 0, @"closed previews are released");
}
// The page views PDFKit adds after a new document are light from the moment they exist,
// however late they come: the check runs every 10 ms for a second, not once at a set time.
static void CheckPagesLightAsTheyCome(PDFView *pdf, BOOL inverted, NSString *what) {
    NSAppearance *light = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    BOOL sawPage = NO, allLight = YES, filtered = YES;
    for (int i = 0; i < 100; i++) {
        NSView *documentView = pdf.documentView;
        if (documentView.contentFilters.count || TSPreviewPagesInverted(pdf) != inverted) filtered = NO;
        for (NSView *child in documentView.subviews) {
            if ([NSStringFromClass(child.class) containsString:@"Page"]) sawPage = YES;
            if (child.appearance != light || child.contentFilters.count) allLight = NO;
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    check(sawPage, [what stringByAppendingString:@": page views come"]);
    check(filtered, [what stringByAppendingString:@": the PDF view draws inverted from the start, and the document view carries no filters"]);
    check(allLight, [what stringByAppendingString:@": every page view is light as soon as it exists"]);
}
// Inside a page view: the paper and the picture of the page (layers with a color or contents
// and no sublayers) take the filters of a dark preview; the layer that holds the tiles never
// does, since the tiles are inverted as they are drawn.
static void CheckPageLayers(PDFView *pdf, BOOL inverted, NSString *what) {
    BOOL paper = NO, tiles = NO;
    for (NSView *child in pdf.documentView.subviews) {
        if (![NSStringFromClass(child.class) containsString:@"Page"]) continue;
        for (CALayer *layer in child.layer.sublayers) {
            BOOL holdsTiles = NO;
            for (CALayer *sublayer in layer.sublayers)
                if ([NSStringFromClass(sublayer.class) containsString:@"Tile"]) holdsTiles = YES;
            if (holdsTiles) {
                tiles = YES;
                check(layer.filters.count == 0, [what stringByAppendingString:@": the tiles are not inverted twice"]);
            } else if (layer.sublayers.count == 0 && (layer.backgroundColor || layer.contents)) {
                paper = YES;
                check(layer.filters.count == (inverted ? 3 : 0),
                      [what stringByAppendingString:@": the paper behind the tiles is inverted with the page, so it does not flash white"]);
            } else if (layer.sublayers.count == 0) {
                check(layer.filters.count == 0, [what stringByAppendingString:@": an empty layer that will hold the tiles takes no filters"]);
            }
        }
    }
    check(paper, [what stringByAppendingString:@": a page view has its paper layer"]);
    (void)tiles;
}
// A selection is multiplied over the page by PDFKit. For a dark preview each selection
// effect layer (the selection and the highlights of found text) inverts its colors and is
// screened over the page, whatever PDFKit sets on the layers inside it; a light preview gets
// the effect layer as PDFKit made it.
static NSUInteger SelectionEffects(PDFView *pdf, BOOL screened, NSUInteger *multiplied) {
    __block NSUInteger found = 0, inner = 0;
    __block void (^walk)(CALayer *) = nil;
    walk = ^(CALayer *layer) {
        for (CALayer *sublayer in layer.sublayers) {
            if ([NSStringFromClass(sublayer.class) containsString:@"SelectionEffect"]) {
                BOOL screen = [sublayer.compositingFilter isEqual:@"screenBlendMode"] && sublayer.filters.count == 3;
                BOOL plain = sublayer.compositingFilter == nil && sublayer.filters.count == 0;
                if (screened ? screen : plain) found++;
                for (CALayer *blend in sublayer.sublayers) if ([blend.compositingFilter isEqual:@"multiplyBlendMode"]) inner++;
            } else if (![NSStringFromClass(sublayer.class) containsString:@"Tile"]) walk(sublayer);
        }
    };
    for (NSView *child in pdf.documentView.subviews)
        if ([NSStringFromClass(child.class) containsString:@"Page"]) walk(child.layer);
    if (multiplied) *multiplied = inner;
    return found;
}
static NSUInteger AllSelectionEffects(PDFView *pdf) {
    NSUInteger screened = SelectionEffects(pdf, YES, NULL), plain = SelectionEffects(pdf, NO, NULL);
    return screened + plain;
}
static PDFDocument *TextPage(void) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef sink = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 410, 380);
    CGContextRef pdf = CGPDFContextCreate(sink, &box, NULL);
    CGPDFContextBeginPage(pdf, NULL);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithCGContext:pdf flipped:NO];
    for (int line = 0; line < 8; line++)
        [@"Selected text on a dark page stays visible." drawAtPoint:NSMakePoint(20, 330 - 30 * line)
            withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:14]}];
    [NSGraphicsContext restoreGraphicsState];
    CGPDFContextEndPage(pdf);
    CGPDFContextClose(pdf);
    CGContextRelease(pdf);
    CGDataConsumerRelease(sink);
    return [[PDFDocument alloc] initWithData:data];
}
// A page view as PDFKit adds it on macOS 15: the layer that will hold the tiles is still
// empty. It must not take the filters; the paper and the picture of the page do. Once
// tiles arrive, the holder still takes none.
static void CheckEmptyTileHolder(void) {
    Class pageClass = objc_allocateClassPair(NSView.class, "TestEmptyPageView", 0); objc_registerClassPair(pageClass);
    Class tileClass = objc_allocateClassPair(CALayer.class, "TestPageLayerTile", 0); objc_registerClassPair(tileClass);
    NSView *pageView = [[pageClass alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    pageView.wantsLayer = YES;
    CALayer *paper = [CALayer layer], *holder = [CALayer layer], *picture = [CALayer layer];
    paper.backgroundColor = NSColor.whiteColor.CGColor;
    picture.contents = [NSImage imageWithSize:NSMakeSize(4, 4) flipped:NO drawingHandler:^BOOL(NSRect r) { return YES; }];
    picture.backgroundColor = NSColor.whiteColor.CGColor;
    for (CALayer *layer in @[paper, holder, picture]) [pageView.layer addSublayer:layer];
    TSLightenPreviewPageView(pageView, TSPreviewInversionFilters());
    check(paper.filters.count == 3 && picture.filters.count == 3, @"the paper and the picture of a new page are inverted");
    check(holder.filters.count == 0, @"the still empty layer that will hold the tiles is not inverted");
    [holder addSublayer:[tileClass layer]];
    TSLightenPreviewPageView(pageView, TSPreviewInversionFilters());
    check(holder.filters.count == 0, @"the layer holding tiles is not inverted");
    TSLightenPreviewPageView(pageView, @[]);
    check(paper.filters.count == 0 && picture.filters.count == 0, @"a light preview takes the filters off the paper");
}
static void CheckSelectionLayers(PDFView *pdf) {
    pdf.document = TextPage();
    TSApplyPreviewInversion(pdf.documentView.enclosingScrollView, YES);
    pdf.scaleFactor = 1.25;
    Settle();
    PDFPage *page = [pdf.document pageAtIndex:0];
    PDFSelection *first = [page selectionForRect:NSMakeRect(10, 250, 300, 90)];
    check(first.string.length > 0, @"the text page has text to select");
    [pdf setCurrentSelection:first animate:NO];
    Settle();
    NSUInteger multiplied = 0;
    NSUInteger all = AllSelectionEffects(pdf);
    check(all > 0 && SelectionEffects(pdf, YES, &multiplied) == all,
          @"each selection effect on a dark page is inverted and screened");
    check(multiplied > 0, @"PDFKit's multiplied layers inside the effect are left as PDFKit set them");
    // Zooming with the selection kept: PDFKit sets its layers again, the effect stays screened.
    pdf.scaleFactor = 3.18; Settle(); pdf.scaleFactor = 5.39; Settle(); pdf.scaleFactor = 1.25; Settle();
    check(pdf.currentSelection.string.length > 0 && SelectionEffects(pdf, YES, NULL) == AllSelectionEffects(pdf),
          @"a kept selection stays screened when the page is zoomed in and out");
    // Highlights of found text, set without a change of the selection.
    [pdf setCurrentSelection:nil];
    PDFSelection *found = [[pdf.document findString:@"visible" withOptions:0] firstObject];
    check(found != nil, @"the text page has a word to highlight");
    found.color = NSColor.yellowColor;
    pdf.highlightedSelections = @[found];
    Settle();
    check(SelectionEffects(pdf, YES, NULL) == AllSelectionEffects(pdf), @"highlights of found text on a dark page are screened as well");
    pdf.highlightedSelections = nil;
    [pdf setCurrentSelection:[page selectionForRect:NSMakeRect(10, 100, 300, 90)] animate:NO];
    Settle();
    TSApplyPreviewInversion(pdf.documentView.enclosingScrollView, NO);
    Settle();
    check(SelectionEffects(pdf, NO, &multiplied) == AllSelectionEffects(pdf) && multiplied > 0,
          @"a light preview gets the selection as PDFKit made it");
    // A selection effect layer that has filters of its own keeps them through dark and back.
    __block CALayer *effect = nil;
    __block void (^find)(CALayer *) = nil;
    find = ^(CALayer *layer) {
        for (CALayer *sublayer in layer.sublayers) {
            if (effect) return;
            if ([NSStringFromClass(sublayer.class) containsString:@"SelectionEffect"]) effect = sublayer;
            else if (![NSStringFromClass(sublayer.class) containsString:@"Tile"]) find(sublayer);
        }
    };
    for (NSView *child in pdf.documentView.subviews)
        if ([NSStringFromClass(child.class) containsString:@"Page"]) find(child.layer);
    check(effect != nil, @"a page view has a selection effect layer");
    CIFilter *own = [CIFilter filterWithName:@"CISepiaTone"];
    effect.filters = @[own];
    TSApplyPreviewInversion(pdf.documentView.enclosingScrollView, YES);
    check(effect.filters.count == 1 && effect.filters.firstObject == own && [effect.compositingFilter isEqual:@"screenBlendMode"],
          @"a selection effect with its own filters keeps them on a dark page");
    TSApplyPreviewInversion(pdf.documentView.enclosingScrollView, NO);
    check(effect.filters.count == 1 && effect.filters.firstObject == own && effect.compositingFilter == nil,
          @"a selection effect keeps its own filters back on a light page");
    effect.filters = nil;
    CheckPageLayers(pdf, NO, @"the selection on a light page");
    [pdf setCurrentSelection:nil];
}
static void CheckReadingPages(PDFView *pdf, BOOL inverted, NSString *what, NSTimeInterval wait) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:wait]];
    [pdf layoutSubtreeIfNeeded];
    NSScrollView *scroll = pdf.documentView.enclosingScrollView;
    CheckPageViews(scroll, NSAppearanceNameDarkAqua, inverted, what);
    CheckPageLayers(pdf, inverted, what);
    CheckScrollersFollowSystem(scroll, NSAppearanceNameDarkAqua, what);
    BOOL shown = NO;
    for (NSView *child in scroll.documentView.subviews) {
        if (![NSStringFromClass(child.class) containsString:@"Page"]) continue;
        NSRect coverage = NSIntersectionRect([pdf convertRect:child.bounds fromView:child], pdf.bounds);
        if (coverage.size.width * coverage.size.height > 1000) shown = YES;
    }
    check(shown, [what stringByAppendingString:@": a page is on screen"]);
}
int main(void) {
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 520)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
            backing:NSBackingStoreBuffered defer:NO];
        window.toolbarStyle = NSWindowToolbarStyleExpanded;
        window.toolbar = [[NSToolbar alloc] initWithIdentifier:@"TSPreviewChromeTest"];
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
        PDFView *pdf = [[PDFView alloc] initWithFrame:window.contentView.bounds];
        pdf.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        pdf.autoScales = YES;
        pdf.document = Document();
        [window.contentView addSubview:pdf];
        [window layoutIfNeeded];
        [pdf layoutSubtreeIfNeeded];
        // PDFKit creates the page view when the magnification changes, not at the first layout.
        if (pdf.documentView.subviews.count == 0) pdf.scaleFactor = 1.5;
        [pdf layoutSubtreeIfNeeded];
        NSScrollView *scroll = pdf.documentView.enclosingScrollView;

        TSApplyPreviewInversion(scroll, NO);
        CheckChrome(window, pdf, NSAppearanceNameDarkAqua, NO);
        NSBitmapImageRep *rep = [pdf bitmapImageRepForCachingDisplayInRect:pdf.bounds];
        [pdf cacheDisplayInRect:pdf.bounds toBitmapImageRep:rep];
        NSColor *gutter = [[rep colorAtX:2 y:rep.pixelsHigh / 2] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        check(gutter.redComponent > 0.7, @"a light preview keeps a light area around the page in a dark window");

        TSApplyPreviewInversion(scroll, YES);
        CheckChrome(window, pdf, NSAppearanceNameDarkAqua, YES);

        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        TSApplyPreviewInversion(scroll, YES);
        CheckChrome(window, pdf, NSAppearanceNameAqua, YES);
        TSApplyPreviewInversion(scroll, NO);
        CheckChrome(window, pdf, NSAppearanceNameAqua, NO);

        NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        MyPDFKitView *magnified = LatePreview();
        TSApplyPreviewInversion(magnified.documentView.enclosingScrollView, YES);
        check(!magnified.documentView.enclosingScrollView.hasHorizontalScroller, @"magnifying starts without a horizontal scroller");
        magnified.scaleFactor = 4;
        CheckLateBar(magnified, YES, @"magnifying the document preview");
        MyPDFKitView *narrowed = LatePreview();
        narrowed.scaleFactor = 0.5;
        TSApplyPreviewInversion(narrowed.documentView.enclosingScrollView, YES);
        narrowed.scaleFactor = 1;
        check(!narrowed.documentView.enclosingScrollView.hasHorizontalScroller, @"narrowing starts without a horizontal scroller");
        [narrowed setFrameSize:NSMakeSize(120, 550)];
        CheckLateBar(narrowed, YES, @"narrowing the document preview");
        MyPDFKitView *plain = LatePreview();
        TSApplyPreviewInversion(plain.documentView.enclosingScrollView, NO);
        plain.scaleFactor = 4;
        CheckLateBar(plain, NO, @"magnifying a light document preview");
        MyPDFKitView *twoUp = SpreadPreview(PagesOfWidths(410, 410), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(twoUp.documentView.enclosingScrollView, YES);
        NSScrollView *twoScroll = twoUp.documentView.enclosingScrollView;
        NSView *twoClip = twoScroll.contentView;
        NSView *twoGutter = nil;
        for (NSView *subview in twoScroll.subviews)
            if ([NSStringFromClass(subview.class) containsString:@"Background"]) twoGutter = subview;
        check(twoClip != nil && twoGutter != nil && !twoScroll.hasHorizontalScroller, @"Two Pages starts without a horizontal scroller");
        ChooseTwoPages(twoUp);
        BOOL sameGutter = NO;
        for (NSView *subview in twoUp.documentView.enclosingScrollView.subviews)
            if (subview == twoGutter) sameGutter = YES;
        check(twoUp.documentView.enclosingScrollView.contentView == twoClip && sameGutter, @"Two Pages keeps the clip view and the area around the pages");
        CheckLateBar(twoUp, YES, @"choosing Two Pages from the document context menu");
        MyPDFKitView *twoUpPlain = SpreadPreview(PagesOfWidths(410, 410), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(twoUpPlain.documentView.enclosingScrollView, NO);
        ChooseTwoPages(twoUpPlain);
        CheckLateBar(twoUpPlain, NO, @"choosing Two Pages on a light document preview");
        MyPDFKitView *turned = SpreadPreview(PagesOfWidths(410, 1100), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(turned.documentView.enclosingScrollView, YES);
        check(!turned.documentView.enclosingScrollView.hasHorizontalScroller, @"the next page starts without a horizontal scroller");
        [turned goToNextPage:nil];
        CheckLateBar(turned, YES, @"turning to a wider page");
        MyPDFKitView *across = SpreadPreview(PagesOfWidths(410, 410), kPDFDisplaySinglePageContinuous);
        TSApplyPreviewInversion(across.documentView.enclosingScrollView, YES);
        check(!across.documentView.enclosingScrollView.hasHorizontalScroller, @"a vertical row starts without a horizontal scroller");
        across.displayDirection = kPDFDisplayDirectionHorizontal;
        CheckLateBar(across, YES, @"laying the pages in a row");
        MyPDFKitView *outlined = SpreadPreview(PagesOfWidths(410, 1100), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(outlined.documentView.enclosingScrollView, YES);
        NSView *outlineClip = outlined.documentView.enclosingScrollView.contentView;
        check(!outlined.documentView.enclosingScrollView.hasHorizontalScroller, @"the outline starts without a horizontal scroller");
        ChooseOutline(outlined);
        check(outlined.documentView.enclosingScrollView.contentView == outlineClip, @"the outline keeps the clip view");
        CheckLateBar(outlined, YES, @"choosing a wider page from the outline");
        MyPDFKitView *outlinedPlain = SpreadPreview(PagesOfWidths(410, 1100), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(outlinedPlain.documentView.enclosingScrollView, NO);
        ChooseOutline(outlinedPlain);
        CheckLateBar(outlinedPlain, NO, @"choosing a wider page from the outline on a light preview");
        MyPDFKitView *linked = SpreadPreview(PagesOfWidths(410, 1100), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(linked.documentView.enclosingScrollView, YES);
        check(!linked.documentView.enclosingScrollView.hasHorizontalScroller, @"the link starts without a horizontal scroller");
        FollowLink(linked);
        CheckLateBar(linked, YES, @"following an internal link to a wider page");
        MyPDFKitView *linkedPlain = SpreadPreview(PagesOfWidths(410, 1100), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(linkedPlain.documentView.enclosingScrollView, NO);
        FollowLink(linkedPlain);
        CheckLateBar(linkedPlain, NO, @"following an internal link on a light preview");
        MyPDFKitView *rectangle = SpreadPreview(PagesOfWidths(410, 1100), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(rectangle.documentView.enclosingScrollView, YES);
        [rectangle goToRect:NSMakeRect(40, 35, 70, 10) onPage:[rectangle.document pageAtIndex:1]];
        CheckLateBar(rectangle, YES, @"jumping to a rectangle on a wider page");
        MyPDFKitView *direct = SpreadPreview(PagesOfWidths(410, 1100), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(direct.documentView.enclosingScrollView, YES);
        [direct goToDestination:WideDestination(direct)];
        CheckLateBar(direct, YES, @"going to a destination on a wider page");
        check(direct.canGoBack, @"the destination is in the back history");
        [direct goBack:nil];
        [direct goForward:nil];
        CheckLateBar(direct, YES, @"going forward to a wider page");
        MyPDFKitView *selected = SpreadPreview(TextPages(), kPDFDisplaySinglePage);
        TSApplyPreviewInversion(selected.documentView.enclosingScrollView, YES);
        PDFSelection *selection = [[selected.document pageAtIndex:1] selectionForRange:NSMakeRange(0, 4)];
        check(selection.string.length > 0, @"the wider page has text to select");
        [selected goToSelection:selection];
        CheckLateBar(selected, YES, @"jumping to a selection on a wider page");
        MyPDFKitView *rotated = SpreadPreview(TallPage(), kPDFDisplaySinglePage);
        TSPreviewWindow *host = [TSPreviewWindow new];
        host.pdf = rotated;
        rotated.myPDFWindow = host;
        TSApplyPreviewInversion(rotated.documentView.enclosingScrollView, YES);
        check(!rotated.documentView.enclosingScrollView.hasHorizontalScroller, @"rotation starts without a horizontal scroller");
        [rotated rotateClockwise:nil];
        CheckLateBar(rotated, YES, @"rotating the document preview");
        MyPDFKitView *rotatedPlain = SpreadPreview(TallPage(), kPDFDisplaySinglePage);
        TSPreviewWindow *plainHost = [TSPreviewWindow new];
        plainHost.pdf = rotatedPlain;
        rotatedPlain.myPDFWindow = plainHost;
        TSApplyPreviewInversion(rotatedPlain.documentView.enclosingScrollView, NO);
        [rotatedPlain rotateCounterclockwise:nil];
        CheckLateBar(rotatedPlain, NO, @"rotating a light document preview");

        // Continuous reading. The wheel and a typeset reload create page views after the choice.
        NSWindow *readingWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 520)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
            backing:NSBackingStoreBuffered defer:NO];
        MyPDFKitView *reading = [[MyPDFKitView alloc] initWithFrame:readingWindow.contentView.bounds];
        reading.autoScales = NO;
        reading.displayMode = kPDFDisplaySinglePageContinuous;
        reading.document = ManyPages();
        [readingWindow.contentView addSubview:reading];
        [reading layoutSubtreeIfNeeded];
        reading.scaleFactor = 1;
        [reading goToFirstPage:nil];
        if (reading.documentView.subviews.count == 0) reading.scaleFactor = 1.5;
        TSApplyPreviewInversion(reading.documentView.enclosingScrollView, YES);
        NSSet *seen = PagePointers(reading);
        TurnWheel(reading);
        Settle();
        BOOL created = NO;
        for (NSView *child in reading.documentView.subviews)
            if ([NSStringFromClass(child.class) containsString:@"Page"] &&
                ![seen containsObject:[NSValue valueWithPointer:(__bridge void *)child]]) created = YES;
        check(created, @"scrolling the document preview creates a page view");
        CheckReadingPages(reading, YES, @"scrolling the document preview", 0.55);
        TSApplyPreviewInversion(reading.documentView.enclosingScrollView, NO);
        reading.document = ManyPages();
        CheckPagesLightAsTheyCome(reading, NO, @"replacing the document preview");
        CheckReadingPages(reading, NO, @"replacing the document preview", 0);
        TSApplyPreviewInversion(reading.documentView.enclosingScrollView, YES);
        NSString *typesetPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"texshop-document-reload.pdf"];
        NSData *typesetData = [ManyPages() dataRepresentation];
        check([typesetData writeToFile:typesetPath atomically:YES], @"the typeset PDF is written");
        PDFDocument *typeset = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:typesetPath]];
        check(typeset.pageCount == 12, @"typesetting reload reads the new PDF");
        reading.document = typeset;
        CheckPagesLightAsTheyCome(reading, YES, @"reloading the document preview after typesetting");
        CheckReadingPages(reading, YES, @"reloading the document preview after typesetting", 0);
        CheckSelectionLayers(reading);
        CheckEmptyTileHolder();
        CheckWatchCloses();
        CheckHookClasses();
        printf("PASS: %d preview window chrome checks\n", checks);
    }
    return 0;
}
'''
program = program.replace('HEADER', header).replace('VIEWMETHODS', view_text)
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory(prefix='texshop-preview-chrome-') as temp:
    temp = Path(temp)
    (temp / 'test.m').write_text(program, encoding='utf-8')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-I', str(root / 'Tests'), *include_args(root),
                    '-framework', 'Cocoa', '-framework', 'Quartz', str(temp / 'test.m'),
                    str(root / 'Sources/Preview/TSPreviewScrollerKeeper.m'), '-o', str(temp / 'test')], check=True)
    (temp / 'home/Library/Preferences').mkdir(parents=True)
    result = subprocess.run([str(temp / 'test')], capture_output=True, text=True, timeout=60,
                            env=dict(os.environ, HOME=str(temp / 'home'), CFFIXED_USER_HOME=str(temp / 'home')))
    if args.mutation:
        assert result.returncode == 1 and 'FAIL:' in result.stderr, result.stdout + result.stderr
        print('PASS: detected', args.mutation)
    elif result.returncode:
        raise SystemExit(result.stdout + result.stderr)
    else:
        print(result.stdout, end='')
