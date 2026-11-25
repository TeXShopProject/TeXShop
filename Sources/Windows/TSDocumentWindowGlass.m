// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSDocumentWindowGlass.m
 */

#import "TSDocumentWindowGlass.h"
#import <objc/runtime.h>

static const void *TSDrawerBaseOffsetKey = &TSDrawerBaseOffsetKey;
static const void *TSPreparedWindowKey = &TSPreparedWindowKey;

// The height of the band of the content view that lies under the title bar and the toolbar.
static CGFloat TSHiddenTopBand(NSWindow *window)
{
    if (!(window.styleMask & NSWindowStyleMaskFullSizeContentView))
        return 0;
    NSView *content = window.contentView;
    return MAX(0, NSHeight(content.frame) - NSMaxY(window.contentLayoutRect));
}

// AppKit draws the frame of a drawer as a light gray bezel, in Dark Mode too. This
// view goes behind the drawer's content and paints the frame in the window's colors.
@interface TSDrawerBacking : NSView
@end

@implementation TSDrawerBacking

- (NSView *)hitTest:(NSPoint)point
{
    // Dragging the edge of the drawer still resizes it.
    return nil;
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(self.bounds);
    NSBezierPath *edge = [NSBezierPath bezierPathWithRect:NSInsetRect(self.bounds, 0.5, 0.5)];
    [NSColor.separatorColor setStroke];
    [edge stroke];
}

@end

// On macOS 26 and later the top corners of a document window, with a title bar and an
// Expanded toolbar or with the toolbar hidden, have a radius of 16 points (measured on macOS 26
// and 27; macOS 27 reports the same through -[NSView effectiveCornerRadii]). They are
// continuous curves that reach the straight side 1.5 times the radius below the top.
static const CGFloat TSWindowCornerHeight = 24;

// A drawer at the side of a window whose content runs under the toolbar starts right where
// the rounding of the window's top corner ends, beside the title bar and the toolbar, so that a
// long outline has room (#67). AppKit would put it at the top of the window, beside the rounded
// corner. It does not go higher than the area below the toolbar, as in full screen, where the
// window has no rounded corners. In a window whose content stays below the toolbar AppKit puts
// the drawer right below the title bar.
static void TSPlaceDrawer(NSDrawer *drawer, NSWindow *window)
{
    NSNumber *base = objc_getAssociatedObject(drawer, TSDrawerBaseOffsetKey);
    if (!base) {
        base = @(drawer.leadingOffset);
        objc_setAssociatedObject(drawer, TSDrawerBaseOffsetKey, base, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSRectEdge edge = drawer.edge == 0 ? drawer.preferredEdge : drawer.edge;
    BOOL side = edge == NSMinXEdge || edge == NSMaxXEdge;
    CGFloat offset = base.doubleValue + (side ? MIN(TSWindowCornerHeight, TSHiddenTopBand(window)) : 0);
    if (drawer.leadingOffset != offset)
        drawer.leadingOffset = offset;
}

static void TSDrawerWillOpen(NSNotification *notification)
{
    NSDrawer *drawer = notification.object;
    NSWindow *window = drawer.parentWindow;
    if (![drawer isKindOfClass:NSDrawer.class] || !window || !objc_getAssociatedObject(window, TSPreparedWindowKey))
        return;
    TSPlaceDrawer(drawer, window);
    // The frame of the drawer takes the window's colors.
    NSView *frame = drawer.contentView.superview;
    if (!frame)
        return;
    for (NSView *subview in frame.subviews)
        if ([subview isKindOfClass:TSDrawerBacking.class])
            return;
    TSDrawerBacking *backing = [[TSDrawerBacking alloc] initWithFrame:frame.bounds];
    backing.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [frame addSubview:backing positioned:NSWindowBelow relativeTo:nil];
}

void TSDocumentWindowPlaceDrawers(NSWindow *window)
{
    if (!window || !objc_getAssociatedObject(window, TSPreparedWindowKey))
        return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (NSDrawer *drawer in window.drawers)
        if (drawer.state == NSDrawerOpenState || drawer.state == NSDrawerOpeningState)
            TSPlaceDrawer(drawer, window);
#pragma clang diagnostic pop
}

BOOL TSDocumentWindowsUseFullSizeContent(void)
{
    if (@available(macOS 26.0, *))
        return YES;
    return NO;
}

// underToolbar is the macOS 26 full-size content view: the pages or the text scroll
// under the title bar and the toolbar. Without it the content view starts below the
// toolbar, and a line is drawn at the bottom of the toolbar.
static void TSDocumentWindowPrepareChrome(NSWindow *window, BOOL underToolbar)
{
    if (!window)
        return;
    objc_setAssociatedObject(window, TSPreparedWindowKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:NSDrawerWillOpenNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *notification) { TSDrawerWillOpen(notification); }];
        // A drawer left open while the window goes into or out of full screen keeps its place
        // otherwise: out of full screen it would stay at the top, beside the rounded corner (#67).
        for (NSNotificationName name in @[NSWindowDidEnterFullScreenNotification, NSWindowDidExitFullScreenNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                        usingBlock:^(NSNotification *notification) { TSDocumentWindowPlaceDrawers(notification.object); }];
    });
    BOOL hasFullSize = (window.styleMask & NSWindowStyleMaskFullSizeContentView) != 0;
    if (hasFullSize != underToolbar) {
        // AppKit keeps the content size and makes the window lower or taller by the height
        // of the title bar and the toolbar; the window keeps the frame it was given instead.
        NSRect frame = window.frame;
        if (underToolbar) {
            window.styleMask |= NSWindowStyleMaskFullSizeContentView;
        } else {
            window.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
        }
        [window setFrame:frame display:NO];
    }
    if (!underToolbar)
        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleLine;
}

