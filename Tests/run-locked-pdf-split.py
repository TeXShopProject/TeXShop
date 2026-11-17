#!/usr/bin/env python3
"""A PDF with a password in a split Preview (#55), with the production code in windows that are
never shown.

PDFKit asks for the password in its own field and unlocks the PDF there. While it shows the
field, it places the view by constraints instead of by its frame, and it leaves the view so
after the PDF is unlocked. Splitting then gave the first part no size, and the window stayed
blank after unsplitting; splitting before typing the password did the same. Each part of a
split is placed by its frame again, so both parts fill the window and follow its size, with
the password field in each part while the PDF is locked.

The page count in the toolbar, the outline and the PDF's own settings could only be read
once the PDF was unlocked: they are filled in then, for each part that shows the PDF.

Stand-ins, and what they hide:
- MyPDFKitView here has only the methods the split code and the unlock call; display styles,
  magnification and Fit to Content Width are plain (run-preview-split-position.py and
  run-fit-content-width.py check them). fitContentWidth counts its calls.
- setupOutline, makePageChanges: and updatePreviewLayoutControls record that they ran;
  the drawer outline, the page number box and the toolbar layout controls are not built.
- The document (TestHost) gives the parts and fixed book and direction settings; the
  toolbar controller that reads the PDF's direction is not used.
- The active-part line (#14) is the production one; it is placed by constraints, so the
  window lays out with them as the Preview window does. The window counts as key, which
  only lets the line show.
- PDFKit writes the test PDF with a user password. It can count the pages of that PDF while
  it is locked; it counts none in the reporter's PDF, whose cross-reference table is
  compressed. The page count fields start at 0, as with the reporter's PDF.

Not covered here: in these windows, AppKit places the parts of a split made while the PDF is
locked by their frames by itself, which it does not in a window on the screen. Splitting
before the password is typed, and the constraints the split view kept, were checked in a
window on the screen (macOS 26.6.2)."""
from pathlib import Path
import argparse
import subprocess
import sys
import tempfile
from source_tree import include_args
from production_fragments import closing_brace, verify_embedded

