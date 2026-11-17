#!/usr/bin/env python3
"""When a Preview view changes its size at a fixed magnification, the text at its top
edge stays there (#53).

Measured in a macOS 26.6.2 virtual machine with the Help manual at 200% in a window made
narrower step by step (scroll bars always shown, TeXShop-audit Issue53 VM確認):
- The document view of a PDFView is not flipped up to macOS 26, so the scroll view keeps
  the bottom of the visible area. The text jumped up by the height of the horizontal
  scroller when it appeared. The keeper of #24 (TSPreviewScrollerKeeper) does not act in
  a window whose content runs under the toolbar, as the Preview window on macOS 26.
- Once the window is narrower than about half the page, AppKit lays the scrollers over
  the content with a bottom content inset of the clip view, and PDFKit's clip view then
  answers every constrainBoundsRect: one scroller higher in the document. The text moved
  down by the height of the scroller at every step of the resize, also when the window
  got wider again, and a place put back through constrainBoundsRect: stayed there.

The models:
- "unflipped": the document view answers NO to isFlipped, as up to macOS 26.
- "shifted": unflipped, and PDFKit's clip view answers constrainBoundsRect: 8.5 points
  higher in the document, as in the narrow view on macOS 26.
- "system": this system as it is.

Preview-like views are PDFViews whose setFrameSize: wraps the change in the production
TSPreviewChangeSize, as MyPDFKitView does; the sources model checks that it does. They
run in windows that are never ordered on screen; -[NSWindow isVisible] answers YES, so
that PDFKit takes the path it takes on screen. The controls without the fix only show
that the test sees the jumps; on a system that no longer jumps they are notes.
"""
import argparse, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file

MUTATIONS = {
    # The Preview views change their size as PDFKit does.
    'not-wrapped': ('MyPDFKitView.m', '        TSPreviewChangeSize(self, ^{ [super setFrameSize:newSize]; });\n',
                    '        [super setFrameSize:newSize];\n'),
    # The text is not put back after the size changed.
    'no-restore': ('TSPreviewScrollerKeeper.m',
                   '    text.page = page;\n    TSMoveTextUp(scroll, TSTextBelowTop(view, scroll, text));\n}\n', '}\n'),
    # A change of the magnification is kept too.
    'scale-kept': ('TSPreviewScrollerKeeper.m',
                   ' || view.scaleFactor != scale)\n        return;\n    text.page = page;', ')\n        return;\n    text.page = page;'),
    # The place is put back through PDFKit's constrainBoundsRect:.
    'pdfkit-constrain': ('TSPreviewScrollerKeeper.m', '    NSPoint target = TSPreviewConstrainedOrigin(clip, bounds);\n',
                         '    NSPoint target = [clip constrainBoundsRect:bounds].origin;\n'),
    # The split divider puts the tops back through PDFKit's constrainBoundsRect:.
    'divider-pdfkit-constrain': ('TSPreviewSplitDivider.m', '        NSPoint target = TSPreviewConstrainedOrigin(clip, bounds);\n',
                                 '        NSPoint target = [clip constrainBoundsRect:bounds].origin;\n'),
    # The place is not limited at the ends of the document.
    'no-limits': ('TSPreviewScrollerKeeper.h',
                  '        origin.y = maximum < minimum ? minimum : fmin(fmax(origin.y, minimum), maximum);\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--binary', type=Path, help='write the test program here instead of running it')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
names = ('TSPreviewScrollerKeeper.m', 'TSPreviewScrollerKeeper.h', 'TSPreviewSplitDivider.m', 'MyPDFKitView.m')
text = {name: source_file(root, name).read_text(encoding='utf-8', errors='surrogateescape') for name in names}
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert text[name].count(old) == 1, args.mutation
    text[name] = text[name].replace(old, new)

view = text['MyPDFKitView.m']
start = view.index('- (void)setFrameSize:(NSSize)newSize')
frame_size = view[start:view.index('\n}\n', start)]
wrapped = '#import "TSPreviewScrollerKeeper.h"' in view and \
    'TSPreviewChangeSize(self, ^{ [super setFrameSize:newSize]; });' in frame_size and \
    frame_size.count('[super setFrameSize:newSize];') == 2

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewScrollerKeeper.h"
#import "TSPreviewSplitDivider.h"
static int failures; static const char *model;
static void Check(BOOL ok, NSString *name) { if (!ok) { printf("FAIL (%s): %s\n", model, name.UTF8String); failures++; } }
static void Control(BOOL ok, NSString *name) { if (!ok) printf("NOTE (%s): not seen on this system: %s\n", model, name.UTF8String); }
static NSScrollerStyle Legacy(id s, SEL c) { return NSScrollerStyleLegacy; }
static BOOL Yes(id s, SEL c) { return YES; }
static BOOL No(id s, SEL c) { return NO; }
static IMP originalConstrain;
// Only the clip views of PDFViews answer one scroller higher.
static NSRect Shifted(NSClipView *self, SEL _cmd, NSRect proposed) {
    NSRect rect = ((NSRect (*)(id, SEL, NSRect))originalConstrain)(self, _cmd, proposed);
    if ([self.documentView isKindOfClass:NSClassFromString(@"PDFDocumentView")])
        rect.origin.y += 8.5;
    return rect;
}

// A Preview view: its size changes through TSPreviewChangeSize, as in MyPDFKitView.
@interface PreviewLike : PDFView @end
@implementation PreviewLike
- (void)setFrameSize:(NSSize)newSize { TSPreviewChangeSize(self, ^{ [super setFrameSize:newSize]; }); }
@end

static PDFDocument *MakeDocument(void) {
    PDFDocument *document = [PDFDocument new];
    for (int i = 0; i < 8; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600, 800)];
        [image lockFocus]; [NSColor.whiteColor set]; NSRectFill(NSMakeRect(0, 0, 600, 800)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return document;
}
static void RunLoop(void) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]]; }
static NSScrollView *Scroll(PDFView *view) { return view.documentView.enclosingScrollView; }
static NSClipView *Clip(PDFView *view) { return Scroll(view).contentView; }

