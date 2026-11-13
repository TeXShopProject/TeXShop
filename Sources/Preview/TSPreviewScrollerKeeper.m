// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreviewScrollerKeeper.h"
#import <objc/runtime.h>

static void *TSPreviewScrollerKeeperKey = &TSPreviewScrollerKeeperKey;
static void *TSPreviewScrollerContext = &TSPreviewScrollerContext;

// The text shown at a place in the visible area, as a point on a page.
typedef struct {
    BOOL valid;
    __unsafe_unretained PDFPage *page;
    NSPoint point;
} TSPreviewText;

static NSScrollView *TSScroll(PDFView *view)
{
    NSScrollView *scroll = view.documentView.enclosingScrollView;
    return [scroll.contentView isKindOfClass:[NSClipView class]] && scroll.superview == view ? scroll : nil;
}

// Places are measured in the clip view's own coordinates, from the top edge of its bounds,
// so that they do not depend on whether its frame has caught up with its bounds yet.

// The size of a point of the view in the clip view: the magnification.
static CGFloat TSUnit(NSClipView *clip)
{
    return NSHeight(clip.frame) > 0 ? NSHeight(clip.bounds) / NSHeight(clip.frame) : 1;
}

static CGFloat TSTop(NSClipView *clip)
{
    return clip.isFlipped ? NSMinY(clip.bounds) : NSMaxY(clip.bounds);
}

// Whether the scroll view has content insets. Then AppKit puts the scroller over the
// bottom inset, and a scroller that comes or goes during a resize can be seen in a state
// that PDFKit is about to change again (measured on macOS 14 and 15, and in the test with
// a document view that is not flipped): the text noted then is not the text at the top.
// The views are left to PDFKit then, as before. The Preview views have no content insets
// (measured on macOS 14, 15 and 26), except for a moment while the window's height changes.
static BOOL TSHasInsets(NSScrollView *scroll)
{
    NSEdgeInsets insets = scroll.contentInsets;
    return insets.top != 0 || insets.bottom != 0;
}

// The height of the area where the text can be seen, in points.
static CGFloat TSVisibleHeight(NSScrollView *scroll)
{
    return NSHeight(scroll.contentView.frame) - scroll.contentInsets.top - scroll.contentInsets.bottom;
}

// The text shown a distance below the top edge of the clip view, in the middle of its width.
static TSPreviewText TSTextAt(PDFView *view, NSScrollView *scroll, CGFloat below)
{
    TSPreviewText text = {0};
    NSClipView *clip = scroll.contentView;
    if (view.document.pageCount == 0 || NSIsEmptyRect(clip.bounds))
        return text;
    CGFloat y = TSTop(clip) + (clip.isFlipped ? below : -below) * TSUnit(clip);
    NSPoint point = [view convertPoint:NSMakePoint(NSMidX(clip.bounds), y) fromView:clip];
    PDFPage *page = [view pageForPoint:point nearest:YES];
    if (page == nil)
        return text;
    text.valid = YES;
    text.page = page;
    text.point = [view convertPoint:point toPage:page];
    return text;
}

// How far the text lies below the top edge of the clip view, in points.
static CGFloat TSTextBelowTop(PDFView *view, NSScrollView *scroll, TSPreviewText text)
{
    NSClipView *clip = scroll.contentView;
    NSPoint point = [clip convertPoint:[view convertPoint:text.point fromPage:text.page] fromView:view];
    return (clip.isFlipped ? point.y - TSTop(clip) : TSTop(clip) - point.y) / TSUnit(clip);
}

// Moves the text up by a distance, as far as the document allows.
static void TSMoveTextUp(NSScrollView *scroll, CGFloat distance)
{
    NSClipView *clip = scroll.contentView;
    if (fabs(distance) < 0.01 || NSIsEmptyRect(clip.bounds) || NSHeight(clip.frame) <= 0)
        return;
    NSRect bounds = clip.bounds;
    bounds.origin.y += (clip.isFlipped ? distance : -distance) * TSUnit(clip);
    NSPoint target = [clip constrainBoundsRect:bounds].origin;
    if (!NSEqualPoints(target, clip.bounds.origin)) {
        [clip scrollToPoint:target];
        [scroll reflectScrolledClipView:clip];
    }
}

