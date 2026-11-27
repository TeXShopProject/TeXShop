// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreviewScrollerKeeper.h"
#import <objc/runtime.h>

static void *TSPreviewScrollerKeeperKey = &TSPreviewScrollerKeeperKey;
static void *TSPreviewScrollerContext = &TSPreviewScrollerContext;
static void *TSPreviewInsetsContext = &TSPreviewInsetsContext;
static void *TSPreviewClipConstrainKey = &TSPreviewClipConstrainKey;

// NSClipView copies the scroll view's top inset and divides it by the magnification,
// then stops a scroll there. PDFKit applies that same top inset in the clip's bounds,
// so at a magnification other than 1 the top of the document is short of the stop by
// the rest of the inset. The scroll is allowed to reach it. Other clip views are left
// as they are.
static Class TSConstrainClasses[8];
static IMP TSConstrainIMPs[8];
static int TSConstrainCount;

static IMP TSConstrainOriginal(id view) {
    for (Class cls = object_getClass(view); cls; cls = class_getSuperclass(cls))
        for (int i = 0; i < TSConstrainCount; i++)
            if (TSConstrainClasses[i] == cls)
                return TSConstrainIMPs[i];
    return NULL;
}

static NSRect TSPreviewConstrainBounds(NSClipView *self, SEL _cmd, NSRect proposed) {
    IMP original = TSConstrainOriginal(self);
    NSRect rect = original ? ((NSRect (*)(id, SEL, NSRect))original)(self, _cmd, proposed) : proposed;
    if (!objc_getAssociatedObject(self, &TSPreviewClipConstrainKey))
        return rect;
    NSScrollView *scroll = self.enclosingScrollView;
    CGFloat magnification = scroll.magnification;
    // Below unit scale the inset is in screen points and AppKit's stop is the one
    // Fit to Window uses. Extending it leaves the first page short of the toolbar.
    if (!isfinite(magnification) || magnification <= 1)
        return rect;
    CGFloat inset = scroll.contentInsets.top;
    if (inset <= 0.5)
        return rect;
    if (self.isFlipped) {
        CGFloat limit = NSMinY(self.documentRect) - inset;
        if (proposed.origin.y < rect.origin.y)
            rect.origin.y = fmax(proposed.origin.y, limit);
    } else {
        CGFloat limit = NSMaxY(self.documentRect) - NSHeight(proposed) + inset;
        if (proposed.origin.y > rect.origin.y)
            rect.origin.y = fmin(proposed.origin.y, limit);
    }
    return rect;
}

static void TSInstallPreviewClipConstrain(NSClipView *clip) {
    if (!clip)
        return;
    objc_setAssociatedObject(clip, &TSPreviewClipConstrainKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Class cls = object_getClass(clip);
    SEL sel = @selector(constrainBoundsRect:);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || method_getImplementation(method) == (IMP)TSPreviewConstrainBounds)
        return;
    if (TSConstrainCount == sizeof TSConstrainClasses / sizeof TSConstrainClasses[0])
        return;
    TSConstrainClasses[TSConstrainCount] = cls;
    TSConstrainIMPs[TSConstrainCount] = method_getImplementation(method);
    TSConstrainCount++;
    class_replaceMethod(cls, sel, (IMP)TSPreviewConstrainBounds, method_getTypeEncoding(method));
}

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
// (measured on macOS 14, 15 and 26), except for a moment while the window's height changes,
// and except for the band under the toolbar of a window whose content runs under it (macOS 26
// and later). Such a view is left to PDFKit too. On macOS 26 its text does move when a
// scroller comes or goes (#53); that happens when the view changes its size, and then
// TSPreviewChangeSize keeps the text.
static BOOL TSHasInsets(NSScrollView *scroll)
{
    NSEdgeInsets insets = scroll.contentInsets;
    return insets.top != 0 || insets.bottom != 0;
}

