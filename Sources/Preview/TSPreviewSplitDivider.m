// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreviewSplitDivider.h"
#import "TSPreviewPanePlace.h"

// The text at the top edge of a part, as a point on a page, and where the part was left.
@interface TSPreviewSplitAnchor : NSObject
@property (strong) PDFPage *page;
@property NSPoint point;
@property CGFloat scale;
// The scroll position the part was left at. While it is unchanged, the part still
// shows the same text, so the same point is kept, even while the part has no height.
@property NSPoint origin;
// The size of the part before the current resize.
@property NSSize size;
// PDFKit is not told about the size of the part until the resize is over.
@property BOOL quiet;
@end

@implementation TSPreviewSplitAnchor
@end

@interface TSPreviewSplitDivider () <NSSplitViewDelegate>
@property (weak) NSSplitView *splitView;
@property (strong) NSMapTable<PDFView *, TSPreviewSplitAnchor *> *anchors;
// The parts of the divider drag going on.
@property (strong, nullable) NSArray<PDFView *> *dragParts;
@end

static NSClipView *TSPartClip(PDFView *view)
{
    NSClipView *clip = view.documentView.enclosingScrollView.contentView;
    return [clip isKindOfClass:[NSClipView class]] ? clip : nil;
}

// Whether a part can follow a change of its height without PDFKit.
//
// PDFKit answers every size change of a PDFView by scrolling to the top of its
// current page, and only then could the top be put back. During a drag that
// happened at every step, and the parts jumped away and back all the time. A
// part whose scale does not depend on its height only needs its scroll view to
// follow the new size, and then PDFKit is told once the resize is over.
static BOOL TSPartCanResizeQuietly(PDFView *view)
{
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    if (scroll.superview != view || TSPartClip(view) == nil)
        return NO;
    if (!view.autoScales)
        return YES;
    // Automatic scaling of continuous pages only fits the width.
    return view.displayMode == kPDFDisplaySinglePageContinuous || view.displayMode == kPDFDisplayTwoUpContinuous;
}

@implementation TSPreviewSplitDivider

- (instancetype)initWithSplitView:(NSSplitView *)splitView
{
    self = [super init];
    if (self) {
        _splitView = splitView;
        _anchors = [NSMapTable weakToStrongObjectsMapTable];
        // The split view tells its delegate when it changes its size.
        if (splitView.delegate == nil)
            splitView.delegate = self;
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
    for (PDFView *view in self.anchors.keyEnumerator.allObjects)
        if ([self.anchors objectForKey:view].quiet)
            view.postsFrameChangedNotifications = YES;
}

+ (BOOL)isDividerDrag:(NSNotification *)notification
{
    // NSSplitView says in its notifications whether the user or the program moved
    // a divider. Without that, the resize is a divider drag when it happens during
    // a mouse drag in the window that is not a resize of the window itself.
    NSNumber *byUser = notification.userInfo[@"NSSplitViewUserResizeKey"];
    if (byUser != nil)
        return byUser.boolValue;
    NSView *splitView = notification.object;
    NSEvent *event = NSApp.currentEvent;
    return [splitView isKindOfClass:[NSView class]] && splitView.window != nil && !splitView.window.inLiveResize &&
        event.window == splitView.window && event.type == NSEventTypeLeftMouseDragged;
}

// The parts of the split that show a document.
- (NSArray<PDFView *> *)parts
{
    NSMutableArray<PDFView *> *parts = [NSMutableArray array];
    for (NSView *subview in self.splitView.subviews)
        if ([subview isKindOfClass:[PDFView class]] && !subview.isHidden && ((PDFView *)subview).document != nil)
            [parts addObject:(PDFView *)subview];
    return parts;
}

- (TSPreviewSplitAnchor *)anchorForView:(PDFView *)view
{
    NSClipView *clip = TSPartClip(view);
    BOOL empty = clip == nil || NSIsEmptyRect(clip.bounds);
    TSPreviewSplitAnchor *anchor = [self.anchors objectForKey:view];
    // The part still shows the text it was left with: keep the same point, instead of
    // reading it back from the scroll position, which may have been limited by the end
    // of the document or by a part without height.
    if (anchor != nil && anchor.page.document == view.document && anchor.scale == view.scaleFactor &&
        (empty || NSEqualPoints(clip.bounds.origin, anchor.origin)))
        return anchor;
    BOOL wasQuiet = anchor.quiet;
    anchor = nil;
    if (!empty) {
        NSScrollView *scroll = view.documentView.enclosingScrollView;
        NSPoint edge = TSPreviewPaneEdge(scroll);
        NSPoint top = [view convertPoint:NSMakePoint(NSMidX(clip.bounds), edge.y) fromView:clip];
        PDFPage *page = [view pageForPoint:top nearest:YES];
        if (page != nil) {
            anchor = [TSPreviewSplitAnchor new];
            anchor.page = page;
            anchor.point = [view convertPoint:top toPage:page];
            anchor.origin = clip.bounds.origin;
            anchor.scale = view.scaleFactor;
            anchor.quiet = wasQuiet;
        }
    }
    if (anchor != nil)
        [self.anchors setObject:anchor forKey:view];
    else {
        if (wasQuiet)
            view.postsFrameChangedNotifications = YES;
        [self.anchors removeObjectForKey:view];
    }
    return anchor;
}

// Scrolls the part so that the point of the anchor is at its top edge, as far as the document allows.
- (void)restore:(TSPreviewSplitAnchor *)anchor inView:(PDFView *)view
{
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    NSClipView *clip = TSPartClip(view);
    if (clip == nil)
        return;
    if (!NSIsEmptyRect(clip.bounds) && anchor.page.document == view.document) {
        NSPoint point = [clip convertPoint:[view convertPoint:anchor.point fromPage:anchor.page] fromView:view];
        NSRect bounds = clip.bounds;
        bounds.origin.y += point.y - TSPreviewPaneEdge(scroll).y;
        NSPoint target = [clip constrainBoundsRect:bounds].origin;
        if (!NSEqualPoints(target, clip.bounds.origin)) {
            [clip scrollToPoint:target];
            [scroll reflectScrolledClipView:clip];
        }
    }
    anchor.origin = clip.bounds.origin;
}

// Gets each part ready to keep its top through a resize.
- (void)prepareParts:(NSArray<PDFView *> *)parts quietly:(BOOL)quietly
{
    for (PDFView *view in parts) {
        TSPreviewSplitAnchor *anchor = [self anchorForView:view];
        if (anchor == nil)
            continue;
        anchor.size = view.bounds.size;
        if (quietly && !anchor.quiet && view.postsFrameChangedNotifications && TSPartCanResizeQuietly(view)) {
            view.postsFrameChangedNotifications = NO;
            anchor.quiet = YES;
        }
    }
}

// Puts the text back at the top of each part after a resize.
- (void)followParts:(NSArray<PDFView *> *)parts
{
    BOOL quiet = NO;
    for (PDFView *view in parts) {
        TSPreviewSplitAnchor *anchor = [self.anchors objectForKey:view];
        if (anchor == nil)
            continue;
        if (anchor.quiet) {
            // The scroll view follows the part as with autoresizing; a flipped clip view
            // keeps its top by itself.
            NSScrollView *scroll = view.documentView.enclosingScrollView;
            NSRect frame = scroll.frame;
            frame.size.width = MAX(0, NSWidth(frame) + NSWidth(view.bounds) - anchor.size.width);
            frame.size.height = MAX(0, NSHeight(frame) + NSHeight(view.bounds) - anchor.size.height);
            scroll.frame = frame;
            quiet = YES;
        } else
            [view layoutDocumentView];
        [self restore:anchor inView:view];
    }
    // PDFKit catches up once the drag or the live resize is over: the event loop is
    // back in the default mode only then.
    if (quiet) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(finishQuietResize) object:nil];
        [self performSelector:@selector(finishQuietResize) withObject:nil afterDelay:0 inModes:@[NSDefaultRunLoopMode]];
    }
}