void TSDocumentWindowPrepare(NSWindow *window)
{
    TSDocumentWindowPrepareChrome(window, TSDocumentWindowsUseFullSizeContent());
}

void TSDocumentWindowPrepareSolidToolbar(NSWindow *window)
{
    TSDocumentWindowPrepareChrome(window, NO);
}

CGFloat TSDocumentWindowHiddenTop(NSView *view)
{
    if (!(view.window.styleMask & NSWindowStyleMaskFullSizeContentView))
        return 0;
    return MAX(0, view.safeAreaInsets.top);
}

BOOL TSDocumentWindowPointIsUnderToolbar(NSWindow *window, NSPoint point)
{
    if (!window || !(window.styleMask & NSWindowStyleMaskFullSizeContentView))
        return NO;
    return point.y >= NSMaxY(window.contentLayoutRect);
}

NSRect TSDocumentWindowRectBelowToolbar(NSView *view, NSRect rect)
{
    NSWindow *window = view.window;
    if (!window || !(window.styleMask & NSWindowStyleMaskFullSizeContentView))
        return rect;
    return NSIntersectionRect(rect, [view convertRect:window.contentLayoutRect fromView:nil]);
}

void TSDocumentWindowSplitInShares(NSSplitView *splitView, CGFloat first, CGFloat second)
{
    if (splitView.arrangedSubviews.count != 2 || first < 0 || second < 0 || first + second <= 0)
        return;
    CGFloat thickness = splitView.dividerThickness;
    CGFloat share = first / (first + second);
    if (splitView.isVertical) {
        [splitView setPosition:round((NSWidth(splitView.bounds) - thickness) * share) ofDividerAtIndex:0];
        return;
    }
    CGFloat hidden = TSDocumentWindowHiddenTop(splitView);
    CGFloat height = NSHeight(splitView.bounds);
    [splitView setPosition:round(hidden + MAX(0, height - hidden - thickness) * share) ofDividerAtIndex:0];
}

void TSDocumentWindowSplitEvenly(NSSplitView *splitView)
{
    TSDocumentWindowSplitInShares(splitView, 1, 1);
}
