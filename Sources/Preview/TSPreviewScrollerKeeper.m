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

// How far a point in the scroll view lies below a height in it, in points.
static CGFloat TSBelow(NSScrollView *scroll, NSPoint point, CGFloat y)
{
    return scroll.isFlipped ? point.y - y : y - point.y;
}

// The top edge of the visible area, below the content insets, as a height in the scroll view.
static CGFloat TSVisibleTop(NSScrollView *scroll)
{
    NSClipView *clip = scroll.contentView;
    NSRect frame = clip.frame;
    CGFloat top = scroll.isFlipped ? NSMinY(frame) : NSMaxY(frame);
    return top + (scroll.isFlipped ? scroll.contentInsets.top : -scroll.contentInsets.top);
}

static CGFloat TSVisibleHeight(NSScrollView *scroll)
{
    return NSHeight(scroll.contentView.frame) - scroll.contentInsets.top - scroll.contentInsets.bottom;
}

// The text shown a distance below the top edge of the visible area, in the middle of its width.
static TSPreviewText TSTextAt(PDFView *view, NSScrollView *scroll, CGFloat below)
{
    TSPreviewText text = {0};
    NSClipView *clip = scroll.contentView;
    if (view.document.pageCount == 0 || NSIsEmptyRect(clip.bounds))
        return text;
    CGFloat y = TSVisibleTop(scroll) + (scroll.isFlipped ? below : -below);
    NSPoint point = [view convertPoint:NSMakePoint(NSMidX(clip.frame), y) fromView:scroll];
    PDFPage *page = [view pageForPoint:point nearest:YES];
    if (page == nil)
        return text;
    text.valid = YES;
    text.page = page;
    text.point = [view convertPoint:point toPage:page];
    return text;
}

// How far the text lies below the top edge of the visible area.
static CGFloat TSTextBelowTop(PDFView *view, NSScrollView *scroll, TSPreviewText text)
{
    NSPoint point = [scroll convertPoint:[view convertPoint:text.point fromPage:text.page] fromView:view];
    return TSBelow(scroll, point, TSVisibleTop(scroll));
}

// Moves the text up by a distance, as far as the document allows.
static void TSMoveTextUp(NSScrollView *scroll, CGFloat distance)
{
    NSClipView *clip = scroll.contentView;
    if (fabs(distance) < 0.01 || NSIsEmptyRect(clip.bounds) || NSHeight(clip.frame) <= 0)
        return;
    // The bounds of the clip view are in document units: the scale of the magnification.
    CGFloat unit = NSHeight(clip.bounds) / NSHeight(clip.frame);
    NSRect bounds = clip.bounds;
    bounds.origin.y += (clip.isFlipped ? distance : -distance) * unit;
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
        TSPreviewText text = (scroll == object && self.suspended == 0) ? TSTextAt(view, scroll, 0) : (TSPreviewText){0};
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
    CGFloat below = height / 2;
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