- (void)splitViewWillResizeSubviews:(NSNotification *)notification
{
    self.dragParts = nil;
    NSSplitView *splitView = self.splitView;
    if (splitView == nil)
        return;
    if (![TSPreviewSplitDivider isDividerDrag:notification]) {
        // The program moves the divider and puts the parts in place itself.
        if ([notification.userInfo[@"NSSplitViewUserResizeKey"] isEqual:@NO])
            [self finishQuietResize];
        return;
    }
    // Only a split into a top and a bottom part.
    NSArray<PDFView *> *parts = [self parts];
    if (splitView.isVertical || parts.count < 2)
        return;
    [self prepareParts:parts quietly:YES];
    self.dragParts = parts;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    NSArray<PDFView *> *parts = self.dragParts;
    self.dragParts = nil;
    [self followParts:parts];
}

// The split view changed its size, as when the window is resized. NSSplitView sizes
// the parts before it posts its notifications in this case, so the top of each part
// is taken here, before the parts are resized.
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize
{
    NSArray<PDFView *> *parts = [self parts];
    BOOL keep = splitView == self.splitView && !splitView.isVertical && parts.count >= 2 &&
        NSHeight(splitView.bounds) != oldSize.height;
    // A change of width can change the scale, which PDFKit has to see at once.
    BOOL quietly = NSWidth(splitView.bounds) == oldSize.width;
    if (!keep || !quietly)
        [self finishQuietResize];
    if (keep)
        [self prepareParts:parts quietly:quietly];
    // The split view sizes the parts as it does without a delegate.
    splitView.delegate = nil;
    [splitView resizeSubviewsWithOldSize:oldSize];
    splitView.delegate = self;
    if (keep)
        [self followParts:parts];
}

- (void)finishQuietResize
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(finishQuietResize) object:nil];
    for (PDFView *view in self.anchors.keyEnumerator.allObjects) {
        TSPreviewSplitAnchor *anchor = [self.anchors objectForKey:view];
        if (!anchor.quiet)
            continue;
        anchor.quiet = NO;
        // Turning the notifications on again posts the size change to PDFKit, which
        // scrolls the part to the top of its current page; the text is put back after it.
        view.postsFrameChangedNotifications = YES;
        if (view.superview != self.splitView || view.document == nil)
            continue;
        [view layoutDocumentView];
        [self restore:anchor inView:view];
    }
}

@end
