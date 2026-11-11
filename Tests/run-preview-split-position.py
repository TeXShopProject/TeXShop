#!/usr/bin/env python3
"""Split, unsplit and switch the preview panes with the production code in a window that is
never shown, and check that the place at the top edge of each pane does not move."""
from pathlib import Path
import argparse
import subprocess
import sys
import tempfile
from source_tree import include_args
from production_fragments import closing_brace, verify_embedded

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['first-not-restored', 'switch-not-swapped', 'shift-not-same',
                                           'second-not-saved', 'edge-ignores-flip',
                                           'deferred-restore', 'restore-before-layout'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
window_source = (root / 'Sources/Windows/TSPreviewWindow.m').read_text(encoding='latin1')
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
header_source = (root / 'Sources/Preview/TSPreviewPanePlace.h').read_text(encoding='latin1')
# The preview also keeps the top of each part while its divider is dragged (#24);
# run the split code together with it when it is there.
divider = root / 'Sources/Preview/TSPreviewSplitDivider.m'
uses_divider = divider.exists()

def last_method(source, signature):
    # TSPreviewWindow.m keeps an older copy of mainSplitPdfKitWindow in a comment.
    start = source.rindex(signature)
    return source[start:closing_brace(source, source.index('{', start))]

split = last_method(window_source, '- (void) mainSplitPdfKitWindow')
switch = last_method(window_source, '- (void)switchViews;')
# Switching the parts of a split window (#25).
parts = last_method(window_source, '- (void)switchSplitParts\n')
splitter = last_method(window_source, '- (void) splitPdfKitWindow:')
view_methods = [last_method(view_source, s) for s in (
    '- (void)saveLocation\n', '- (void)restoreLocation\n', '- (NSInteger)index\n', '- (void)moveSplitToCorrectSpot:')]
fragments = [('complete method: ' + text.split('\n')[0], source, text)
             for source, text in [(window_source, split), (window_source, switch), (window_source, parts), (window_source, splitter)]
             + [(view_source, m) for m in view_methods]]

for problem, old, new in (
        ('first-not-restored', 'TSPreviewPaneRestore(firstView, firstTop);', ''),
        ('switch-not-swapped', 'TSPreviewPaneRestore(upperView, lower);', 'TSPreviewPaneRestore(upperView, upper);'),
        ('shift-not-same', 'TSPreviewPaneRestore(secondView, firstTop);', ';'),
        ('second-not-saved', '[secondView saveLocation];', ''),
        ('restore-before-layout', '    [self.pdfKitSplitView adjustSubviews];\n    [self.pdfKitSplitView layoutSubtreeIfNeeded];\n    TSPreviewPaneRestore', '    TSPreviewPaneRestore')):
    if args.mutation == problem:
        assert split.count(old) + parts.count(old) >= 1, problem
        split, parts = split.replace(old, new), parts.replace(old, new)
if args.mutation == 'deferred-restore':
    # Putting the place back once more later undoes what the user did in between.
    old = '    TSPreviewPaneRestore(firstView, firstTop);\n    if (self.windowIsSplit)'
    assert split.count(old) == 1
    split = split.replace(old, '    TSPreviewPaneRestore(firstView, firstTop);\n'
                          '    dispatch_async(dispatch_get_main_queue(), ^{ TSPreviewPaneRestore(firstView, firstTop); });\n    if (self.windowIsSplit)')
    old = '    TSPreviewPaneRestore(lowerView, upper);\n'
    assert parts.count(old) == 1
    parts = parts.replace(old, old + '    dispatch_async(dispatch_get_main_queue(), ^{ TSPreviewPaneRestore(upperView, lower); });\n')
if args.mutation == 'edge-ignores-flip':
    old = 'CGFloat top = clip.isFlipped ? NSMinY(bounds) + insets.top : NSMaxY(bounds) - insets.top;'
    assert header_source.count(old) == 1
    header_source = header_source.replace(old, 'CGFloat top = NSMaxY(bounds) - insets.top;')

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewPanePlace.h"
DIVIDERIMPORT
#define NEW_PDF_FIT_TO_NONE 1
#define NEW_PDF_FIT_TO_WINDOW 4
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSEventModifierFlags flags;
static NSEventModifierFlags currentFlags(id s, SEL c) { return flags; }
@interface TSLinkPreviewView : NSView @end
@implementation TSLinkPreviewView @end
@interface MyPDFKitView : PDFView {
    TSPreviewPanePlace splitPlace;
    NSInteger pageStyle, firstPageStyle, resizeOption;
}
@property BOOL locationSaved, verticalSplitSaved, horizontalSplitSaved;
@property double horizontalHeight1, horizontalHeight2, verticalWidth1, verticalWidth2, fixedScale;
@property BOOL oldUsed, doScroll; @property NSRect oldVisibleRect; @property NSInteger oldIndex;
@property BOOL singlePage;
- (void)moveSplitToCorrectSpot:(NSInteger)index;
- (void)saveLocation;
- (void)restoreLocation;
@end
@implementation MyPDFKitView
- (NSInteger)pageStyle { return pageStyle; }
- (NSInteger)firstPageStyle { return firstPageStyle; }
- (NSInteger)resizeOption { return resizeOption; }
- (void)setPageStyle:(NSInteger)s { pageStyle = s; }
- (void)setFirstPageStyle:(NSInteger)s { firstPageStyle = s; }
- (void)setResizeOption:(NSInteger)s { resizeOption = s; }
- (double)magnification { return self.scaleFactor; }
- (void)setMagnification:(double)m { [self setScaleFactor:m]; }
// pageStyle 1 is single page, 3 continuous single page (PDF_*_STYLE in globals.h).
- (void)setupPageStyle { [self setDisplayMode:pageStyle == 1 ? kPDFDisplaySinglePage : kPDFDisplaySinglePageContinuous]; [self setDisplaysPageBreaks:pageStyle != 1]; }
- (void)setupMagnificationStyle { if (resizeOption == NEW_PDF_FIT_TO_WINDOW) [self setAutoScales:YES]; else [self setScaleFactor:self.fixedScale]; }
- (void)cleanupMarqueeKeepingPinnedLinkPreview {}
- (void)resetSearchDelegate {}
- (void)becomeActiveView {}
- (BOOL)hasPinnedLinkPreview { return YES; }
- (TSLinkPreviewView *)detachPinnedLinkPreviewWithWindowFrame:(NSRect *)f { return nil; }
- (void)attachPinnedLinkPreview:(TSLinkPreviewView *)p windowFrame:(NSRect)f {}
VIEWMETHODS
@end
@interface TestWindow : NSWindow
@property BOOL firstTime, windowIsSplit, horizontal;
@property PDFView *activeView, *myPDFKitView, *myPDFKitView2;
@property NSSplitView *pdfKitSplitView;
DIVIDERPROPERTY
- (void)mainSplitPdfKitWindow;
- (void)splitPdfKitWindow:(id)sender;
- (void)switchViews;
@end
@implementation TestWindow
- (void)keepPinnedLinkPreviewsInView {}
SPLITMETHOD
SWITCHMETHOD
PARTSMETHOD
SPLITTERMETHOD
@end

static void settle(NSWindow *w) {
    for (int i = 0; i < 4; i++) {
        [w layoutIfNeeded];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}
// Screen points between the top edge of a pane and the place, or a large number if the
// place is on a page that is not shown.
static CGFloat distanceFromTop(PDFView *v, TSPreviewPanePlace place) {
    NSScrollView *scroll = v.documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    PDFPage *page = [v.document pageAtIndex:place.pageIndex];
    if (v.displayMode == kPDFDisplaySinglePage && v.currentPage != page) return 1e9;
    NSPoint point = [clip convertPoint:[v convertPoint:place.pagePoint fromPage:page] fromView:v];
    NSRect b = clip.bounds;
    CGFloat d = clip.isFlipped ? point.y - NSMinY(b) : NSMaxY(b) - point.y;
    return d * scroll.magnification;
}
static TSPreviewPanePlace topOf(PDFView *v) {
    NSClipView *clip = v.documentView.enclosingScrollView.contentView;
    NSRect b = clip.bounds;
    NSPoint top = [v convertPoint:NSMakePoint(NSMidX(b), clip.isFlipped ? NSMinY(b) : NSMaxY(b)) fromView:clip];
    PDFPage *page = [v pageForPoint:top nearest:YES];
    return (TSPreviewPanePlace){YES, [v.document indexForPage:page], [v convertPoint:top toPage:page]};
}
static void scrollTo(PDFView *v, NSUInteger pageIndex, CGFloat y) {
    [v goToRect:NSMakeRect(100, y, 1, 1) onPage:[v.document pageAtIndex:pageIndex]];
}
static BOOL near(CGFloat d) { return fabs(d) < 0.01; }

typedef struct { TestWindow *window; MyPDFKitView *first, *second; } Preview;
static Preview makePreview(PDFDocument *doc, double scale, NSInteger style) {
    TestWindow *w = [[TestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 900)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    NSSplitView *sv = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [w.contentView addSubview:sv];
    MyPDFKitView *a = [[MyPDFKitView alloc] initWithFrame:sv.bounds], *b = [[MyPDFKitView alloc] initWithFrame:sv.bounds];
    for (MyPDFKitView *v in @[a, b]) {
        // As in TSDocument.nib.
        v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        v.autoresizesSubviews = NO; v.wantsLayer = YES;
        v.fixedScale = scale;
        [v setPageStyle:style];
        [v setResizeOption:scale > 0 ? NEW_PDF_FIT_TO_NONE : NEW_PDF_FIT_TO_WINDOW];
    }
    [sv addSubview:a];
    w.pdfKitSplitView = sv; w.myPDFKitView = a; w.myPDFKitView2 = b; w.activeView = a;
    w.firstTime = YES; w.horizontal = YES;
    a.document = doc; [a setupPageStyle]; [a setupMagnificationStyle];
    settle(w);
    return (Preview){w, a, b};
}
static void split(Preview p, NSEventModifierFlags modifiers) {
    flags = modifiers; [p.window splitPdfKitWindow:nil]; flags = 0; settle(p.window);
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    method_setImplementation(class_getClassMethod(NSEvent.class, @selector(modifierFlags)), (IMP)currentFlags);
    PDFDocument *doc = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]];
    check(doc.pageCount >= 6, @"test document has pages");
    NSArray *scales = @[@1, @1.5, @0.75, @0];
    for (NSNumber *scale in scales) for (NSNumber *option in @[@NO, @YES]) {
        NSString *name = [NSString stringWithFormat:@"%@ at %@%%", option.boolValue ? @"side by side" : @"top and bottom",
                          scale.doubleValue ? @(scale.doubleValue * 100) : @"fit"];
        Preview p = makePreview(doc, scale.doubleValue, 3);
        scrollTo(p.first, 1, 500); settle(p.window);
        TSPreviewPanePlace start = topOf(p.first);
        for (int i = 1; i <= 3; i++) {
            split(p, option.boolValue ? NSEventModifierFlagOption : 0);
            check(p.window.windowIsSplit && p.second.superview, [name stringByAppendingString:@": the window is split"]);
            check(near(distanceFromTop(p.first, start)), [NSString stringWithFormat:@"%@: split %d keeps the top of the first pane (moved %.2f)", name, i, distanceFromTop(p.first, start)]);
            split(p, 0);
            check(!p.window.windowIsSplit && !p.second.superview, [name stringByAppendingString:@": the window is unsplit"]);
            check(near(distanceFromTop(p.first, start)), [NSString stringWithFormat:@"%@: unsplit %d keeps the top (moved %.2f)", name, i, distanceFromTop(p.first, start)]);
        }
        // Switching swaps exactly what the panes show at their top edges, however often.
        split(p, option.boolValue ? NSEventModifierFlagOption : 0);
        scrollTo(p.second, 3, 300); settle(p.window);
        TSPreviewPanePlace upper = topOf(p.first), lower = topOf(p.second);
        for (int i = 1; i <= 5; i++) {
            [p.window switchViews]; settle(p.window);
            TSPreviewPanePlace a = i % 2 ? lower : upper, b = i % 2 ? upper : lower;
            check(near(distanceFromTop(p.first, a)) && near(distanceFromTop(p.second, b)),
                  [NSString stringWithFormat:@"%@: switch %d swaps the panes exactly (%.2f, %.2f)", name, i, distanceFromTop(p.first, a), distanceFromTop(p.second, b)]);
        }
        // The second pane shows its place again when the window is split next time,
        // and the first pane still keeps its top.
        upper = topOf(p.first); lower = topOf(p.second);
        split(p, 0);
        check(near(distanceFromTop(p.first, upper)), [name stringByAppendingString:@": unsplitting after switching keeps the top"]);
        split(p, option.boolValue ? NSEventModifierFlagOption : 0);
        check(near(distanceFromTop(p.first, upper)) && near(distanceFromTop(p.second, lower)),
              [NSString stringWithFormat:@"%@: splitting again shows the second pane's place (%.2f)", name, distanceFromTop(p.second, lower)]);
        [p.window close];
    }
    {   // Shift-split: both panes show the place that was at the top of the window.
        Preview p = makePreview(doc, 1, 3);
        split(p, 0); scrollTo(p.second, 5, 300); settle(p.window); split(p, 0);
        scrollTo(p.first, 2, 600); settle(p.window);
        TSPreviewPanePlace start = topOf(p.first);
        split(p, NSEventModifierFlagShift);
        check(near(distanceFromTop(p.first, start)), @"shift-split keeps the top of the first pane");
        check(near(distanceFromTop(p.second, start)), [NSString stringWithFormat:@"shift-split: the second pane shows the same place (%.2f)", distanceFromTop(p.second, start)]);
        check(fabs(NSHeight(p.first.frame) - NSHeight(p.second.frame)) < 1, @"shift-split: the panes have the same size");
        [p.window close];
    }
    {   // Single page display: the panes can show different pages.
        Preview p = makePreview(doc, 1.5, 1);
        scrollTo(p.first, 2, 500); settle(p.window);
        TSPreviewPanePlace start = topOf(p.first);
        split(p, 0);
        check(near(distanceFromTop(p.first, start)), @"single page: split keeps the top");
        scrollTo(p.second, 4, 750); settle(p.window);
        TSPreviewPanePlace upper = topOf(p.first), lower = topOf(p.second);
        check(upper.pageIndex == 2 && lower.pageIndex == 4, @"single page: the panes show different pages");
        [p.window switchViews]; settle(p.window);
        check(near(distanceFromTop(p.first, lower)) && near(distanceFromTop(p.second, upper)), @"single page: switch swaps the pages and places");
        split(p, 0);
        check(near(distanceFromTop(p.first, lower)), [NSString stringWithFormat:@"single page: unsplit keeps the top (%.2f)", distanceFromTop(p.first, lower)]);
        [p.window close];
    }
    {   // Near the end of the document the larger pane cannot keep the top; it shows the end.
        Preview p = makePreview(doc, 1, 3);
        [p.first goToPage:[doc pageAtIndex:doc.pageCount - 1]];
        NSClipView *clip = p.first.documentView.enclosingScrollView.contentView;
        [p.first.documentView scrollPoint:NSMakePoint(0, NSMaxY(clip.documentRect))]; settle(p.window);
        split(p, 0);
        scrollTo(p.first, doc.pageCount - 1, 60); settle(p.window);
        split(p, 0);
        NSRect b = clip.bounds, d = clip.documentRect;
        check(fabs(NSMaxY(b) - NSMaxY(d)) < 1, @"unsplitting at the end of the document shows the end without a gap");
        [p.window close];
    }
    {   // Scrolling or switching right after splitting, before the run loop turns again, is kept.
        Preview p = makePreview(doc, 1, 3);
        scrollTo(p.first, 1, 500); settle(p.window);
        flags = 0; [p.window splitPdfKitWindow:nil];
        scrollTo(p.first, 4, 300);
        TSPreviewPanePlace moved = topOf(p.first);
        settle(p.window);
        check(near(distanceFromTop(p.first, moved)), [NSString stringWithFormat:@"scrolling right after splitting is kept (%.2f)", distanceFromTop(p.first, moved)]);
        [p.window splitPdfKitWindow:nil];
        scrollTo(p.first, 2, 400);
        moved = topOf(p.first);
        settle(p.window);
        check(near(distanceFromTop(p.first, moved)), @"scrolling right after unsplitting is kept");
        [p.window splitPdfKitWindow:nil]; settle(p.window);
        scrollTo(p.second, 5, 300); settle(p.window);
        TSPreviewPanePlace upper = topOf(p.first), lower = topOf(p.second);
        [p.window switchViews];
        [p.window switchViews];
        settle(p.window);
        check(near(distanceFromTop(p.first, upper)) && near(distanceFromTop(p.second, lower)),
              [NSString stringWithFormat:@"switching twice in a row returns both panes (%.2f, %.2f)", distanceFromTop(p.first, upper), distanceFromTop(p.second, lower)]);
        [p.window close];
    }
    printf("PASS: %lu checks\n", (unsigned long)checks);
    return 0;
}}
'''
program = (program.replace('DIVIDERIMPORT', '#import "TSPreviewSplitDivider.h"' if uses_divider else '')
           .replace('DIVIDERPROPERTY', '@property (strong) TSPreviewSplitDivider *previewSplitDivider;' if uses_divider else '')
           .replace('VIEWMETHODS', '\n'.join(view_methods))
           .replace('SPLITTERMETHOD', splitter).replace('SPLITMETHOD', split).replace('SWITCHMETHOD', switch).replace('PARTSMETHOD', parts))
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    (temp / 'TSPreviewPanePlace.h').write_text(header_source, encoding='latin1')
    tex = temp / 'doc.tex'
    tex.write_text('\\documentclass{article}\\begin{document}\n' +
                   '\n\n'.join('Paragraph %d. ' % i + 'Text of the test document. ' * 40 for i in range(120)) +
                   '\n\\end{document}\n')
    pdflatex = next((p for p in ('/Applications/TeXLive/2026/bin/universal-darwin/pdflatex', '/Library/TeX/texbin/pdflatex')
                     if Path(p).exists()), 'pdflatex')
    subprocess.run([pdflatex, '-interaction=batchmode', '-output-directory', str(temp), str(tex)],
                   check=True, stdout=subprocess.DEVNULL, cwd=temp)
    (temp / 'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    '-I', str(temp), '-I', str(root / 'Tests'), *include_args(root),
                    str(temp / 'test.m'), *([str(divider)] if uses_divider else []), '-o', str(temp / 'test')], check=True)
    result = subprocess.run([str(temp / 'test'), str(temp / 'doc.pdf')], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.strip().splitlines()[-1])
    else:
        print(output.strip())
        sys.exit(result.returncode)
