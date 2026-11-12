#import "TSLinkPreviewView.h"
#import "TSLinkPreviewGeometry.h"
#import <objc/runtime.h>

// Sizes on screen, independent of the preview's magnification.
static const CGFloat TSLinkPreviewGrip = 6;
static const CGFloat TSLinkPreviewMinimumWidth = 120;
static const CGFloat TSLinkPreviewMinimumHeight = 40;
static const CGFloat TSLinkPreviewLineScroll = 10;
// A moved popup keeps this much of its width and height in view, so it can be dragged back.
static const CGFloat TSLinkPreviewKeptFraction = 0.05;
static const CGFloat TSLinkPreviewKeptMinimum = 20;
// Page points around a line that still count as its text, so the cursor does not flicker
// between lines.
static const CGFloat TSLinkPreviewLineSlack = 2;
// The page label in the lower right corner: white bold text on a gray capsule.
static const CGFloat TSLinkPreviewLabelFontSize = 11;
static const CGFloat TSLinkPreviewLabelMargin = 3;
// A popup shows its linked page and, in the continuous displays, the next one (#14).
#define TSLinkPreviewMaximumPages 2

typedef NS_ENUM(NSInteger, TSLinkPreviewDrag) {
    TSLinkPreviewDragNone,
    TSLinkPreviewDragMove,
    TSLinkPreviewDragResize,
    TSLinkPreviewDragSelect,
};

@implementation TSLinkPreviewView
{
    NSImage *_image;
    NSSize _pageSize;
    // The pages in the image, from top to bottom, with their rectangles in the image and
    // the transforms from page space to the image.
    PDFPage *_pages[TSLinkPreviewMaximumPages];
    NSRect _pageRects[TSLinkPreviewMaximumPages];
    CGAffineTransform _transforms[TSLinkPreviewMaximumPages];
    NSUInteger _pageCount;
    TSLinkPreviewDrag _drag;
    TSLinkPreviewEdge _dragEdges;
    NSPoint _dragStart, _selectionStart;
    PDFPage *_selectionStartPage;
    NSRect _startFrame, _startSource;
}

