#!/usr/bin/env python3
"""The annotation toolbar of the Preview (Issue #49), with production code and nothing on screen.

Builds the production TSAnnotationBar, TSAnnotationTextPopover and TSDocument's AnnotationBar
category (with stand-ins for TSDocument, MyPDFKitView and TSPreviewWindow) and checks:
- the bar in every language: both layouts, their widths (the narrow one at most 480 points),
  labels that fit, names for VoiceOver, the order of the » menu;
- edit mode: one way in and out for the document, both parts of the Preview, annotationsExist,
  the annotation menu, the bar shown while in edit mode;
- the part the tools act on, the Preview menu item, moving between the Preview window and the
  window that shows both, closing a window;
- the text popover: what commits and what discards (spec §3.6.3), the binding to the annotation;
- the color and font panels: closed by the bar only while they still serve its document (§3.7).

--images DIR also writes pictures of the bar (both layouts, light and dark, en and ja).
--widths prints the width of both layouts in every language.
--mutation NAME checks that the checks catch a broken production line.
"""
import argparse, re, subprocess, sys, tempfile
from pathlib import Path
from source_tree import source_file

MUTATIONS = {
    'click-commits-at-once': ('TSAnnotationTextPopover.m',
        '    [self performSelector:@selector(outsideClickIsOver) withObject:nil afterDelay:0\n                  inModes:@[NSDefaultRunLoopMode]];\n',
        '    [self outsideClickIsOver];\n'),
    'one-part-only': ('TSDocument-AnnotationBar.m',
        '    [(MyPDFKitView *)self.myPDFKitView2 applyAnnotationEditMode:on];\n', ''),
    'any-active-view': ('TSDocument-AnnotationBar.m',
        '    if (active != nil && active == self.myPDFKitView2 && window.windowIsSplit)\n', '    if (active != nil)\n'),
    'panels-never-change-hands': ('TSAnnotationBar.m',
        '    if (window == _attachedWindow || TSIsSharedPanel(window) || window == _textPopover.view.window)\n        return;\n    _ownsColorPanel = _ownsFontPanel = NO;\n',
        '    return;\n'),
    'no-binding-check': ('TSAnnotationTextPopover.m',
        '                 && [self changed] && [self bindingIsValid];\n', '                 && [self changed];\n'),
    'hide-keeps-edit-mode': ('TSDocument-AnnotationBar.m',
        '    if (window == nil)\n        return;\n    [self setAnnotationEditMode:NO];\n', '    if (window == nil)\n        return;\n'),
    'no-minimum-width': ('TSAnnotationBar.m', '    minSize.width = MAX(minSize.width, _compactWidth);\n', ''),
    'close-discards-first': None,
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
parser.add_argument('--images', type=Path)
parser.add_argument('--widths', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
names = ['TSAnnotationBar.h', 'TSAnnotationBar.m', 'TSAnnotationTextPopover.h', 'TSAnnotationTextPopover.m',
         'TSDocument-AnnotationBar.m', 'TSDocumentWindowGlass.h', 'TSDocumentWindowGlass.m', 'TSPreviewPanePlace.h']
text = {n: source_file(root, n).read_text(encoding='utf-8') for n in names}
if args.mutation and MUTATIONS[args.mutation]:
    n, old, new = MUTATIONS[args.mutation]
    assert text[n].count(old) == 1, args.mutation
    text[n] = text[n].replace(old, new)

# Closing a window asks to save unsaved annotations (committing the text being edited) before the
# annotation toolbar is taken off, which drops the text (spec §3.6.3); the shared color and font
# panels are closed by the toolbar only (spec §3.7).
def method_body(name, start):
    t = source_file(root, name).read_text(encoding='utf-8')
    a = t.index(start)
    return t[a:t.index('\n}\n', a)]
order_problems = []
document_close = method_body('TSDocument.m', '- (void)close\n{')
if not document_close.index('[self callSaveAnnotations]') < document_close.index('[self annotationWindowWillClose: nil]'):
    order_problems.append('TSDocument close takes the toolbar off before it saves the annotations')
if 'sharedColorPanel] close' in document_close or 'sharedFontPanel] close' in document_close:
    order_problems.append('TSDocument close closes the shared color or font panel itself')
preview_close = method_body('TSPreviewWindow.m', '- (void)close\n{')
if not preview_close.index('callSaveAnnotations]') < preview_close.index('annotationWindowWillClose: self]'):
    order_problems.append('the Preview window takes the toolbar off before it saves the annotations')
split_close = method_body('TSFullSplitWindow.m', '- (void)close\n{\n')
if not split_close.index('[[self.myDocument textWindow] close]') < split_close.index('annotationWindowWillClose: self]'):
    order_problems.append('the one window takes the toolbar off before the document asks to save')
if args.mutation == 'close-discards-first':
    order_problems.append('mutation')

# The category's interface comes from the production header.
header = source_file(root, 'TSDocument.h').read_text(encoding='utf-8')
a = header.index('@interface TSDocument (AnnotationBar) <TSAnnotationBarHost>')
category = header[a:header.index('@end', a) + 4]

stub_document = r'''#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSAnnotationBar.h"
@interface TSPreviewWindow : NSWindow
@property (nonatomic) BOOL windowIsSplit;
@property (nonatomic, strong) PDFView *activeView;
@property (weak) NSSplitView *pdfKitSplitView;
@end
@interface TSDocument : NSObject {
@public
    TSAnnotationBar *_annotationBar;
    BOOL _annotationEditMode;
    BOOL _annotationSaveAllPages;
}
@property (strong) PDFView *myPDFKitView;
@property (strong) PDFView *myPDFKitView2;
@property (strong) TSPreviewWindow *pdfKitWindow;
@property (strong) NSWindow *oneWindow;
@property BOOL oneWindowShown;
@property BOOL annotationsExist;
@property BOOL docUseAnnotationMenu;
- (BOOL)useFullSplitWindow;
- (id)fullSplitWindow;
@end
''' + category + '\n'

stub_view = r'''#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
@interface MyPDFKitView : PDFView
@property BOOL editModeValue;
@property NSInteger applied;
@property (strong) PDFAnnotation *selected;
@property (strong) NSMutableArray<NSString *> *commands;
- (void)applyAnnotationEditMode:(BOOL)edit;
- (PDFAnnotation *)selectedAnnotationForEditing;
@end
'''

program = r'''
#import "TestAppKitIsolation.h"
#import "TSDocument.h"
#import "MyPDFKitView.h"
#import "TSAnnotationBar.h"
#import "TSAnnotationTextPopover.h"

static int failures;
static void Check(BOOL ok, NSString *name) { if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }
// The event loop back in the default mode, after what a click started.
static void RunLoop(void) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }

// Localizable.strings of the language under test.
static NSDictionary *Strings;
static IMP OriginalLocalized;
// Only the program's own strings (the main bundle) come from the language under test.
static NSString *TSTestLocalized(NSBundle *self, SEL _cmd, NSString *key, NSString *value, NSString *table) {
    if (self == NSBundle.mainBundle && (table == nil || [table isEqual:@"Localizable"]))
        return Strings[key] ?: value ?: key;
    return ((NSString *(*)(id, SEL, NSString *, NSString *, NSString *))OriginalLocalized)(self, _cmd, key, value, table);
}
static NSWindow *KeyWindow;
static NSWindow *TSTestKeyWindow(id self, SEL _cmd) { return KeyWindow; }

@implementation TSPreviewWindow
@end
@implementation TSDocument
- (BOOL)useFullSplitWindow { return self.oneWindowShown; }
- (id)fullSplitWindow { return self.oneWindow; }
@end

@implementation MyPDFKitView
- (instancetype)initWithFrame:(NSRect)frame { if ((self = [super initWithFrame:frame])) _commands = [NSMutableArray array]; return self; }
- (void)applyAnnotationEditMode:(BOOL)edit { self.applied++; self.editModeValue = edit; }
- (PDFAnnotation *)selectedAnnotationForEditing { return self.selected; }
- (void)record:(SEL)s { [self.commands addObject:NSStringFromSelector(s)]; }
- (void)strikeoutAnnotation:(id)s { [self record:_cmd]; }   - (void)highlightAnnotation:(id)s { [self record:_cmd]; }
- (void)underlineAnnotation:(id)s { [self record:_cmd]; }   - (void)squareAnnotation:(id)s { [self record:_cmd]; }
- (void)bsquareAnnotation:(id)s { [self record:_cmd]; }     - (void)circleAnnotation:(id)s { [self record:_cmd]; }
- (void)bcircleAnnotation:(id)s { [self record:_cmd]; }     - (void)arrowAnnotation:(id)s { [self record:_cmd]; }
- (void)textAnnotation:(id)s { [self record:_cmd]; }        - (void)btextAnnotation:(id)s { [self record:_cmd]; }
- (void)popupAnnotation:(id)s { [self record:_cmd]; }       - (void)showColorPanel:(id)s { [self record:_cmd]; }
- (void)showFontPanel:(id)s { [self record:_cmd]; }         - (void)removeStreams:(id)s { [self record:_cmd]; }
- (void)saveAnnotations:(id)s { [self record:_cmd]; }
@end

static PDFDocument *MakeDocument(void) {
    PDFDocument *document = [PDFDocument new];
    for (int i = 0; i < 4; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600, 800)];
        [image lockFocus]; [NSColor.whiteColor set]; NSRectFill(NSMakeRect(0, 0, 600, 800)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return document;
}
static PDFAnnotation *AddText(PDFPage *page, NSString *contents) {
    PDFAnnotation *a = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(100, 100, 120, 30) forType:PDFAnnotationSubtypeFreeText withProperties:nil];
    a.contents = contents; a.alignment = NSTextAlignmentCenter;
    [page addAnnotation:a];
    return a;
}
static NSWindow *MakeWindow(NSRect frame) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable
                                                backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed = NO;
    w.toolbar = [[NSToolbar alloc] initWithIdentifier:@"test"];
    return w;
}

static void WriteImage(NSView *view, NSString *path, NSAppearanceName appearance) {
    view.appearance = [NSAppearance appearanceNamed:appearance];
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext = context;
    [(appearance == NSAppearanceNameDarkAqua ? [NSColor colorWithWhite:0.17 alpha:1] : [NSColor colorWithWhite:0.95 alpha:1]) setFill];
    NSRectFill(view.bounds);
    [NSGraphicsContext restoreGraphicsState];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}

// The views that draw a title in the bar fit it.
static void CheckLabels(TSAnnotationBar *bar, NSString *lang, NSString *layout) {
    for (NSView *view in @[bar.editModeButton, bar.saveButton, bar.saveAllCheckBox]) {
        if (view.isHidden || view.superview == nil) continue;
        NSButton *b = (NSButton *)view;
        if (b.imagePosition == NSImageOnly) continue;
        Check(NSWidth(b.frame) + 0.5 >= b.intrinsicContentSize.width,
              [NSString stringWithFormat:@"%@ %@: \"%@\" fits (%.1f < %.1f)", lang, layout, b.title, NSWidth(b.frame), b.intrinsicContentSize.width]);
    }
}

static void TestBar(NSString *lang, NSString *stringsPath, NSString *images, BOOL widths) {
    Strings = [NSDictionary dictionaryWithContentsOfFile:stringsPath];
    Check(Strings.count > 0, [lang stringByAppendingString:@": strings read"]);
    TSDocument *document = [TSDocument new];
    document->_annotationSaveAllPages = YES;   // as a document starts
    MyPDFKitView *first = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    document.myPDFKitView = first;
    TSAnnotationBar *bar = [[TSAnnotationBar alloc] initWithHost:document];
    Check(bar.saveAllCheckBox.state == NSControlStateValueOn, [lang stringByAppendingString:@": All Pages starts on"]);
    NSView *view = bar.view;
    Check(bar.compactWidth <= 480, [NSString stringWithFormat:@"%@: the narrow bar is at most 480 points (%.0f)", lang, bar.compactWidth]);
    Check(bar.compactWidth < bar.fullWidth, [lang stringByAppendingString:@": the narrow bar is narrower"]);
    if (widths) printf("%-6s full %4.0f  narrow %4.0f\n", lang.UTF8String, bar.fullWidth, bar.compactWidth);
    NSWindow *holder = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, bar.fullWidth, 36) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    holder.releasedWhenClosed = NO;
    [holder.contentView addSubview:view];
    for (int layout = 0; layout < 2; layout++) {
        CGFloat width = layout == 0 ? bar.fullWidth : bar.compactWidth;
        view.frame = NSMakeRect(0, 0, width, 36);
        [view layoutSubtreeIfNeeded];
        [view layoutSubtreeIfNeeded];
        Check(bar.compact == (layout == 1), [NSString stringWithFormat:@"%@: layout %d chosen for its width", lang, layout]);
        Check(bar.colorButton.isHidden == (layout == 1) && bar.saveButton.isHidden == (layout == 1) && bar.overflowButton.isHidden == (layout == 0),
              [NSString stringWithFormat:@"%@: layout %d shows its controls", lang, layout]);
        for (NSButton *tool in bar.toolButtons)
            Check(!tool.isHidden && NSMaxX([tool convertRect:tool.bounds toView:view]) <= width,
                  [NSString stringWithFormat:@"%@: tool %@ shown inside the bar in layout %d", lang, tool.toolTip, layout]);
        Check(!bar.closeButton.isHidden && NSMaxX([bar.closeButton convertRect:bar.closeButton.bounds toView:view]) <= width + 0.5,
              [NSString stringWithFormat:@"%@: close button inside the bar in layout %d", lang, layout]);
        CheckLabels(bar, lang, layout ? @"narrow" : @"full");
        if (images && ([lang isEqual:@"en"] || [lang isEqual:@"ja"])) {
            for (int edit = 0; edit < 2; edit++) {
                document->_annotationEditMode = edit;
                [bar updateControls];
                for (NSAppearanceName a in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua])
                    WriteImage(view, [images stringByAppendingPathComponent:[NSString stringWithFormat:@"bar-%@-%@-%@-%@.png", lang, layout ? @"narrow" : @"full",
                                                                              edit ? @"edit" : @"run", a == NSAppearanceNameAqua ? @"light" : @"dark"]], a);
            }
            document->_annotationEditMode = NO;
            [bar updateControls];
        }
    }
    // Names: every tool has its own, from the annotation menu, also for VoiceOver.
    NSMutableSet *seen = [NSMutableSet set];
    for (NSButton *tool in bar.toolButtons) {
        Check(tool.toolTip.length && [tool.accessibilityLabel isEqual:tool.toolTip], [NSString stringWithFormat:@"%@: tool %ld named", lang, (long)tool.tag]);
        [seen addObject:tool.toolTip ?: @""];
    }
    Check(seen.count == 11, [lang stringByAppendingString:@": the 11 tools have 11 names"]);
    for (NSView *c in @[bar.editModeButton, bar.colorButton, bar.fontButton, bar.textButton, bar.moreButton, bar.overflowButton, bar.closeButton])
        Check(c.accessibilityLabel.length > 0, [NSString stringWithFormat:@"%@: %@ has a name", lang, c.className]);
    // The text popover: the three alignments and OK fit side by side.
    TSAnnotationTextPopover *popover = bar.textPopover;
    NSView *content = popover.view;
    content.frame = (NSRect){NSZeroPoint, content.fittingSize};
    [content layoutSubtreeIfNeeded];
    NSSegmentedControl *alignment = popover.alignmentControl;
    Check(alignment.segmentCount == 3, [lang stringByAppendingString:@": three alignments"]);
    Check(NSWidth(alignment.frame) + 0.5 >= alignment.intrinsicContentSize.width
          && NSMaxX(alignment.frame) + 12 <= NSMinX(popover.okButton.frame) + 0.5
          && NSMaxX(popover.okButton.frame) <= NSWidth(content.bounds),
          [NSString stringWithFormat:@"%@: the alignments (%@ / %@ / %@) and OK fit", lang,
           [alignment labelForSegment:0], [alignment labelForSegment:1], [alignment labelForSegment:2]]);
    Check(NSWidth(content.frame) <= 420, [NSString stringWithFormat:@"%@: the text popover is at most 420 points wide (%.0f)", lang, NSWidth(content.frame)]);
    [holder close];
}

static void TestEditModeAndTargets(void) {
    TSDocument *document = [TSDocument new];
    document->_annotationSaveAllPages = YES;
    MyPDFKitView *first = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    MyPDFKitView *second = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    first.document = MakeDocument(); second.document = first.document;
    document.myPDFKitView = first; document.myPDFKitView2 = second;
    TSPreviewWindow *preview = [[TSPreviewWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 500)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    preview.releasedWhenClosed = NO;
    preview.toolbar = [[NSToolbar alloc] initWithIdentifier:@"preview"];
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:[preview.contentView bounds]];
    [split addSubview:first]; [split addSubview:second];
    [preview.contentView addSubview:split];
    preview.pdfKitSplitView = split;
    document.pdfKitWindow = preview;
    NSSize originalMin = preview.minSize;

    // Into edit mode: both parts, once each; the bar is shown; the guard rails are armed.
    [document setAnnotationEditMode:YES];
    Check(document.annotationEditMode && first.editModeValue && second.editModeValue, @"edit mode reaches both parts");
    Check(first.applied == 1 && second.applied == 1, @"each part is told once");
    Check(document.annotationsExist && document.docUseAnnotationMenu, @"edit mode arms the guard rails and the annotation menu");
    TSAnnotationBar *bar = document.annotationBar;
    Check(bar.attachedWindow == preview && [preview.titlebarAccessoryViewControllers containsObject:bar], @"edit mode shows the bar in the Preview window");
    Check(preview.minSize.width >= bar.compactWidth && preview.contentMinSize.width >= bar.compactWidth && NSWidth(preview.frame) >= bar.compactWidth,
          @"the window is at least as wide as the narrow bar");
    [document setAnnotationEditMode:YES];
    Check(first.applied == 1 && second.applied == 1, @"no change, no calls");
    Check(bar.editModeButton.state == NSControlStateValueOn, @"the switch shows edit mode");
    // Out of edit mode: both parts; annotationsExist stays; the bar stays.
    [document setAnnotationEditMode:NO];
    Check(!first.editModeValue && !second.editModeValue && !document.docUseAnnotationMenu, @"run mode reaches both parts and the menu");
    Check(document.annotationsExist, @"leaving edit mode keeps the guard rails armed");
    Check(bar.attachedWindow == preview && bar.editModeButton.state == NSControlStateValueOff, @"the bar stays, showing run mode");
    for (NSButton *tool in bar.toolButtons) Check(!tool.enabled, @"tools are off in run mode");
    Check(!bar.textButton.enabled && !bar.colorButton.enabled, @"color, font and text are off in run mode");

    // The part the tools act on.
    preview.activeView = nil; Check([document annotationTargetView] == first, @"no active part: the first part");
    preview.windowIsSplit = NO; preview.activeView = second; Check([document annotationTargetView] == first, @"the second part while not split: the first part");
    preview.windowIsSplit = YES; Check([document annotationTargetView] == second, @"the active second part of a split Preview");
    preview.activeView = [[PDFView alloc] initWithFrame:NSZeroRect]; Check([document annotationTargetView] == first, @"another document's view: the first part");
    preview.activeView = second;
    [document setAnnotationEditMode:YES];
    for (NSUInteger i = 0; i < TSAnnotationToolCount(); i++) [bar.toolButtons[i] performClick:nil];
    NSMutableArray *expected = [NSMutableArray array];
    for (NSUInteger i = 0; i < TSAnnotationToolCount(); i++) [expected addObject:NSStringFromSelector(TSAnnotationToolAtIndex(i).action)];
    Check([second.commands isEqual:expected] && first.commands.count == 0, @"the 11 tools reach the active part, in order");
    Check(preview.firstResponder == second, @"the part acted on becomes the first responder");

    // Text button: only for a selected text annotation.
    [bar updateControls]; Check(!bar.textButton.enabled, @"no selection: no text editing");
    PDFPage *page = [second.document pageAtIndex:0];
    PDFAnnotation *square = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(10, 10, 50, 50) forType:PDFAnnotationSubtypeSquare withProperties:nil];
    [page addAnnotation:square];
    second.selected = square; [bar updateControls]; Check(!bar.textButton.enabled, @"a square is not text");
    PDFAnnotation *text = AddText(page, @"Hello");
    second.selected = text; [bar updateControls]; Check(bar.textButton.enabled, @"a text annotation can be edited");

    // Menu item.
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"x" action:@selector(displayChoicesPanel:) keyEquivalent:@""];
    NSWindow *source = MakeWindow(NSMakeRect(0, 0, 300, 300));
    KeyWindow = source;
    Check(![document validateAnnotationBarItem:item], @"the menu item is off in the source window");
    KeyWindow = preview;
    Check([document validateAnnotationBarItem:item], @"the menu item is on in the Preview window");
    KeyWindow = nil;
    [source close];
    [document validateAnnotationBarItem:item];
    Check([item.title isEqual:@"Hide Annotation Toolbar"], @"the menu item hides the shown bar");
    // Hiding: run mode, the bar goes, annotationsExist stays, the minimum size comes back.
    [document displayChoicesPanel:item];
    Check(!document.annotationEditMode && !first.editModeValue && !second.editModeValue, @"hiding the bar leaves edit mode");
    Check(bar.attachedWindow == nil && ![preview.titlebarAccessoryViewControllers containsObject:bar], @"hiding takes the bar off the window");
    Check(preview.minSize.width == originalMin.width, @"hiding gives the window its minimum width back");
    Check(document.annotationsExist, @"hiding keeps the guard rails armed");
    [document validateAnnotationBarItem:item];
    Check([item.title isEqual:@"Show Annotation Toolbar"], @"the menu item shows the hidden bar");
    [document displayChoicesPanel:item];
    Check(bar.attachedWindow == preview && !document.annotationEditMode, @"showing the bar does not enter edit mode");

    // The window that shows both, and back.
    NSWindow *one = MakeWindow(NSMakeRect(0, 0, 900, 600));
    document.oneWindow = one;
    [document setAnnotationEditMode:YES];
    document.oneWindowShown = YES; [document annotationBarFollowWindowChange];
    Check(bar.attachedWindow == one && ![preview.titlebarAccessoryViewControllers containsObject:bar] && [one.titlebarAccessoryViewControllers containsObject:bar],
          @"the bar moves to the window that shows both");
    Check(document.annotationEditMode && first.editModeValue, @"edit mode survives the move");
    Check(preview.minSize.width == originalMin.width, @"the Preview window gets its minimum width back");
    document.oneWindowShown = NO; [document annotationBarFollowWindowChange];
    Check(bar.attachedWindow == preview, @"the bar moves back to the Preview window");

    // Closing another window does nothing; closing the bar's window leaves edit mode and takes the bar off.
    [document annotationWindowWillClose:one];
    Check(bar.attachedWindow == preview && document.annotationEditMode, @"another window closing changes nothing");
    [document annotationWindowWillClose:preview];
    Check(bar.attachedWindow == nil && !document.annotationEditMode, @"the bar's window closing ends edit mode");
    Check(document.annotationsExist, @"closing keeps annotationsExist for the guard rails");

    // A narrow window gets wider when the bar is shown.
    NSRect frame = preview.frame; frame.size.width = 250; [preview setFrame:frame display:NO];
    [document showAnnotationBar];
    Check(NSWidth(preview.frame) >= bar.compactWidth, @"a narrow window is widened for the bar");
    [document hideAnnotationBar];
    [preview close]; [one close];
}

static void TestPopover(void) {
    TSDocument *document = [TSDocument new];
    MyPDFKitView *first = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    MyPDFKitView *second = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    first.document = MakeDocument(); second.document = first.document;
    document.myPDFKitView = first; document.myPDFKitView2 = second;
    TSPreviewWindow *preview = [[TSPreviewWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 500)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    preview.releasedWhenClosed = NO; preview.toolbar = [[NSToolbar alloc] initWithIdentifier:@"p"];
    [preview.contentView addSubview:first];
    document.pdfKitWindow = preview;
    [document setAnnotationEditMode:YES];
    TSAnnotationBar *bar = document.annotationBar;
    TSAnnotationTextPopover *popover = bar.textPopover;
    PDFPage *page = [first.document pageAtIndex:1];
    PDFAnnotation *a = AddText(page, @"Old text");
    NSView *detached = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    void (^open)(PDFAnnotation *, PDFView *) = ^(PDFAnnotation *annotation, PDFView *view) {
        [popover showForAnnotation:annotation inView:view relativeToView:detached];
    };

    open(a, first);
    Check(popover.shown && [popover.textView.string isEqual:@"Old text"] && popover.alignmentControl.selectedSegment == 1, @"the popover shows the text and its alignment");
    popover.textView.string = @"New text"; popover.alignmentControl.selectedSegment = 0;
    [popover.okButton performClick:nil];
    Check(!popover.shown && [a.contents isEqual:@"New text"] && a.alignment == NSTextAlignmentLeft, @"OK writes the text and the alignment");

    open(a, first); popover.textView.string = @"Escaped";
    [popover finishWithReason:TSAnnotationTextFinishCancel];
    Check(!popover.shown && [a.contents isEqual:@"New text"], @"Escape writes nothing");

    // A click outside commits once what it started is over.
    open(a, first); popover.textView.string = @"Clicked away";
    [popover noteOutsideClick];
    Check(popover.shown && [a.contents isEqual:@"New text"], @"a click outside does not commit at once");
    RunLoop();
    Check(!popover.shown && [a.contents isEqual:@"Clicked away"], @"a click outside commits after its actions");

    // A click whose action discards (the bar's close button, the end of the split): the discard wins.
    open(a, first); popover.textView.string = @"Lost";
    [popover noteOutsideClick];
    [document hideAnnotationBar];
    RunLoop();
    Check(!popover.shown && [a.contents isEqual:@"Clicked away"], @"closing the bar from a click discards");
    [document setAnnotationEditMode:YES];
    open(a, second); popover.textView.string = @"Lost too";
    [popover noteOutsideClick];
    [document annotationPartWillCollapse:second];
    RunLoop();
    Check([a.contents isEqual:@"Clicked away"], @"ending the split from a click discards the second part's text");
    open(a, first); popover.textView.string = @"Lost again";
    [popover noteOutsideClick];
    [document setAnnotationEditMode:NO];
    RunLoop();
    Check([a.contents isEqual:@"Clicked away"], @"leaving edit mode from a click discards");
    [document setAnnotationEditMode:YES];

    // Saving commits first.
    open(a, first); popover.textView.string = @"Saved";
    [popover noteOutsideClick];
    [document annotationsWillBeSaved];
    Check(!popover.shown && [a.contents isEqual:@"Saved"], @"saving commits the text first");
    RunLoop();

    // Closing a window with the text being edited: the guard rails save first (the text goes in),
    // then the toolbar is taken off. The saved PDF holds the text.
    PDFAnnotation *closing = AddText(page, @"Before closing");
    open(closing, first); popover.textView.string = @"Pending saved text"; popover.alignmentControl.selectedSegment = 2;
    [document annotationsWillBeSaved];
    [document annotationWindowWillClose:nil];
    NSURL *saved = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString]];
    saved = [saved URLByAppendingPathExtension:@"pdf"];
    Check([first.document writeToURL:saved], @"the annotated PDF is written");
    PDFDocument *reread = [[PDFDocument alloc] initWithURL:saved];
    BOOL found = NO;
    for (PDFAnnotation *x in [reread pageAtIndex:1].annotations)
        if ([TSAnnotationTextPopover canEditAnnotation:x] && [x.contents isEqual:@"Pending saved text"] && x.alignment == NSTextAlignmentRight) found = YES;
    Check(found, @"closing after saving keeps the text being edited in the saved PDF");
    [NSFileManager.defaultManager removeItemAtURL:saved error:nil];
    [document showAnnotationBar]; [document setAnnotationEditMode:YES];

    // The binding: a removed annotation, a replaced PDF.
    open(a, first); popover.textView.string = @"Removed";
    [document annotationWillBeRemoved:a];
    Check(!popover.shown && [a.contents isEqual:@"Saved"], @"removing the annotation discards");
    open(a, first); popover.textView.string = @"Gone";
    [page removeAnnotation:a];
    [popover finishWithReason:TSAnnotationTextFinishCommit];
    Check([a.contents isEqual:@"Saved"], @"an annotation no longer on its page is not written");
    a = AddText(page, @"Fresh");
    open(a, first); popover.textView.string = @"Replaced";
    first.document = MakeDocument();
    [document annotationViewDocumentChanged:[NSNotification notificationWithName:PDFViewDocumentChangedNotification object:first]];
    Check(!popover.shown && [a.contents isEqual:@"Fresh"], @"a new PDF in the part discards");
    second.document = first.document;
    PDFAnnotation *b = AddText([first.document pageAtIndex:0], @"B");
    open(b, first); popover.textView.string = @"B2";
    first.document = MakeDocument();
    [popover finishWithReason:TSAnnotationTextFinishCommit];
    Check([b.contents isEqual:@"B"], @"a replaced PDF is never written into");
    // Nothing changed: nothing written.
    first.document = b.page.document;
    open(b, first);
    NSString *before = b.contents;
    [popover finishWithReason:TSAnnotationTextFinishCommit];
    Check(b.contents == before, @"an unchanged popover writes nothing");
    [preview close];
}

static void TestSharedPanels(void) {
    TSDocument *document = [TSDocument new];
    MyPDFKitView *first = [[MyPDFKitView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    first.document = MakeDocument();
    document.myPDFKitView = first;
    TSPreviewWindow *preview = [[TSPreviewWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 500)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    preview.releasedWhenClosed = NO; preview.toolbar = [[NSToolbar alloc] initWithIdentifier:@"p"];
    NSTextView *source = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 300, 400, 100)];
    [preview.contentView addSubview:first]; [preview.contentView addSubview:source];
    document.pdfKitWindow = preview;
    [document setAnnotationEditMode:YES];
    TSAnnotationBar *bar = document.annotationBar;
    NSWindow *other = MakeWindow(NSMakeRect(0, 0, 300, 300));
    KeyWindow = preview;

    [bar.colorButton performClick:nil];
    Check(bar.ownsColorPanel && [first.commands containsObject:@"showColorPanel:"], @"the color button opens the color panel for this document");
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:[NSColorPanel sharedColorPanel]];
    Check(bar.ownsColorPanel, @"the color panel itself becoming key keeps it with the bar");
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidBecomeKeyNotification object:other];
    Check(!bar.ownsColorPanel, @"another window becoming key moves the color panel to it");
    [bar.colorButton performClick:nil]; [bar.fontButton performClick:nil];
    Check(bar.ownsColorPanel && bar.ownsFontPanel, @"both panels opened from the bar");
    [preview makeFirstResponder:source];
    Check(!bar.ownsColorPanel && !bar.ownsFontPanel, @"the source taking the focus moves the panels to it");
    [preview makeFirstResponder:first];
    [bar.fontButton performClick:nil];
    Check(bar.ownsFontPanel && !bar.ownsColorPanel, @"color and font are kept apart");
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:[NSFontPanel sharedFontPanel]];
    Check(!bar.ownsFontPanel, @"a closed font panel is no longer the bar's");
    // Closing: only panels still serving the document.
    [bar.colorButton performClick:nil];
    KeyWindow = other;
    [bar closeSharedPanelsIfOwned];
    Check(!bar.ownsColorPanel, @"closing forgets the panels");
    [preview close]; [other close];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        OriginalLocalized = method_setImplementation(class_getInstanceMethod(NSBundle.class, @selector(localizedStringForKey:value:table:)), (IMP)TSTestLocalized);
        method_setImplementation(class_getInstanceMethod(NSApplication.class, @selector(keyWindow)), (IMP)TSTestKeyWindow);
        NSString *interfaces = @(argv[1]);
        NSString *images = argc > 2 && strlen(argv[2]) ? @(argv[2]) : nil;
        BOOL widths = argc > 3 && !strcmp(argv[3], "widths");
        for (NSString *lang in @[@"en", @"de", @"es", @"fr", @"it", @"ja", @"ko", @"nl", @"pt", @"pt-PT", @"ro", @"zh_CN"])
            TestBar(lang, [interfaces stringByAppendingFormat:@"/%@.lproj/Localizable.strings", lang], images, widths);
        Strings = [NSDictionary dictionaryWithContentsOfFile:[interfaces stringByAppendingString:@"/en.lproj/Localizable.strings"]];
        TestEditModeAndTargets();
        TestPopover();
        TestSharedPanels();
        if (failures == 0) printf("PASS: annotation toolbar (12 languages, edit mode, targets, windows, text popover, shared panels)\n");
        return failures ? 1 : 0;
    }
}
'''

with tempfile.TemporaryDirectory(prefix='texshop-annotation-toolbar-') as tmp:
    tmp = Path(tmp)
    for n, t in text.items():
        (tmp / n).write_text(t, encoding='utf-8')
    (tmp / 'TSDocument.h').write_text(stub_document, encoding='utf-8')
    (tmp / 'MyPDFKitView.h').write_text(stub_view, encoding='utf-8')
    (tmp / 'probe.m').write_text(program, encoding='utf-8')
    sources = [tmp / n for n in ('probe.m', 'TSAnnotationBar.m', 'TSAnnotationTextPopover.m', 'TSDocument-AnnotationBar.m', 'TSDocumentWindowGlass.m')]
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-mmacosx-version-min=14.0', '-framework', 'Cocoa', '-framework', 'Quartz',
                    '-I', str(tmp), '-I', str(root / 'Tests'), *map(str, sources), '-o', str(tmp / 'probe')], check=True)
    if args.images:
        args.images.mkdir(parents=True, exist_ok=True)
    if order_problems:
        print('\n'.join('FAIL: ' + p for p in order_problems))
    result = subprocess.run([str(tmp / 'probe'), str(root / 'Resources/Interfaces'), str(args.images or ''), 'widths' if args.widths else ''],
                            capture_output=True, text=True, timeout=300)
    print(result.stdout, end='')
    if result.returncode and not args.mutation:
        print(result.stderr[-3000:], end='')
    failed = result.returncode != 0 or bool(order_problems)
    if args.mutation:
        if not failed:
            sys.exit(f'FAIL: mutation {args.mutation} was not detected')
        print(f'PASS: detected mutation {args.mutation}')
    elif failed:
        sys.exit(1)
