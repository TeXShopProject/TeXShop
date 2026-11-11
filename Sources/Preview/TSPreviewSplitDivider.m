// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreviewSplitDivider.h"

// The page and the point on it at the top edge of a part.
@interface TSPreviewSplitAnchor : NSObject
@property (weak) PDFView *view;
@property (strong) PDFPage *page;
@property NSPoint point;
@end

@implementation TSPreviewSplitAnchor
@end

@interface TSPreviewSplitDivider ()
@property (weak) NSSplitView *splitView;
@property (strong) NSArray<TSPreviewSplitAnchor *> *anchors;
@end

@implementation TSPreviewSplitDivider

- (instancetype)initWithSplitView:(NSSplitView *)splitView
{
    self = [super init];
    if (self) {
        _splitView = splitView;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(splitViewWillResizeSubviews:)
                       name:NSSplitViewWillResizeSubviewsNotification object:splitView];
        [center addObserver:self selector:@selector(splitViewDidResizeSubviews:)
                       name:NSSplitViewDidResizeSubviewsNotification object:splitView];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

+ (BOOL)isDividerDrag:(NSNotification *)notification
{
    // NSSplitView marks a resize by the user in its notifications. Otherwise the
    // resize is a divider drag when it happens during a mouse drag in the window
    // that is not a resize of the window itself.
    if ([notification.userInfo[@"NSSplitViewUserResizeKey"] boolValue])
        return YES;
    NSView *splitView = notification.object;
    NSEvent *event = NSApp.currentEvent;
    return [splitView isKindOfClass:[NSView class]] && splitView.window != nil && !splitView.window.inLiveResize &&
        event.window == splitView.window && event.type == NSEventTypeLeftMouseDragged;
}

- (void)splitViewWillResizeSubviews:(NSNotification *)notification
{
    self.anchors = nil;
    NSSplitView *splitView = self.splitView;
    // Only a split into a top and a bottom part.
    if (splitView == nil || splitView.isVertical || ![TSPreviewSplitDivider isDividerDrag:notification])
        return;
    NSMutableArray<TSPreviewSplitAnchor *> *anchors = [NSMutableArray array];
    for (NSView *subview in splitView.subviews) {
        if (![subview isKindOfClass:[PDFView class]] || subview.isHidden)
            continue;
        PDFView *view = (PDFView *)subview;
        if (view.document == nil || NSIsEmptyRect(view.bounds))
            continue;
        NSRect bounds = view.bounds;
        NSPoint top = NSMakePoint(NSMidX(bounds), view.isFlipped ? NSMinY(bounds) : NSMaxY(bounds));
        PDFPage *page = [view pageForPoint:top nearest:YES];
        if (page == nil)
            continue;
        TSPreviewSplitAnchor *anchor = [TSPreviewSplitAnchor new];
        anchor.view = view;
        anchor.page = page;
        anchor.point = [view convertPoint:top toPage:page];
        [anchors addObject:anchor];
    }
    // A single part has nothing to keep apart from.
    if (anchors.count >= 2)
        self.anchors = anchors;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    NSArray<TSPreviewSplitAnchor *> *anchors = self.anchors;
    self.anchors = nil;
    for (TSPreviewSplitAnchor *anchor in anchors) {
        PDFView *view = anchor.view;
        NSView *documentView = view.documentView;
        NSClipView *clipView = (NSClipView *)documentView.superview;
        if (view == nil || ![clipView isKindOfClass:[NSClipView class]] || anchor.page.document != view.document)
            continue;
        [view layoutDocumentView];
        NSPoint inView = [view convertPoint:anchor.point fromPage:anchor.page];
        NSPoint inDocument = [documentView convertPoint:inView fromView:view];
        NSRect visible = clipView.documentVisibleRect;
        CGFloat topEdge = documentView.isFlipped ? NSMinY(visible) : NSMaxY(visible);
        NSRect bounds = clipView.bounds;
        bounds.origin.y += inDocument.y - topEdge;
        [clipView scrollToPoint:[clipView constrainBoundsRect:bounds].origin];
        [documentView.enclosingScrollView reflectScrolledClipView:clipView];
    }
}

@end
