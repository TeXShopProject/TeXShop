#!/usr/bin/env python3
"""Document windows and the Preview window's toolbar edge.

The windows of the compiled TSDocument nibs of every language get an Expanded
toolbar and then the production preparation setupToolbar uses. They are not
ordered on screen. On macOS 26 and later the source window, the Preview
window and the combined window use a full-size content view and are not given
a toolbar line. The glass then takes on the page color and ends in a hard
edge, as Preview.app does. Earlier systems keep the nib's separator. A clip
view clips to its bounds, so a scrolled page cannot paint into the toolbar.
The test checks:

- the three document windows use a full-size content view on macOS 26 and
  later, and none is given a toolbar line; the text and the first page start
  at the toolbar. Earlier systems keep the nib's separator, and the Preview
  clip view clips;
- splitting the source (the production splitWindow:) puts the divider in the
  middle of the area that can be seen, in the source window and in the combined
  window, with and without a full-size content view (the combined window used to
  leave the lower part far smaller);
- a drawer at the side of the Preview window, on macOS 26 and later, starts
  where the rounding of the window's top corner ends; the same drawer beside the
  combined window starts where
  the rounding of the window's top corner ends, beside the title bar and the toolbar
  (#67), and not higher than the area below the toolbar where that area starts higher,
  as in full screen, also when it is left open into and out of full screen; on macOS 27
  and later the window's corner radius that AppKit reports still gives that place; the
  drawer's frame takes the window's colors in Dark Mode, on every system.

--images DIR draws the windows of the Base and Japanese nibs offscreen, before
and after TSDocumentWindowPrepare, in Light and Dark Mode. Offscreen drawing has
no glass: the toolbar and the band under it are drawn flat.
"""
import argparse, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file
from production_fragments import method, verify_embedded