// Above unit scale, PDFKit stores the top inset in the clip view's bounds and then
// magnifies it, so the property is the toolbar band divided by the magnification.
// At unit scale and below, the property is that band in screen points. Dividing
// there subtracts the band twice.
static CGFloat TSMag(NSScrollView *scroll)
{
    CGFloat magnification = scroll.magnification;
    return (isfinite(magnification) && magnification > 0.01) ? magnification : 1;
}

static CGFloat TSTopInsetScreen(NSScrollView *scroll)
{
    CGFloat magnification = TSMag(scroll);
    CGFloat top = scroll.contentInsets.top;
    return magnification > 1 ? top * magnification : top;
}

// The height of the area where the text can be seen, in points.
static CGFloat TSVisibleHeight(NSScrollView *scroll)
{
    return NSHeight(scroll.contentView.frame) - TSTopInsetScreen(scroll) - scroll.contentInsets.bottom;
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
    NSPoint target = TSPreviewConstrainedOrigin(clip, bounds);
    if (!NSEqualPoints(target, clip.bounds.origin)) {
        [clip scrollToPoint:target];
        [scroll reflectScrolledClipView:clip];
    }
}

// The height of the band under the toolbar and the title bar of a window whose content runs
// under them (macOS 26 and later). The safe area of the content view of the window keeps it
// while the window changes its size; the top inset of the scroll view and the frames of the
// views can be seen in a state of the resize that AppKit is about to change again (measured
// in macOS 15.6.1 and 26.6.2).
static CGFloat TSToolbarBand(NSView *view)
{
    NSWindow *window = view.window;
    if (!window || !(window.styleMask & NSWindowStyleMaskFullSizeContentView))
        return 0;
    return fmax(0, window.contentView.safeAreaInsets.top);
}

// How far below the top edge of the clip view the text can be read, in points: the part of
// the band that lies over the view. Asked when the view has its new size.
static CGFloat TSReadableBelow(NSScrollView *scroll, CGFloat band)
{
    NSClipView *clip = scroll.contentView;
    NSView *content = clip.window.contentView;
    if (band <= 0 || !content)
        return 0;
    NSRect frame = [content convertRect:clip.bounds fromView:clip];
    CGFloat distance = content.isFlipped ? NSMinY(frame) - NSMinY(content.bounds) : NSMaxY(content.bounds) - NSMaxY(frame);
    return fmin(fmax(0, band - distance), NSHeight(clip.frame));
}

// Draws the window color from the top of a magnified PDF scroll view down to the first
// page. At the top of a light page the glass would otherwise sample the light gutter and
// the toolbar would turn light. A scrolled page moves above this view, so the glass takes
// the page color. The view clips: on macOS 14 and later a view draws outside its bounds
// unless it clips, and that would cover the page. Clicks pass through.
@interface TSPreviewToolbarShield : NSView
@end

@implementation TSPreviewToolbarShield
- (BOOL)isOpaque { return NO; }
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSAppearance *appearance = self.window.effectiveAppearance;
    if (!appearance) appearance = NSApp.effectiveAppearance;
    [appearance performAsCurrentDrawingAppearance:^{
        [[NSColor.windowBackgroundColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace] setFill];
        NSRectFill(self.bounds);
    }];
}
@end

static void *TSPreviewToolbarShieldKey = &TSPreviewToolbarShieldKey;

