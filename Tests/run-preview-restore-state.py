#!/usr/bin/env python3
"""Check that the Preview comes back as it was on the next launch of TeXShop (#71).

Up to 6.00 RC2, a source restored only the frame and the page of its Preview, and a PDF opened by
itself was not reopened at all. Now the state of the Preview is kept: the display format,
magnification and the place at the top edge of each part, whether the window is split, top and
bottom or side by side, where the divider is, which part is in use, and the Two-Page Arrangement
chosen. The Preview window of a PDF opened by itself keeps its file and frame as well.

The production code that encodes and restores this state runs unchanged in stand-in classes: a
window with a real NSSplitView and two real PDFView parts, never shown, and a document that keeps the
arrangement chosen. The state goes through a keyed archive that requires secure coding, as AppKit's
restorable state does. macOS's own part, which reopens the document and calls these methods on the
next launch, was checked on macOS 26 and 15 with the real application.
--mutation split-not-restored, share-ignored, places-not-restored, page-unbounded,
arrangement-lost, frame-not-restored, content-width-not-fitted, old-state-taken leave out one part
of the restoration; the harness must then fail.
"""
import argparse
import os
import subprocess
import tempfile
from pathlib import Path
from production_fragments import closing_brace, verify_embedded
from source_tree import include_args