typedef struct { PDFPage *page; NSPoint point; } Mark;
static CGFloat TopInWindow(PDFView *view) {
    NSClipView *clip = Clip(view); NSRect b = clip.bounds;
    return [clip convertPoint:NSMakePoint(NSMidX(b), clip.isFlipped ? NSMinY(b) : NSMaxY(b)) toView:nil].y;
}
static Mark MarkAt(PDFView *view) {
    NSPoint p = [view convertPoint:NSMakePoint(NSMidX(Clip(view).frame), TopInWindow(view)) fromView:nil];
    PDFPage *page = [view pageForPoint:p nearest:YES];
    return (Mark){page, [view convertPoint:p toPage:page]};
}
static CGFloat Below(PDFView *view, Mark mark) {
    return TopInWindow(view) - [view convertPoint:[view convertPoint:mark.point fromPage:mark.page] toView:nil].y;
}
static PDFView *MakeView(NSRect frame, PDFDocument *document, BOOL preview, BOOL autoScales) {
    PDFView *view = [[(preview ? PreviewLike.class : PDFView.class) alloc] initWithFrame:frame];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.autoresizesSubviews = NO; view.wantsLayer = YES;
    view.document = document;
    if (preview) [TSPreviewScrollerKeeper installInView:view];
    view.displayMode = kPDFDisplaySinglePageContinuous;
    view.autoScales = autoScales;
    if (!autoScales) view.scaleFactor = 1.0;
    return view;
}
static void ScrollIntoPage(PDFView *view, NSUInteger index, CGFloat into) {
    NSClipView *clip = Clip(view); PDFPage *page = [view.document pageAtIndex:index];
    NSRect r = [view.documentView convertRect:[view convertRect:[page boundsForBox:kPDFDisplayBoxCropBox] fromPage:page] fromView:view];
    CGFloat y = clip.isFlipped ? NSMinY(r) + into : NSMaxY(r) - into - NSHeight(clip.bounds);
    [clip scrollToPoint:NSMakePoint(NSMinX(clip.bounds), y)];
    [Scroll(view) reflectScrolledClipView:clip];
    [view.window layoutIfNeeded]; RunLoop();
}
static void SetSize(NSWindow *window, CGFloat width, CGFloat height) {
    NSRect frame = window.frame; CGFloat top = NSMaxY(frame);
    frame.size.width = width; frame.size.height = height; frame.origin.y = top - height;
    [window setFrame:frame display:NO]; [window layoutIfNeeded]; RunLoop();
}
// A window as the Preview window: with a toolbar, shown or hidden, and on macOS 26 and later
// with its content under the toolbar (TSDocumentWindowPrepare).
@interface WindowToolbar : NSObject <NSToolbarDelegate> @end
@implementation WindowToolbar
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return @[@"item"]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return @[@"item"]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = @"Item"; item.image = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:nil];
    return item;
}
@end
static WindowToolbar *windowToolbar;
static BOOL toolbarHidden;
static NSWindow *MakeWindow(CGFloat width, CGFloat height) {
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskResizable;
    if (@available(macOS 26.0, *)) style |= NSWindowStyleMaskFullSizeContentView;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height) styleMask:style
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.toolbarStyle = NSWindowToolbarStyleExpanded;
    if (!windowToolbar) windowToolbar = [WindowToolbar new];
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"preview"];
    toolbar.delegate = windowToolbar; window.toolbar = toolbar;
    toolbar.visible = !toolbarHidden;
    return window;
}
// The widths of a slow drag: narrower than the page, then wider again.
static NSArray<NSNumber *> *DragWidths(void) {
    NSMutableArray *widths = [NSMutableArray array];
    for (int w = 900; w >= 400; w -= 20) [widths addObject:@(w)];
    for (int w = 420; w <= 900; w += 20) [widths addObject:@(w)];
    return widths;
}