@interface TSPreviewScrollerKeeper ()
@property (weak) PDFView *view;
// Held so that the observation can always be removed.
@property (strong, nullable) NSScrollView *scrollView;
@property (strong, nullable) PDFPage *page;
@property NSPoint point;
@property BOOL pending;
// While the magnification changes, the text is put in place afterwards.
@property NSInteger suspended;
// The text that the last change of the size kept at the top, and where the view was then,
// at which magnification.
@property (strong, nullable) PDFPage *keptPage;
@property NSPoint keptPoint;
@property CGFloat keptBelow;
// How much of the band lay over the view after the last change of its size, and the height of
// the band then.
@property BOOL hasReadableBelow;
@property CGFloat readableBelow;
@property CGFloat readableBand;
// The part of the band over the view is checked again once the views are laid out: while this
// turn of the event loop lasts, and when the view is laid out in it.
@property BOOL checkScheduled;
@property BOOL checkPending;
@property NSPoint keptOrigin;
@property CGFloat keptScale;
// The clip whose bounds are watched so the band over the toolbar can follow scrolling.
@property (strong, nullable) NSClipView *observedClip;
// While the top inset and the band are being put in place, a bounds change from that
// scroll does not start the work again.
@property BOOL placingGround;
- (void)placeToolbarGround;
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

- (void)observeClip:(nullable NSClipView *)clip
{
    if (clip == self.observedClip)
        return;
    if (self.observedClip)
        [NSNotificationCenter.defaultCenter removeObserver:self name:NSViewBoundsDidChangeNotification object:self.observedClip];
    self.observedClip = clip;
    if (!clip)
        return;
    clip.postsBoundsChangedNotifications = YES;
    TSInstallPreviewClipConstrain(clip);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(clipBoundsChanged:)
                                               name:NSViewBoundsDidChangeNotification object:clip];
}

- (void)observeScrollView:(nullable NSScrollView *)scrollView
{
    if (scrollView == self.scrollView)
        return;
    [self.scrollView removeObserver:self forKeyPath:@"hasHorizontalScroller" context:TSPreviewScrollerContext];
    [self.scrollView removeObserver:self forKeyPath:@"contentInsets" context:TSPreviewInsetsContext];
    [self observeClip:nil];
    self.scrollView = scrollView;
    self.pending = NO;
    [scrollView addObserver:self forKeyPath:@"hasHorizontalScroller" options:NSKeyValueObservingOptionPrior
                    context:TSPreviewScrollerContext];
    [scrollView addObserver:self forKeyPath:@"contentInsets" options:0 context:TSPreviewInsetsContext];
    [self observeClip:scrollView.contentView];
    [self placeToolbarGround];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == TSPreviewInsetsContext) {
        // In a window laid out with Auto Layout, AppKit gives the scroll view the part of the
        // band over it as its top inset once the views are laid out, and moves the text with
        // the edge of the inset. A change of the size that is still being settled puts its
        // text back at the top of the area where it can be read.
        if (self.checkPending)
            [self checkReadableTop];
        return;
    }
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


// A split view sets the sizes and the places of its parts one after the other, and PDFKit
// and Auto Layout lay out the views after that, so while a part changes its size, the part of
// the band over it may be read from a place that is about to change, and the place it was
// given may move again. Once the views are laid out, the text kept by the last change is put
// at the top of the area where it can be read: in the same turn of the event loop, and again
// whenever the view is laid out until the window has been drawn. Only a distance up to the
// height of the band is made good: a larger move is a deliberate one of the program, as to a
// page. The part of the band over the view is noted for the next change.
- (void)checkReadableTop
{
    PDFView *view = self.view;
    NSScrollView *scroll = view ? TSScroll(view) : nil;
    if (scroll == nil)
        return;
    CGFloat band = TSToolbarBand(view);
    CGFloat below = TSReadableBelow(scroll, band);
    PDFPage *kept = self.keptPage;
    if (band > 0 && kept.document == view.document) {
        CGFloat distance = TSTextBelowTop(view, scroll, (TSPreviewText){YES, kept, self.keptPoint}) - below;
        if (fabs(distance) >= 0.5 && fabs(distance) <= band) {
            TSMoveTextUp(scroll, distance);
            self.keptOrigin = scroll.contentView.bounds.origin;
            self.keptScale = view.scaleFactor;
        }
        self.keptBelow = below;
    }
    self.hasReadableBelow = YES;
    self.readableBelow = below;
    self.readableBand = band;
}