- (instancetype)initWithFrame:(NSRect)frame image:(NSImage *)image source:(NSRect)source
                     pageSize:(NSSize)pageSize page:(PDFPage *)page
                    transform:(CGAffineTransform)transform
{
    if ((self = [self initWithFrame:frame image:image source:source pageSize:pageSize pages:@[] pageRects:NULL]) && page) {
        _pages[0] = page;
        _pageRects[0] = NSMakeRect(0, 0, pageSize.width, pageSize.height);
        _transforms[0] = transform;
        _pageCount = 1;
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame image:(NSImage *)image source:(NSRect)source
                     pageSize:(NSSize)pageSize pages:(NSArray<PDFPage *> *)pages
                    pageRects:(const NSRect *)pageRects
{
    if ((self = [super initWithFrame:frame])) {
        _image = image;
        _source = source;
        _pageSize = pageSize;
        for (PDFPage *page in pages) {
            if (_pageCount == TSLinkPreviewMaximumPages || !page.pageRef) break;
            NSRect rect = pageRects[_pageCount];
            CGPDFPageRef reference = page.pageRef;
            _pages[_pageCount] = page;
            _pageRects[_pageCount] = rect;
            _transforms[_pageCount] = CGPDFPageGetDrawingTransform(reference, kCGPDFCropBox, NSRectToCGRect(rect), 0, true);
            _pageCount++;
        }
        // The image draws its whole page; only the part inside the popup may be seen (#21).
        self.clipsToBounds = YES;
        // The preview sees the pointer move only while it is over the preview, so the popup
        // itself notices the pointer leaving it, also straight onto the toolbar (#14).
        [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
            options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
              owner:self userInfo:nil]];
    }
    return self;
}

// The rectangle in this view that shows `rect`, given in image coordinates.
- (NSRect)viewRectForImageRect:(NSRect)rect
{
    NSRect bounds = self.bounds;
    CGFloat sx = NSWidth(_source) > 0 ? NSWidth(bounds) / NSWidth(_source) : 1;
    CGFloat sy = NSHeight(_source) > 0 ? NSHeight(bounds) / NSHeight(_source) : 1;
    return NSMakeRect(NSMinX(bounds) + (NSMinX(rect) - NSMinX(_source)) * sx,
                      NSMinY(bounds) + (NSMinY(rect) - NSMinY(_source)) * sy,
                      NSWidth(rect) * sx, NSHeight(rect) * sy);
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    // Since macOS 14 a view may draw outside its bounds, and the image draws the whole
    // linked page: nothing outside the popup may be drawn (#21).
    NSRectClip(bounds);
    [[NSGraphicsContext currentContext] setShouldAntialias:NO];
    [[NSColor whiteColor] set];
    NSRectFill(bounds);
    [_image drawInRect:bounds fromRect:_source operation:NSCompositingOperationSourceOver fraction:1.0
        respectFlipped:YES hints:nil];
    if (_selection && _pageCount) {
        // The page is always drawn light, so use the light selection color.
        [[NSAppearance appearanceNamed:NSAppearanceNameAqua] performAsCurrentDrawingAppearance:^{
            [[NSColor selectedTextBackgroundColor] set];
        }];
        for (PDFSelection *line in _selection.selectionsByLine)
            for (NSUInteger i = 0; i < _pageCount; i++) {
                NSRect pageRect = [line boundsForPage:_pages[i]];
                if (NSIsEmptyRect(pageRect)) continue;
                NSRect imageRect = NSRectFromCGRect(CGRectApplyAffineTransform(NSRectToCGRect(pageRect), _transforms[i]));
                NSRectFillUsingOperation(NSIntersectionRect(bounds, [self viewRectForImageRect:imageRect]),
                                         NSCompositingOperationMultiply);
            }
    }
    [self drawPageLabelInRect:bounds];
    [[NSColor blackColor] set];
    NSFrameRect(bounds);
}

- (void)drawPageLabelInRect:(NSRect)bounds
{
    if (!self.pageLabel.length) return;
    CGFloat unit = [self unitsPerScreenPoint];
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:TSLinkPreviewLabelFontSize * unit],
                                 NSForegroundColorAttributeName: NSColor.whiteColor};
    NSSize size = [self.pageLabel sizeWithAttributes:attributes];
    CGFloat height = ceil(size.height), radius = height / 2, margin = TSLinkPreviewLabelMargin * unit;
    NSRect capsule = NSMakeRect(NSMaxX(bounds) - margin - ceil(size.width) - 2 * radius, NSMinY(bounds) + margin,
                                ceil(size.width) + 2 * radius, height);
    if (NSWidth(capsule) > NSWidth(bounds) - 2 * margin || NSHeight(capsule) > NSHeight(bounds) - 2 * margin) return;
    [NSGraphicsContext saveGraphicsState];
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];
    [[NSColor colorWithWhite:0.55 alpha:0.8] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:capsule xRadius:radius yRadius:radius] fill];
    [self.pageLabel drawAtPoint:NSMakePoint(NSMinX(capsule) + radius, NSMinY(capsule) + (height - size.height) / 2)
                 withAttributes:attributes];
    [NSGraphicsContext restoreGraphicsState];
}

- (NSView *)hitTest:(NSPoint)point
{
    return self.pinned ? [super hitTest:point] : nil;
}

// Screen points per unit of the superview, which PDFKit magnifies.
- (CGFloat)unitsPerScreenPoint
{
    NSRect unit = [self.superview convertRect:NSMakeRect(0, 0, 1, 1) fromView:nil];
    return NSWidth(unit) > 0 ? NSWidth(unit) : 1;
}

- (NSPoint)locationOfEvent:(NSEvent *)event
{
    return [self.superview convertPoint:event.locationInWindow fromView:nil];
}

- (NSRect)availableRect
{
    return NSInsetRect(self.superview.visibleRect, 5, 5);
}

// The part of a moved popup that stays in view, so that it can be dragged back.
- (NSSize)keptSizeForFrame:(NSRect)frame
{
    CGFloat unit = [self unitsPerScreenPoint];
    return NSMakeSize(MAX(NSWidth(frame) * TSLinkPreviewKeptFraction, TSLinkPreviewKeptMinimum * unit),
                      MAX(NSHeight(frame) * TSLinkPreviewKeptFraction, TSLinkPreviewKeptMinimum * unit));
}

- (void)keepInView
{
    if (!self.superview) return;
    NSRect frame = TSLinkPreviewMove(self.frame, NSZeroSize, [self availableRect], [self keptSizeForFrame:self.frame],
                                     self.superview.isFlipped);
    if (NSEqualRects(frame, self.frame)) return;
    self.frame = frame;
    [self setNeedsDisplay:YES];
}