// An unsplit view: the width crosses the width of the page step by step. Returns the
// largest distance of the text from the top edge.
static CGFloat WidthSteps(PDFDocument *document, BOOL preview) {
    NSWindow *window = MakeWindow(900, 700);
    PDFView *view = MakeView(window.contentView.bounds, document, preview, NO);
    [window.contentView addSubview:view]; SetSize(window, 900, 700);
    ScrollIntoPage(view, 2, 60);
    Mark mark = MarkAt(view); CGFloat worst = 0;
    for (NSNumber *width in DragWidths()) {
        SetSize(window, width.doubleValue, 700);
        worst = fmax(worst, fabs(Below(view, mark)));
    }
    return worst;
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    model = argv[1];
    const char *names[2] = {model, strdup([NSString stringWithFormat:@"%s, toolbar hidden", model].UTF8String)};
    if (!strcmp(model, "sources")) {
        Check(WRAPPED, @"MyPDFKitView changes its size through TSPreviewChangeSize, except when Fit to Content Width refits");
        return failures ? 1 : 0;
    }
    method_setImplementation(class_getClassMethod(NSScroller.class, @selector(preferredScrollerStyle)), (IMP)Legacy);
    method_setImplementation(class_getInstanceMethod(NSWindow.class, @selector(isVisible)), (IMP)Yes);
    [NSApplication sharedApplication];
    BOOL shifted = !strcmp(model, "shifted");
    PDFDocument *document = MakeDocument();
    if (shifted && !MakeView(NSMakeRect(0, 0, 100, 100), document, NO, NO).documentView.isFlipped) {
        // On a system that does not flip the document view, PDFKit itself asks its clip view
        // at every scroll, and the shift would move all scrolling: the model is for later systems.
        printf("shifted: not modelled on this system\n");
        return 0;
    }
    if (shifted || !strcmp(model, "unflipped"))
        method_setImplementation(class_getInstanceMethod(NSClassFromString(@"PDFDocumentView"), @selector(isFlipped)), (IMP)No);
    if (shifted) {
        // The clip view class of a PDFView: PDFClipView up to macOS 26, NSClipView later.
        Class cls = Clip(MakeView(NSMakeRect(0, 0, 100, 100), document, NO, NO)).class;
        Method m = class_getInstanceMethod(cls, @selector(constrainBoundsRect:));
        originalConstrain = method_getImplementation(m);
        if (!class_addMethod(cls, @selector(constrainBoundsRect:), (IMP)Shifted, method_getTypeEncoding(m)))
            method_setImplementation(m, (IMP)Shifted);
    }
    BOOL flipped;
    { PDFView *probe = MakeView(NSMakeRect(0, 0, 100, 100), document, NO, NO); flipped = probe.documentView.isFlipped; }
    {
        PDFView *probe = MakeView(NSMakeRect(0, 0, 400, 400), document, NO, NO);
        NSClipView *clip = Clip(probe); NSRect b = clip.bounds; b.origin.y += 1;
        printf("%s: document view flipped %d, clip %s, constrain +1 -> %+.1f\n", model, flipped, clip.className.UTF8String,
               NSMinY([clip constrainBoundsRect:b]) - NSMinY(clip.bounds));
    }

    for (int hidden = 0; hidden < 2; hidden++) {
        toolbarHidden = hidden;
        model = hidden ? names[1] : names[0];
        // Width steps without a split, as in the report.
        {
            CGFloat kept = WidthSteps(document, YES);
            Check(kept <= 0.5, [NSString stringWithFormat:@"the text at the top stays while the width changes step by step (%.2fpt)", kept]);
            CGFloat bare = WidthSteps(document, NO);
            if (!flipped)
                Control(bare >= (shifted ? 30 : 10), [NSString stringWithFormat:@"without the fix the text moves (%.2fpt)", bare]);
        }

        // The height of an unsplit window changes: the text at the top stays.
        {
            NSWindow *window = MakeWindow(900, 700);
            PDFView *view = MakeView(window.contentView.bounds, document, YES, NO);
            [window.contentView addSubview:view]; SetSize(window, 900, 700);
            ScrollIntoPage(view, 3, 120);
            Mark mark = MarkAt(view); CGFloat worst = 0;
            for (NSNumber *height in @[@500, @760, @430, @700]) {
                SetSize(window, 900, height.doubleValue);
                worst = fmax(worst, fabs(Below(view, mark)));
            }
            Check(worst <= 0.5, [NSString stringWithFormat:@"the text at the top stays while the height changes (%.2fpt)", worst]);
        }

        // Automatic scaling: the magnification follows the width, and the place is PDFKit's.
        {
            CGFloat scales[2], places[2];
            for (int preview = 0; preview < 2; preview++) {
                NSWindow *window = MakeWindow(900, 700);
                PDFView *view = MakeView(window.contentView.bounds, document, preview, YES);
                [window.contentView addSubview:view]; SetSize(window, 900, 700);
                ScrollIntoPage(view, 3, 120);
                Mark mark = MarkAt(view);
                SetSize(window, 600, 700);
                scales[preview] = view.scaleFactor;
                places[preview] = Below(view, mark);
            }
            Check(fabs(scales[1] - scales[0]) < 1e-6, @"automatic scaling follows the width as without the fix");
            Check(fabs(places[1] - places[0]) <= 0.5, [NSString stringWithFormat:
                  @"with automatic scaling the place is left to PDFKit (%.2f and %.2fpt)", places[1], places[0]]);
        }

        // The ends of the document still limit the place: at the end, a size change that
        // would need the text below the last page leaves the last page at the bottom.
        {
            NSWindow *window = MakeWindow(900, 700);
            PDFView *view = MakeView(window.contentView.bounds, document, YES, NO);
            [window.contentView addSubview:view]; SetSize(window, 900, 700);
            NSClipView *clip = Clip(view);
            CGFloat end = clip.isFlipped ? 1e7 : -1e7;
            [clip scrollToPoint:NSMakePoint(NSMinX(clip.bounds), end)];
            [clip scrollToPoint:[clip constrainBoundsRect:clip.bounds].origin];
            [Scroll(view) reflectScrolledClipView:clip]; RunLoop();
            SetSize(window, 900, 760); SetSize(window, 450, 760);
            NSRect visible = clip.documentVisibleRect, document = clip.documentRect;
            BOOL atEnd = clip.isFlipped ? NSMaxY(visible) <= NSMaxY(document) + 0.5 : NSMinY(visible) >= NSMinY(document) - 0.5 - (shifted ? 8.5 : 0);
            Check(atEnd, [NSString stringWithFormat:@"the view does not go past the end of the document (visible %@, document %@)",
                          NSStringFromRect(visible), NSStringFromRect(document)]);
        }

        // On macOS 26 and later the band under the toolbar is a lasting top inset, which
        // TSPreviewScrollerKeeper leaves to PDFKit.
        if (@available(macOS 26.0, *)) {
            NSWindow *window = MakeWindow(900, 650);
            PDFView *view = MakeView(window.contentView.bounds, document, YES, NO);
            [window.contentView addSubview:view]; SetSize(window, 900, 650);
            Check(toolbarHidden || Scroll(view).contentInsets.top > 20, @"the view has the band under the toolbar as its top inset");
        }

        // A window split into a top and a bottom part, with the divider keeper: the width and
        // the height change, and both parts keep their tops.
        for (int vertical = 0; vertical < 2; vertical++) {
            NSWindow *window = MakeWindow(1000, 700);
            NSSplitView *split = [[NSSplitView alloc] initWithFrame:window.contentView.bounds];
            split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; split.vertical = vertical;
            [window.contentView addSubview:split];
            PDFView *a = MakeView(NSMakeRect(0, 0, 500, 350), document, YES, NO);
            PDFView *b = MakeView(NSMakeRect(0, 0, 500, 350), document, YES, NO);
            [split addSubview:a]; [split addSubview:b]; [split adjustSubviews];
            TSPreviewSplitDivider *divider = [[TSPreviewSplitDivider alloc] initWithSplitView:split];
            // A view held by Auto Layout in each part, as the line along the active part: with
            // it the window lays itself out with Auto Layout, as the Preview window does (#47).
            for (NSView *part in split.subviews) {
                NSView *line = [[NSView alloc] initWithFrame:part.bounds];
                line.translatesAutoresizingMaskIntoConstraints = NO;
                [part addSubview:line];
                [NSLayoutConstraint activateConstraints:@[
                    [line.leadingAnchor constraintEqualToAnchor:part.leadingAnchor], [line.trailingAnchor constraintEqualToAnchor:part.trailingAnchor],
                    [line.topAnchor constraintEqualToAnchor:part.safeAreaLayoutGuide.topAnchor], [line.bottomAnchor constraintEqualToAnchor:part.bottomAnchor]]];
            }
            // Steps narrower than half the page put the scrollers over the content on macOS 26.
            // The frame of the window is set as in the steps below; windows stay smaller than
            // the screen, which AppKit moves and shrinks larger ones to.
            SetSize(window, 1000, 700);
            ScrollIntoPage(a, 1, 300); ScrollIntoPage(b, 4, 450);
            Mark ma = MarkAt(a), mb = MarkAt(b); CGFloat worst = 0; NSMutableString *steps = [NSMutableString string];
            NSArray *sizes = vertical ? @[@[@1300, @700], @[@900, @700], @[@900, @560], @[@1240, @560], @[@1240, @700],
                                              @[@560, @700], @[@560, @560], @[@560, @660], @[@1000, @700]]
                                      : @[@[@560, @700], @[@1000, @700], @[@450, @700], @[@450, @560], @[@450, @660],
                                              @[@280, @660], @[@280, @560], @[@280, @700], @[@1000, @560]];
            for (NSArray *size in sizes) {
                SetSize(window, [size[0] doubleValue], [size[1] doubleValue]);
                worst = fmax(worst, fmax(fabs(Below(a, ma)), fabs(Below(b, mb))));
                [steps appendFormat:@" %@x%@: %.2f/%.2f", size[0], size[1], Below(a, ma), Below(b, mb)];
            }
            Check(worst <= 0.5, [NSString stringWithFormat:@"split %s: both parts keep their tops while the window changes (%.2fpt;%@)",
                                 vertical ? "side by side" : "top and bottom", worst, steps]);
            (void)divider;
        }
    }
    model = names[0];

    if (failures) return 1;
    printf("PASS (%s): the text at the top stays when a Preview view changes its size\n", model);
} return 0; }
'''.replace('WRAPPED', 'YES' if wrapped else 'NO')

with tempfile.TemporaryDirectory(prefix='texshop-preview-resize-') as tmp:
    tmp = Path(tmp)
    (tmp / 'probe.m').write_text(program, encoding='utf-8')
    for name in ('TSPreviewScrollerKeeper.m', 'TSPreviewScrollerKeeper.h', 'TSPreviewSplitDivider.m'):
        (tmp / name).write_text(text[name], encoding='utf-8', errors='surrogateescape')
    # The copies in tmp, mutated or not, come before the Sources tree.
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-mmacosx-version-min=14.0', '-framework', 'Cocoa', '-framework', 'Quartz', '-I', str(tmp), *include_args(root),
                    '-I', str(root / 'Tests'), str(tmp / 'probe.m'), str(tmp / 'TSPreviewScrollerKeeper.m'),
                    str(tmp / 'TSPreviewSplitDivider.m'), '-o', str(tmp / 'probe')], check=True)
    if args.binary:
        import shutil
        shutil.copy2(tmp / 'probe', args.binary)
        print(f'wrote {args.binary}; run it with the models sources, unflipped, shifted and system')
        sys.exit(0)
    failed = False
    for model in ('sources', 'unflipped', 'shifted', 'system'):
        result = subprocess.run([str(tmp / 'probe'), model], capture_output=True, text=True, timeout=300)
        print(result.stdout, end='')
        if result.returncode:
            if not args.mutation:
                print(result.stderr)
            failed = True
    if args.mutation:
        if not failed:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif failed:
        sys.exit('FAIL')