- (void)checkReadableTopLater
{
    self.checkPending = YES;
    if (self.checkScheduled)
        return;
    self.checkScheduled = YES;
    __weak TSPreviewScrollerKeeper *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        TSPreviewScrollerKeeper *keeper = weakSelf;
        keeper.checkScheduled = NO;
        if (!keeper.checkPending)
            return;
        [keeper checkReadableTop];
        // The window is laid out and drawn before the event loop waits again; AppKit can still
        // move the text then, as when it gives the scroll view a new top inset. The last check
        // comes after all of that.
        CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, false, LONG_MAX,
                                                                           ^(CFRunLoopObserverRef runLoopObserver, CFRunLoopActivity activity) {
            TSPreviewScrollerKeeper *last = weakSelf;
            if (last.checkPending && !last.checkScheduled) {
                [last checkReadableTop];
                last.checkPending = NO;
            }
        });
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
        CFRelease(observer);
    });
}

// The part of the toolbar band that lies over this scroll view, in screen points.
- (CGFloat)bandOverScroll:(NSScrollView *)scroll
{
    return TSReadableBelow(scroll, TSToolbarBand(self.view));
}

// Keeps the magnified top inset equal to the toolbar band on screen, and paints the
// window color above the first page so a light gutter cannot light the glass.
- (void)placeToolbarGround
{
    if (self.placingGround)
        return;
    PDFView *view = self.view;
    NSScrollView *scroll = view ? TSScroll(view) : nil;
    NSClipView *clip = scroll.contentView;
    if (!scroll || !clip)
        return;
    self.placingGround = YES;
    NSWindow *window = view.window;
    BOOL underToolbar = window && (window.styleMask & NSWindowStyleMaskFullSizeContentView);
    CGFloat magnification = TSMag(scroll);
    CGFloat band = underToolbar ? [self bandOverScroll:scroll] : 0;
    CGFloat wanted = band / magnification;
    if (magnification <= 1)
        wanted = band;
    if (underToolbar && scroll.automaticallyAdjustsContentInsets)
        scroll.automaticallyAdjustsContentInsets = NO;
    NSEdgeInsets insets = scroll.contentInsets;
    if (underToolbar && fabs(insets.top - wanted) >= 0.25) {
        CGFloat shift = insets.top - wanted;
        insets.top = wanted;
        scroll.contentInsets = insets;
        if (magnification > 1) {
            // The document point at the bottom of the band stays where it is.
            // Below unit scale the inset is in screen points, and this shift is not.
            NSPoint origin = clip.bounds.origin;
            origin.y += clip.isFlipped ? shift : -shift;
            [clip scrollToPoint:origin];
            [scroll reflectScrolledClipView:clip];
        } else if (view.autoScales) {
            // Fit to Window measured the old inset. Measure the band again.
            view.autoScales = NO;
            view.autoScales = YES;
        }
    }
    TSPreviewToolbarShield *shield = objc_getAssociatedObject(scroll, TSPreviewToolbarShieldKey);
    if (!underToolbar || band < 1) {
        shield.hidden = YES;
        self.placingGround = NO;
        return;
    }
    if (!shield) {
        shield = [[TSPreviewToolbarShield alloc] initWithFrame:NSZeroRect];
        shield.autoresizingMask = NSViewNotSizable;
        shield.clipsToBounds = YES;
        objc_setAssociatedObject(scroll, TSPreviewToolbarShieldKey, shield, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (shield.superview != scroll)
        [scroll addSubview:shield positioned:NSWindowAbove relativeTo:clip];
    PDFPage *page = view.document.pageCount ? [view.document pageAtIndex:0] : nil;
    if (!page) {
        shield.hidden = YES;
        self.placingGround = NO;
        return;
    }
    NSRect pageRect = [view convertRect:[view convertRect:[page boundsForBox:view.displayBox] fromPage:page] toView:nil];
    NSRect inScroll = [scroll convertRect:pageRect fromView:nil];
    BOOL flipped = scroll.isFlipped;
    CGFloat pageEdge = flipped ? NSMinY(inScroll) : NSMaxY(inScroll);
    CGFloat viewEdge = flipped ? NSMinY(scroll.bounds) : NSMaxY(scroll.bounds);
    CGFloat height = flipped ? pageEdge - viewEdge : viewEdge - pageEdge;
    // The natural margin under the band is a few points. A larger value is a page that
    // has not reached the band; only the band, plus that margin, is painted.
    CGFloat limit = band + 24;
    if (height > limit)
        height = limit;
    if (height < 0.5) {
        shield.hidden = YES;
    } else {
        shield.hidden = NO;
        shield.frame = flipped ? NSMakeRect(NSMinX(scroll.bounds), viewEdge, NSWidth(scroll.bounds), height)
                                : NSMakeRect(NSMinX(scroll.bounds), pageEdge, NSWidth(scroll.bounds), height);
    }
    self.placingGround = NO;
}

- (void)clipBoundsChanged:(NSNotification *)notification
{
    (void)notification;
    [self placeToolbarGround];
}
@end

void TSPreviewChangeScale(PDFView *view, void (NS_NOESCAPE ^change)(void))
{
    TSPreviewScrollerKeeper *keeper = [TSPreviewScrollerKeeper keeperForView:view];
    NSScrollView *scroll = TSScroll(view);
    CGFloat height = scroll ? TSVisibleHeight(scroll) : 0;
    // The centre of the area where the text can be seen.
    CGFloat below = scroll ? TSTopInsetScreen(scroll) + height / 2 : 0;
    TSPreviewText text = scroll ? TSTextAt(view, scroll, below) : (TSPreviewText){0};
    PDFPage *page = text.page;
    keeper.suspended++;
    change();
    keeper.suspended--;
    // The magnified inset follows the new scale before the text is put back.
    [keeper placeToolbarGround];
    // Without a change of the visible height, PDFKit's own place is kept.
    if (!text.valid || TSScroll(view) != scroll || page.document != view.document ||
        fabs(TSVisibleHeight(scroll) - height) < 0.5)
        return;
    text.page = page;
    TSMoveTextUp(scroll, TSTextBelowTop(view, scroll, text) - below);
}

void TSPreviewChangeSize(PDFView *view, void (NS_NOESCAPE ^change)(void))
{
    TSPreviewScrollerKeeper *keeper = [TSPreviewScrollerKeeper keeperForView:view];
    NSScrollView *scroll = TSScroll(view);
    // How much of the band lies over the view can be asked only once the view has its new
    // size: all of it at the top of the window, none in the lower part of a split window, or a
    // part of it when the upper part is lower than the band. While the band keeps its height,
    // how much of it lay over the view before is what the last change of the size left; the
    // text read there now goes to the top of the area where it can be read afterwards, also
    // when the change moves the view under the band, as a resize at a corner of a split
    // window does. Otherwise, the first time and after the toolbar was shown or hidden, the
    // text at the top edge and the text just below the band are noted, and the one nearer to
    // the top of the area where it can be read is kept. Once the views are laid out, the text
    // kept is put at that top (checkReadableTopLater).
    CGFloat band = scroll ? TSToolbarBand(view) : 0;
    BOOL knownBefore = scroll && keeper.hasReadableBelow && fabs(keeper.readableBand - band) < 0.5;
    TSPreviewText before = knownBefore ? TSTextAt(view, scroll, keeper.readableBelow) : (TSPreviewText){0};
    PDFPage *beforePage = before.page;
    NSInteger count = band > 0 ? 2 : 1;
    CGFloat offsets[2] = {0, band};
    TSPreviewText samples[2];
    __strong PDFPage *samplePages[2];
    for (NSInteger i = 0; i < count; i++) {
        samples[i] = scroll ? TSTextAt(view, scroll, offsets[i]) : (TSPreviewText){0};
        samplePages[i] = samples[i].page;
    }
    TSPreviewText atEdge = samples[0];
    // PDFKit's clip view puts its place on whole pixels up to macOS 26, so at a new
    // magnification the text comes back up to a pixel off, and it rounds the place again
    // later. While the view has not moved since the last change by more than that rounding and
    // that text is still where it was kept, it is kept again, so that the pixels do not add up
    // over the steps of a resize (measured in macOS 26.6.2). Scrolling by a point or more moves
    // the view, and the text there then is kept.
    PDFPage *kept = keeper.keptPage;
    keeper.keptPage = nil;
    CGFloat pixel = scroll ? fmax(1, 1 / TSUnit(scroll.contentView)) : 1;
    BOOL keepAgain = atEdge.valid && kept.document == view.document && view.scaleFactor == keeper.keptScale &&
        fabs(scroll.contentView.bounds.origin.y - keeper.keptOrigin.y) <= 0.5 * TSUnit(scroll.contentView) &&
        fabs(TSTextBelowTop(view, scroll, (TSPreviewText){YES, kept, keeper.keptPoint}) - keeper.keptBelow) <= 1.5 * pixel;
    CGFloat keptBelow = keeper.keptBelow;
    NSPoint keptPoint = keeper.keptPoint;
    PDFPage *edgePage = samplePages[0];
    // A scroller that comes or goes during the change is covered here.
    keeper.suspended++;
    change();
    keeper.suspended--;
    // With automatic scaling, as Fit to Window, the magnification follows the size, and the
    // text stays at the top too: PDFKit kept another place, which on macOS 26 and earlier lay
    // far from the text (#53).
    if (!atEdge.valid || TSScroll(view) != scroll || edgePage.document != view.document)
        return;
    CGFloat below = TSReadableBelow(scroll, band);
    TSPreviewText text = atEdge;
    text.page = edgePage;
    // The text noted nearer to the top of the area where it can be read, kept at the same
    // distance from the top edge.
    NSInteger nearest = 0;
    for (NSInteger i = 1; i < count; i++)
        if (fabs(offsets[i] - below) < fabs(offsets[nearest] - below))
            nearest = i;
    CGFloat target = 0;
    if (knownBefore && keepAgain) {
        text = (TSPreviewText){YES, kept, keptPoint};
        target = below;
    } else if (knownBefore && before.valid && beforePage.document == view.document) {
        text = before;
        text.page = beforePage;
        target = below;
    } else if (keepAgain && fabs(offsets[nearest] - keptBelow) < 0.01) {
        text = (TSPreviewText){YES, kept, keptPoint};
        target = keptBelow;
    } else if (samples[nearest].valid && samplePages[nearest].document == view.document) {
        text = samples[nearest];
        text.page = samplePages[nearest];
        target = offsets[nearest];
    }
    TSMoveTextUp(scroll, TSTextBelowTop(view, scroll, text) - target);
    keeper.keptPage = text.page;
    keeper.keptPoint = text.point;
    keeper.keptBelow = target;
    [keeper checkReadableTopLater];
    keeper.keptOrigin = scroll.contentView.bounds.origin;
    keeper.keptScale = view.scaleFactor;
}

void TSPreviewPlaceSetByProgram(PDFView *view)
{
    TSPreviewScrollerKeeper *keeper = [TSPreviewScrollerKeeper keeperForView:view];
    NSScrollView *scroll = TSScroll(view);
    if (scroll && keeper.keptPage != nil) {
        keeper.keptOrigin = scroll.contentView.bounds.origin;
        keeper.keptScale = view.scaleFactor;
        // The split divider puts back the text at the top edge of the part, also once a quiet
        // resize is over; the text kept at the top of the area where it can be read goes back there.
        [keeper checkReadableTop];
    }
}

void TSPreviewViewDidLayout(PDFView *view)
{
    TSPreviewScrollerKeeper *keeper = [TSPreviewScrollerKeeper keeperForView:view];
    [keeper placeToolbarGround];
    if (keeper && !keeper.checkPending) {
        // Auto Layout can move the view after its last change of size: the part of the band
        // over it is noted again for the next change.
        NSScrollView *scroll = TSScroll(view);
        if (scroll) {
            CGFloat band = TSToolbarBand(view);
            keeper.hasReadableBelow = YES;
            keeper.readableBelow = TSReadableBelow(scroll, band);
            keeper.readableBand = band;
        }
    }
}

// Above unit scale the top inset of a preview under the toolbar is the band divided by the
// magnification (see TSMag), and PDFKit puts the place it goes to at that inset taken as
// screen points: a link target or an outline entry lay under the toolbar (#78). The band is
// taken from the window's safe area and the place of the view in the window, not from the
// inset, so the part of a split window or of the window that shows the source and the
// Preview gets its own share of the band. A place that PDFKit put some way below its inset,
// as the top of the next page below the gap between pages, keeps that distance below the band,
// as at unit scale; one that PDFKit could not put at its inset, at an end of the document,
// goes right below the band.
void TSPreviewRevealBelowToolbar(PDFView *view, PDFPage *page, NSPoint point)
{
    NSScrollView *scroll = TSScroll(view);
    if (!scroll || !page || page.document != view.document || NSIsEmptyRect(scroll.contentView.bounds))
        return;
    CGFloat below = TSReadableBelow(scroll, TSToolbarBand(view));
    if (below < 1)
        return;
    CGFloat distance = TSTextBelowTop(view, scroll, (TSPreviewText){YES, page, point});
    if (!isfinite(distance) || distance >= below - 0.5)
        return;
    CGFloat inset = fmax(0, scroll.contentInsets.top);
    TSMoveTextUp(scroll, -fmax(below - inset, below - distance));
}

// Puts a point back at the top edge of the clip view, under the band, where the point that
// PDFKit names the current destination lies. PDFKit puts such a point at its top inset.
void TSPreviewPutAtTop(PDFView *view, PDFPage *page, NSPoint point)
{
    NSScrollView *scroll = TSScroll(view);
    if (!scroll || !page || page.document != view.document || NSIsEmptyRect(scroll.contentView.bounds))
        return;
    CGFloat distance = TSTextBelowTop(view, scroll, (TSPreviewText){YES, page, point});
    if (isfinite(distance))
        TSMoveTextUp(scroll, distance);
}

// Back and Forward go to the current destination noted before a move, the point at the top
// edge of the clip view, under the band. PDFKit puts it at its top inset, so the view came
// back lower by the inset taken as screen points, at every magnification (#78).
void TSPreviewHistoryPlaceToTop(PDFView *view)
{
    NSScrollView *scroll = TSScroll(view);
    if (!scroll || TSToolbarBand(view) <= 0 || NSIsEmptyRect(scroll.contentView.bounds))
        return;
    CGFloat inset = scroll.contentInsets.top;
    if (inset > 0.5)
        TSMoveTextUp(scroll, inset);
}

void TSPreviewPlaceChosenByProgram(PDFView *view)
{
    // The text kept by the last change of the size is not put back once the views are laid out.
    [TSPreviewScrollerKeeper keeperForView:view].keptPage = nil;
}

BOOL TSPreviewSizeChangeKeptText(PDFView *view)
{
    TSPreviewScrollerKeeper *keeper = [TSPreviewScrollerKeeper keeperForView:view];
    NSScrollView *scroll = TSScroll(view);
    PDFPage *kept = keeper.keptPage;
    return scroll && kept.document == view.document && view.scaleFactor == keeper.keptScale &&
        fabs(scroll.contentView.bounds.origin.y - keeper.keptOrigin.y) <= 0.5 * TSUnit(scroll.contentView);
}
