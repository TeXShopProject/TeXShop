// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSDocumentWindowGlass.m
 */

#import "TSDocumentWindowGlass.h"
#import <objc/runtime.h>

static const void *TSDrawerBaseOffsetKey = &TSDrawerBaseOffsetKey;

// The height of the band of the content view that lies under the title bar and the toolbar.
static CGFloat TSHiddenTopBand(NSWindow *window)
{
    if (!(window.styleMask & NSWindowStyleMaskFullSizeContentView))
        return 0;
    NSView *content = window.contentView;
    return MAX(0, NSHeight(content.frame) - NSMaxY(window.contentLayoutRect));
}

// A drawer at the side of a window starts below the toolbar, as it did before the
// content ran under it.
static void TSDrawerWillOpen(NSNotification *notification)
{
    NSDrawer *drawer = notification.object;
    NSWindow *window = drawer.parentWindow;
    if (![drawer isKindOfClass:NSDrawer.class] || !window)
        return;
    NSNumber *base = objc_getAssociatedObject(drawer, TSDrawerBaseOffsetKey);
    if (!base) {
        base = @(drawer.leadingOffset);
        objc_setAssociatedObject(drawer, TSDrawerBaseOffsetKey, base, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSRectEdge edge = drawer.edge == 0 ? drawer.preferredEdge : drawer.edge;
    BOOL side = edge == NSMinXEdge || edge == NSMaxXEdge;
    drawer.leadingOffset = base.doubleValue + (side ? TSHiddenTopBand(window) : 0);
}

BOOL TSDocumentWindowsUseFullSizeContent(void)
{
    if (@available(macOS 26.0, *))
        return YES;
    return NO;
}

void TSDocumentWindowUseFullSizeContent(NSWindow *window)
{
    if (!window || !TSDocumentWindowsUseFullSizeContent())
        return;
    if (window.styleMask & NSWindowStyleMaskFullSizeContentView)
        return;
    window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:NSDrawerWillOpenNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *notification) { TSDrawerWillOpen(notification); }];
    });
}

void TSDocumentWindowSplitEvenly(NSSplitView *splitView)
{
    if (splitView.arrangedSubviews.count != 2 || !(splitView.window.styleMask & NSWindowStyleMaskFullSizeContentView))
        return;
    CGFloat thickness = splitView.dividerThickness;
    if (splitView.isVertical) {
        [splitView setPosition:floor((NSWidth(splitView.bounds) - thickness) / 2) ofDividerAtIndex:0];
        return;
    }
    CGFloat hidden = splitView.safeAreaInsets.top;
    CGFloat height = NSHeight(splitView.bounds);
    [splitView setPosition:floor(hidden + (height - hidden - thickness) / 2) ofDividerAtIndex:0];
}