MUTATIONS = {
    # The windows keep their content below the toolbar.
    'not-full-size': ('TSDocumentWindowGlass.m', '            window.styleMask |= NSWindowStyleMaskFullSizeContentView;\n', ''),
    # The window keeps its content size and gets lower by the height of the toolbar.
    'frame-not-kept': ('TSDocumentWindowGlass.m', '        [window setFrame:frame display:NO];\n', ''),
    # Splitting the source leaves the parts where AppKit puts them.
    'source-split-not-even': ('TSDocument.m', '\t\tTSDocumentWindowSplitEvenly(splitView);\n', ''),
    # The band under the toolbar counts as part of the top part.
    'band-counted': ('TSDocumentWindowGlass.m', '    CGFloat hidden = TSDocumentWindowHiddenTop(splitView);\n', '    CGFloat hidden = 0;\n'),
    # The drawer starts at the top of the window, beside the rounded corner.
    'drawer-at-top': ('TSDocumentWindowGlass.m', '    CGFloat offset = base.doubleValue + (side ? MIN(TSWindowCornerHeight, TSHiddenTopBand(window)) : 0);\n',
        '    CGFloat offset = base.doubleValue;\n'),
    # The drawer starts right below the title bar, as in 6.00 beta 8.
    'drawer-below-title': ('TSDocumentWindowGlass.m', '    CGFloat offset = base.doubleValue + (side ? MIN(TSWindowCornerHeight, TSHiddenTopBand(window)) : 0);\n',
        '    CGFloat offset = base.doubleValue + (side ? MIN(NSHeight([NSWindow frameRectForContentRect:NSMakeRect(0, 0, 100, 100) styleMask:window.styleMask & ~NSWindowStyleMaskFullSizeContentView]) - 100, TSHiddenTopBand(window)) : 0);\n'),
    # The drawer starts below the toolbar and the bars under it, as in 6.00 beta 1 to 7.
    'drawer-below-toolbar': ('TSDocumentWindowGlass.m', '    CGFloat offset = base.doubleValue + (side ? MIN(TSWindowCornerHeight, TSHiddenTopBand(window)) : 0);\n',
        '    CGFloat offset = base.doubleValue + (side ? TSHiddenTopBand(window) : 0);\n'),
    # The drawer keeps clear of the rounded corner also where the band is shorter, as in full screen.
    'drawer-corner-always': ('TSDocumentWindowGlass.m', '    CGFloat offset = base.doubleValue + (side ? MIN(TSWindowCornerHeight, TSHiddenTopBand(window)) : 0);\n',
        '    CGFloat offset = base.doubleValue + (side ? TSWindowCornerHeight : 0);\n'),
    # The rounding is taken to end at the radius, not at 1.5 times the radius.
    'drawer-at-radius': ('TSDocumentWindowGlass.m', 'static const CGFloat TSWindowCornerHeight = 24;\n',
        'static const CGFloat TSWindowCornerHeight = 16;\n'),
    # A drawer left open out of full screen stays at the top, beside the rounded corner.
    'drawer-not-placed-after-full-screen': ('TSDocumentWindowGlass.m', '        for (NSNotificationName name in @[NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification])\n',
        '        for (NSNotificationName name in @[])\n'),
    # The drawer's frame keeps AppKit's light gray bezel.
    'drawer-frame-light': ('TSDocumentWindowGlass.m', '    [frame addSubview:backing positioned:NSWindowBelow relativeTo:nil];\n', ''),
    # The source window and the combined window are given the Preview window's line.
    'separator-on-source': ('TSDocumentWindowGlass.m',
        'void TSDocumentWindowPrepare(NSWindow *window)\n{\n    TSDocumentWindowPrepareChrome(window, TSDocumentWindowsUseFullSizeContent());\n}\n',
        'void TSDocumentWindowPrepare(NSWindow *window)\n{\n    TSDocumentWindowPrepareChrome(window, TSDocumentWindowsUseFullSizeContent());\n    if (window)\n        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleLine;\n}\n'),
    # The Preview clip view draws a scrolled page into the toolbar.
    'preview-clip-open': ('TSDocumentWindowGlass.m',
        '            view.clipsToBounds = YES;\n',
        '            view.clipsToBounds = NO;\n'),
    # setupToolbar's trio skips the Preview window, so it is never prepared.
    'preview-not-prepared': ('TSDocumentWindowGlass.m',
        '        TSDocumentWindowPrepare(window);\n',
        '        if (window != previewWindow)\n            TSDocumentWindowPrepare(window);\n'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--images', type=Path, help='write offscreen pictures of the windows here')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
names = ('TSDocumentWindowGlass.m', 'TSDocument.m')
text = {name: source_file(root, name).read_text(encoding='latin1') for name in names}
split_method = method(text['TSDocument.m'], '- (void) splitWindow: sender')
fragments = [('complete method: splitWindow:', text['TSDocument.m'], split_method)]
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    target = split_method if name == 'TSDocument.m' else text[name]
    assert target.count(old) == 1, args.mutation
    if name == 'TSDocument.m':
        split_method = split_method.replace(old, new)
    else:
        text[name] = text[name].replace(old, new)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSDocumentWindowGlass.h"
static int failures, checks;
static void Check(BOOL ok, NSString *name) { checks++; if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }
static void TSSplitToggleItemsFollowSplit(void) {}

// The status bar under the source: only its messages, sent to nil here.
@interface NSObject (TSSourceStatusBarMessages)
- (void)selectionDidChange;
- (void)placeBelowView:(id)view;
@end
// The nib's File's Owner, with the instance variables splitWindow: uses.
@interface TSDocument : NSObject
{
@public
    NSSplitView *splitView;
    NSScrollView *scrollView, *scrollView2;
    NSTextView *textView, *textView1, *textView2;
    NSView *leftView, *rightView;
    NSWindow *textWindow, *fullSplitWindow;
    NSDrawer *myDrawer;
    BOOL windowIsSplit, useFullSplitWindow;
}
@property (strong) NSWindow *pdfKitWindow;
@property (strong) id sourceStatusBar; // the status bar under the source; nil here
@property (strong) PDFView *myPDFKitView, *myPDFKitView2;
@end
@implementation TSDocument
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
- (void)removeCurrentLineColor:(id)view {}
SPLITMETHOD
@end
static void Register(NSString *name, Class base) {
    if (NSClassFromString(name)) return;
    objc_registerClassPair(objc_allocateClassPair(base, name.UTF8String, 0));
}

// An Expanded toolbar with a few items, as the document windows have.
@interface GlassToolbar : NSObject <NSToolbarDelegate> @end
@implementation GlassToolbar
- (NSArray *)items { return @[@"a", @"b", @"c", @"d", @"e"]; }
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return self.items; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return self.items; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = identifier; item.image = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:nil];
    return item;
}
@end
static GlassToolbar *toolbarDelegate;

