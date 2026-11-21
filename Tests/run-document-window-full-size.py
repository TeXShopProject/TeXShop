#!/usr/bin/env python3
"""Document windows whose content runs under the toolbar (macOS 26 and later).

The windows of the compiled TSDocument nibs of every language, which are never
ordered on screen, get an Expanded toolbar and then the production
TSDocumentWindowPrepare, as setupToolbar does. The test checks:

- the source window, the Preview window and the combined window use a full-size
  content view, and the text and the first page start below the toolbar;
- splitting the source (the production splitWindow:) puts the divider in the
  middle of the area that can be seen, in the source window and in the combined
  window, with and without a full-size content view (the combined window used to
  leave the lower part far smaller);
- a drawer at the side of the Preview window starts right below the title bar, beside
  the toolbar (#67), and not higher than the area below the toolbar where that area
  starts higher, as in full screen; its frame takes the window's colors in Dark Mode,
  on every system.

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
    'not-full-size': ('TSDocumentWindowGlass.m', '        window.styleMask |= NSWindowStyleMaskFullSizeContentView;\n', ''),
    # The window keeps its content size and gets lower by the height of the toolbar.
    'frame-not-kept': ('TSDocumentWindowGlass.m', '        [window setFrame:frame display:NO];\n', ''),
    # Splitting the source leaves the parts where AppKit puts them.
    'source-split-not-even': ('TSDocument.m', '\t\tTSDocumentWindowSplitEvenly(splitView);\n', ''),
    # The band under the toolbar counts as part of the top part.
    'band-counted': ('TSDocumentWindowGlass.m', '    CGFloat hidden = TSDocumentWindowHiddenTop(splitView);\n', '    CGFloat hidden = 0;\n'),
    # The drawer starts at the top of the window, beside the title bar.
    'drawer-at-top': ('TSDocumentWindowGlass.m', '    CGFloat offset = base.doubleValue + (side ? MIN(TSTitleBarHeight(window), TSHiddenTopBand(window)) : 0);\n',
        '    CGFloat offset = base.doubleValue;\n'),
    # The drawer starts below the toolbar and the bars under it, as before #67.
    'drawer-below-toolbar': ('TSDocumentWindowGlass.m', '    CGFloat offset = base.doubleValue + (side ? MIN(TSTitleBarHeight(window), TSHiddenTopBand(window)) : 0);\n',
        '    CGFloat offset = base.doubleValue + (side ? TSHiddenTopBand(window) : 0);\n'),
    # The drawer starts right below the title bar also where the band is shorter, as in full screen.
    'drawer-title-always': ('TSDocumentWindowGlass.m', '    CGFloat offset = base.doubleValue + (side ? MIN(TSTitleBarHeight(window), TSHiddenTopBand(window)) : 0);\n',
        '    CGFloat offset = base.doubleValue + (side ? TSTitleBarHeight(window) : 0);\n'),
    # The drawer's frame keeps AppKit's light gray bezel.
    'drawer-frame-light': ('TSDocumentWindowGlass.m', '    [frame addSubview:backing positioned:NSWindowBelow relativeTo:nil];\n', ''),
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
static CGFloat Band(NSWindow *window) { return NSHeight(window.contentView.frame) - NSMaxY(window.contentLayoutRect); }
// A window whose band under the toolbar is shorter than the title bar, as in full screen.
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
    if (prepare)
        for (NSWindow *w in @[doc->textWindow, doc.pdfKitWindow, doc->fullSplitWindow]) {
            NSRect frame = w.frame;
            TSDocumentWindowPrepare(w);
            Check(NSEqualRects(frame, w.frame), [NSString stringWithFormat:@"%@ keeps its frame (%@, %@)", NSStringFromClass(w.class),
                                                 NSStringFromRect(frame), NSStringFromRect(w.frame)]);
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
    for (NSString *name in @[@"TSConsoleWindow", @"TSFullSplitWindow", @"TSFullscreenWindow", @"TSHTMLWindow", @"TSLogWindow",
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
            Check(((w.styleMask & NSWindowStyleMaskFullSizeContentView) != 0) == glass,
                  [NSString stringWithFormat:@"%@ uses a full-size content view on macOS 26 and later%@", NSStringFromClass(w.class), nibName]);
        if (!glass) continue;

        // The source window: the first line starts below the toolbar.
        CGFloat band = Band(doc->textWindow);
        ScrollTop(doc->scrollView); Settle(doc->textWindow);
        NSRect first = FirstLine(doc->textView1);
        Check(band > 20 && fabs(doc->scrollView.contentInsets.top - band) < 0.5,
              [NSString stringWithFormat:@"the source's top inset is the band under the toolbar (%.1f, %.1f)%@", doc->scrollView.contentInsets.top, band, nibName]);
        Check(fabs(NSMaxY(first) - NSMaxY(doc->textWindow.contentLayoutRect)) <= 1.5,
              [NSString stringWithFormat:@"the first line starts below the toolbar (%.1f, %.1f)%@", NSMaxY(first), NSMaxY(doc->textWindow.contentLayoutRect), nibName]);
        // The Preview window: the first page starts below the toolbar.
        NSWindow *pw = doc.pdfKitWindow; PDFView *pv = doc.myPDFKitView;
        [pv goToFirstPage:nil]; ScrollTop(pv.documentView.enclosingScrollView); Settle(pw);
        PDFPage *page = [pdf pageAtIndex:0];
        NSRect pageRect = [pv convertRect:[pv convertRect:[page boundsForBox:kPDFDisplayBoxCropBox] fromPage:page] toView:nil];
        Check(fabs(pv.documentView.enclosingScrollView.contentInsets.top - Band(pw)) < 0.5 && NSMaxY(pageRect) <= NSMaxY(pw.contentLayoutRect) + 0.5
              && NSMaxY(pageRect) > NSMaxY(pw.contentLayoutRect) - 20,
              [NSString stringWithFormat:@"the first page starts just below the toolbar (%.1f, %.1f)%@", NSMaxY(pageRect), NSMaxY(pw.contentLayoutRect), nibName]);
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

        // The drawer of the Preview window starts right below the title bar, beside the toolbar,
        // as in a window whose content stays below the toolbar (#67), with a frame in the window's colors.
        CGFloat base = doc->myDrawer.leadingOffset;
        NSDrawer *drawer = OpenDrawer(doc);
        Check(TitleBar(pw) > 20 && TitleBar(pw) < Band(pw) - 20 &&
              fabs(drawer.leadingOffset - (base + TitleBar(pw))) < 0.5,
              [NSString stringWithFormat:@"the drawer starts right below the title bar (%.1f, title bar %.1f, band %.1f)%@",
               drawer.leadingOffset, TitleBar(pw), Band(pw), nibName]);
        // A band shorter than the title bar: the drawer does not go higher than it.
        if (!originalLayoutRect) {
            Method m = class_getInstanceMethod(NSWindow.class, @selector(contentLayoutRect));
            originalLayoutRect = method_setImplementation(m, (IMP)ShortLayoutRect);
        }
        for (NSNumber *band in @[@9, @21]) {
            shortBandWindow = pw; shortBand = band.doubleValue;
            OpenDrawer(doc);
            Check(fabs(Band(pw) - shortBand) < 0.5 && fabs(drawer.leadingOffset - (base + shortBand)) < 0.5,
                  [NSString stringWithFormat:@"with a band of %.0f under a title bar of %.1f the drawer starts below the band (%.1f)%@",
                   shortBand, TitleBar(pw), drawer.leadingOffset, nibName]);
        }
        shortBandWindow = nil;
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
    printf("PASS: %d checks: document windows run their content under the toolbar\n", checks);
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
