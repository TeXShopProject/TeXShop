#!/usr/bin/env python3
"""Exercise production link-popup event handling without showing windows or saving settings."""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['move-dismisses', 'stale-timer', 'other-window', 'cleanup-state', 'ordinary-escape', 'modified-escape', 'click-cleanup', 'initialize-cleanup'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/MyPDFKitView.m').read_text(encoding='latin1')
def method(signature):
    start = source.rindex(signature)
    body = source[start:source.index('\n}', start) + 2]
    if args.mutation == 'click-cleanup' and signature == '- (void) mouseDown:':
        body = body.replace('if (self.handlingLink) [self doKillPopup];', '')
    if args.mutation == 'initialize-cleanup' and signature == '- (void) initializeDisplay':
        body = body.replace('if (self.handlingLink) [self doKillPopup];', '')
    return body
methods = '\n'.join(method(signature) for signature in (
    '- (void) increaseTimerNumber', '- (void) changeLinkPopups', '- (void) mouseMoved:',
    '- (void)handleLink:', '- (NSEvent *)handleLinkPreviewEvent:',
    '- (void)observeLinkPreviewEvents', '- (void)linkPreviewWindowWillClose:',
    '- (void)viewWillMoveToWindow:', '- (void)doKillPopup', '- (void)killPopup:',
    '- (void)setDocument:(PDFDocument *)document', '- (void)cleanupMarquee:',
    '- (void) mouseDown:', '- (void) initializeDisplay'))
if args.mutation == 'move-dismisses':
    methods = methods.replace('!self.skipLinks && !self.globalLongTerm', '!self.skipLinks')
elif args.mutation == 'stale-timer':
    methods = methods.replace('aTimerNumber != self.timerNumber || ', '')
elif args.mutation == 'other-window':
    methods = methods.replace('event.window != self.window || ', '')
elif args.mutation == 'cleanup-state':
    methods = methods.replace('if (self.handlingLink) { [self doKillPopup]; return; }', '')
elif args.mutation == 'ordinary-escape':
    methods = methods.replace('self.globalLongTerm && event.type == NSEventTypeKeyDown', 'event.type == NSEventTypeKeyDown')
elif args.mutation == 'modified-escape':
    methods = methods.replace('&& !(event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl\n                                    | NSEventModifierFlagOption | NSEventModifierFlagShift))', '')
program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TestAppKitIsolation.h"
#import "TSLinkPreviewGeometry.h"
#import "OverView.h"
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
#define NEW_MOUSE_MODE_SELECT_TEXT 5
#define NEW_MOUSE_MODE_SCROLL 1
#define NEW_MOUSE_MODE_SELECT_PDF 2
#define NEW_MOUSE_MODE_MAG_GLASS 3
#define NEW_MOUSE_MODE_MAG_GLASS_L 4
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
    check(mask == (NSEventMaskKeyDown | NSEventMaskFlagsChanged), @"monitor mask");
    id block = [handler copy]; [handlers addObject:block]; return block;
}
static void removeMonitor(id self, SEL sel, id monitor) { [handlers removeObjectIdenticalTo:monitor]; }
@interface TestDocument : NSObject
@property BOOL previewDisplaysAsBook, previewDisplaysRTL, pdfSinglePage;
@property NSInteger stringWindowAlignment;
- (void)updatePreviewLayoutControls;
@end
@implementation TestDocument
- (void)updatePreviewLayoutControls {}
@end
@interface MyPDFKitView : PDFView {
    NSInteger mouseMode, currentMouseMode;
    BOOL _editMode,protectFind,downOverLink,showSync,fromTypesetOrQuit,firstTimeSave,drawMark;
    NSInteger pageStyle,firstPageStyle,resizeOption;
    NSRect oldVisibleRect,rect,selectedRect;
    BOOL _pdfViewReady;
    id linkPreviewEventMonitor;
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
@end
@implementation MyPDFKitView
- (void)setupPageStyle {}
- (void)setupMagnificationStyle {}
- (void)updateBackground:(NSRect)rect {}
- (void)setDrawMark:(BOOL)value { drawMark=value; }
// Stop the rest of mouseDown after its production popup-cleanup entry path.
- (BOOL)annotationMouseDown:(NSEvent *)event { return YES; }
- (void)doSync:(NSPoint)point {}
- (void)doMagnifyingGlass:(NSEvent *)event level:(NSInteger)level {}
- (void)scrollByDragging:(NSEvent *)event {}
- (void)startDragging:(NSEvent *)event {}
- (void)selectARectForMavericks:(NSEvent *)event {}
- (void)updateDarkModeInversion {}
- (void)scaleChanged:(id)sender {}
- (PDFAreaOfInterest)areaOfInterestForMouse:(NSEvent *)event { return self.inLink ? kPDFLinkArea : 0; }
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
    check(view.handlingLink == 2 && view.overView.superview == view.documentView, @"real link produces overlay");
}
int main(void) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    handlers = [NSMutableArray new];
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(modifierFlags)), (IMP)currentFlags);
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(mouseLocation)), (IMP)currentMouse);
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(addLocalMonitorForEventsMatchingMask:handler:)), (IMP)addMonitor);
    TSReplaceTestMethod(class_getClassMethod(NSEvent.class,@selector(removeMonitor:)), (IMP)removeMonitor);
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
    show(view, 0);
    for (NSNumber *modifier in @[@0,@(NSEventModifierFlagOption)]) {
        NSEvent *escape = event(window,NSEventTypeKeyDown,modifier.unsignedIntegerValue,@"\033",NSZeroPoint);
        NSEvent *(^normalHandler)(NSEvent *) = handlers.lastObject;
        check(normalHandler(escape) == escape && view.overView, @"ordinary popup leaves Escape for editor and search");
    }
    flags = NSEventModifierFlagOption;
    check(!view.globalLongTerm, @"ordinary hover is not pinned");
    [view killPopup:timeout(view)];
    check(!view.overView && !view.handlingLink && !handlers.count, @"ordinary timeout removes overlay and monitor");
    show(view, 0);
    [view mouseMoved:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    check(!view.overView, @"ordinary move away dismisses");
    show(view, NSEventModifierFlagOption);
    flags = 0;
    check(view.globalLongTerm, @"Option at show pins");
    NSTimer *oldTimeout = timeout(view);
    for (NSNumber *inLink in @[@NO,@YES]) {
        view.inLink = inLink.boolValue;
        [view mouseMoved:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
        check(view.globalLongTerm && view.overView, @"pinned popup survives pointer on or off links");
    }
    [view killPopup:oldTimeout]; check(view.overView != nil, @"pin survives timeout and modifier release");
    NSEvent *(^handler)(NSEvent *) = handlers.lastObject;
    NSEvent *foreignEscape = event(otherWindow,NSEventTypeKeyDown,0,@"\033",NSZeroPoint);
    check(handler(foreignEscape) == foreignEscape && view.overView, @"other windows retain Escape");
    for (NSNumber *modifier in @[@(NSEventModifierFlagOption),@(NSEventModifierFlagCommand),@(NSEventModifierFlagControl),@(NSEventModifierFlagShift)]) {
        NSEvent *escape = event(window,NSEventTypeKeyDown,modifier.unsignedIntegerValue,@"\033",NSZeroPoint);
        check(handler(escape) == escape && view.overView, @"modified Escape is not consumed even when pinned");
    }
    NSEvent *ordinaryKey = event(window,NSEventTypeKeyDown,0,@"a",NSZeroPoint);
    check(handler(ordinaryKey) == ordinaryKey, @"ordinary keys pass through");
    check(handler(event(window,NSEventTypeKeyDown,0,@"\033",NSZeroPoint)) == nil, @"Escape consumed in owner window");
    check(!view.overView && !view.globalLongTerm && !handlers.count, @"Escape clears state and monitor");
    show(view, 0);
    [view killPopup:oldTimeout]; check(view.overView != nil, @"old timer cannot dismiss newer popup");
    handler = handlers.lastObject;
    NSEvent *option = event(window,NSEventTypeFlagsChanged,NSEventModifierFlagOption,@"",NSZeroPoint);
    check(handler(option) == option && view.globalLongTerm, @"Option after show pins without consuming modifier");
    handler(event(window,NSEventTypeFlagsChanged,0,@"",NSZeroPoint));
    check(view.globalLongTerm, @"releasing Option leaves pin");
    [view changeLinkPopups]; check(!view.overView && !handlers.count && view.skipLinks, @"disabling popups clears pin");
    [view changeLinkPopups];
    view.handlingLink = 1;
    NSTimer *pending = showTimer(view);
    [view doKillPopup]; [view handleLink:pending];
    check(!view.overView && !view.handlingLink, @"cancelled pending timer cannot recreate popup");
    show(view,NSEventModifierFlagOption);
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:otherWindow];
    check(view.overView != nil, @"other window closing has no effect");
    [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillCloseNotification object:window];
    check(!view.overView && !handlers.count, @"owner close cleans overlay and monitor");
    show(view,NSEventModifierFlagOption);
    view.document = doc;
    check(!view.overView && !handlers.count, @"PDF reload clears popup and monitor");
    show(view,NSEventModifierFlagOption);
    [view cleanupMarquee:YES];
    check(!view.overView && !view.handlingLink && !view.globalLongTerm && !handlers.count, @"cleanupMarquee clears popup state and monitor");
    flags=0; view.inLink=YES;
    [view mouseMoved:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    check(view.handlingLink == 1, @"hover resumes after cleanupMarquee");
    [view handleLink:showTimer(view)];
    check(view.overView != nil, @"next hover displays overlay after cleanupMarquee");
    [view doKillPopup];
    show(view,NSEventModifierFlagOption);
    [view mouseDown:event(window,NSEventTypeMouseMoved,0,@"",NSZeroPoint)];
    check(!view.overView && !view.handlingLink && !handlers.count, @"click clears popup and monitor before annotation handling");
    show(view,NSEventModifierFlagOption);
    [SUD registerDefaults:@{LinkPopupsKey:@YES}];
    [view initializeDisplay];
    check(!view.overView && !view.handlingLink && !handlers.count, @"initializeDisplay clears popup and monitor");
    view.handlingLink=1; NSTimer *beforeInitialize=showTimer(view);
    [view initializeDisplay];
    view.handlingLink=1; [view handleLink:beforeInitialize];
    check(!view.overView, @"initializeDisplay invalidates pending timer");
    [view doKillPopup];
    show(view,NSEventModifierFlagOption);
    [view removeFromSuperview];
    check(!view.overView && !handlers.count, @"detaching view clears popup");
    printf("PASS: %lu popup event/lifecycle checks\n", (unsigned long)checks);
    return 0;
}}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-pinned-link-') as directory:
    temporary = Path(directory)
    native = temporary / 'probe.m'
    native.write_text(program)
    exe = temporary / 'probe'
    subprocess.run(['xcrun','clang','-fobjc-arc','-framework','Cocoa','-framework','PDFKit',
                    '-I'+str(root/'Sources'),'-I'+str(root/'Tests'),str(native),
                    str(root/'Sources/OverView.m'),'-o',str(exe)],check=True)
    home = temporary/'home'
    (home/'Library/Preferences').mkdir(parents=True)
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
    result = subprocess.run([str(exe)], env=env, capture_output=True, text=True, timeout=30)
    print(result.stdout, end='')
    if args.mutation:
        expected = {'move-dismisses':'pinned popup survives', 'stale-timer':'old timer cannot dismiss',
                    'other-window':'other windows retain Escape', 'cleanup-state':'cleanupMarquee clears',
                    'ordinary-escape':'ordinary popup leaves Escape', 'modified-escape':'modified Escape is not consumed',
                    'click-cleanup':'click clears popup', 'initialize-cleanup':'initializeDisplay clears popup'}[args.mutation]
        assert result.returncode == 1 and expected in result.stderr, result.stderr
        print('PASS: detected mutation ' + args.mutation)
    else:
        if result.returncode: print(result.stderr)
        result.check_returncode()