static void Settle(NSWindow *window) {
    for (int i = 0; i < 4; i++) {
        [window layoutIfNeeded];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}
// A view at the top left corner of a window that asks for corners concentric with the window's:
// macOS 27 and later tell the radius they get.
@interface CornerProbe : NSView @end
@implementation CornerProbe
- (NSViewCornerConfiguration *)cornerConfiguration API_AVAILABLE(macos(27.0)) {
    return [NSViewCornerConfiguration configurationWithRadius:NSViewCornerRadius.containerConcentricRadius];
}
@end
// A drawer opens only beside a window on the screen; this one tells that it is open.
static NSDrawer *drawerLooksOpen; static IMP originalDrawerState;
static NSDrawerState DrawerState(NSDrawer *self, SEL _cmd) {
    return self == drawerLooksOpen ? NSDrawerOpenState : ((NSDrawerState (*)(id, SEL))originalDrawerState)(self, _cmd);
}
static CGFloat Band(NSWindow *window) { return NSHeight(window.contentView.frame) - NSMaxY(window.contentLayoutRect); }
// A window whose band under the toolbar is shorter than the rounding of its corners, as in full screen.
static NSWindow *shortBandWindow; static CGFloat shortBand; static IMP originalLayoutRect;
static NSRect ShortLayoutRect(NSWindow *self, SEL _cmd) {
    NSRect rect = ((NSRect (*)(id, SEL))originalLayoutRect)(self, _cmd);
    if (self == shortBandWindow)
        rect.size.height = NSHeight(self.contentView.frame) - shortBand - NSMinY(rect);
    return rect;
}
// The height of the title bar alone, without the toolbar.
static CGFloat TitleBar(NSWindow *window) {
    NSRect content = NSMakeRect(0, 0, 100, 100);
    return NSHeight([NSWindow frameRectForContentRect:content styleMask:window.styleMask & ~NSWindowStyleMaskFullSizeContentView]) - 100;
}
static NSString *SampleText(void) {
    NSMutableString *s = [NSMutableString stringWithString:@"\\documentclass{article}\n\\begin{document}\n"];
    for (int i = 1; i <= 120; i++) [s appendFormat:@"Line %d of the sample: the text runs under the toolbar when it is scrolled.\n", i];
    [s appendString:@"\\end{document}\n"];
    return s;
}

static NSData *nibData;
static PDFDocument *pdf;
// A fresh document from the nib, with toolbars, text and pages; prepared as setupToolbar does it.
static TSDocument *Open(BOOL prepare) {
    TSDocument *doc = [TSDocument new];
    NSNib *nib = [[NSNib alloc] initWithNibData:nibData bundle:nil];
    NSArray *objects;
    if (![nib instantiateWithOwner:doc topLevelObjects:&objects]) return nil;
    for (NSWindow *w in objects) if ([w isKindOfClass:NSWindow.class]) w.releasedWhenClosed = NO;
    doc->textView = doc->textView1;
    [doc->scrollView2 removeFromSuperview];
    [doc.myPDFKitView2 removeFromSuperview];
    [doc->textView1.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:SampleText()
        attributes:@{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:13]}]];
    [doc->textView2.layoutManager replaceTextStorage:doc->textView1.textStorage];
    doc->textView1.selectedRange = NSMakeRange(0, 0);
    doc.myPDFKitView.document = pdf;
    for (NSWindow *w in @[doc->textWindow, doc.pdfKitWindow, doc->fullSplitWindow]) {
        w.toolbarStyle = NSWindowToolbarStyleExpanded;
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:[@"glass-" stringByAppendingString:NSStringFromClass(w.class)]];
        toolbar.delegate = toolbarDelegate; w.toolbar = toolbar;
    }
    [doc->textWindow setFrame:NSMakeRect(40, 40, 600, 640) display:NO];
    [doc.pdfKitWindow setFrame:NSMakeRect(700, 40, 640, 760) display:NO];
    if (prepare) {
        NSRect textFrame = doc->textWindow.frame;
        NSRect previewFrame = doc.pdfKitWindow.frame;
        NSRect combinedFrame = doc->fullSplitWindow.frame;
        // The same call setupToolbar makes. All three windows go through it.
        TSDocumentWindowPrepareTrio(doc->textWindow, doc.pdfKitWindow, doc->fullSplitWindow);
        Check(NSEqualRects(textFrame, doc->textWindow.frame) && NSEqualRects(previewFrame, doc.pdfKitWindow.frame)
              && NSEqualRects(combinedFrame, doc->fullSplitWindow.frame),
              @"the three document windows keep their frames");
    }
    for (NSWindow *w in @[doc->textWindow, doc.pdfKitWindow, doc->fullSplitWindow]) Settle(w);
    return doc;
}
// As doMove does: the source and the Preview go into the two sides of the combined window.
static void Combine(TSDocument *doc) {
    [doc->splitView removeFromSuperview];
    [doc->leftView addSubview:doc->splitView];
    doc->splitView.frame = doc->leftView.bounds;
    NSView *pdfSplit = doc.myPDFKitView.superview;
    [pdfSplit removeFromSuperview];
    [doc->rightView addSubview:pdfSplit];
    pdfSplit.frame = doc->rightView.bounds;
    [doc->fullSplitWindow setFrame:NSMakeRect(40, 40, 1120, 640) display:NO];
    doc->useFullSplitWindow = YES;
    Settle(doc->fullSplitWindow);
}
// The heights of the two source parts that can be seen.
static void SourceParts(TSDocument *doc, CGFloat *upper, CGFloat *lower) {
    *upper = NSHeight(doc->scrollView.frame) - TSDocumentWindowHiddenTop(doc->splitView);
    *lower = NSHeight(doc->scrollView2.frame);
}
static NSRect FirstLine(NSTextView *view) {
    NSRect line = [view.layoutManager lineFragmentRectForGlyphAtIndex:0 effectiveRange:NULL];
    line = NSOffsetRect(line, view.textContainerOrigin.x, view.textContainerOrigin.y);
    return [view convertRect:line toView:nil];
}
static void ScrollTop(NSScrollView *scroll) {
    NSClipView *clip = scroll.contentView;
    NSRect b = clip.bounds; b.origin.y = scroll.documentView.isFlipped ? -1e6 : 1e6;
    [clip scrollToPoint:[clip constrainBoundsRect:b].origin]; [scroll reflectScrolledClipView:clip];
}
static NSBitmapImageRep *Draw(NSWindow *window) {
    NSView *frame = window.contentView.superview;
    [window layoutIfNeeded]; [frame layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep = [frame bitmapImageRepForCachingDisplayInRect:frame.bounds];
    [frame cacheDisplayInRect:frame.bounds toBitmapImageRep:rep];
    return rep;
}
static void Save(NSWindow *window, NSString *dir, NSString *name) {
    if (!dir) return;
    [[Draw(window) representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:YES];
}
static NSDrawer *OpenDrawer(TSDocument *doc) {
    NSDrawer *drawer = doc->myDrawer;
    // A drawer opens only beside a window on the screen; the window is told it opens.
    [NSNotificationCenter.defaultCenter postNotificationName:NSDrawerWillOpenNotification object:drawer];
    return drawer;
}
static NSView *DrawerFrame(NSDrawer *drawer) { return drawer.contentView.superview; }
static NSColor *DrawerEdge(NSDrawer *drawer) {
    NSView *frame = DrawerFrame(drawer);
    frame.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSBitmapImageRep *rep = [frame bitmapImageRepForCachingDisplayInRect:frame.bounds];
    [frame cacheDisplayInRect:frame.bounds toBitmapImageRep:rep];
    return [[rep colorAtX:3 y:rep.pixelsHigh / 2] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    toolbarDelegate = [GlassToolbar new];
    for (NSString *name in @[@"TSConsoleWindow", @"TSFullSplitWindow", @"TSHTMLWindow", @"TSLogWindow",
                             @"TSPreviewWindow", @"TSTextEditorWindow"]) Register(name, NSWindow.class);
    Register(@"MyPDFView", NSView.class);
    Register(@"MyPDFKitView", PDFView.class); Register(@"ScrapPDFKitView", PDFView.class);
    Register(@"TSTextView", NSTextView.class); Register(@"ScrapTextView", NSTextView.class);
    Register(@"TSAdvancedFindTextView", NSTextView.class);
    pdf = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:@(argv[1])]];
    Check(pdf.pageCount >= 3, @"the test document has pages");
    NSString *images = getenv("IMAGES") ? @(getenv("IMAGES")) : nil;
    BOOL glass = NO;
    if (@available(macOS 26.0, *)) glass = YES;
    printf("full-size content view on this system: %s\n", glass ? "yes" : "no");

    for (int i = 2; i < argc; i++) {
        NSString *path = @(argv[i]);
        NSString *lang = path.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.lastPathComponent.stringByDeletingPathExtension;
        NSString *nibName = [NSString stringWithFormat:@" (%@)", lang];
        nibData = [NSData dataWithContentsOfFile:path];
        BOOL pictures = images && ([lang isEqual:@"Base"] || [lang isEqual:@"ja"]);

        TSDocument *doc = Open(YES);
        Check(doc && doc->textWindow && doc.pdfKitWindow && doc->fullSplitWindow && doc->myDrawer, [@"the nib has the document windows" stringByAppendingString:nibName]);
        for (NSWindow *w in @[doc->textWindow, doc.pdfKitWindow, doc->fullSplitWindow])
            Check(((w.styleMask & NSWindowStyleMaskFullSizeContentView) != 0) == glass
                  && w.titlebarSeparatorStyle != NSTitlebarSeparatorStyleLine,
                  [NSString stringWithFormat:@"%@ uses a full-size content view on macOS 26 and later and keeps the nib's toolbar separator%@", NSStringFromClass(w.class), nibName]);
        NSClipView *previewClip = doc.myPDFKitView.documentView.enclosingScrollView.contentView;
        Check(previewClip.clipsToBounds, [@"a scrolled page cannot paint the Preview toolbar" stringByAppendingString:nibName]);
        if (!glass) continue;

        // The source window: the first line starts below the toolbar.
        CGFloat band = Band(doc->textWindow);
        ScrollTop(doc->scrollView); Settle(doc->textWindow);
        NSRect first = FirstLine(doc->textView1);
        Check(band > 20 && fabs(doc->scrollView.contentInsets.top - band) < 0.5,
              [NSString stringWithFormat:@"the source's top inset is the band under the toolbar (%.1f, %.1f)%@", doc->scrollView.contentInsets.top, band, nibName]);
        Check(fabs(NSMaxY(first) - NSMaxY(doc->textWindow.contentLayoutRect)) <= 1.5,
              [NSString stringWithFormat:@"the first line starts below the toolbar (%.1f, %.1f)%@", NSMaxY(first), NSMaxY(doc->textWindow.contentLayoutRect), nibName]);
        // The Preview window runs under the toolbar. PDFView keeps its own margin
        // above the page, about five points on this system.
        NSWindow *pw = doc.pdfKitWindow; PDFView *pv = doc.myPDFKitView;
        [pv goToFirstPage:nil]; ScrollTop(pv.documentView.enclosingScrollView); Settle(pw);
        PDFPage *page = [pdf pageAtIndex:0];
        NSRect pageRect = [pv convertRect:[pv convertRect:[page boundsForBox:kPDFDisplayBoxCropBox] fromPage:page] toView:nil];
        CGFloat previewBand = Band(pw);
        Check(previewBand > 20
              && NSMaxY(pageRect) <= NSMaxY(pw.contentLayoutRect) + 0.5
              && NSMaxY(pageRect) > NSMaxY(pw.contentLayoutRect) - 20,
              [NSString stringWithFormat:@"the first page starts at the toolbar (%.1f, %.1f, band %.1f)%@",
               NSMaxY(pageRect), NSMaxY(pw.contentLayoutRect), previewBand, nibName]);
        if (pictures) {
            for (NSString *look in @[@"light", @"dark"]) {
                NSAppearance *a = [NSAppearance appearanceNamed:[look isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                doc->textWindow.appearance = a; pw.appearance = a;
                Save(doc->textWindow, images, [NSString stringWithFormat:@"%@-after-01-source-top-%@", lang, look]);
                Save(pw, images, [NSString stringWithFormat:@"%@-after-05-preview-top-%@", lang, look]);
            }
        }

        // Splitting the source window: the parts share the area below the toolbar.
        [doc splitWindow:nil]; Settle(doc->textWindow);
        CGFloat upper, lower; SourceParts(doc, &upper, &lower);
        Check(fabs(upper - lower) <= 1, [NSString stringWithFormat:@"the source window splits in the middle of the area below the toolbar (%.1f, %.1f)%@", upper, lower, nibName]);
        if (pictures)
            for (NSString *look in @[@"light", @"dark"]) {
                doc->textWindow.appearance = [NSAppearance appearanceNamed:[look isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                Save(doc->textWindow, images, [NSString stringWithFormat:@"%@-after-03-source-split-%@", lang, look]);
            }
        [doc splitWindow:nil]; Settle(doc->textWindow);
        Check(doc->scrollView2.superview == nil, [@"the source window is unsplit again" stringByAppendingString:nibName]);

        // The Preview window runs under the toolbar, so its drawer starts where the
        // rounding of the top corner ends, beside the title bar and the toolbar.
        CGFloat previewBase = doc->myDrawer.leadingOffset;
        NSDrawer *previewDrawer = OpenDrawer(doc);
        Check(fabs(previewDrawer.leadingOffset - (previewBase + 24)) < 0.5,
              [NSString stringWithFormat:@"the Preview window's drawer starts where the rounding of the corner ends (%.1f)%@",
               previewDrawer.leadingOffset, nibName]);
        // The same drawer beside the combined window, whose content still runs under the toolbar,
        // starts where the rounding of that window's top corner ends (24 points below the top),
        // beside the title bar and the toolbar (#67).
        NSWindow *host = doc->fullSplitWindow;
        [doc->myDrawer setParentWindow:host];
        // Opening the drawer on the Preview window did not add the corner height.
        // Later checks use the offset from before that.
        CGFloat base = previewBase;
        NSDrawer *drawer = OpenDrawer(doc);
        Check(TitleBar(host) > 24 && TitleBar(host) < Band(host) - 20 &&
              fabs(drawer.leadingOffset - (base + 24)) < 0.5,
              [NSString stringWithFormat:@"the drawer starts where the rounding of the corner ends (%.1f, title bar %.1f, band %.1f)%@",
               drawer.leadingOffset, TitleBar(host), Band(host), nibName]);
        // macOS 27 and later tell the corner radius: the rounding (a continuous curve) ends at
        // 1.5 times it, where the drawer starts.
        if (@available(macOS 27.0, *)) {
            CornerProbe *probe = [[CornerProbe alloc] initWithFrame:NSMakeRect(0, NSHeight(host.contentView.bounds) - 80, 80, 80)];
            [host.contentView addSubview:probe];
            [probe invalidateCornerConfiguration];
            CGFloat radius = probe.effectiveCornerRadii.topLeft;
            [probe removeFromSuperview];
            Check(radius > 0 && fabs(1.5 * radius - (drawer.leadingOffset - base)) < 0.5,
                  [NSString stringWithFormat:@"the window's corner radius %.1f ends its rounding where the drawer starts (%.1f)%@",
                   radius, drawer.leadingOffset - base, nibName]);
        }
        // A band shorter than the rounding, as in full screen: the drawer does not go higher than it.
        if (!originalLayoutRect) {
            Method m = class_getInstanceMethod(NSWindow.class, @selector(contentLayoutRect));
            originalLayoutRect = method_setImplementation(m, (IMP)ShortLayoutRect);
            originalDrawerState = method_setImplementation(class_getInstanceMethod(NSDrawer.class, @selector(state)), (IMP)DrawerState);
        }
        for (NSNumber *band in @[@9, @21]) {
            shortBandWindow = host; shortBand = band.doubleValue;
            OpenDrawer(doc);
            Check(fabs(Band(host) - shortBand) < 0.5 && fabs(drawer.leadingOffset - (base + shortBand)) < 0.5,
                  [NSString stringWithFormat:@"with a band of %.0f the drawer starts below the band (%.1f)%@",
                   shortBand, drawer.leadingOffset, nibName]);
        }
        // A drawer left open into and out of full screen (where the band is 0) is placed again
        // when the window has gone in or out, without being opened again.
        drawerLooksOpen = drawer;
        shortBandWindow = host; shortBand = 0;
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidEnterFullScreenNotification object:host];
        Check(fabs(drawer.leadingOffset - base) < 0.5,
              [NSString stringWithFormat:@"an open drawer goes to the top in full screen (%.1f)%@", drawer.leadingOffset, nibName]);
        shortBandWindow = nil;
        [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidExitFullScreenNotification object:host];
        Check(fabs(drawer.leadingOffset - (base + 24)) < 0.5,
              [NSString stringWithFormat:@"out of full screen an open drawer goes back below the rounded corner (%.1f)%@", drawer.leadingOffset, nibName]);
        drawerLooksOpen = nil;
        OpenDrawer(doc);
        NSColor *edge = DrawerEdge(drawer);
        Check(edge.brightnessComponent < 0.4, [NSString stringWithFormat:@"in Dark Mode the drawer's frame is dark (%.2f)%@", edge.brightnessComponent, nibName]);
        OpenDrawer(doc);
        NSUInteger backings = 0;
        for (NSView *v in DrawerFrame(drawer).subviews) if ([NSStringFromClass(v.class) isEqual:@"TSDrawerBacking"]) backings++;
        Check(backings == 1, [@"opening the drawer again adds nothing more" stringByAppendingString:nibName]);

        // The combined window: both parts of the source share the area below the toolbar.
        Combine(doc);
        [doc splitWindow:nil]; Settle(doc->fullSplitWindow);
        SourceParts(doc, &upper, &lower);
        Check(fabs(upper - lower) <= 1, [NSString stringWithFormat:@"the combined window splits the source in the middle of the area below the toolbar (%.1f, %.1f)%@", upper, lower, nibName]);
        if (pictures)
            for (NSString *look in @[@"light", @"dark"]) {
                doc->fullSplitWindow.appearance = [NSAppearance appearanceNamed:[look isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                Save(doc->fullSplitWindow, images, [NSString stringWithFormat:@"%@-after-11-one-window-split-%@", lang, look]);
            }

        // As on macOS 14 and 15: windows without a full-size content view.
        TSDocument *old = Open(YES);
        for (NSWindow *w in @[old->textWindow, old.pdfKitWindow, old->fullSplitWindow]) { w.styleMask &= ~NSWindowStyleMaskFullSizeContentView; Settle(w); }
        [old splitWindow:nil]; Settle(old->textWindow);
        SourceParts(old, &upper, &lower);
        Check(fabs(upper - lower) <= 1, [NSString stringWithFormat:@"without a full-size content view the source window splits in the middle (%.1f, %.1f)%@", upper, lower, nibName]);
        [old splitWindow:nil];
        Combine(old);
        [old splitWindow:nil]; Settle(old->fullSplitWindow);
        SourceParts(old, &upper, &lower);
        Check(fabs(upper - lower) <= 1, [NSString stringWithFormat:@"without a full-size content view the combined window splits the source in the middle (%.1f, %.1f)%@", upper, lower, nibName]);
        CGFloat oldBase = old->myDrawer.leadingOffset;
        NSDrawer *oldDrawer = OpenDrawer(old);
        Check(fabs(oldDrawer.leadingOffset - oldBase) < 0.5, [@"without a full-size content view the drawer stays where it was" stringByAppendingString:nibName]);
        Check(DrawerEdge(oldDrawer).brightnessComponent < 0.4, [@"without a full-size content view the drawer's frame is dark in Dark Mode too" stringByAppendingString:nibName]);

        // Before: the windows as they were, for the pictures.
        if (pictures) {
            TSDocument *before = Open(NO);
            NSWindow *bw = before.pdfKitWindow;
            ScrollTop(before->scrollView); [before.myPDFKitView goToFirstPage:nil]; ScrollTop(before.myPDFKitView.documentView.enclosingScrollView);
            for (NSString *look in @[@"light", @"dark"]) {
                NSAppearance *a = [NSAppearance appearanceNamed:[look isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                before->textWindow.appearance = a; bw.appearance = a;
                Save(before->textWindow, images, [NSString stringWithFormat:@"%@-before-01-source-top-%@", lang, look]);
                Save(bw, images, [NSString stringWithFormat:@"%@-before-05-preview-top-%@", lang, look]);
            }
            [before splitWindow:nil]; Settle(before->textWindow);
            for (NSString *look in @[@"light", @"dark"]) {
                before->textWindow.appearance = [NSAppearance appearanceNamed:[look isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                Save(before->textWindow, images, [NSString stringWithFormat:@"%@-before-03-source-split-%@", lang, look]);
            }
            [before splitWindow:nil];
            Combine(before);
            [before splitWindow:nil]; Settle(before->fullSplitWindow);
            for (NSString *look in @[@"light", @"dark"]) {
                before->fullSplitWindow.appearance = [NSAppearance appearanceNamed:[look isEqual:@"dark"] ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
                Save(before->fullSplitWindow, images, [NSString stringWithFormat:@"%@-before-11-one-window-split-%@", lang, look]);
            }
        }
    }
    if (failures) return 1;
    printf("PASS: %d checks: document windows run under the toolbar on macOS 26 and later\n", checks);
} return 0; }
'''.replace('SPLITMETHOD', split_method)
if not args.mutation:
    verify_embedded(program, fragments)

nibs = sorted((str(p) for p in (root / 'Resources/Interfaces').glob('*.lproj/TSDocument.nib/keyedobjects*.nib')),
              key=lambda p: '/Base.lproj/' not in p)
if len(nibs) < 12:
    sys.exit(f'FAIL: only {len(nibs)} compiled TSDocument nibs')
with tempfile.TemporaryDirectory(prefix='texshop-full-size-') as tmp:
    tmp = Path(tmp)
    tex = tmp / 'doc.tex'
    tex.write_text('\\documentclass{article}\\begin{document}\\section{One}' + ' '.join(['Text of the page.'] * 400)
                   + '\\section{Two}' + ' '.join(['More text.'] * 600) + '\\end{document}\n')
    pdflatex = next((p for p in ('/Applications/TeXLive/2026/bin/universal-darwin/pdflatex', '/Library/TeX/texbin/pdflatex')
                     if Path(p).exists()), 'pdflatex')
    subprocess.run([pdflatex, '-interaction=batchmode', '-output-directory', str(tmp), str(tex)],
                   check=True, stdout=subprocess.DEVNULL, cwd=tmp)
    (tmp / 'probe.m').write_text(program, encoding='latin1')
    (tmp / 'TSDocumentWindowGlass.m').write_text(text['TSDocumentWindowGlass.m'], encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'Quartz', *include_args(root),
                    '-I', str(root / 'Tests'), str(tmp / 'probe.m'), str(tmp / 'TSDocumentWindowGlass.m'),
                    '-o', str(tmp / 'probe')], check=True)
    env = None
    if args.images:
        import os
        args.images.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, IMAGES=str(args.images.resolve()))
    result = subprocess.run([str(tmp / 'probe'), str(tmp / 'doc.pdf'), *nibs], capture_output=True, text=True, timeout=600, env=env)
    print(result.stdout, end='')
    if args.mutation:
        if result.returncode == 0:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif result.returncode:
        print(result.stderr[-3000:])
        sys.exit('FAIL')