MUTATIONS = {
    'split-not-restored': ('window', '    if ([coder decodeBoolForKey:@"TSPreviewSplit"] && second) {', '    if (NO) {'),
    'share-ignored': ('window', '            if (share > 0 && share < 1) {', '            if (NO) {'),
    'places-not-restored': ('window', '        [one restorePreviewPlace:firstPlace];\n', ''),
    'arrangement-lost': ('window', '    if ([coder containsValueForKey:@"TSPreviewDirection"]) {', '    if (NO) {'),
    'frame-not-restored': ('window', '    if (frame.length)\n', '    if (NO)\n'),
    'old-state-taken': ('window', " || ![coder containsValueForKey:@\"TSPreviewFirstPageStyle\"]) return NO;", ') return NO;'),
    'page-unbounded': ('view', 'MIN((NSUInteger)index, pageCount - 1)', '(NSUInteger)index'),
    'content-width-not-fitted': ('view', '    if (resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH)\n        [self fitContentWidth];\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
window_source = (root / 'Sources/Windows/TSPreviewWindow.m').read_text(encoding='latin1')

def region(source, start_marker, end_marker):
    start = source.index(start_marker)
    end_start = source.index(end_marker, start)
    end = closing_brace(source, source.index('{', end_start))
    assert source.count(start_marker) == 1
    return source[start:end]

# The part: its state and its place (MyPDFKitView.m).
view_text = region(view_source, '// Restoring the Preview on the next launch of TeXShop, as macOS does', '- (void)previewStateChanged')
# The window: split, part in use, arrangement, and the restorable state of a PDF opened by itself
# (TSPreviewWindow.m); the class method that asks NSDocumentController to reopen the file is left out.
window_text = region(window_source, '#pragma mark - The Preview on the next launch (#71)', '- (void)restoreStateWithCoder:(NSCoder *)coder\n{\n    [super')
fragments = [('statements: the state of a part', view_source, view_text),
             ('statements: the state of the window', window_source, window_text)]
if args.mutation:
    which, old, new = MUTATIONS[args.mutation]
    if which == 'window':
        assert window_text.count(old) == 1, args.mutation
        window_text = window_text.replace(old, new)
    else:
        assert view_text.count(old) == 1, args.mutation
        view_text = view_text.replace(old, new)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewPanePlace.h"
#import "globals.h"

@interface TestDocument : NSObject
@property (strong) NSNumber *previewBookOverride, *previewDirectionOverride;
@property (strong) NSURL *fileURL;
@property NSInteger invalidations, layoutUpdates;
- (void)invalidateRestorableState;
- (void)updatePreviewLayoutControls;
@end
@implementation TestDocument
- (void)invalidateRestorableState { self.invalidations++; }
- (void)updatePreviewLayoutControls { self.layoutUpdates++; }
@end
#define TSDocument TestDocument

@interface MyPDFKitView : PDFView {
@public
    NSInteger pageStyle, firstPageStyle, resizeOption;
}
@property (weak) TestDocument *myDocument;
@property NSInteger arrangements, contentWidthFits, activations;
- (void)applyPreviewArrangement;
- (void)becomeActiveView;
- (void)encodePreviewStateWithCoder:(NSCoder *)coder prefix:(NSString *)prefix;
- (TSPreviewPanePlace)restorePreviewDisplayWithCoder:(NSCoder *)coder prefix:(NSString *)prefix;
- (void)restorePreviewPlace:(TSPreviewPanePlace)place;
@end

// AppKit's own part of a window's restorable state needs AppKit's coder; it is left out here.
@interface AppKitStateWindow : NSWindow
@end
@implementation AppKitStateWindow
- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {}
- (void)restoreStateWithCoder:(NSCoder *)coder {}
@end

@interface TestWindow : AppKitStateWindow <NSWindowRestoration>
@property BOOL windowIsSplit, horizontal;
@property (strong) PDFView *myPDFKitView, *myPDFKitView2, *activeView;
@property (strong) NSSplitView *pdfKitSplitView;
@property (strong) TestDocument *myDocument;
@property NSInteger splits;
- (void)encodePreviewStateWithCoder:(NSCoder *)coder;
- (BOOL)restorePreviewStateWithCoder:(NSCoder *)coder;
@end
#define TSPreviewWindow TestWindow
static void TSSplitToggleItemsFollowSplit(void) {}

@implementation MyPDFKitView
- (void)setupPageStyle {
    switch (pageStyle) {
        case PDF_SINGLE_PAGE_STYLE: self.displayMode = kPDFDisplaySinglePage; break;
        case PDF_TWO_PAGE_STYLE: self.displayMode = kPDFDisplayTwoUp; break;
        case PDF_MULTI_PAGE_STYLE: self.displayMode = kPDFDisplaySinglePageContinuous; break;
        case PDF_DOUBLE_MULTI_PAGE_STYLE: self.displayMode = kPDFDisplayTwoUpContinuous; break;
    }
}
- (void)setMagnification:(double)magnification { self.scaleFactor = magnification; resizeOption = resizeOption ?: NEW_PDF_FIT_TO_NONE; }
- (void)scaleChanged:(NSNotification *)notification {}
- (void)fitContentWidth { self.contentWidthFits++; }
- (void)becomeActiveView { ((TestWindow *)self.window).activeView = self; self.activations++; }
- (void)applyPreviewArrangement { self.arrangements++; }
VIEWMETHODS
@end

@implementation TestWindow
- (void)mainSplitPdfKitWindow {
    self.windowIsSplit = YES;
    self.splits++;
    NSSplitView *s = self.pdfKitSplitView;
    CGFloat whole = (s.isVertical ? NSWidth(s.bounds) : NSHeight(s.bounds)) - s.dividerThickness;
    [s setPosition:round(whole / 2) ofDividerAtIndex:0];
    [s adjustSubviews];
}
- (void)showActivePart {}
+ (void)restoreWindowWithIdentifier:(NSUserInterfaceItemIdentifier)identifier state:(NSCoder *)state
                  completionHandler:(void (^)(NSWindow *, NSError *))completionHandler { completionHandler(nil, nil); }
WINDOWMETHODS
@end

static void check(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static BOOL near(CGFloat a, CGFloat b, CGFloat d) { return fabs(a - b) <= d; }
static void pump(void) {
    for (int i = 0; i < 5; i++) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
static PDFDocument *book(NSInteger pages) {
    PDFDocument *document = [[PDFDocument alloc] init];
    for (NSInteger i = 0; i < pages; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(612, 792)];
        [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, 612, 792)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return document;
}

// A Preview window as TeXShop opens it: not split, MultiPage, Fit to Window.
static TestWindow *preview(PDFDocument *document) {
    TestWindow *w = [[TestWindow alloc] initWithContentRect:NSMakeRect(100, 100, 700, 760)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    w.myDocument = [TestDocument new];
    w.myDocument.fileURL = [NSURL fileURLWithPath:@"/tmp/issue71-paper.pdf"];
    NSSplitView *s = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
    s.dividerStyle = NSSplitViewDividerStyleThin;
    w.pdfKitSplitView = s;
    MyPDFKitView *parts[2];
    for (int i = 0; i < 2; i++) {
        MyPDFKitView *v = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 700, 380)];
        v.myDocument = w.myDocument;
        v->pageStyle = PDF_MULTI_PAGE_STYLE; v->firstPageStyle = PDF_FIRST_LEFT; v->resizeOption = NEW_PDF_FIT_TO_WINDOW;
        [v setupPageStyle];
        v.document = document;
        v.autoScales = YES;
        [s addSubview:v];
        parts[i] = v;
    }
    w.contentView = s;
    w.myPDFKitView = parts[0]; w.myPDFKitView2 = parts[1]; w.activeView = parts[0];
    // Not split: the second part has no room.
    [s setPosition:NSHeight(s.bounds) ofDividerAtIndex:0];
    [s adjustSubviews];
    [w layoutIfNeeded];
    return w;
}
static void scrollTo(PDFView *v, NSInteger index, CGFloat y) {
    [v goToDestination:[[PDFDestination alloc] initWithPage:[v.document pageAtIndex:index] atPoint:NSMakePoint(0, y)]];
    [v layoutDocumentView];
}
static NSData *archive(void (^encode)(NSKeyedArchiver *)) {
    NSKeyedArchiver *a = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    encode(a);
    [a finishEncoding];
    return a.encodedData;
}
static NSKeyedUnarchiver *unarchiver(NSData *data) {
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:NULL];
    u.requiresSecureCoding = YES;
    return u;
}
static CGFloat share(TestWindow *w) {
    NSSplitView *s = w.pdfKitSplitView;
    NSRect a = s.subviews[0].frame, b = s.subviews[1].frame;
    CGFloat one = s.isVertical ? NSWidth(a) : NSHeight(a), two = s.isVertical ? NSWidth(b) : NSHeight(b);
    return one / (one + two);
}
static void samePlace(PDFView *a, PDFView *b, NSString *what) {
    TSPreviewPanePlace p = TSPreviewPaneCapture(a), q = TSPreviewPaneCapture(b);
    check(p.valid && q.valid && p.pageIndex == q.pageIndex && near(p.pagePoint.y, q.pagePoint.y, 2) && near(p.pagePoint.x, q.pagePoint.x, 2),
          [NSString stringWithFormat:@"%@: the same place (page %lu at %@, not page %lu at %@)", what, (unsigned long)p.pageIndex + 1,
           NSStringFromPoint(p.pagePoint), (unsigned long)q.pageIndex + 1, NSStringFromPoint(q.pagePoint)]);
}

int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    PDFDocument *pdf = book(7);

    for (NSNumber *sideBySide in @[@NO, @YES]) {
        NSString *name = sideBySide.boolValue ? @"side by side" : @"top and bottom";
        // The Preview as the user left it: split, each part with its own display format and place.
        TestWindow *before = preview(pdf);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView, *two = (MyPDFKitView *)before.myPDFKitView2;
        one->pageStyle = PDF_DOUBLE_MULTI_PAGE_STYLE; [one setupPageStyle];
        one.autoScales = NO; one->resizeOption = NEW_PDF_FIT_TO_NONE; one.scaleFactor = 1.4;
        [before.pdfKitSplitView setVertical:sideBySide.boolValue];
        before.horizontal = !sideBySide.boolValue;
        [before mainSplitPdfKitWindow];
        NSSplitView *s = before.pdfKitSplitView;
        [s setPosition:round(((s.isVertical ? NSWidth(s.bounds) : NSHeight(s.bounds)) - s.dividerThickness) * 0.35) ofDividerAtIndex:0];
        [s adjustSubviews];
        two->pageStyle = PDF_SINGLE_PAGE_STYLE; [two setupPageStyle];
        two.autoScales = NO; two->resizeOption = NEW_PDF_FIT_TO_NONE; two.scaleFactor = 0.9;
        [before layoutIfNeeded];
        scrollTo(one, 1, 400); scrollTo(two, 4, 300);
        before.activeView = two;
        before.myDocument.previewDirectionOverride = @YES;
        before.myDocument.previewBookOverride = @NO;
        NSData *state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });

        // The next launch: the PDF is opened again in a Preview as TeXShop opens it.
        TestWindow *after = preview(pdf);
        MyPDFKitView *a1 = (MyPDFKitView *)after.myPDFKitView, *a2 = (MyPDFKitView *)after.myPDFKitView2;
        check([after restorePreviewStateWithCoder:unarchiver(state)], [name stringByAppendingString:@": the state is restored"]);
        pump();
        check(after.windowIsSplit && after.splits == 1 && after.horizontal == !sideBySide.boolValue
              && after.pdfKitSplitView.isVertical == sideBySide.boolValue, [name stringByAppendingString:@": the window is split the same way"]);
        check(near(share(after), share(before), 0.01), [NSString stringWithFormat:@"%@: the divider is where it was (%.3f, not %.3f)",
                                                       name, share(before), share(after)]);
        check(after.activeView == a2 && a2.activations == 1, [name stringByAppendingString:@": the second part is in use again"]);
        check(a1->pageStyle == PDF_DOUBLE_MULTI_PAGE_STYLE && a1.displayMode == kPDFDisplayTwoUpContinuous
              && a2->pageStyle == PDF_SINGLE_PAGE_STYLE && a2.displayMode == kPDFDisplaySinglePage,
              [name stringByAppendingString:@": each part has its display format"]);
        check(!a1.autoScales && near(a1.scaleFactor, 1.4, 0.001) && !a2.autoScales && near(a2.scaleFactor, 0.9, 0.001)
              && a1->resizeOption == NEW_PDF_FIT_TO_NONE, [name stringByAppendingString:@": each part has its magnification"]);
        samePlace(one, a1, [name stringByAppendingString:@", first part"]);
        samePlace(two, a2, [name stringByAppendingString:@", second part"]);
        check([after.myDocument.previewDirectionOverride isEqual:@YES] && [after.myDocument.previewBookOverride isEqual:@NO]
              && a1.arrangements == 1 && a2.arrangements == 1, [name stringByAppendingString:@": the Two-Page Arrangement chosen comes back"]);
        check(after.myDocument.layoutUpdates >= 1, [name stringByAppendingString:@": the toolbar follows"]);
        [before close]; [after close];
    }

    {   // Not split, Fit to Width (the magnification fits the window again), the document's own arrangement.
        TestWindow *before = preview(pdf);
        MyPDFKitView *one = (MyPDFKitView *)before.myPDFKitView;
        one->pageStyle = PDF_SINGLE_PAGE_STYLE; [one setupPageStyle];
        one->resizeOption = NEW_PDF_FIT_TO_WIDTH; one.autoScales = YES;
        scrollTo(one, 2, 500);
        NSData *state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
        TestWindow *after = preview(pdf);
        after.myDocument.previewDirectionOverride = @YES;
        MyPDFKitView *a1 = (MyPDFKitView *)after.myPDFKitView;
        check([after restorePreviewStateWithCoder:unarchiver(state)], @"not split: the state is restored");
        pump();
        check(!after.windowIsSplit && after.splits == 0 && after.activeView == a1, @"not split: the window stays unsplit");
        check(a1->pageStyle == PDF_SINGLE_PAGE_STYLE && a1.autoScales && a1->resizeOption == NEW_PDF_FIT_TO_WIDTH, @"not split: Single Page, Fit to Width");
        samePlace(one, a1, @"not split");
        check(after.myDocument.previewDirectionOverride == nil, @"not split: the document's own arrangement is used again");

        // Fit to Content Width is fitted again in the window shown.
        one->resizeOption = NEW_PDF_FIT_TO_CONTENT_WIDTH; one.autoScales = NO; one.scaleFactor = 1.2;
        state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
        after = preview(pdf); a1 = (MyPDFKitView *)after.myPDFKitView;
        [after restorePreviewStateWithCoder:unarchiver(state)]; pump();
        check(a1->resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH && a1.contentWidthFits == 1, @"Fit to Content Width is fitted again");

        // The PDF has fewer pages since: its last page is shown.
        scrollTo(one, 6, 300);
        state = archive(^(NSKeyedArchiver *a) { [before encodePreviewStateWithCoder:a]; });
        after = preview(book(3)); a1 = (MyPDFKitView *)after.myPDFKitView;
        [after restorePreviewStateWithCoder:unarchiver(state)]; pump();
        check([a1.document indexForPage:TSPreviewPaneCapture(a1).valid ? [a1.document pageAtIndex:TSPreviewPaneCapture(a1).pageIndex] : nil] == 2,
              @"a shorter PDF shows its last page");

        // A state saved by an earlier version has only the page: nothing here is restored.
        NSData *old = archive(^(NSKeyedArchiver *a) { [a encodeInteger:3 forKey:@"VisiblePDFPage"]; });
        after = preview(pdf); a1 = (MyPDFKitView *)after.myPDFKitView;
        check(![after restorePreviewStateWithCoder:unarchiver(old)] && a1->pageStyle == PDF_MULTI_PAGE_STYLE && a1.autoScales,
              @"an earlier version's state is left to the source's page restoration");
        // A Preview without a PDF keeps nothing.
        TestWindow *empty = preview(nil);
        NSData *none = archive(^(NSKeyedArchiver *a) { [empty encodePreviewStateWithCoder:a]; });
        check(![unarchiver(none) containsValueForKey:@"TSPreviewFirstPageStyle"], @"a Preview without a PDF keeps nothing");
    }

    {   // The Preview window of a PDF opened by itself keeps its file and frame; a source's does not.
        TestWindow *before = preview(pdf);
        // Inside the visible part of the screen, which setFrameFromString: keeps windows in.
        NSRect visible = NSScreen.mainScreen.visibleFrame;
        [before setFrame:NSMakeRect(NSMinX(visible) + 60, NSMinY(visible) + 40, 600, MIN(600, NSHeight(visible) - 80)) display:NO];
        NSData *own = archive(^(NSKeyedArchiver *a) { [before encodeRestorableStateWithCoder:a]; });
        check(![unarchiver(own) containsValueForKey:@"TSPreviewDocumentURL"], @"a source's Preview keeps no file of its own");
        before.restorationClass = [TestWindow class];
        own = archive(^(NSKeyedArchiver *a) { [before encodeRestorableStateWithCoder:a]; });
        NSKeyedUnarchiver *u = unarchiver(own);
        check([[u decodeObjectOfClass:[NSURL class] forKey:@"TSPreviewDocumentURL"] isEqual:before.myDocument.fileURL],
              @"a PDF opened by itself keeps its file");
        TestWindow *after = preview(pdf);
        after.restorationClass = [TestWindow class];
        [after restoreStateWithCoder:unarchiver(own)]; pump();
        check(NSEqualRects(after.frame, before.frame), [NSString stringWithFormat:@"the window comes back at its frame (%@, not %@)",
                                                        NSStringFromRect(before.frame), NSStringFromRect(after.frame)]);
        check([unarchiver(own) containsValueForKey:@"TSPreviewFirstPageStyle"], @"a PDF opened by itself keeps the state of its Preview");
    }
    puts("PASS: the Preview comes back split as it was, with the display format, magnification and place of each part, the Two-Page Arrangement chosen and its frame");
} return 0; }
'''
program = program.replace('VIEWMETHODS', view_text).replace('WINDOWMETHODS', window_text)
verify_embedded(program, fragments if not args.mutation else [])
with tempfile.TemporaryDirectory(prefix='texshop-restore-state-') as directory:
    temp = Path(directory)
    (temp / 'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    '-I', str(root / 'Tests'), *include_args(root), str(temp / 'test.m'),
                    str(root / 'Sources/Preview/TSPreviewScrollerKeeper.m'), '-o', str(temp / 'test')], check=True)
    home = temp / 'home'
    (home / 'Library' / 'Preferences').mkdir(parents=True)
    environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temp))
    result = subprocess.run([str(temp / 'test')], timeout=120, env=environment, capture_output=True, text=True)
    output = (result.stdout + result.stderr).strip()
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.splitlines()[-1])
    else:
        print(output)
        result.check_returncode()
