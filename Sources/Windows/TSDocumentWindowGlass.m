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

// The height of the title bar of a window, without the toolbar and the bars under it.
static CGFloat TSTitleBarHeight(NSWindow *window)
{
    NSRect content = NSMakeRect(0, 0, 100, 100);
    NSWindowStyleMask style = window.styleMask & ~NSWindowStyleMaskFullSizeContentView;
    return MAX(0, NSHeight([NSWindow frameRectForContentRect:content styleMask:style]) - NSHeight(content));
}

// A drawer at the side of a window starts right below the title bar, beside the toolbar and a
// bar under it, such as the annotation toolbar, so that a long outline has room (#67). AppKit
// puts it there in a window whose content stays below the toolbar (measured on macOS 15 and
// 26), and at the top of the window, beside the title bar, in a window whose content runs
// under the toolbar. It does not go higher than the area below the toolbar, as in full screen.
static void TSPlaceDrawer(NSDrawer *drawer, NSWindow *window)
{
    NSNumber *base = objc_getAssociatedObject(drawer, TSDrawerBaseOffsetKey);
    if (!base) {
        base = @(drawer.leadingOffset);
        objc_setAssociatedObject(drawer, TSDrawerBaseOffsetKey, base, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSRectEdge edge = drawer.edge == 0 ? drawer.preferredEdge : drawer.edge;
    BOOL side = edge == NSMinXEdge || edge == NSMaxXEdge;
    CGFloat offset = base.doubleValue + (side ? MIN(TSTitleBarHeight(window), TSHiddenTopBand(window)) : 0);
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

void TSDocumentWindowPrepare(NSWindow *window)
{
    if (!window)
        return;
    objc_setAssociatedObject(window, TSPreparedWindowKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:NSDrawerWillOpenNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *notification) { TSDrawerWillOpen(notification); }];
    });
    if (TSDocumentWindowsUseFullSizeContent() && !(window.styleMask & NSWindowStyleMaskFullSizeContentView)) {
        // AppKit keeps the content size and makes the window lower by the height of the title
        // bar and the toolbar; the window keeps the frame it was given instead.
        NSRect frame = window.frame;
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
        [window setFrame:frame display:NO];
    }
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