- (TSLinkPreviewEdge)edgesAtPoint:(NSPoint)point
{
    return TSLinkPreviewEdgeAt(self.frame, point, TSLinkPreviewGrip * [self unitsPerScreenPoint],
                               self.superview.isFlipped);
}

// The page under a point in the superview's coordinates, and the point on that page: the
// page whose rectangle in the image is nearest, so a point in the gap between two pages
// belongs to one of them.
- (PDFPage *)pageAtPoint:(NSPoint)point pagePoint:(NSPoint *)pagePoint
{
    *pagePoint = NSZeroPoint;
    if (!_pageCount) return nil;
    NSPoint local = [self convertPoint:point fromView:self.superview];
    NSRect bounds = self.bounds;
    CGFloat sx = NSWidth(bounds) > 0 ? NSWidth(_source) / NSWidth(bounds) : 1;
    CGFloat sy = NSHeight(bounds) > 0 ? NSHeight(_source) / NSHeight(bounds) : 1;
    CGPoint image = CGPointMake(NSMinX(_source) + (local.x - NSMinX(bounds)) * sx,
                                NSMinY(_source) + (local.y - NSMinY(bounds)) * sy);
    NSUInteger nearest = 0;
    CGFloat distance = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < _pageCount; i++) {
        CGFloat d = MAX(MAX(NSMinY(_pageRects[i]) - image.y, image.y - NSMaxY(_pageRects[i])), 0);
        if (d < distance) { distance = d; nearest = i; }
    }
    *pagePoint = NSPointFromCGPoint(CGPointApplyAffineTransform(image, CGAffineTransformInvert(_transforms[nearest])));
    return _pages[nearest];
}

- (BOOL)selectsText
{
    return _pageCount && !(self.usesHandTool && self.usesHandTool());
}

- (BOOL)isTextOnPage:(PDFPage *)page atPoint:(NSPoint)point
{
    if (!page) return NO;
    PDFSelection *line = [page selectionForLineAtPoint:point];
    if (!line.string.length) return NO;
    NSRect bounds = NSInsetRect([line boundsForPage:page], -TSLinkPreviewLineSlack, -TSLinkPreviewLineSlack);
    return NSPointInRect(point, bounds);
}

- (BOOL)isTextAtPoint:(NSPoint)point
{
    NSPoint pagePoint;
    PDFPage *page = [self pageAtPoint:point pagePoint:&pagePoint];
    return [self isTextOnPage:page atPoint:pagePoint];
}

// The text from where the drag started to `page` and `point`, also across the two pages.
- (PDFSelection *)selectionToPage:(PDFPage *)page point:(NSPoint)point
{
    PDFPage *start = _selectionStartPage;
    if (!start || !page) return nil;
    if (page == start) return [page selectionFromPoint:_selectionStart toPoint:point];
    PDFDocument *document = start.document;
    if (!document || document != page.document) return nil;
    if ([document indexForPage:page] < [document indexForPage:start])
        return [document selectionFromPage:page atPoint:point toPage:start atPoint:_selectionStart];
    return [document selectionFromPage:start atPoint:_selectionStart toPage:page atPoint:point];
}

- (NSCursor *)cursorForEdges:(TSLinkPreviewEdge)edges
{
    if (edges == TSLinkPreviewEdgeNone)
        return _drag == TSLinkPreviewDragMove ? NSCursor.closedHandCursor : NSCursor.openHandCursor;
    if (@available(macOS 15.0, *)) {
        NSCursorFrameResizePosition position = 0;
        if (edges & TSLinkPreviewEdgeTop) position |= NSCursorFrameResizePositionTop;
        if (edges & TSLinkPreviewEdgeBottom) position |= NSCursorFrameResizePositionBottom;
        if (edges & TSLinkPreviewEdgeLeft) position |= NSCursorFrameResizePositionLeft;
        if (edges & TSLinkPreviewEdgeRight) position |= NSCursorFrameResizePositionRight;
        return [NSCursor frameResizeCursorFromPosition:position inDirections:NSCursorFrameResizeDirectionsAll];
    }
    if (edges & (TSLinkPreviewEdgeLeft | TSLinkPreviewEdgeRight)) return NSCursor.resizeLeftRightCursor;
    return NSCursor.resizeUpDownCursor;
}

