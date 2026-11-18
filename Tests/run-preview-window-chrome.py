#!/usr/bin/env python3
"""The preview's appearance applies to the pages, not to the window frame.

On macOS 26 and later the preview runs under the toolbar. Forcing the PDF scroll
view to the light appearance used to make AppKit draw the title bar and the
toolbar light as well. Scroll bars are part of that frame: they keep the system's
appearance and are not inverted. On macOS 27 an overlay scroller copies the clip
view and the document view, so those stay unset too. Each page view, and the area
around the pages, is still drawn light (and inverted for a dark preview).

The windows are never ordered on screen. Defaults stay in memory.
"""
import argparse, os, subprocess, tempfile
from pathlib import Path
from production_fragments import method, verify_embedded
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['scroll-appearance', 'bar-appearance', 'bar-filters', 'late-scroller', 'display-mode', 'late-page', 'late-direction', 'late-destination', 'late-rotation', 'visible-pages', 'document-changed'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
header = (root / 'Sources/Preview/TSPreviewAppearance.h').read_text()
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
view_methods = [method(view_source, signature) for signature in (
    '- (void)setScaleFactor:(CGFloat)scale', '- (void)setFrameSize:(NSSize)newSize',
    '- (void)setDisplayMode:(PDFDisplayMode)mode', '- (void)setDisplayDirection:(PDFDisplayDirection)direction',
    '- (void)keepHorizontalPositionDuring:(void (NS_NOESCAPE ^)(void))navigation',
    '- (BOOL)scrollingKeepsPage', '- (BOOL)isPageTurnFromScrolling:(SEL)selector',
    '- (void)goToNextPage:(id)sender',
    '- (NSMenu *)menuForEvent:(NSEvent *)theEvent',
    '- (MyPDFKitView *)previewPartForMenuEvent: (NSEvent *)theEvent',
    '- (PDFDestination *)internalLinkDestinationAtPoint: (NSPoint)viewPoint',
    '- (void)goToDestination:(PDFDestination *)destination',
    '- (void)goToRect:(PDFRect)rect onPage:(PDFPage *)page',
    '- (void)goToSelection:(PDFSelection *)selection',
    '- (IBAction) takeDestinationFromOutline: (id) sender',
    '- (void) rotateClockwise:sender',
    '- (void) rotateCounterclockwise:sender',
    '- (void) goBack:sender',
    '- (void) goForward: sender')]
fragments = [('complete method: ' + item.split('\n', 1)[0], view_source, item) for item in view_methods]
reapply = '    TSReapplyPreviewInversion(self.documentView.enclosingScrollView);\n'
def strip_reapply(index):
    assert view_methods[index].count(reapply) == 1, args.mutation
    view_methods[index] = view_methods[index].replace(reapply, '')
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
elif args.mutation == 'late-scroller':
    strip_reapply(0)
    strip_reapply(1)
elif args.mutation == 'display-mode':
    strip_reapply(2)
elif args.mutation == 'late-direction':
    strip_reapply(3)
elif args.mutation == 'late-page':
    strip_reapply(4)
elif args.mutation == 'late-destination':
    strip_reapply(11)
elif args.mutation == 'late-rotation':
    strip_reapply(15)
    strip_reapply(16)
elif args.mutation in ('visible-pages', 'document-changed'):
    marker = ('PDFViewVisiblePagesChangedNotification' if args.mutation == 'visible-pages'
              else 'PDFViewDocumentChangedNotification')
    old = '    TSFollowPreviewInversion(pdfView.documentView.enclosingScrollView); // %s\n' % marker
    assert header.count(old) == 1, args.mutation
    header = header.replace(old, '')
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
    check(scroll.documentView.appearance == nil && scroll.documentView.contentFilters.count == 0,
          [what stringByAppendingString:@": the document view stays with the system"]);
    BOOL page = NO;
    for (NSView *child in scroll.documentView.subviews) {
        if (![NSStringFromClass(child.class) containsString:@"Page"]) continue;
        page = YES;
        check(child.appearance == light, [what stringByAppendingString:@": the page is drawn light"]);
        check(child.contentFilters.count == (inverted ? 3 : 0), [what stringByAppendingString:@": the page has the preview's filters"]);
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
@end
@implementation MyPDFKitView
- (void)fitContentWidthKeepingTop:(TSContentTop)top {}
- (void)closePinnedLinkPreview {}
- (void)cleanupMarquee:(BOOL)terminate {}
- (void)cleanupMarqueeKeepingPinnedLinkPreview {}
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
static void CheckReadingPages(PDFView *pdf, BOOL inverted, NSString *what, NSTimeInterval wait) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:wait]];
    [pdf layoutSubtreeIfNeeded];
    NSScrollView *scroll = pdf.documentView.enclosingScrollView;
    CheckPageViews(scroll, NSAppearanceNameDarkAqua, inverted, what);
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
        PDFView *reading = [[PDFView alloc] initWithFrame:readingWindow.contentView.bounds];
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
        CheckReadingPages(reading, NO, @"replacing the document preview", 0.32);
        TSApplyPreviewInversion(reading.documentView.enclosingScrollView, YES);
        NSString *typesetPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"texshop-document-reload.pdf"];
        NSData *typesetData = [ManyPages() dataRepresentation];
        check([typesetData writeToFile:typesetPath atomically:YES], @"the typeset PDF is written");
        PDFDocument *typeset = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:typesetPath]];
        check(typeset.pageCount == 12, @"typesetting reload reads the new PDF");
        reading.document = typeset;
        CheckReadingPages(reading, YES, @"reloading the document preview after typesetting", 0.32);
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
