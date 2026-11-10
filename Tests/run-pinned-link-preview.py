#!/usr/bin/env python3
"""Exercise production link-popup event handling without showing windows or saving settings."""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['move-dismisses', 'stale-timer', 'other-window', 'cleanup-state', 'ordinary-escape', 'modified-escape', 'click-cleanup', 'initialize-cleanup',
                                           'unpinned-interactive', 'pinned-transparent', 'scroll-chains', 'scroll-moves-frame', 'option-not-forwarded', 'kill-leaves-view', 'cursor-overridden', 'resize-scales',
                                           'click-kills-pin', 'cleanup-in-click-kills-pin', 'cursor-not-restored', 'hand-selects', 'no-selection', 'move-confined', 'copy-ignores-popup', 'click-keeps-selection',
                                           'tool-change-kills-pin', 'flag-not-restored', 'click-keeps-focus',
                                           'no-page-label', 'label-unscaled', 'tooltip-kept', 'tooltip-always-hidden',
                                           'tooltip-trusts-data', 'label-from-index'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
def method(signature):
    start = source.rindex(signature)
    body = source[start:source.index('\n}', start) + 2]
    if args.mutation == 'click-cleanup' and signature == '- (void) mouseDown:':
        body = body.replace('if (self.handlingLink && !self.globalLongTerm) [self doKillPopup];', '')
    if args.mutation == 'click-kills-pin' and signature == '- (void) mouseDown:':
        body = body.replace('if (self.handlingLink && !self.globalLongTerm) [self doKillPopup];', 'if (self.handlingLink) [self doKillPopup];')
    if args.mutation == 'initialize-cleanup' and signature == '- (void) initializeDisplay':
        body = body.replace('if (self.handlingLink) [self doKillPopup];', '')
    return body
methods = '\n'.join(method(signature) for signature in (
    '- (void) increaseTimerNumber', '- (void) changeLinkPopups', '- (void) mouseMoved:',
    '- (void)handleLink:', '- (NSEvent *)handleLinkPreviewEvent:',
    '- (void)observeLinkPreviewEvents', '- (void)linkPreviewWindowWillClose:',
    '- (void)viewWillMoveToWindow:', '- (void)doKillPopup', '- (void)killPopup:',
    '- (void)setDocument:(PDFDocument *)document', '- (void)cleanupMarquee:',
    '- (void) mouseDown:', '- (void) mouseDownKeepingPinnedLinkPreview:', '- (void) initializeDisplay',
    '- (NSCursor *) cursorForToolWithEvent:', '- (void) copy:', '- (BOOL) validateMenuItem:',
    '- (void) keepingPinnedLinkPreview:', '- (void) changeMouseMode:',
    '+ (void)initialize', '- (BOOL)showsLinkPreviewForAnnotation:'))
if args.mutation == 'move-dismisses':
    methods = methods.replace('!self.skipLinks && !self.globalLongTerm', '!self.skipLinks')
elif args.mutation == 'stale-timer':
    methods = methods.replace('aTimerNumber != self.timerNumber || ', '')
elif args.mutation == 'other-window':
    methods = methods.replace('event.window != self.window || ', '')
elif args.mutation == 'cleanup-state':
    methods = methods.replace('if (self.handlingLink && !(self.globalLongTerm && keepsPinnedLinkPreview)) { [self doKillPopup]; return; }', '')
elif args.mutation == 'ordinary-escape':
    methods = methods.replace('self.globalLongTerm && event.type == NSEventTypeKeyDown', 'event.type == NSEventTypeKeyDown')
elif args.mutation == 'option-not-forwarded':
    methods = methods.replace('        linkPreview.pinned = YES;\n', '')
elif args.mutation == 'kill-leaves-view':
    methods = methods.replace('    [linkPreview removeFromSuperview];\n    linkPreview = nil;\n', '    linkPreview = nil;\n')
elif args.mutation == 'cursor-overridden':
    methods = methods.replace('        [previewCursor set];\n        showsLinkPreviewCursor = YES;\n        return;', '        [previewCursor set];\n        showsLinkPreviewCursor = YES;')
elif args.mutation == 'cleanup-in-click-kills-pin':
    methods = methods.replace('if (self.handlingLink && !(self.globalLongTerm && keepsPinnedLinkPreview))', 'if (self.handlingLink)')
elif args.mutation == 'tool-change-kills-pin':
    methods = methods.replace('[self keepingPinnedLinkPreview:^{ [self cleanupMarquee: YES]; }];', '[self cleanupMarquee: YES];')
elif args.mutation == 'flag-not-restored':
    methods = methods.replace('    @finally {\n        keepsPinnedLinkPreview = previous;\n    }', '    @finally {\n    }')
elif args.mutation == 'cursor-not-restored':
    methods = methods.replace('        [[self cursorForToolWithEvent: theEvent] set];\n', '')
elif args.mutation == 'label-from-index':
    methods = methods.replace('if (linkedPage.label.length)', 'if ((linkedPage = [linkedPage.document pageAtIndex:[linkedPage.document indexForPage:linkedPage]]).label.length)').replace(
        '@"Page label in the corner of a link popup; %@ is the page label given in the PDF"), linkedPage.label]',
        '@"Page label in the corner of a link popup; %@ is the page label given in the PDF"), @([linkedPage.document indexForPage:linkedPage] + 1).stringValue]')
elif args.mutation == 'tooltip-always-hidden':
    methods = methods.replace('return !self.skipLinks && mouseMode != NEW_MOUSE_MODE_SELECT_PDF &&', 'return')
elif args.mutation == 'copy-ignores-popup':
    methods = methods.replace('\tif (previewText.length) {', '\tif (NO) {')
elif args.mutation == 'modified-escape':
    methods = methods.replace('&& !(event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl\n                                    | NSEventModifierFlagOption | NSEventModifierFlagShift))', '')
preview_source = (root / 'Sources/Preview/TSLinkPreviewView.m').read_text()
preview_mutations = {
    'unpinned-interactive': ('return self.pinned ? [super hitTest:point] : nil;', 'return [super hitTest:point];'),
    'pinned-transparent': ('return self.pinned ? [super hitTest:point] : nil;', 'return nil;'),
    'scroll-moves-frame': ('    [self setNeedsDisplay:YES];\n}\n\n@end', '    self.frame = NSOffsetRect(self.frame, 0.1, 0);\n    [self setNeedsDisplay:YES];\n}\n\n@end'),
    'scroll-chains': ('    [self setNeedsDisplay:YES];\n}\n\n@end', '    [self setNeedsDisplay:YES];\n    [super scrollWheel:event];\n}\n\n@end'),
    'hand-selects': ('return _page && !(self.usesHandTool && self.usesHandTool());', 'return _page != nil;'),
    'no-selection': ('} else if ([self selectsText] && [self isTextAtPagePoint:pagePoint]) {', '} else if (NO) {'),
    'move-confined': ('frame = TSLinkPreviewMove(_startFrame, delta, [self availableRect], kept, flipped);',
                      'frame = TSLinkPreviewMove(_startFrame, delta, [self availableRect], _startFrame.size, flipped);'),
    'click-keeps-selection': ('NSEqualRects(self.frame, _startFrame)) self.selection = nil;', 'NO) self.selection = nil;'),
    'click-keeps-focus': ('            if (self.window.firstResponder != owner) [self.window makeFirstResponder:owner];\n', ''),
    'no-page-label': ('    if (!self.pageLabel.length) return;\n', '    return;\n'),
    'label-unscaled': ('[NSFont boldSystemFontOfSize:TSLinkPreviewLabelFontSize * unit]', '[NSFont boldSystemFontOfSize:TSLinkPreviewLabelFontSize]'),
    'tooltip-kept': ('if (annotation && (__bridge void *)annotation == data && [pdfView showsLinkPreviewForAnnotation:annotation])', 'if (NO)'),
    'tooltip-trusts-data': ('if (annotation && (__bridge void *)annotation == data && [pdfView showsLinkPreviewForAnnotation:annotation])',
                            'if (annotation && [pdfView showsLinkPreviewForAnnotation:annotation])'),
    'resize-scales': ('                            [self availableRect], _pageSize, flipped, &frame, &source);',
                      '                            [self availableRect], _pageSize, flipped, &frame, &source);\n        source = _startSource;'),
}
if args.mutation in preview_mutations:
    old, new = preview_mutations[args.mutation]
    assert preview_source.count(old) == 1, args.mutation
    preview_source = preview_source.replace(old, new)
program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"
#import "TSLinkPreviewGeometry.h"
#import "OverView.h"
#import "TSLinkPreviewView.h"
#define SUD NSUserDefaults.standardUserDefaults
#define FlashFixKey @"flash"
#define FlashDelayKey @"delay"
#define LinkPopupsKey @"links"
#define ShowSyncMarksKey @"sync"
#define PdfPageStyleKey @"pageStyle"
#define PdfFirstPageStyleKey @"firstPage"
#define PdfKitFitSizeKey @"fit"
#define NEW_PDF_FIT_TO_WIDTH 2
#define NEW_PDF_FIT_TO_HEIGHT 3
#define PDF_FIT_TO_WINDOW 4
// The values of Sources/App/globals.h, which mouseMoved: also uses as numbers.
#define NEW_MOUSE_MODE_SCROLL 1
#define NEW_MOUSE_MODE_SELECT_TEXT 2
#define NEW_MOUSE_MODE_SELECT_PDF 5
#define NEW_MOUSE_MODE_MAG_GLASS 3
#define NEW_MOUSE_MODE_MAG_GLASS_L 4
#define PdfCopyTypeKey @"copyType"
#define IMAGE_TYPE_PDF 3
#define IMAGE_TYPE_EPS 4
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static NSEventModifierFlags flags;
static NSEventModifierFlags currentFlags(id self, SEL sel) { return flags; }
static NSPoint currentMouse(id self, SEL sel) { return NSZeroPoint; }
static NSMutableArray *handlers;
static id addMonitor(id self, SEL sel, NSEventMask mask, id handler) {
    // Text views add monitors of their own; only the popup's is recorded.
    if (mask != (NSEventMaskKeyDown | NSEventMaskFlagsChanged)) return [NSObject new];
    id block = [handler copy]; [handlers addObject:block]; return block;
}
static void removeMonitor(id self, SEL sel, id monitor) { [handlers removeObjectIdenticalTo:monitor]; }
// Whether a click also cleans up the marquee on its way, as selecting text or the magnifying glass do.
static BOOL cleanupInClick;
// Makes the click fail on its way, as an exception would.
static BOOL throwInClick;
// Copy writes to a private pasteboard, never the user's clipboard.
static NSPasteboard *testPasteboard;
static NSPasteboard *generalPasteboard(id self, SEL sel) { return testPasteboard; }
@interface TestDocument : NSObject
@property BOOL previewDisplaysAsBook, previewDisplaysRTL, pdfSinglePage;
@property NSInteger stringWindowAlignment;
- (void)updatePreviewLayoutControls;
- (BOOL)validatePreviewLayoutItem:(NSMenuItem *)item;
- (NSMenu *)mousemodeMenu;
- (NSMatrix *)mousemodeMatrix;
@end
@implementation TestDocument
- (void)updatePreviewLayoutControls {}
- (BOOL)validatePreviewLayoutItem:(NSMenuItem *)item { return YES; }
- (NSMenu *)mousemodeMenu { return nil; }
- (NSMatrix *)mousemodeMatrix { return nil; }
@end
@interface MyPDFKitView : PDFView {
    NSInteger mouseMode, currentMouseMode;
    BOOL _editMode,protectFind,downOverLink,showSync,fromTypesetOrQuit,firstTimeSave,drawMark;
    NSInteger pageStyle,firstPageStyle,resizeOption;
    NSRect oldVisibleRect,rect,selectedRect;
    BOOL _pdfViewReady;
    id linkPreviewEventMonitor;
    TSLinkPreviewView *linkPreview;
    BOOL showsLinkPreviewCursor;
    BOOL keepsPinnedLinkPreview;
}
@property BOOL skipLinks, globalLongTerm, inLink;
@property TestDocument *myDocument;
@property NSInteger handlingLink, timerNumber;
@property OverView *overView;
@property BOOL firstTime,oldUsed,doScroll,PDFFlashFix;
@property NSInteger stringAlignment;
@property NSString *oneOffSearchString;
@property NSWindow *myPDFWindow;
@property NSTimeInterval PDFFlashDelay;
@property NSView *myHideView1,*myHideView2;
@property NSTimer *selRectTimer;
- (void)initializeDisplay;
- (void)cleanupMarquee:(BOOL)terminate;
- (void)setupPageStyle;
- (void)setupMagnificationStyle;
- (void)doKillPopup;
- (NSEvent *)handleLinkPreviewEvent:(NSEvent *)event;
- (void)observeLinkPreviewEvents;
- (void)handleLink:(NSTimer *)timer;
- (void)killPopup:(NSTimer *)timer;
- (TSLinkPreviewView *)preview;
- (void)setTestMouseMode:(NSInteger)mode;
@end
@implementation MyPDFKitView
- (TSLinkPreviewView *)preview { return linkPreview; }
- (void)setupPageStyle {}
- (void)setupMagnificationStyle {}
- (void)updateBackground:(NSRect)rect {}
- (void)setDrawMark:(BOOL)value { drawMark=value; }
- (void)setTestMouseMode:(NSInteger)mode { mouseMode = currentMouseMode = mode; }
- (NSData *)imageDataFromSelectionType:(NSInteger)type { return nil; }
// Stop the rest of mouseDown after its production popup-cleanup entry path. Clicks clean up
// the marquee on their way (selecting text, the magnifying glass), so do that here too.
- (BOOL)annotationMouseDown:(NSEvent *)event {
    if (cleanupInClick) [self cleanupMarquee:YES];
    if (throwInClick) [NSException raise:@"TestException" format:@"click fails"];
    return YES;
}
- (void)doSync:(NSPoint)point {}
- (void)doMagnifyingGlass:(NSEvent *)event level:(NSInteger)level {}
- (void)scrollByDragging:(NSEvent *)event {}
- (void)startDragging:(NSEvent *)event {}
- (void)selectARectForMavericks:(NSEvent *)event {}
- (void)updateDarkModeInversion {}
- (void)scaleChanged:(id)sender {}
- (PDFAreaOfInterest)areaOfInterestForMouse:(NSEvent *)event { return self.inLink ? kPDFLinkArea : kPDFPageArea; }
METHODS
@end
static NSEvent *event(NSWindow *window, NSEventType type, NSEventModifierFlags modifiers, NSString *text, NSPoint point) {
    if (type == NSEventTypeMouseMoved)
        return [NSEvent mouseEventWithType:type location:point modifierFlags:modifiers timestamp:0 windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:0 pressure:0];
    return [NSEvent keyEventWithType:type location:point modifierFlags:modifiers timestamp:0 windowNumber:window.windowNumber context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:0];
}
static NSTimer *timeout(MyPDFKitView *view) {
    return [NSTimer timerWithTimeInterval:4 target:view selector:@selector(killPopup:) userInfo:@[@(view.timerNumber)] repeats:NO];
}
static NSTimer *showTimer(MyPDFKitView *view) {
    NSPoint location = [view convertPoint:NSMakePoint(30,730) fromPage:[view.document pageAtIndex:0]];
    location = [view convertPoint:location toView:nil];
    NSEvent *move = event(view.window, NSEventTypeMouseMoved, flags, @"", location);
    return [NSTimer timerWithTimeInterval:.2 target:view selector:@selector(handleLink:)
        userInfo:@[@(view.timerNumber), [NSValue valueWithPoint:NSZeroPoint], move] repeats:NO];
}
static void show(MyPDFKitView *view, NSEventModifierFlags modifiers) {
    flags = modifiers;
    view.handlingLink = 1;
    [view handleLink:showTimer(view)];
    check(view.handlingLink == 2 && view.preview.superview == view.documentView, @"real link produces popup");
    check(view.preview.pinned == ((modifiers & NSEventModifierFlagOption) != 0), @"popup is pinned only with Option");
}

static NSEvent *clicks(NSWindow *window, NSEventType type, NSPoint point, NSInteger count) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0 windowNumber:window.windowNumber
        context:nil eventNumber:0 clickCount:count pressure:1];
}
static NSEvent *mouse(NSWindow *window, NSEventType type, NSPoint point) { return clicks(window, type, point, 1); }
static NSEvent *scroll(int32_t dy, int32_t dx) {
    CGEventRef cg = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, dy, dx);
    NSEvent *result = [NSEvent eventWithCGEvent:cg]; CFRelease(cg); return result;
}
static BOOL approx(CGFloat a, CGFloat b) { return fabs(a-b) < 0.01; }
// Window coordinates of a point inside the popup, `inset` screen points from its right edge.
static NSPoint windowPoint(TSLinkPreviewView *preview, CGFloat fromLeft, CGFloat fromBottom) {
    NSRect frame = [preview.superview convertRect:preview.frame toView:nil];
    return NSMakePoint(NSMinX(frame) + fromLeft, NSMinY(frame) + fromBottom);
}
static void testInteraction(MyPDFKitView *view, NSWindow *window) {
    NSView *root = window.contentView.superview;
    show(view, 0);
    TSLinkPreviewView *preview = view.preview;
    NSPoint center = windowPoint(preview, NSWidth([preview convertRect:preview.bounds toView:nil])/2,
                                 NSHeight([preview convertRect:preview.bounds toView:nil])/2);
    check([root hitTest:center] != preview, @"hovering popup leaves the mouse to the preview");
    check([preview cursorAtPoint:[view.documentView convertPoint:center fromView:nil]] == nil, @"hovering popup keeps the preview cursor");
    flags = NSEventModifierFlagOption;
    NSEvent *(^handler)(NSEvent *) = handlers.lastObject;
    handler(event(window,NSEventTypeFlagsChanged,NSEventModifierFlagOption,@"",NSZeroPoint));
    flags = 0;
    check(preview.pinned, @"Option while shown makes the popup interactive");
    check([root hitTest:center] == preview, @"pinned popup takes clicks inside it");
    NSRect outside = [view.documentView convertRect:view.documentView.visibleRect toView:nil];
    NSPoint far = NSMakePoint(NSMinX(outside) + 2, NSMinY(outside) + 2);
    check([root hitTest:far] != preview, @"clicks outside the pinned popup reach the preview");

    NSRect startFrame = preview.frame, startSource = preview.source;
    CGFloat scale = NSWidth(startFrame) / NSWidth(startSource);
    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, center)];
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, center)];
    check(view.preview == preview && preview.superview && view.handlingLink == 2 && handlers.count == 1,
          @"click inside pinned popup keeps it");
    check(NSEqualRects(preview.frame, startFrame) && NSEqualRects(preview.source, startSource), @"click without drag changes nothing");

    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, center)];
    check(NSCursor.currentCursor == NSCursor.closedHandCursor, @"dragging shows a closed hand");
    [preview mouseDragged:mouse(window, NSEventTypeLeftMouseDragged, NSMakePoint(center.x - 30, center.y - 20))];
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, NSMakePoint(center.x - 30, center.y - 20))];
    NSRect moved = [view.documentView convertRect:preview.frame toView:nil];
    NSRect before = [view.documentView convertRect:startFrame toView:nil];
    check(approx(NSMinX(moved), NSMinX(before) - 30) && approx(NSMinY(moved), NSMinY(before) - 20) &&
          approx(NSWidth(moved), NSWidth(before)) && NSEqualRects(preview.source, startSource),
          @"dragging the inside moves the popup with its contents");

    NSRect frame = preview.frame, source = preview.source;
    NSRect onScreen = [view.documentView convertRect:frame toView:nil];
    NSPoint edge = windowPoint(preview, NSWidth(onScreen) - 2, NSHeight(onScreen) / 2);
    NSPoint edgeInView = [view.documentView convertPoint:edge fromView:nil];
    check([preview cursorAtPoint:edgeInView] != NSCursor.openHandCursor && [preview cursorAtPoint:edgeInView] != nil,
          @"edge shows a resize cursor");
    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, edge)];
    [preview mouseDragged:mouse(window, NSEventTypeLeftMouseDragged, NSMakePoint(edge.x - 40, edge.y + 15))];
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, NSMakePoint(edge.x - 40, edge.y + 15))];
    NSRect resized = [view.documentView convertRect:preview.frame toView:nil];
    check(approx(NSWidth(resized), NSWidth(onScreen) - 40) && approx(NSMinX(resized), NSMinX(onScreen)) &&
          approx(NSHeight(resized), NSHeight(onScreen)), @"dragging the right edge resizes the popup");
    check(approx(NSWidth(preview.frame) / NSWidth(preview.source), scale) && approx(NSMinX(preview.source), NSMinX(source)),
          @"resizing keeps the text size and the left side of the page");

    NSRect clip = view.documentView.enclosingScrollView.contentView.bounds;
    source = preview.source; frame = preview.frame;
    CGFloat unit = NSWidth([view.documentView convertRect:NSMakeRect(0,0,1,1) fromView:nil]);
    [preview scrollWheel:scroll(12, -9)];
    check(approx(NSMinY(preview.source), NSMinY(source) + 12 * unit / scale) &&
          approx(NSMinX(preview.source), NSMinX(source) + 9 * unit / scale) &&
          approx(NSWidth(preview.source), NSWidth(source)),
          @"scrolling moves the page inside the popup");
    check(NSEqualRects(preview.frame, frame), @"scrolling leaves the popup in place");
    check(NSEqualRects(view.documentView.enclosingScrollView.contentView.bounds, clip),
          @"scrolling the popup leaves the preview where it is");
    for (int i = 0; i < 400; i++) [preview scrollWheel:scroll(-40, 0)];
    check(approx(NSMinY(preview.source), 0) && NSEqualRects(view.documentView.enclosingScrollView.contentView.bounds, clip),
          @"scrolling stops at the bottom of the page");
    check(NSEqualRects(preview.frame, frame), @"scrolling to the page edge leaves the popup in place");

    [NSCursor.arrowCursor set];
    [view mouseMoved:mouse(window, NSEventTypeMouseMoved, windowPoint(preview, 20, 15))];
    check(NSCursor.currentCursor == NSCursor.openHandCursor, @"pointer over pinned popup shows an open hand");

    check(handler(event(window,NSEventTypeKeyDown,0,@"\033",NSZeroPoint)) == nil, @"Escape closes a moved popup");
    check(!view.preview && !preview.superview && !handlers.count, @"closing removes the popup view");
}
// A page whose text starts at the link destination (20, 600).
static PDFDocument *textDocument(void) {
    NSMutableData *data = [NSMutableData data];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
    CGRect box = CGRectMake(0, 0, 600, 800);
    CGContextRef context = CGPDFContextCreate(consumer, &box, NULL);
    CGPDFContextBeginPage(context, NULL);
    NSDictionary *attributes = @{(id)kCTFontAttributeName: (__bridge id)CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL)};
    NSArray *lines = @[@"Lemma 2. Every bounded sequence of real numbers has a convergent subsequence.",
                       @"Proof. Choose a monotone subsequence and apply the monotone convergence theorem.",
                       @"This completes the proof of the lemma, which is used again in the next section."];
    for (NSUInteger i = 0; i < lines.count; i++) {
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)
            [[NSAttributedString alloc] initWithString:lines[i] attributes:attributes]);
        CGContextSetTextPosition(context, 20, 588 - 16 * i);
        CTLineDraw(line, context);
        CFRelease(line);
    }
    CGPDFContextEndPage(context);
    CGPDFContextClose(context);
    CGContextRelease(context);
    CGDataConsumerRelease(consumer);
    PDFDocument *doc = [[PDFDocument alloc] initWithData:data];
    PDFPage *page = [doc pageAtIndex:0];
    PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,720,100,25) forType:PDFAnnotationSubtypeLink withProperties:nil];
    link.destination = [[PDFDestination alloc] initWithPage:page atPoint:NSMakePoint(20,600)]; [page addAnnotation:link];
    return doc;
}
// Window points inside the popup where the cursor is `cursor`, away from the edges.
static NSPoint findPoint(MyPDFKitView *view, NSCursor *cursor) {
    TSLinkPreviewView *preview = view.preview;
    NSRect frame = [preview.superview convertRect:preview.frame toView:nil];
    for (CGFloat y = NSMaxY(frame) - 10; y > NSMinY(frame) + 10; y -= 2)
        for (CGFloat x = NSMinX(frame) + 10; x < NSMaxX(frame) - 10; x += 3) {
            NSPoint point = NSMakePoint(x, y);
            if ([preview cursorAtPoint:[view.documentView convertPoint:point fromView:nil]] == cursor) return point;
        }
    return NSMakePoint(NAN, NAN);
}
// Some system cursors are new objects on each call.
static BOOL sameCursor(NSCursor *a, NSCursor *b) {
    return a == b || (a && b && NSEqualPoints(a.hotSpot, b.hotSpot) &&
                      [a.image.TIFFRepresentation isEqualToData:b.image.TIFFRepresentation]);
}
static void drag(TSLinkPreviewView *preview, NSWindow *window, NSPoint from, NSPoint to) {
    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, from)];
    [preview mouseDragged:mouse(window, NSEventTypeLeftMouseDragged, to)];
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, to)];
}
static void testTools(MyPDFKitView *view, NSWindow *window, PDFDocument *doc) {
    view.document = doc; [view layoutDocumentView];
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    show(view, NSEventModifierFlagOption);
    flags = 0;
    TSLinkPreviewView *preview = view.preview;
    NSPoint text = findPoint(view, NSCursor.IBeamCursor), blank = findPoint(view, NSCursor.openHandCursor);
    check(!isnan(text.x), @"pointer over text in a pinned popup shows an I-beam");
    check(!isnan(blank.x), @"pointer away from text shows an open hand to move the popup");
    NSRect frame = preview.frame;
    drag(preview, window, text, NSMakePoint(text.x + 120, text.y));
    check(preview.selection.string.length > 3 && preview.selectionIsRecent && NSEqualRects(preview.frame, frame),
          @"dragging over text selects it and leaves the popup in place");
    NSString *selected = preview.selection.string;
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
    check([view validateMenuItem:copyItem], @"Copy is enabled for text selected in the popup");
    [testPasteboard clearContents];
    [view copy:nil];
    check([[testPasteboard stringForType:NSPasteboardTypeString] isEqualToString:selected], @"Copy copies the popup selection");
    // With the keyboard elsewhere, a click in the popup brings Copy to its preview.
    NSTextView *field = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 50, 20)];
    [window.contentView addSubview:field];
    field.string = @"sourceSentinel"; [field selectAll:nil];
    [window makeFirstResponder:field];
    [preview mouseDown:clicks(window, NSEventTypeLeftMouseDown, text, 2)];
    [preview mouseUp:clicks(window, NSEventTypeLeftMouseUp, text, 2)];
    check(window.firstResponder == view, @"clicking the popup makes its preview the active view");
    [testPasteboard clearContents];
    check([window.firstResponder tryToPerform:@selector(copy:) with:nil] &&
          [[testPasteboard stringForType:NSPasteboardTypeString] isEqualToString:preview.selection.string],
          @"Copy through the responder chain copies the popup selection");
    [field removeFromSuperview];
    [preview mouseDown:clicks(window, NSEventTypeLeftMouseDown, text, 1)];
    [preview mouseUp:clicks(window, NSEventTypeLeftMouseUp, text, 1)];
    drag(preview, window, text, NSMakePoint(text.x + 120, text.y));
    cleanupInClick = YES;
    [view mouseDown:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    cleanupInClick = NO;
    check(view.preview == preview && !preview.selectionIsRecent && preview.selection,
          @"clicking the preview keeps the popup and its highlight but not for Copy");
    [preview mouseDown:clicks(window, NSEventTypeLeftMouseDown, text, 2)];
    [preview mouseUp:clicks(window, NSEventTypeLeftMouseUp, text, 2)];
    check(preview.selection.string.length > 0 && preview.selection.string.length < 20 && preview.selectionIsRecent,
          @"double-clicking selects a word");
    [preview mouseDown:mouse(window, NSEventTypeLeftMouseDown, blank)];
    [preview mouseUp:mouse(window, NSEventTypeLeftMouseUp, blank)];
    check(!preview.selection && NSEqualRects(preview.frame, frame), @"a click away from text clears the selection");
    drag(preview, window, blank, NSMakePoint(blank.x + 7, blank.y - 5));
    NSRect moved = [view.documentView convertRect:preview.frame toView:nil];
    NSRect before = [view.documentView convertRect:frame toView:nil];
    check(approx(NSMinX(moved), NSMinX(before) + 7) && approx(NSMinY(moved), NSMinY(before) - 5),
          @"dragging away from text moves the popup");

    [view setTestMouseMode:NEW_MOUSE_MODE_MAG_GLASS];
    check(!isnan(findPoint(view, NSCursor.IBeamCursor).x), @"the magnifying glass acts as the pointer inside the popup");
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_PDF];
    check(!isnan(findPoint(view, NSCursor.IBeamCursor).x), @"the selection tool acts as the pointer inside the popup");

    [view setTestMouseMode:NEW_MOUSE_MODE_SCROLL];
    check(isnan(findPoint(view, NSCursor.IBeamCursor).x), @"with the hand tool the whole popup moves");
    text = findPoint(view, NSCursor.openHandCursor);
    frame = preview.frame;
    drag(preview, window, text, NSMakePoint(text.x + 5, text.y + 4));
    check(!preview.selection && !NSEqualRects(preview.frame, frame), @"hand tool moves over text instead of selecting");

    // Leaving the popup shows the tool's cursor, however fast the pointer moves.
    NSRect visible = [view.documentView convertRect:view.documentView.visibleRect toView:nil];
    NSPoint away = NSMakePoint(NSMinX(visible) + 3, NSMinY(visible) + 3);
    NSDictionary *expected = @{@(NEW_MOUSE_MODE_SCROLL): NSCursor.openHandCursor, @(NEW_MOUSE_MODE_MAG_GLASS): NSCursor.arrowCursor,
                               @(NEW_MOUSE_MODE_SELECT_PDF): NSCursor.crosshairCursor, @(NEW_MOUSE_MODE_SELECT_TEXT): NSCursor.arrowCursor};
    for (NSNumber *mode in expected) {
        [view setTestMouseMode:mode.integerValue];
        NSPoint edge = windowPoint(preview, 2, 20);
        [view mouseMoved:mouse(window, NSEventTypeMouseMoved, edge)];
        check(!sameCursor(NSCursor.currentCursor, expected[mode]), @"edge of the popup shows a resize cursor");
        [view mouseMoved:mouse(window, NSEventTypeMouseMoved, away)];
        check(sameCursor(NSCursor.currentCursor, expected[mode]), @"leaving the popup shows the tool's cursor");
    }

    // A pinned popup can be pushed almost out of the preview.
    [view setTestMouseMode:NEW_MOUSE_MODE_SCROLL];
    CGFloat unit = NSWidth([view.documentView convertRect:NSMakeRect(0,0,1,1) fromView:nil]);
    NSRect available = NSInsetRect(view.documentView.visibleRect, 5, 5);
    for (NSValue *direction in @[[NSValue valueWithSize:NSMakeSize(-5000,-5000)], [NSValue valueWithSize:NSMakeSize(5000,5000)]]) {
        NSPoint start = findPoint(view, NSCursor.openHandCursor);
        frame = preview.frame;
        drag(preview, window, start, NSMakePoint(start.x + direction.sizeValue.width, start.y + direction.sizeValue.height));
        NSRect shown = NSIntersectionRect(preview.frame, available);
        check(approx(NSWidth(shown), MAX(NSWidth(frame) * 0.05, 20 * unit)) &&
              approx(NSHeight(shown), MAX(NSHeight(frame) * 0.05, 20 * unit)) &&
              approx(NSWidth(preview.frame), NSWidth(frame)),
              @"moved popup keeps only a small part in view");
        drag(preview, window, findPoint(view, NSCursor.openHandCursor), findPoint(view, NSCursor.openHandCursor));
    }
    // Changing the tool keeps a pinned popup; the selection tool's marquee goes away.
    for (NSNumber *target in @[@(NEW_MOUSE_MODE_SELECT_TEXT), @(NEW_MOUSE_MODE_MAG_GLASS), @(NEW_MOUSE_MODE_SCROLL)]) {
        [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_PDF];
        OverView *marquee = [[OverView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [view.documentView addSubview:marquee]; view.overView = marquee;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""]; item.tag = target.integerValue;
        [view changeMouseMode:item];
        check(view.preview == preview && preview.superview && view.globalLongTerm && handlers.count == 1,
              @"changing the tool keeps a pinned popup");
        if (target.integerValue != NEW_MOUSE_MODE_SCROLL)
            check(!view.overView && !marquee.superview, @"changing the tool still removes the marquee");
        [marquee removeFromSuperview]; view.overView = nil;
    }
    // A click that fails on its way leaves later cleanups as they were.
    throwInClick = YES;
    @try { [view mouseDown:mouse(window, NSEventTypeLeftMouseDown, away)]; } @catch (NSException *exception) {}
    throwInClick = NO;
    check(view.preview == preview, @"a failed click keeps the pinned popup");
    [view cleanupMarquee:YES];
    check(!view.preview && !handlers.count, @"after a failed click, cleanup outside a click dismisses the popup");

    // Hovering shows popups with every tool but the selection tool.
    for (NSNumber *mode in @[@(NEW_MOUSE_MODE_SCROLL), @(NEW_MOUSE_MODE_SELECT_TEXT), @(NEW_MOUSE_MODE_MAG_GLASS), @(NEW_MOUSE_MODE_SELECT_PDF)]) {
        [view setTestMouseMode:mode.integerValue];
        view.inLink = YES; view.handlingLink = 0;
        [view mouseMoved:mouse(window, NSEventTypeMouseMoved, away)];
        check((view.handlingLink == 1) == (mode.integerValue != NEW_MOUSE_MODE_SELECT_PDF), @"hovering a link starts a popup unless the selection tool is chosen");
        view.inLink = NO; [view doKillPopup];
    }
    [view doKillPopup];
    [view setTestMouseMode:0];
}
// Fraction of the pixels in `rect` (view points, y up) that are the label's gray, not page white or text black.
static double grayShare(NSBitmapImageRep *rep, NSView *view, NSRect rect) {
    double scale = rep.pixelsWide / NSWidth(view.bounds); NSUInteger gray = 0, all = 0;
    for (NSInteger y = (NSInteger)(NSMinY(rect) * scale); y < (NSInteger)(NSMaxY(rect) * scale); y++)
        for (NSInteger x = (NSInteger)(NSMinX(rect) * scale); x < (NSInteger)(NSMaxX(rect) * scale); x++) {
            NSColor *c = [[rep colorAtX:x y:rep.pixelsHigh - 1 - y] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            CGFloat l = (c.redComponent + c.greenComponent + c.blueComponent) / 3;
            all++; if (l > 0.55 && l < 0.75 && fabs(c.redComponent - c.blueComponent) < 0.05) gray++;
        }
    return all ? (double)gray / all : 0;
}
static NSBitmapImageRep *render(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    return rep;
}
// Stands in front of PDFKit's tool tip method before the filter is installed, so that user
// data PDFKit would not pass reaches it intact instead of being read by the filter.
static struct { int notAnObject; } opaqueToolTipData = {77};
static NSString *(*pdfKitToolTip)(id, SEL, NSView *, NSToolTipTag, NSPoint, void *);
static NSString *fakeToolTip(id self, SEL sel, NSView *view, NSToolTipTag tag, NSPoint point, void *data) {
    if (data == &opaqueToolTipData) return opaqueToolTipData.notAnObject == 77 ? @"opaque" : @"changed";
    return pdfKitToolTip(self, sel, view, tag, point, data);
}
static void installFakeToolTip(void) {
    Method method = class_getInstanceMethod(NSClassFromString(@"PDFPageView"), @selector(view:stringForToolTip:point:userData:));
    check(method != NULL, @"PDFKit's page view has a tool tip method");
    pdfKitToolTip = (NSString *(*)(id, SEL, NSView *, NSToolTipTag, NSPoint, void *))method_setImplementation(method, (IMP)fakeToolTip);
}
static NSView *pageViewOf(PDFView *view) {
    NSMutableArray *views = [NSMutableArray arrayWithObject:view];
    while (views.count) {
        NSView *candidate = views.lastObject; [views removeLastObject];
        if ([NSStringFromClass(candidate.class) isEqualToString:@"PDFPageView"] && candidate.window) return candidate;
        [views addObjectsFromArray:candidate.subviews];
    }
    return nil;
}
// The tool tip PDFKit's page view gives for `annotation`, asked at its center as the tool tip manager would.
static NSString *toolTip(PDFView *view, PDFAnnotation *annotation, void *data) {
    NSView *pageView = pageViewOf(view);
    check(pageView != nil, @"PDFKit draws pages in page views");
    NSPoint center = [view convertPoint:NSMakePoint(NSMidX(annotation.bounds), NSMidY(annotation.bounds)) fromPage:annotation.page];
    return [(id<NSViewToolTipOwner>)pageView view:pageView stringForToolTip:0 point:[pageView convertPoint:center fromView:view] userData:data];
}
// Physical page 1 is labeled i and page 2 is 157, as in a book with front matter.
static PDFDocument *labeledDocument(void) {
    PDFDocument *doc = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:@(getenv("TS_LABELED_PDF"))]];
    check(doc.pageCount == 2 && [[doc pageAtIndex:0].label isEqualToString:@"i"] && [[doc pageAtIndex:1].label isEqualToString:@"157"],
          @"labeled test PDF");
    PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,720,100,25) forType:PDFAnnotationSubtypeLink withProperties:nil];
    link.destination = [[PDFDestination alloc] initWithPage:[doc pageAtIndex:1] atPoint:NSMakePoint(20,600)];
    [[doc pageAtIndex:0] addAnnotation:link];
    PDFAnnotation *web = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,650,100,25) forType:PDFAnnotationSubtypeLink withProperties:nil];
    web.URL = [NSURL URLWithString:@"https://example.com/"];
    [[doc pageAtIndex:0] addAnnotation:web];
    return doc;
}
static void testPageLabelAndToolTips(MyPDFKitView *view, NSWindow *window, PDFDocument *doc) {
    view.document = doc; view.autoScales = NO; view.scaleFactor = 2; [view layoutDocumentView];
    [view goToPage:[doc pageAtIndex:0]];
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_TEXT];
    show(view, 0);
    TSLinkPreviewView *preview = view.preview;
    check([preview.pageLabel isEqualToString:[@"Page " stringByAppendingString:[doc pageAtIndex:0].label]],
          @"popup names the target page by its label");
    check([[doc pageAtIndex:0].label isEqualToString:@"1"], @"a PDF without page labels numbers its pages");
    CGFloat unit = NSWidth([view.documentView convertRect:NSMakeRect(0,0,1,1) fromView:nil]);
    NSRect bounds = preview.bounds;
    NSBitmapImageRep *rep = render(preview);
    NSRect corner = NSMakeRect(NSMaxX(bounds) - 30 * unit, NSMinY(bounds) + 3 * unit, 26 * unit, 10 * unit);
    NSRect left = NSMakeRect(NSMinX(bounds) + 4 * unit, NSMinY(bounds) + 3 * unit, 26 * unit, 10 * unit);
    check(grayShare(rep, preview, corner) > 0.3 && grayShare(rep, preview, left) < 0.01,
          @"page label is drawn in the lower right corner");
    NSRect beyond = NSMakeRect(NSMaxX(bounds) - 90 * unit, NSMinY(bounds) + 3 * unit, 20 * unit, 10 * unit);
    check(grayShare(rep, preview, beyond) < 0.01, @"page label keeps its size on screen");
    if (getenv("TS_LABEL_PNG")) [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(getenv("TS_LABEL_PNG")) atomically:YES];
    [view doKillPopup];
    view.autoScales = YES; [view layoutDocumentView];

    // The popup names the linked page by its label, not by its position or the page with the link.
    PDFDocument *labeled = labeledDocument();
    view.document = labeled; [view layoutDocumentView]; [view goToPage:[labeled pageAtIndex:0]];
    show(view, 0);
    check([view.preview.pageLabel isEqualToString:@"Page 157"], @"popup shows the label of the linked page");
    [view doKillPopup];

    // PDFKit's "Go to page" tool tip gives way to the popup.
    [window.contentView display];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    PDFAnnotation *link = nil, *web = nil;
    for (PDFAnnotation *annotation in [labeled pageAtIndex:0].annotations) {
        if (annotation.destination) link = annotation;
        if (annotation.URL) web = annotation;
    }
    check(toolTip(view, link, (__bridge void *)link) == nil, @"internal link gets no PDFKit tool tip while popups are on");
    check([toolTip(view, web, (__bridge void *)web) length] > 0, @"a web link keeps its tool tip");
    check([toolTip(view, link, &opaqueToolTipData) isEqualToString:@"opaque"],
          @"user data that is not the link reaches PDFKit untouched");
    view.skipLinks = YES;
    check([toolTip(view, link, (__bridge void *)link) length] > 0, @"tool tip stays when link popups are off");
    view.skipLinks = NO;
    [view setTestMouseMode:NEW_MOUSE_MODE_SELECT_PDF];
    check([toolTip(view, link, (__bridge void *)link) length] > 0, @"tool tip stays with the selection tool, which shows no popups");
    [view setTestMouseMode:0];
    // Another PDFView showing the same document keeps PDFKit's tool tips.
    PDFView *plain = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 650, 850)];
    NSWindow *other = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,850) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    other.releasedWhenClosed = NO;
    [other.contentView addSubview:plain];
    plain.document = labeled; plain.autoScales = YES; [plain layoutDocumentView];
    [other.contentView display];
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    check([toolTip(plain, link, (__bridge void *)link) length] > 0, @"a PDFView without popups keeps the tool tip");
    [plain removeFromSuperview];
    view.autoScales = YES; [view layoutDocumentView];
    [view setTestMouseMode:0];
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    installFakeToolTip();
    handlers = [NSMutableArray new];
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(modifierFlags)), (IMP)currentFlags);
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(mouseLocation)), (IMP)currentMouse);
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(addLocalMonitorForEventsMatchingMask:handler:)), (IMP)addMonitor);
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(removeMonitor:)), (IMP)removeMonitor);
    testPasteboard = [NSPasteboard pasteboardWithUniqueName];
    TSReplaceTestMethod(class_getClassMethod(NSPasteboard.class,@selector(generalPasteboard)), (IMP)generalPasteboard);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,850) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSWindow *otherWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,650,850) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO; otherWindow.releasedWhenClosed = NO;
    MyPDFKitView *view = [[MyPDFKitView alloc] initWithFrame:window.contentView.bounds];
    [window.contentView addSubview:view];
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(600,800)];
    [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,600,800)); [image unlockFocus];
    PDFDocument *doc = [PDFDocument new];
    PDFPage *page = [[PDFPage alloc] initWithImage:image]; [doc insertPage:page atIndex:0];
    PDFAnnotation *link = [[PDFAnnotation alloc] initWithBounds:NSMakeRect(20,720,100,25) forType:PDFAnnotationSubtypeLink withProperties:nil];
    link.destination = [[PDFDestination alloc] initWithPage:page atPoint:NSMakePoint(20,600)]; [page addAnnotation:link];
    view.document = doc; view.autoScales = YES; [view layoutDocumentView];
    testInteraction(view, window);
    testTools(view, window, textDocument());
    testPageLabelAndToolTips(view, window, textDocument());
    view.document = doc; [view layoutDocumentView];
    show(view, 0);
    for (NSNumber *modifier in @[@0,@(NSEventModifierFlagOption)]) {
        NSEvent *escape = event(window,NSEventTypeKeyDown,modifier.unsignedIntegerValue,@"\033",NSZeroPoint);
        NSEvent *(^normalHandler)(NSEvent *) = handlers.lastObject;
        check(normalHandler(escape) == escape && view.preview, @"ordinary popup leaves Escape for editor and search");
    }
    flags = NSEventModifierFlagOption;
    check(!view.globalLongTerm, @"ordinary hover is not pinned");
    [view killPopup:timeout(view)];
    check(!view.preview && !view.handlingLink && !handlers.count, @"ordinary timeout removes overlay and monitor");
    show(view, 0);
    [view mouseMoved:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    check(!view.preview, @"ordinary move away dismisses");
    show(view, NSEventModifierFlagOption);
    flags = 0;
    check(view.globalLongTerm, @"Option at show pins");
    NSTimer *oldTimeout = timeout(view);
    for (NSNumber *inLink in @[@NO,@YES]) {
        view.inLink = inLink.boolValue;
        [view mouseMoved:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
        check(view.globalLongTerm && view.preview, @"pinned popup survives pointer on or off links");
    }
    [view killPopup:oldTimeout]; check(view.preview != nil, @"pin survives timeout and modifier release");
    NSEvent *(^handler)(NSEvent *) = handlers.lastObject;
    NSEvent *foreignEscape = event(otherWindow,NSEventTypeKeyDown,0,@"\033",NSZeroPoint);
    check(handler(foreignEscape) == foreignEscape && view.preview, @"other windows retain Escape");
    for (NSNumber *modifier in @[@(NSEventModifierFlagOption),@(NSEventModifierFlagCommand),@(NSEventModifierFlagControl),@(NSEventModifierFlagShift)]) {
        NSEvent *escape = event(window,NSEventTypeKeyDown,modifier.unsignedIntegerValue,@"\033",NSZeroPoint);
        check(handler(escape) == escape && view.preview, @"modified Escape is not consumed even when pinned");
    }
    NSEvent *ordinaryKey = event(window,NSEventTypeKeyDown,0,@"a",NSZeroPoint);
    check(handler(ordinaryKey) == ordinaryKey, @"ordinary keys pass through");
    check(handler(event(window,NSEventTypeKeyDown,0,@"\033",NSZeroPoint)) == nil, @"Escape consumed in owner window");
    check(!view.preview && !view.globalLongTerm && !handlers.count, @"Escape clears state and monitor");
    show(view, 0);
    [view killPopup:oldTimeout]; check(view.preview != nil, @"old timer cannot dismiss newer popup");
    handler = handlers.lastObject;
    NSEvent *option = event(window,NSEventTypeFlagsChanged,NSEventModifierFlagOption,@"",NSZeroPoint);
    check(handler(option) == option && view.globalLongTerm, @"Option after show pins without consuming modifier");
    handler(event(window,NSEventTypeFlagsChanged,0,@"",NSZeroPoint));
    check(view.globalLongTerm, @"releasing Option leaves pin");
    [view changeLinkPopups]; check(!view.preview && !handlers.count && view.skipLinks, @"disabling popups clears pin");
    [view changeLinkPopups];
    view.handlingLink = 1;
    NSTimer *pending = showTimer(view);
    [view doKillPopup]; [view handleLink:pending];
    check(!view.preview && !view.handlingLink, @"cancelled pending timer cannot recreate popup");
    show(view,NSEventModifierFlagOption);
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:otherWindow];
    check(view.preview != nil, @"other window closing has no effect");
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:window];
    check(!view.preview && !handlers.count, @"owner close cleans overlay and monitor");
    show(view,NSEventModifierFlagOption);
    view.document = doc;
    check(!view.preview && !handlers.count, @"PDF reload clears popup and monitor");
    show(view,NSEventModifierFlagOption);
    [view cleanupMarquee:YES];
    check(!view.preview && !view.handlingLink && !view.globalLongTerm && !handlers.count, @"cleanupMarquee clears popup state and monitor");
    flags=0; view.inLink=YES;
    [view mouseMoved:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    check(view.handlingLink == 1, @"hover resumes after cleanupMarquee");
    [view handleLink:showTimer(view)];
    check(view.preview != nil, @"next hover displays overlay after cleanupMarquee");
    [view doKillPopup];
    show(view,0);
    [view mouseDown:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    check(!view.preview && !view.handlingLink && !handlers.count, @"click clears an ordinary popup and monitor before annotation handling");
    show(view,NSEventModifierFlagOption);
    cleanupInClick = YES;
    [view mouseDown:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    cleanupInClick = NO;
    check(view.preview && view.preview.superview && view.globalLongTerm && handlers.count == 1,
          @"click outside keeps a pinned popup, also through the marquee cleanup");
    [view cleanupMarquee:YES];
    check(!view.preview && !handlers.count, @"cleanup outside a click still clears a pinned popup");
    show(view,NSEventModifierFlagOption);
    [SUD registerDefaults:@{LinkPopupsKey:@YES}];
    [view initializeDisplay];
    check(!view.preview && !view.handlingLink && !handlers.count, @"initializeDisplay clears popup and monitor");
    view.handlingLink=1; NSTimer *beforeInitialize=showTimer(view);
    [view initializeDisplay];
    view.handlingLink=1; [view handleLink:beforeInitialize];
    check(!view.preview, @"initializeDisplay invalidates pending timer");
    [view doKillPopup];
    show(view,NSEventModifierFlagOption);
    [view removeFromSuperview];
    check(!view.preview && !handlers.count, @"detaching view clears popup");
    [testPasteboard releaseGlobally];
    printf("PASS: %lu popup event/lifecycle checks\n", (unsigned long)checks);
    return 0;
}}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-pinned-link-') as directory:
    temporary = Path(directory)
    native = temporary / 'probe.m'
    native.write_text(program)
    preview_file = temporary / 'TSLinkPreviewView.m'
    preview_file.write_text(preview_source)
    exe = temporary / 'probe'
    subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',
                    *include_args(root),'-I'+str(root/'Tests'),str(native),
                    str(root/'Sources/Preview/OverView.m'),str(preview_file),'-o',str(exe)],check=True)
    home = temporary/'home'
    (home/'Library/Preferences').mkdir(parents=True)
    # Two empty pages with a PageLabels tree: i, then 157.
    objects = [b'<< /Type /Catalog /Pages 2 0 R /PageLabels << /Nums [0 << /S /r >> 1 << /S /D /St 157 >>] >> >>',
               b'<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << >> >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << >> >>']
    pdf = bytearray(b'%PDF-1.4\n'); offsets = []
    for number, body in enumerate(objects, 1):
        offsets.append(len(pdf)); pdf += b'%d 0 obj\n' % number + body + b'\nendobj\n'
    xref = len(pdf)
    pdf += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1) + b''.join(b'%010d 00000 n \n' % o for o in offsets)
    pdf += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objects) + 1, xref)
    (temporary / 'labeled.pdf').write_bytes(bytes(pdf))
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TS_LABELED_PDF=str(temporary / 'labeled.pdf'))
    result = subprocess.run([str(exe)], env=env, capture_output=True, text=True, timeout=30)
    print(result.stdout, end='')
    if args.mutation:
        expected = {'move-dismisses':('pinned popup survives', 'edge of the popup shows a resize cursor'), 'stale-timer':'old timer cannot dismiss',
                    'other-window':'other windows retain Escape', 'cleanup-state':('cleanupMarquee clears', 'after a failed click, cleanup outside a click dismisses'),
                    'ordinary-escape':'ordinary popup leaves Escape', 'modified-escape':'modified Escape is not consumed',
                    'click-cleanup':'click clears an ordinary popup', 'initialize-cleanup':'initializeDisplay clears popup',
                    'click-kills-pin':('click outside keeps a pinned popup', 'clicking the preview keeps the popup'),
                    'cleanup-in-click-kills-pin':('click outside keeps a pinned popup', 'clicking the preview keeps the popup'),
                    'cursor-not-restored':"leaving the popup shows the tool's cursor", 'hand-selects':'with the hand tool the whole popup moves',
                    'no-selection':'dragging over text selects it', 'move-confined':'moved popup keeps only a small part',
                    'copy-ignores-popup':'Copy copies the popup selection',
                    'tool-change-kills-pin':'changing the tool keeps a pinned popup', 'flag-not-restored':'after a failed click',
                    'click-keeps-focus':'clicking the popup makes its preview the active view', 'click-keeps-selection':'a click away from text clears',
                    'no-page-label':'page label is drawn in the lower right corner', 'label-unscaled':'page label keeps its size on screen',
                    'tooltip-kept':'internal link gets no PDFKit tool tip', 'tooltip-trusts-data':'user data that is not the link',
                    'label-from-index':'popup shows the label of the linked page', 'tooltip-always-hidden':'tool tip stays when link popups are off',
                    'unpinned-interactive':'hovering popup leaves the mouse', 'pinned-transparent':'pinned popup takes clicks',
                    'scroll-chains':'scrolling the popup leaves the preview', 'scroll-moves-frame':'scrolling leaves the popup in place', 'option-not-forwarded':'Option while shown makes',
                    'kill-leaves-view':'closing removes the popup view', 'cursor-overridden':'shows an open hand',
                    'resize-scales':'resizing keeps the text size'}[args.mutation]
        if isinstance(expected, str): expected = (expected,)
        assert result.returncode == 1 and any(message in result.stderr for message in expected), result.stderr
        print('PASS: detected mutation ' + args.mutation)
    else:
        if result.returncode: print(result.stderr)
        result.check_returncode()
