// The scroll event that AppKit is handling, for "Do not turn pages by scrolling"
// (NoScrollPageTurnKey). NSApplication's sendEvent: passes the event to local
// monitors and then to the view under the pointer; the event counts as being
// handled from then until the main run loop turns. A page turn that PDFKit asks
// for in that time comes from the scroll; one asked for later does not, even
// though NSApp.currentEvent still names the last scroll event.
#import <Cocoa/Cocoa.h>

static NSEvent *TSScrollEventInDispatch;

static inline void TSScrollPageTurnInstallMonitor(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel handler:^NSEvent *(NSEvent *event) {
            TSScrollEventInDispatch = event;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (TSScrollEventInDispatch == event)
                    TSScrollEventInDispatch = nil;
            });
            return event;
        }];
    });
}

// The scroll event being handled in window, or nil.
static inline NSEvent *TSScrollEventBeingHandled(NSWindow *window)
{
    NSEvent *event = TSScrollEventInDispatch;
    if (event.window && event.window != window)
        return nil;
    return event;
}