- (NSCursor *)cursorAtPoint:(NSPoint)point
{
    if (!self.pinned || !self.superview) return nil;
    if (_drag == TSLinkPreviewDragSelect) return NSCursor.IBeamCursor;
    if (_drag != TSLinkPreviewDragNone) return [self cursorForEdges:_dragEdges];
    // A popup moved partly out of the preview has no cursor over its hidden part, which can
    // lie under the toolbar (#14).
    if (!NSPointInRect(point, self.frame) || !NSPointInRect(point, self.superview.visibleRect)) return nil;
    TSLinkPreviewEdge edges = [self edgesAtPoint:point];
    if (edges == TSLinkPreviewEdgeNone && [self selectsText] && [self isTextAtPoint:point])
        return NSCursor.IBeamCursor;
    return [self cursorForEdges:edges];
}

- (void)setSelection:(PDFSelection *)selection
{
    _selection = selection.string.length ? selection : nil;
    self.selectionIsRecent = _selection != nil;
    [self setNeedsDisplay:YES];
}

- (PDFView *)ownerPDFView
{
    for (NSView *owner = self.superview; owner; owner = owner.superview)
        if ([owner isKindOfClass:PDFView.class]) return (PDFView *)owner;
    return nil;
}

// Once the pointer is outside the popup: the preview's tool shows its cursor over the
// preview, and anywhere else, such as over the toolbar, the arrow comes back (#14).
- (void)showCursorOutsideWithEvent:(NSEvent *)event
{
    PDFView *owner = [self ownerPDFView];
    NSPoint point = owner ? [owner convertPoint:event.locationInWindow fromView:nil] : NSZeroPoint;
    // A view that does not clip has a visible rect beyond its bounds, up to the toolbar.
    if (owner && owner.window == event.window && NSPointInRect(point, NSIntersectionRect(owner.bounds, owner.visibleRect))
        && [owner respondsToSelector:@selector(showToolCursorOutsideLinkPreviewWithEvent:)])
        [owner showToolCursorOutsideLinkPreviewWithEvent:event];
    else
        [NSCursor.arrowCursor set];
}

- (void)mouseExited:(NSEvent *)event
{
    // While dragging, the popup has the drag's cursor everywhere until the button is released.
    if (!self.pinned || [self cursorAtPoint:[self locationOfEvent:event]]) return;
    [self showCursorOutsideWithEvent:event];
}

- (void)mouseDown:(NSEvent *)event
{
    // A click makes the popup's preview the active one, so that Copy and the keyboard reach it.
    PDFView *owner = [self ownerPDFView];
    if (owner && self.window.firstResponder != owner) [self.window makeFirstResponder:owner];
    NSPoint point = [self locationOfEvent:event];
    _dragEdges = [self edgesAtPoint:point];
    _dragStart = point;
    _startFrame = self.frame;
    _startSource = _source;
    NSPoint pagePoint;
    PDFPage *page = [self pageAtPoint:point pagePoint:&pagePoint];
    if (_dragEdges != TSLinkPreviewEdgeNone) {
        _drag = TSLinkPreviewDragResize;
    } else if ([self selectsText] && [self isTextOnPage:page atPoint:pagePoint]) {
        _drag = TSLinkPreviewDragSelect;
        _selectionStart = pagePoint;
        _selectionStartPage = page;
        if (event.clickCount == 2) self.selection = [page selectionForWordAtPoint:pagePoint];
        else if (event.clickCount >= 3) self.selection = [page selectionForLineAtPoint:pagePoint];
        else self.selection = nil;
    } else {
        _drag = TSLinkPreviewDragMove;
    }
    [[self cursorAtPoint:point] set];
}