@interface TSPreviewScrollerKeeper ()
@property (weak) PDFView *view;
// Held so that the observation can always be removed.
@property (strong, nullable) NSScrollView *scrollView;
@property (strong, nullable) PDFPage *page;
@property NSPoint point;
@property BOOL pending;
// While the magnification changes, the text is put in place afterwards.
@property NSInteger suspended;
@end

@implementation TSPreviewScrollerKeeper

+ (void)installInView:(PDFView *)view
{
    TSPreviewScrollerKeeper *keeper = objc_getAssociatedObject(view, TSPreviewScrollerKeeperKey);
    if (keeper == nil) {
        keeper = [[TSPreviewScrollerKeeper alloc] initWithView:view];
        objc_setAssociatedObject(view, TSPreviewScrollerKeeperKey, keeper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [keeper observeScrollView:TSScroll(view)];
}

+ (nullable TSPreviewScrollerKeeper *)keeperForView:(PDFView *)view
{
    return objc_getAssociatedObject(view, TSPreviewScrollerKeeperKey);
}

- (instancetype)initWithView:(PDFView *)view
{
    self = [super init];
    if (self)
        _view = view;
    return self;
}

- (void)dealloc
{
    [self observeScrollView:nil];
}

- (void)observeScrollView:(nullable NSScrollView *)scrollView
{
    if (scrollView == self.scrollView)
        return;
    [self.scrollView removeObserver:self forKeyPath:@"hasHorizontalScroller" context:TSPreviewScrollerContext];
    self.scrollView = scrollView;
    self.pending = NO;
    [scrollView addObserver:self forKeyPath:@"hasHorizontalScroller" options:NSKeyValueObservingOptionPrior
                    context:TSPreviewScrollerContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != TSPreviewScrollerContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    PDFView *view = self.view;
    NSScrollView *scroll = view ? TSScroll(view) : nil;
    if ([change[NSKeyValueChangeNotificationIsPriorKey] boolValue]) {
        // PDFKit is about to add or remove the scroller: note the text at the top edge.
        TSPreviewText text = (scroll == object && self.suspended == 0 && !TSHasInsets(scroll)) ?
            TSTextAt(view, scroll, 0) : (TSPreviewText){0};
        self.pending = text.valid;
        self.page = text.page;
        self.point = text.point;
        return;
    }
    if (!self.pending)
        return;
    self.pending = NO;
    PDFPage *page = self.page;
    self.page = nil;
    if (scroll != object || page.document != view.document)
        return;
    TSMoveTextUp(scroll, TSTextBelowTop(view, scroll, (TSPreviewText){YES, page, self.point}));
}

@end

void TSPreviewChangeScale(PDFView *view, void (NS_NOESCAPE ^change)(void))
{
    TSPreviewScrollerKeeper *keeper = [TSPreviewScrollerKeeper keeperForView:view];
    NSScrollView *scroll = TSScroll(view);
    CGFloat height = scroll ? TSVisibleHeight(scroll) : 0;
    // The centre of the area where the text can be seen.
    CGFloat below = scroll ? scroll.contentInsets.top + height / 2 : 0;
    TSPreviewText text = scroll ? TSTextAt(view, scroll, below) : (TSPreviewText){0};
    PDFPage *page = text.page;
    keeper.suspended++;
    change();
    keeper.suspended--;
    // Without a change of the visible height, PDFKit's own place is kept.
    if (!text.valid || TSScroll(view) != scroll || page.document != view.document ||
        fabs(TSVisibleHeight(scroll) - height) < 0.5)
        return;
    text.page = page;
    TSMoveTextUp(scroll, TSTextBelowTop(view, scroll, text) - below);
}
