// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreviewSplitDivider.h"
#import "TSPreviewScrollerKeeper.h"

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

// The top edge of a part, in clip view coordinates. The content insets are left out:
// up to macOS 26, AppKit gives the top part a content inset as large as the change of
// the window's height for a moment while the window is resized, and a place noted then
// was put back that much too low once the inset was gone.
static CGFloat TSPartTop(NSClipView *clip)
{
    return clip.isFlipped ? NSMinY(clip.bounds) : NSMaxY(clip.bounds);
}

// Whether the scroll position of a part is still where it was left. A move of less than a
// point is not a scroll by the user: AppKit aligns the position to the pixels of the
// screen, for instance when the top part gets a content inset for a moment while the
// window is resized, and reading the text at the top again then let it creep.
static BOOL TSPartStillAt(NSClipView *clip, NSPoint origin)
{
    CGFloat unit = NSHeight(clip.frame) > 0 ? NSHeight(clip.bounds) / NSHeight(clip.frame) : 1;
    return fabs(clip.bounds.origin.x - origin.x) < unit && fabs(clip.bounds.origin.y - origin.y) < unit;
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

// Whether the parts fill the split view: they line up with its edges, with the dividers between them.
static BOOL TSSplitViewPartsFill(NSSplitView *splitView, NSArray<NSView *> *parts)
{
    BOOL vertical = splitView.isVertical;
    NSRect bounds = splitView.bounds;
    CGFloat position = vertical ? NSMinX(bounds) : NSMinY(bounds);
    for (NSView *part in parts) {
        NSRect frame = part.frame;
        if (vertical ? (NSMinX(frame) != position || NSMinY(frame) != NSMinY(bounds) || NSHeight(frame) != NSHeight(bounds))
                     : (NSMinY(frame) != position || NSMinX(frame) != NSMinX(bounds) || NSWidth(frame) != NSWidth(bounds)))
            return NO;
        position = (vertical ? NSMaxX(frame) : NSMaxY(frame)) + splitView.dividerThickness;
    }
    return position - splitView.dividerThickness == (vertical ? NSMaxX(bounds) : NSMaxY(bounds));
}

// Gives the parts the new size of the split view. NSSplitView sizes them as it does without
// a delegate. But once a view in the window uses Auto Layout, as the line along the active
// part does, NSSplitView leaves the sizing to a delegate that implements
// splitView:resizeSubviewsWithOldSize:, and its own sizing leaves the parts as they were
// (#47). Then each part keeps its share of the length along the split, and takes the whole
// size across it.
static void TSSplitViewSizeParts(NSSplitView *splitView, NSSize oldSize)
{
    NSMutableArray<NSView *> *parts = [NSMutableArray array];
    for (NSView *subview in splitView.subviews)
        if (!subview.isHidden)
            [parts addObject:subview];
    if (parts.count == 0)
        return;
    id<NSSplitViewDelegate> delegate = splitView.delegate;
    splitView.delegate = nil;
    [splitView resizeSubviewsWithOldSize:oldSize];
    splitView.delegate = delegate;
    if (TSSplitViewPartsFill(splitView, parts))
        return;
    BOOL vertical = splitView.isVertical;
    NSRect bounds = splitView.bounds;
    CGFloat thickness = splitView.dividerThickness;
    CGFloat oldTotal = 0;
    for (NSView *part in parts)
        oldTotal += vertical ? NSWidth(part.frame) : NSHeight(part.frame);
    CGFloat newTotal = MAX(0, (vertical ? NSWidth(bounds) : NSHeight(bounds)) - thickness * (parts.count - 1));
    CGFloat position = vertical ? NSMinX(bounds) : NSMinY(bounds);
    CGFloat used = 0;
    for (NSUInteger i = 0; i < parts.count; i++) {
        NSView *part = parts[i];
        CGFloat length;
        if (i + 1 == parts.count)
            length = newTotal - used;
        else if (oldTotal > 0)
            length = round((vertical ? NSWidth(part.frame) : NSHeight(part.frame)) * newTotal / oldTotal);
        else
            length = round(newTotal / parts.count);
        length = MAX(0, MIN(length, newTotal - used));
        part.frame = vertical ? NSMakeRect(position, NSMinY(bounds), length, NSHeight(bounds))
                              : NSMakeRect(NSMinX(bounds), position, NSWidth(bounds), length);
        position += length + thickness;
        used += length;
    }
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
        (empty || TSPartStillAt(clip, anchor.origin)))
        return anchor;
    BOOL wasQuiet = anchor.quiet;
    anchor = nil;
    if (!empty) {
        NSPoint top = [view convertPoint:NSMakePoint(NSMidX(clip.bounds), TSPartTop(clip)) fromView:clip];
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
        bounds.origin.y += point.y - TSPartTop(clip);
        NSPoint target = TSPreviewConstrainedOrigin(clip, bounds);
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
        // A new magnification, as with Fit to Window when the width changes too: the part
        // kept the text at the top of the area where it can be read while it changed its
        // size, below the toolbar for the upper part. The top edge of the part is under the
        // toolbar, and putting the text there back would move what can be read (#53).
        if (!anchor.quiet && view.scaleFactor != anchor.scale && TSPreviewSizeChangeKeptText(view)) {
            [self.anchors removeObjectForKey:view];
            continue;
        }
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
    TSSplitViewSizeParts(splitView, oldSize);
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