- (void)mouseDragged:(NSEvent *)event
{
    if (_drag == TSLinkPreviewDragNone) return;
    NSPoint point = [self locationOfEvent:event];
    if (_drag == TSLinkPreviewDragSelect) {
        NSPoint pagePoint;
        PDFPage *page = [self pageAtPoint:point pagePoint:&pagePoint];
        self.selection = [self selectionToPage:page point:pagePoint];
        return;
    }
    NSSize delta = NSMakeSize(point.x - _dragStart.x, point.y - _dragStart.y);
    BOOL flipped = self.superview.isFlipped;
    NSRect frame = _startFrame, source = _startSource;
    CGFloat unit = [self unitsPerScreenPoint];
    if (NSEqualSizes(delta, NSZeroSize)) {
        // Back at the starting point: restore it exactly.
    } else if (_drag == TSLinkPreviewDragMove) {
        frame = TSLinkPreviewMove(_startFrame, delta, [self availableRect], [self keptSizeForFrame:frame], flipped);
    } else {
        TSLinkPreviewResize(_startFrame, _startSource, _dragEdges, delta,
                            NSMakeSize(TSLinkPreviewMinimumWidth * unit, TSLinkPreviewMinimumHeight * unit),
                            [self availableRect], _pageSize, flipped, &frame, &source);
    }
    _source = source;
    self.frame = frame;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
    if (_drag == TSLinkPreviewDragNone) return;
    // A click that moved nothing clears the selection, as in the preview.
    if (_drag == TSLinkPreviewDragMove && NSEqualRects(self.frame, _startFrame)) self.selection = nil;
    _drag = TSLinkPreviewDragNone;
    // A drag can end outside the popup, as when its edge stops below the toolbar and the
    // pointer goes on: the drag's cursor must not stay there (#14).
    NSCursor *cursor = [self cursorAtPoint:[self locationOfEvent:event]];
    if (cursor) [cursor set];
    else [self showCursorOutsideWithEvent:event];
}

// Scrolls only the popup's page: the preview underneath stays where it is.
- (void)scrollWheel:(NSEvent *)event
{
    if (!self.pinned) return;
    CGFloat dx = event.scrollingDeltaX, dy = event.scrollingDeltaY;
    if (!event.hasPreciseScrollingDeltas) {
        dx *= TSLinkPreviewLineScroll;
        dy *= TSLinkPreviewLineScroll;
    }
    CGFloat scale = NSWidth(_source) > 0 ? NSWidth(self.frame) / NSWidth(_source) : 1;
    CGFloat factor = [self unitsPerScreenPoint] / scale;
    // Positive deltas move content right and down, as in a scroll view.
    _source = TSLinkPreviewPan(_source, NSMakeSize(dx * factor, -dy * factor), _pageSize);
    [self setNeedsDisplay:YES];
}

@end

static NSString *(*TSPageViewToolTip)(id, SEL, NSView *, NSToolTipTag, NSPoint, void *);

// The tool tip is left out only for the link annotation under `point`, found through the
// PDFView, and only when PDFKit's user data is that very annotation. The user data is never
// dereferenced, so a change in what PDFKit passes there falls back to its own tool tip.
static NSString *TSFilteredPageViewToolTip(NSView *self, SEL selector, NSView *view, NSToolTipTag tag,
                                           NSPoint point, void *data)
{
    PDFView *pdfView = nil;
    for (NSView *ancestor = self.superview; ancestor && !pdfView; ancestor = ancestor.superview)
        if ([ancestor isKindOfClass:PDFView.class]) pdfView = (PDFView *)ancestor;
    if (data && view && [pdfView respondsToSelector:@selector(showsLinkPreviewForAnnotation:)]) {
        NSPoint location = [pdfView convertPoint:point fromView:view];
        PDFPage *page = [pdfView pageForPoint:location nearest:NO];
        PDFAnnotation *annotation = page ? [page annotationAtPoint:[pdfView convertPoint:location toPage:page]] : nil;
        if (annotation && (__bridge void *)annotation == data && [pdfView showsLinkPreviewForAnnotation:annotation])
            return nil;
    }
    return TSPageViewToolTip(self, selector, view, tag, point, data);
}

BOOL TSLinkPreviewInstallToolTipFilter(void)
{
    static BOOL installed;
    if (installed) return YES;
    Class pageView = NSClassFromString(@"PDFPageView");
    SEL selector = @selector(view:stringForToolTip:point:userData:);
    struct objc_method_description owner =
        protocol_getMethodDescription(@protocol(NSViewToolTipOwner), selector, YES, YES);
    if (!pageView || ![pageView isSubclassOfClass:NSView.class] || !owner.types) return NO;
    // Replace only the page view's own method, never one it inherits.
    unsigned count = 0;
    Method *methods = class_copyMethodList(pageView, &count), found = NULL;
    for (unsigned i = 0; i < count; i++)
        if (method_getName(methods[i]) == selector) found = methods[i];
    free(methods);
    if (!found || strcmp(method_getTypeEncoding(found), owner.types) != 0) return NO;
    TSPageViewToolTip = (NSString *(*)(id, SEL, NSView *, NSToolTipTag, NSPoint, void *))
        method_setImplementation(found, (IMP)TSFilteredPageViewToolTip);
    installed = YES;
    return YES;
}