MUTATIONS = {
    # The parts keep the placement PDFKit left them with.
    'no-frame-placement': ('window', '    TSPreviewPlacePartByFrame(firstView);\n    TSPreviewPlacePartByFrame(secondView);\n', ''),
    # Only an unlocked PDF is placed by frames: splitting before the password is typed fails.
    'unlocked-only': ('window', '    TSPreviewPlacePartByFrame(firstView);\n    TSPreviewPlacePartByFrame(secondView);\n',
                      '    if (![[firstView document] isLocked]) {\n        TSPreviewPlacePartByFrame(firstView);\n        TSPreviewPlacePartByFrame(secondView);\n    }\n'),
    # The constraints of the split view that placed the part are kept.
    'placing-kept': ('window', '    [NSLayoutConstraint deactivateConstraints: placing];\n', ''),
    'no-page-count': ('view', '    [totalPage setIntegerValue:totalPages];\n', ''),
    'other-part-not-adopted': ('view', '            [part adoptUnlockedDocument];\n', '            ;\n'),
    'no-outline': ('view', '    [self setupOutline];\n}', '}'),
    'no-content-width': ('view', '    if (resizeOption == NEW_PDF_FIT_TO_CONTENT_WIDTH)\n        [self fitContentWidth];\n', ''),
    'other-document': ('view', '    if (document != [self document])\n        return;\n', ''),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
window_source = (root / 'Sources/Windows/TSPreviewWindow.m').read_text(encoding='latin1')
view_source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
divider = root / 'Sources/Preview/TSPreviewSplitDivider.m'

def last_method(source, signature):
    # TSPreviewWindow.m keeps an older copy of mainSplitPdfKitWindow in a comment.
    start = source.rindex(signature)
    return source[start:closing_brace(source, source.index('{', start))]

fragments = []
def span(first, last):
    start = window_source.index(first); end = window_source.index(last, start) + len(last)
    fragments.append(('statements:' + first, window_source, window_source[start:end]))
    return window_source[start:end]

# The line along the active part of a split window (#14), with the setters that show it.
line_class = span('@interface TSPreviewActivePartLine : NSView', '''    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

@end''')
line_methods = span('- (void)setActiveView:(PDFView *)activeView', '''            TSActivePartLineInView(self, view).shown = shown;
    }
}''')
window_parts = [last_method(window_source, s) for s in (
    'static void TSPreviewPlacePartByFrame(NSView *part)', '- (void) mainSplitPdfKitWindow', '- (void) splitPdfKitWindow:',
    # Unsplitting while the second part is in use first switches the parts (#52).
    '- (void)switchSplitParts\n')]
view_methods = [last_method(view_source, s) for s in (
    '- (void)documentDidUnlock:(NSNotification *)notification', '- (void)adoptUnlockedDocument',
    '- (void)saveLocation\n', '- (void)restoreLocation\n', '- (NSInteger)index\n', '- (void)moveSplitToCorrectSpot:')]
fragments += [('complete method: ' + text.split('\n')[0], source, text)
             for source, text in [(window_source, m) for m in window_parts] + [(view_source, m) for m in view_methods]]
if args.mutation:
    where, old, new = MUTATIONS[args.mutation]
    texts = window_parts if where == 'window' else view_methods
    assert sum(t.count(old) for t in texts) == 1, args.mutation
    texts[:] = [t.replace(old, new) for t in texts]

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TestAppKitIsolation.h"
#import "TSPreviewPanePlace.h"
#import "TSDocumentWindowGlass.h"
#import "TSPreviewSplitDivider.h"
#define NEW_PDF_FIT_TO_NONE 1
#define NEW_PDF_FIT_TO_WINDOW 4
#define NEW_PDF_FIT_TO_CONTENT_WIDTH 6
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSEventModifierFlags flags;
static NSEventModifierFlags currentFlags(id s, SEL c) { return flags; }
// The split toolbar buttons are checked in run-split-toggle-option.py.
static void TSSplitToggleItemsFollowSplit(void) {}
@class TestHost, TSPreviewWindow;
@interface TSLinkPreviewView : NSView @end
@implementation TSLinkPreviewView @end
@interface MyPDFKitView : PDFView <PDFDocumentDelegate> {
    TSPreviewPanePlace splitPlace;
    NSInteger pageStyle, firstPageStyle, resizeOption, totalPages;
    NSTextField *totalPage, *stotalPage, *totalPage1;
}
@property BOOL locationSaved, verticalSplitSaved, horizontalSplitSaved;
@property double horizontalHeight1, horizontalHeight2, verticalWidth1, verticalWidth2;
@property BOOL oldUsed, doScroll; @property NSRect oldVisibleRect; @property NSInteger oldIndex;
@property (weak) TestHost *myDocument;
@property (weak) TSPreviewWindow *myPDFWindow;
@property NSInteger contentWidthFits, outlineSetups, shownPageIndex;
- (void)moveSplitToCorrectSpot:(NSInteger)index;
- (void)saveLocation;
- (void)restoreLocation;
- (void)adoptUnlockedDocument;
@end
@interface TestHost : NSObject
@property (weak) MyPDFKitView *myPDFKitView, *myPDFKitView2;
@property NSInteger layoutControlUpdates;
- (void)annotationPartWillCollapse:(id)view;
- (BOOL)previewDisplaysAsBook;
- (BOOL)previewDisplaysRTL;
- (void)updatePreviewLayoutControls;
@end
@implementation TestHost
- (void)annotationPartWillCollapse:(id)view {}
- (BOOL)previewDisplaysAsBook { return NO; }
- (BOOL)previewDisplaysRTL { return NO; }
- (void)updatePreviewLayoutControls { self.layoutControlUpdates++; }
@end
@interface TSPreviewWindow : NSWindow
@property (strong) TestHost *myDocument;
@property BOOL firstTime, horizontal;
@property (nonatomic) BOOL windowIsSplit;
@property (nonatomic, retain) PDFView *activeView;
@property PDFView *myPDFKitView, *myPDFKitView2;
- (void)showActivePart;
@property NSSplitView *pdfKitSplitView;
@property (strong) TSPreviewSplitDivider *previewSplitDivider;
- (void)mainSplitPdfKitWindow;
- (void)splitPdfKitWindow:(id)sender;
- (void)switchSplitParts;
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
- (void)setupPageStyle { [self setDisplayMode:kPDFDisplaySinglePageContinuous]; }
- (void)setupMagnificationStyle { [self setAutoScales:YES]; }
- (void)fitContentWidth { self.contentWidthFits++; }
- (void)measureContentLater {}
- (void)centreContentRowLater {}
- (void)cleanupMarqueeKeepingPinnedLinkPreview {}
- (void)notificationSetup {}
- (void)resetSearchDelegate {}
- (void)becomeActiveView {}
- (BOOL)hasPinnedLinkPreview { return YES; }
- (TSLinkPreviewView *)detachPinnedLinkPreviewWithWindowFrame:(NSRect *)f { return nil; }
- (void)attachPinnedLinkPreview:(TSLinkPreviewView *)p windowFrame:(NSRect)f {}
- (void)setupOutline { self.outlineSetups++; }
- (void)makePageChanges:(NSInteger)pageNumber { self.shownPageIndex = pageNumber; }
- (NSInteger)shownTotalPages { return totalPages; }
- (void)connectPageCountFields { totalPage = [NSTextField new]; stotalPage = [NSTextField new]; totalPage1 = [NSTextField new];
    totalPage.integerValue = stotalPage.integerValue = totalPage1.integerValue = 0; }
- (NSArray<NSTextField *> *)pageCountFields { return @[totalPage, stotalPage, totalPage1]; }
VIEWMETHODS
@end
LINECLASS
@implementation TSPreviewWindow
- (BOOL)isKeyWindow { return YES; }
- (void)keepPinnedLinkPreviewsInView {}
LINEMETHODS
WINDOWMETHODS
@end

// The window's content runs under its toolbar, as the Preview window's on macOS 26 and later.
@interface GlassToolbar : NSObject <NSToolbarDelegate> @end
@implementation GlassToolbar
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar { return @[@"item"]; }
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar { return @[@"item"]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.label = @"Item"; item.image = [NSImage imageWithSystemSymbolName:@"doc" accessibilityDescription:nil];
    return item;
}
@end
static GlassToolbar *glassToolbar;
static void settle(NSWindow *w) {
    for (int i = 0; i < 5; i++) {
        [w layoutIfNeeded];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
    }
}
static NSSecureTextField *passwordField(NSView *v) {
    if ([v isKindOfClass:NSSecureTextField.class]) return (NSSecureTextField *)v;
    for (NSView *s in v.subviews) { NSSecureTextField *f = passwordField(s); if (f) return f; }
    return nil;
}
// The password field can be seen: it and the views around it are not hidden, and it lies in the part.
static BOOL passwordFieldShown(PDFView *v) {
    NSSecureTextField *f = passwordField(v);
    if (!f || f.isHiddenOrHasHiddenAncestor) return NO;
    return NSContainsRect(v.bounds, [f convertRect:f.bounds toView:v]);
}

typedef struct { TSPreviewWindow *window; TestHost *host; MyPDFKitView *first, *second; } Preview;
static Preview makePreview(NSURL *url, BOOL underToolbar, NSInteger resizeOption) {
    TSPreviewWindow *w = [[TSPreviewWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 760)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    if (underToolbar) {
        if (!glassToolbar) glassToolbar = [GlassToolbar new];
        w.toolbarStyle = NSWindowToolbarStyleExpanded;
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"glass"];
        toolbar.delegate = glassToolbar; w.toolbar = toolbar;
        w.styleMask |= NSWindowStyleMaskFullSizeContentView;
    }
    NSSplitView *sv = [[NSSplitView alloc] initWithFrame:w.contentView.bounds];
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [w.contentView addSubview:sv];
    TestHost *host = [TestHost new];
    MyPDFKitView *a = [[MyPDFKitView alloc] initWithFrame:sv.bounds], *b = [[MyPDFKitView alloc] initWithFrame:sv.bounds];
    for (MyPDFKitView *v in @[a, b]) {
        // As in TSDocument.nib.
        v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        v.autoresizesSubviews = NO; v.wantsLayer = YES;
        [v setPageStyle:3]; [v setResizeOption:resizeOption];
        v.myDocument = host; v.myPDFWindow = w;
    }
    [a connectPageCountFields];
    [sv addSubview:a];
    host.myPDFKitView = a; host.myPDFKitView2 = b;
    w.myDocument = host; w.pdfKitSplitView = sv; w.myPDFKitView = a; w.myPDFKitView2 = b; w.activeView = a;
    w.firstTime = YES; w.horizontal = YES;
    // As showWithPath: does: the document is shown, then the first part hears from it.
    PDFDocument *doc = [[PDFDocument alloc] initWithURL:url];
    a.document = doc; [a setupPageStyle]; [a setupMagnificationStyle];
    doc.delegate = a;
    settle(w);
    return (Preview){w, host, a, b};
}
static void split(Preview p) { [p.window splitPdfKitWindow:nil]; settle(p.window); }
static void resize(Preview p, CGFloat width, CGFloat height) {
    NSRect f = p.window.frame; f.size = NSMakeSize(width, height);
    [p.window setFrame:f display:NO]; settle(p.window);
}
static void unlockIn(Preview p, PDFView *part, NSString *password) {
    NSSecureTextField *f = passwordField(part);
    check(f != nil, @"PDFKit shows its password field in the part");
    f.stringValue = password;
    [f sendAction:f.action to:f.target];
    settle(p.window);
}
// The parts fill the split view: across it, and along it with the divider between them.
static void checkFilled(Preview p, NSString *when) {
    NSSplitView *sv = p.window.pdfKitSplitView;
    // A split shows each part placed by its frame, and the split view keeps no constraints
    // that placed a part: in a window on the screen they held the window at its size, and
    // PDFKit may place a part by constraints again only when it is shown.
    if (p.window.windowIsSplit)
        for (PDFView *part in @[p.first, p.second]) {
            check(part.translatesAutoresizingMaskIntoConstraints, [when stringByAppendingString:@": each part is placed by its frame"]);
            for (NSLayoutConstraint *c in sv.constraints)
                check(!((c.firstItem == part || c.secondItem == part) && ![c isKindOfClass:NSClassFromString(@"NSAutoresizingMaskLayoutConstraint")]),
                      [NSString stringWithFormat:@"%@: the split view does not place a part by constraints (%@)", when, c]);
        }
    NSRect bounds = sv.bounds, a = p.first.frame;
    if (!p.window.windowIsSplit) {
        check(p.second.superview == nil, [when stringByAppendingString:@": the second part is gone"]);
        check(fabs(NSWidth(a) - NSWidth(bounds)) < 1 && fabs(NSHeight(a) - NSHeight(bounds)) < 1,
              [NSString stringWithFormat:@"%@: the part fills the window (%@ in %@)", when, NSStringFromRect(a), NSStringFromRect(bounds)]);
        return;
    }
    NSRect b = p.second.frame;
    check(p.second.superview == sv, [when stringByAppendingString:@": the second part is shown"]);
    check(fabs(NSWidth(a) - NSWidth(bounds)) < 1 && fabs(NSWidth(b) - NSWidth(bounds)) < 1,
          [NSString stringWithFormat:@"%@: both parts are as wide as the window (%@, %@ in %@)", when, NSStringFromRect(a), NSStringFromRect(b), NSStringFromRect(bounds)]);
    check(NSHeight(a) > 100 && NSHeight(b) > 100 && fabs(NSHeight(a) + NSHeight(b) + sv.dividerThickness - NSHeight(bounds)) < 1,
          [NSString stringWithFormat:@"%@: the parts share the height (%@, %@ in %@)", when, NSStringFromRect(a), NSStringFromRect(b), NSStringFromRect(bounds)]);
}
static void checkUnlocked(Preview p, NSString *when, NSArray<MyPDFKitView *> *parts) {
    NSInteger count = p.first.document.pageCount;
    check(!p.first.document.isLocked && count > 1, [when stringByAppendingString:@": the PDF is unlocked"]);
    for (NSTextField *field in [p.first pageCountFields])
        check(field.integerValue == count, [NSString stringWithFormat:@"%@: the toolbar shows the page count (%ld, not %ld)", when, (long)count, (long)field.integerValue]);
    check(p.first.outlineSetups == 1, [when stringByAppendingString:@": the outline is set up once"]);
    check(p.first.shownPageIndex == 0, [when stringByAppendingString:@": the page number shows the first page"]);
    check(p.host.layoutControlUpdates == 1, [when stringByAppendingString:@": the layout controls follow the PDF's own settings"]);
    for (MyPDFKitView *part in parts) {
        check(part.shownTotalPages == count, [when stringByAppendingString:@": each part counts the pages"]);
        check(part.contentWidthFits == 1, [when stringByAppendingString:@": each part fits the width of the content once"]);
        check(!passwordFieldShown(part), [when stringByAppendingString:@": no part shows the password field"]);
    }
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];
    method_setImplementation(class_getClassMethod(NSEvent.class, @selector(modifierFlags)), (IMP)currentFlags);
    NSURL *plain = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    NSURL *locked = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
    PDFDocument *source = [[PDFDocument alloc] initWithURL:plain];
    check([source writeToURL:locked withOptions:@{PDFDocumentUserPasswordOption: @"secret", PDFDocumentOwnerPasswordOption: @"owner"}],
          @"the test PDF with a password is written");
    check([[PDFDocument alloc] initWithURL:locked].isLocked, @"the test PDF is locked");
    NSMutableArray *layouts = [NSMutableArray arrayWithObject:@NO];
    if (@available(macOS 26.0, *)) [layouts addObject:@YES];
    for (NSNumber *underToolbar in layouts) {
        NSString *window = underToolbar.boolValue ? @"window under the toolbar" : @"window";
        {   // The steps of the report: type the password, then split, unsplit and split again.
            NSString *name = [@"unlocked, then split, " stringByAppendingString:window];
            Preview p = makePreview(locked, underToolbar.boolValue, NEW_PDF_FIT_TO_CONTENT_WIDTH);
            check(passwordFieldShown(p.first), [name stringByAppendingString:@": the part shows the password field"]);
            unlockIn(p, p.first, @"secret");
            checkUnlocked(p, name, @[p.first]);
            check(p.second.contentWidthFits == 0, [name stringByAppendingString:@": the hidden part is left alone"]);
            checkFilled(p, [name stringByAppendingString:@", unsplit"]);
            split(p); checkFilled(p, [name stringByAppendingString:@", split"]);
            resize(p, 900, 700); checkFilled(p, [name stringByAppendingString:@", split, window changed"]);
            split(p); checkFilled(p, [name stringByAppendingString:@", unsplit again"]);
            resize(p, 760, 820); checkFilled(p, [name stringByAppendingString:@", unsplit, window changed"]);
            split(p); checkFilled(p, [name stringByAppendingString:@", split again"]);
            [p.window close];
        }
        {   // Split before the password is typed: each part shows the field until it is typed in one.
            NSString *name = [@"split, then unlocked, " stringByAppendingString:window];
            Preview p = makePreview(locked, underToolbar.boolValue, NEW_PDF_FIT_TO_CONTENT_WIDTH);
            split(p); checkFilled(p, [name stringByAppendingString:@", split while locked"]);
            check(passwordFieldShown(p.first) && passwordFieldShown(p.second), [name stringByAppendingString:@": both parts show the password field"]);
            split(p); checkFilled(p, [name stringByAppendingString:@", unsplit while locked"]);
            resize(p, 900, 700); checkFilled(p, [name stringByAppendingString:@", unsplit while locked, window changed"]);
            split(p); checkFilled(p, [name stringByAppendingString:@", split while locked again"]);
            unlockIn(p, p.second, @"secret");
            checkUnlocked(p, name, @[p.first, p.second]);
            checkFilled(p, [name stringByAppendingString:@", unlocked in the second part"]);
            resize(p, 760, 820); checkFilled(p, [name stringByAppendingString:@", window changed"]);
            split(p); checkFilled(p, [name stringByAppendingString:@", unsplit"]);
            split(p); checkFilled(p, [name stringByAppendingString:@", split again"]);
            [p.window close];
        }
        {   // A PDF without a password is shown as before.
            NSString *name = [@"PDF without a password, " stringByAppendingString:window];
            Preview p = makePreview(plain, underToolbar.boolValue, NEW_PDF_FIT_TO_WINDOW);
            check(!passwordFieldShown(p.first) && p.first.translatesAutoresizingMaskIntoConstraints, [name stringByAppendingString:@": no password field"]);
            split(p); checkFilled(p, [name stringByAppendingString:@", split"]);
            split(p); checkFilled(p, [name stringByAppendingString:@", unsplit"]);
            check(p.first.outlineSetups == 0 && p.first.contentWidthFits == 0, [name stringByAppendingString:@": nothing is unlocked"]);
            [p.window close];
        }
    }
    {   // Another PDF unlocked does not touch the part.
        Preview p = makePreview(plain, NO, NEW_PDF_FIT_TO_CONTENT_WIDTH);
        PDFDocument *other = [[PDFDocument alloc] initWithURL:locked];
        [p.first documentDidUnlock:[NSNotification notificationWithName:PDFDocumentDidUnlockNotification object:other]];
        check(p.first.outlineSetups == 0 && p.first.contentWidthFits == 0 && p.host.layoutControlUpdates == 0,
              @"the unlocking of another PDF is ignored");
        [p.window close];
    }
    printf("PASS: %lu checks\n", (unsigned long)checks);
    return 0;
}}
'''
program = (program.replace('VIEWMETHODS', '\n'.join(view_methods)).replace('WINDOWMETHODS', '\n'.join(window_parts))
           .replace('LINECLASS', line_class).replace('LINEMETHODS', line_methods))
if not args.mutation:
    verify_embedded(program, fragments)
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    tex = temp / 'doc.tex'
    tex.write_text('\\documentclass{article}\\begin{document}\n' +
                   '\n\n'.join('Paragraph %d. ' % i + 'Text of the test document. ' * 40 for i in range(60)) +
                   '\n\\end{document}\n')
    pdflatex = next((p for p in ('/Applications/TeXLive/2026/bin/universal-darwin/pdflatex', '/Library/TeX/texbin/pdflatex')
                     if Path(p).exists()), 'pdflatex')
    subprocess.run([pdflatex, '-interaction=batchmode', '-output-directory', str(temp), str(tex)],
                   check=True, stdout=subprocess.DEVNULL, cwd=temp)
    (temp / 'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'PDFKit',
                    '-I', str(temp), '-I', str(root / 'Tests'), *include_args(root),
                    str(temp / 'test.m'), str(divider), str(root / 'Sources/Windows/TSDocumentWindowGlass.m'), '-o', str(temp / 'test')], check=True)
    result = subprocess.run([str(temp / 'test'), str(temp / 'doc.pdf'), str(temp / 'locked.pdf')], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation
        print('PASS: detected mutation ' + args.mutation + ': ' + output.strip().splitlines()[-1])
    else:
        print(output.strip())
        sys.exit(result.returncode)
