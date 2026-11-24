#import "TSLinkPreviewView.h"
#import "TSLinkPreviewGeometry.h"
#import "TSDocumentWindowGlass.h"
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
// The page label in the lower right: white bold text on a gray capsule. Eleven points on
// screen at 100% and above, the size of a popup opened at the current magnification. Below
// 100% that size is larger, in page points, than the label drawn at 100%, and it then covers
// the page or is dropped, so the label is never larger than it is at 100% (#14).
static const CGFloat TSLinkPreviewLabelFontSize = 11;
// A long label is not shrunk below this on screen. Anything smaller is a gray speck,
// so the label is left out instead (#14).
static const CGFloat TSLinkPreviewLabelMinimumScreenSize = 6;
static const CGFloat TSLinkPreviewLabelMargin = 3;
// The popup's corners, in page points, so they grow and shrink with the page in the popup.
static const CGFloat TSLinkPreviewCornerRadius = 6;
// The black edge, in page points, so it grows and shrinks with the page. One page point
// looked heavy; this is a little thinner, and it stays at least one pixel wide on screen (#14).
static const CGFloat TSLinkPreviewEdgeWidth = 0.75;
// A popup shows its linked page and, in the continuous displays, the next one (#14).
#define TSLinkPreviewMaximumPages 2

// Samples along each rounded corner of the edge, for the room of the page label.
#define TSLinkPreviewCornerSamples 48

// How far a page label capsule of `capsuleSize`, `inset.x` in from the right and `inset.y`
// up from the bottom of a popup of `size`, stays inside the black edge of width `edge`,
// measured to the inner side of the edge. A popup lower or narrower than its corners has
// elliptical corners: AppKit limits each radius of a rounded rectangle to half its side,
// for the clip and the edge alike. The edge is stroked along the rectangle `edge / 2`
// inside the popup, so the inner side of the edge is `edge / 2` inside that line. The
// capsule is a bar between the centers of its two half circles, widened by its radius (#14).
static CGFloat TSLinkPreviewLabelClearance(NSSize size, CGFloat edge, NSSize capsuleSize, NSPoint inset)
{
    CGFloat w = size.width, h = size.height, r = capsuleSize.height / 2;
    CGFloat cy = inset.y + r, x0 = w - inset.x - capsuleSize.width + r, x1 = w - inset.x - r;
    // The straight sides.
    CGFloat least = MIN(MIN(inset.x - edge, inset.y - edge),
                        MIN(h - edge - inset.y - capsuleSize.height, w - edge - inset.x - capsuleSize.width));
    // The corners of the line the edge is stroked along.
    CGFloat line = MAX(TSLinkPreviewCornerRadius - edge / 2, 0);
    CGFloat rx = MIN(line, (w - edge) / 2), ry = MIN(line, (h - edge) / 2);
    if (!(rx > 0) || !(ry > 0)) return least;
    CGFloat lo = edge / 2, cxs[2] = {lo + rx, w - lo - rx}, cys[2] = {lo + ry, h - lo - ry};
    for (NSInteger corner = 0; corner < 4; corner++) {
        CGFloat ccx = cxs[corner & 1], ccy = cys[corner >> 1];
        CGFloat sx = (corner & 1) ? 1 : -1, sy = (corner >> 1) ? 1 : -1;
        for (NSInteger i = 0; i <= TSLinkPreviewCornerSamples; i++) {
            CGFloat t = (CGFloat)M_PI_2 * i / TSLinkPreviewCornerSamples;
            CGFloat bx = ccx + sx * rx * cos(t), by = ccy + sy * ry * sin(t);
            CGFloat nearX = MIN(MAX(bx, x0), x1);
            least = MIN(least, hypot(bx - nearX, by - cy) - r - edge / 2);
        }
    }
    return least;
}

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
    // The preview whose magnification the popup follows.
    __weak PDFView *_magnifiedView;
    id _scaleObserver;
    // The page the popup lies on and its frame in that page's space, while the pages move.
    PDFPage *_placePage;
    NSRect _placeOnPage;
    // The popup was brought into view because its page was no longer shown; _placePage and
    // _placeOnPage still hold the place it goes back to once its page is shown again (#35).
    BOOL _awayFromPlace;
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

- (void)dealloc
{
    if (_scaleObserver) [NSNotificationCenter.defaultCenter removeObserver:_scaleObserver];
}

// When the magnification changes, AppKit magnifies what the popup drew before and does not
// draw it again: its page would be blurred, and its edge and page label would keep the
// earlier magnification. So the popup draws itself again for the preview it is in (#14).
- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    PDFView *preview = nil;
    for (NSView *view = self.superview; view && !preview; view = view.superview)
        if ([view isKindOfClass:[PDFView class]]) preview = (PDFView *)view;
    if (preview == _magnifiedView && (_scaleObserver || !preview)) return;
    if (_scaleObserver) [NSNotificationCenter.defaultCenter removeObserver:_scaleObserver];
    _scaleObserver = nil;
    _magnifiedView = preview;
    if (!preview) return;
    __weak TSLinkPreviewView *weakSelf = self;
    _scaleObserver = [NSNotificationCenter.defaultCenter addObserverForName:PDFViewScaleChangedNotification
        object:preview queue:nil usingBlock:^(NSNotification *note) {
            [weakSelf setNeedsDisplay:YES];
        }];
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
    CGFloat radius = TSLinkPreviewCornerRadius;
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];
    [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius] addClip];
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
    // A thin black edge that sets the page apart from the light page under it (#14).
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];
    CGFloat width = MAX(TSLinkPreviewEdgeWidth, [self unitsPerPixel]);
    NSBezierPath *edge = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, width / 2, width / 2)
                                                         xRadius:MAX(radius - width / 2, 0) yRadius:MAX(radius - width / 2, 0)];
    edge.lineWidth = width;
    [[NSColor blackColor] setStroke];
    [edge stroke];
}

- (void)drawPageLabelInRect:(NSRect)bounds
{
    if (!self.pageLabel.length) return;
    // `scale` is one screen point, in page points, and never more than one page point.
    // Above 100% the label stays eleven points on screen. Below 100% it stays the size it
    // has at 100%, which still fits a short popup near the bottom of the page (#14).
    CGFloat unit = [self unitsPerScreenPoint];
    CGFloat scale = MIN(unit, 1);
    CGFloat fontSize = TSLinkPreviewLabelFontSize * scale;
    // Six points on screen, and never above the size before shrinking. Below about 55%
    // that size is already under six points, so the label is shown as it is or left out.
    CGFloat fontFloor = MIN(fontSize, TSLinkPreviewLabelMinimumScreenSize * unit);
    CGFloat margin = TSLinkPreviewLabelMargin * scale;
    // The corners and the edge are in page points, so they grow on screen. The capsule
    // keeps the margin clear inside the edge, also along the rounded corners, and otherwise
    // goes as far into the lower right corner as that allows (#14).
    CGFloat edge = MAX(TSLinkPreviewEdgeWidth, [self unitsPerPixel]);
    CGFloat clear = edge + margin;
    CGFloat inset = clear, insetX = clear;
    CGFloat roomW = NSWidth(bounds) - 2 * inset, roomH = NSHeight(bounds) - 2 * inset;
    BOOL placed = NO;
    // The capsule is never nearer the edge than `clear`. A fraction of a page point is many
    // screen points at a high magnification. Reject only a room that is not there; the
    // six-point floor decides whether the label fits.
    if (!(roomW > 0) || !(roomH > 0)) return;
    NSSize size = NSZeroSize;
    CGFloat height = 0, radius = 0, drawn = 1;
    NSRect capsule = NSZeroRect;
    // One page point is many screen points at a high magnification. Round the capsule to
    // screen pixels, or the round-up itself makes the label larger than the one at 100% (#14).
    CGFloat px = [self unitsPerPixel];
    if (!(px > 0)) px = 1;
    // A short popup can still be too low for the 100% label once the corner is left clear.
    // Shrink the type to the room instead of dropping the page information.
    for (NSInteger attempt = 0; attempt < 12; attempt++) {
        // The metrics of a fraction of a point do not stay in proportion, so measure the
        // eleven-point font and scale that to the size being drawn.
        NSSize sample = [self.pageLabel sizeWithAttributes:@{NSFontAttributeName:
                         [NSFont boldSystemFontOfSize:TSLinkPreviewLabelFontSize]}];
        drawn = fontSize / TSLinkPreviewLabelFontSize;
        size = NSMakeSize(sample.width * drawn, sample.height * drawn);
        height = ceil(size.height / px) * px;
        CGFloat textWidth = ceil(size.width / px) * px;
        radius = height / 2;
        // Move the capsule in from the corner along the diagonal, in steps of a pixel, to
        // the first place that keeps the margin inside the edge, then to within a hundredth
        // of a pixel. A popup lower than its corners has a curve all along its right side,
        // so the capsule stops at the middle of the height and goes on to the left; likewise
        // it stops at the middle of the width of a narrow popup. Once it is a corner radius in
        // from the right and the bottom, the corners there no longer limit it (#14).
        NSSize capsuleSize = NSMakeSize(textWidth + height, height);
        CGFloat middleX = MAX((NSWidth(bounds) - capsuleSize.width) / 2, clear);
        CGFloat middleY = MAX((NSHeight(bounds) - capsuleSize.height) / 2, clear);
        CGFloat step = MAX(px, TSLinkPreviewCornerRadius / 256);
        CGFloat farthest = MIN(clear + TSLinkPreviewCornerRadius, MAX(middleX, middleY));
        CGFloat (^room)(CGFloat) = ^CGFloat(CGFloat along) {
            return TSLinkPreviewLabelClearance(bounds.size, edge, capsuleSize,
                                               NSMakePoint(MIN(along, middleX), MIN(along, middleY)));
        };
        // The last step ends at `farthest` itself, however little is left for it (#14).
        NSInteger steps = (NSInteger)ceil((farthest - clear) / step);
        CGFloat last = clear, best = -CGFLOAT_MAX, bestAlong = clear, found = -1, before = clear;
        for (NSInteger i = 0; i <= steps; i++) {
            CGFloat along = MIN(clear + i * step, farthest);
            CGFloat here = room(along);
            if (here >= margin) { found = along; before = MIN(last, along); break; }
            if (here > best) { best = here; bestAlong = along; }
            last = along;
        }
        // The room grows and then shrinks along the way, so it can be enough only between two
        // steps. Look for its top between the neighbors of the best step tried (#14).
        if (found < 0) {
            CGFloat low = MAX(clear, bestAlong - step), high = MIN(last, bestAlong + step);
            for (NSInteger third = 0; third < 40 && high - low > px / 100; third++) {
                CGFloat a = low + (high - low) / 3, b = high - (high - low) / 3;
                if (room(a) < room(b)) low = a; else high = b;
            }
            CGFloat top = (low + high) / 2;
            if (room(top) >= margin) {
                found = top;
                before = MAX(clear, bestAlong - step);
            }
        }
        placed = found >= 0;
        if (placed) {
            // Back toward the corner, to the first place with room.
            for (NSInteger halve = 0; found - before > px / 100 && halve < 20; halve++) {
                CGFloat middle = (before + found) / 2;
                if (room(middle) >= margin) found = middle;
                else before = middle;
            }
            insetX = MIN(found, middleX);
            inset = MIN(found, middleY);
        }
        capsule = NSMakeRect(NSMaxX(bounds) - insetX - capsuleSize.width, NSMinY(bounds) + inset,
                             capsuleSize.width, capsuleSize.height);
        if (placed) break;
        // A step that barely misses stalls on the rounded line height, so drop by a tenth
        // then. Otherwise try the size that was measured to fit, and stop at the floor.
        CGFloat fit = MIN(roomW / NSWidth(capsule), roomH / NSHeight(capsule));
        CGFloat next = fontSize * fit;
        if (!(next < fontSize * (CGFloat)0.99)) next = fontSize * (CGFloat)0.9;
        if (!(next > 0) || !(next < fontSize)) return;
        if (next < fontFloor) {
            if (!(fontSize > fontFloor)) return;
            next = fontFloor;
        }
        fontSize = next;
    }
    if (!placed) return;
    [NSGraphicsContext saveGraphicsState];
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];
    [[NSColor colorWithWhite:0.55 alpha:0.8] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:capsule xRadius:radius yRadius:radius] fill];
    // Draw the eleven-point font at `drawn`, so the glyphs match the measured capsule.
    NSAffineTransform *glyph = [NSAffineTransform transform];
    [glyph translateXBy:NSMinX(capsule) + radius yBy:NSMinY(capsule) + (height - size.height) / 2];
    [glyph scaleBy:drawn];
    [glyph concat];
    [self.pageLabel drawAtPoint:NSZeroPoint withAttributes:@{NSFontAttributeName:
        [NSFont boldSystemFontOfSize:TSLinkPreviewLabelFontSize],
        NSForegroundColorAttributeName: NSColor.whiteColor}];
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

// Units of the superview in one pixel of the screen.
- (CGFloat)unitsPerPixel
{
    CGFloat backing = self.window.backingScaleFactor;
    return [self unitsPerScreenPoint] / (backing > 0 ? backing : 1);
}

- (NSPoint)locationOfEvent:(NSEvent *)event
{
    return [self.superview convertPoint:event.locationInWindow fromView:nil];
}

// The part of the preview's pages that can be seen. On macOS 26 and later the pages run
// under the title bar and the toolbar; what lies under them does not count (#44).
- (NSRect)visibleRectOfPreview
{
    return TSDocumentWindowRectBelowToolbar(self.superview, self.superview.visibleRect);
}

- (NSRect)availableRect
{
    return NSInsetRect([self visibleRectOfPreview], 5, 5);
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

- (void)rememberPlaceOnPage
{
    PDFView *preview = [self ownerPDFView];
    // Away from its place, the popup keeps the place it had, until it goes back there.
    if (_awayFromPlace && _placePage && _placePage.document == preview.document) return;
    _awayFromPlace = NO;
    _placePage = nil;
    NSView *documentView = self.superview;
    if (!preview || !documentView || !preview.document) return;
    NSRect frame = [preview convertRect:self.frame fromView:documentView];
    NSPoint corner = NSMakePoint(NSMinX(frame), preview.isFlipped ? NSMinY(frame) : NSMaxY(frame));
    PDFPage *page = [preview pageForPoint:corner nearest:YES];
    if (!page) return;
    _placePage = page;
    _placeOnPage = [preview convertRect:frame toPage:page];
}

- (BOOL)returnToPlaceOnPage
{
    PDFPage *page = _placePage;
    _placePage = nil;
    _awayFromPlace = NO;
    PDFView *preview = [self ownerPDFView];
    NSView *documentView = self.superview;
    if (!page || !preview || !documentView || page.document != preview.document) return NO;
    // The continuous displays lay out every page; the others only the pages they show. A
    // popup whose page is not shown keeps its place for when the page is shown again.
    PDFDisplayMode mode = preview.displayMode;
    if (mode != kPDFDisplaySinglePageContinuous && mode != kPDFDisplayTwoUpContinuous
        && ![preview.visiblePages containsObject:page]) {
        _placePage = page;
        _awayFromPlace = YES;
        return NO;
    }
    NSRect frame = [documentView convertRect:[preview convertRect:_placeOnPage fromPage:page] fromView:preview];
    if (!isfinite(NSMinX(frame)) || !isfinite(NSMinY(frame)) || !isfinite(NSWidth(frame)) || !isfinite(NSHeight(frame))
        || NSWidth(frame) <= 0 || NSHeight(frame) <= 0) return NO;
    if (!NSEqualRects(frame, self.frame)) {
        self.frame = frame;
        [self setNeedsDisplay:YES];
    }
    return YES;
}

- (TSLinkPreviewView *)copyWithFrame:(NSRect)frame
{
    TSLinkPreviewView *copy = [[TSLinkPreviewView alloc] initWithFrame:frame image:_image source:_source
                                                               pageSize:_pageSize pages:@[] pageRects:NULL];
    for (NSUInteger i = 0; i < _pageCount; i++) {
        copy->_pages[i] = _pages[i];
        copy->_pageRects[i] = _pageRects[i];
        copy->_transforms[i] = _transforms[i];
    }
    copy->_pageCount = _pageCount;
    copy->_selection = _selection;
    copy.pageLabel = self.pageLabel;
    return copy;
}

- (void)encodeContentWithCoder:(NSCoder *)coder prefix:(NSString *)prefix
{
    PDFDocument *document = _pageCount ? _pages[0].document : nil;
    if (!document) return;
    NSMutableArray<NSNumber *> *indices = [NSMutableArray array];
    for (NSUInteger i = 0; i < _pageCount; i++) {
        NSUInteger index = [document indexForPage:_pages[i]];
        if (index == NSNotFound) return;
        [indices addObject:@(index)];
    }
    [coder encodeObject:indices forKey:[prefix stringByAppendingString:@"Pages"]];
    // The part in view, from the corner of the page it shows most of: the linked page, or the next
    // one when it was scrolled there. That keeps it when the next page is gone or the pages change
    // size; the size of the whole image tells whether they did.
    NSUInteger anchor = 0;
    CGFloat nearest = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < _pageCount; i++) {
        CGFloat shared = NSWidth(NSIntersectionRect(_source, _pageRects[i])) * NSHeight(NSIntersectionRect(_source, _pageRects[i]));
        CGFloat distance = shared > 0 ? -shared
            : hypot(MAX(MAX(NSMinX(_pageRects[i]) - NSMidX(_source), NSMidX(_source) - NSMaxX(_pageRects[i])), 0),
                    MAX(MAX(NSMinY(_pageRects[i]) - NSMidY(_source), NSMidY(_source) - NSMaxY(_pageRects[i])), 0));
        if (distance < nearest) {
            nearest = distance;
            anchor = i;
        }
    }
    [coder encodeInteger:(NSInteger)anchor forKey:[prefix stringByAppendingString:@"SourcePage"]];
    [coder encodeRect:NSOffsetRect(_source, -NSMinX(_pageRects[anchor]), -NSMinY(_pageRects[anchor]))
               forKey:[prefix stringByAppendingString:@"SourceOnPage"]];
    // The size of each page, which tells whether the pages changed: the whole image can keep its
    // size when only one of them does.
    for (NSUInteger i = 0; i < _pageCount; i++)
        [coder encodeSize:_pageRects[i].size forKey:[prefix stringByAppendingFormat:@"PageSize%lu", (unsigned long)i]];
    // Whether the part in view lay within that page from top to bottom, or went on across the gap;
    // then its height is kept from the gap, the top of the next page, which it straddles.
    BOOL within = NSMinY(_source) >= NSMinY(_pageRects[anchor]) - 0.5 && NSMaxY(_source) <= NSMaxY(_pageRects[anchor]) + 0.5;
    [coder encodeBool:within forKey:[prefix stringByAppendingString:@"SourceWithinPage"]];
    if (!within && _pageCount == 2)
        [coder encodeDouble:NSMinY(_source) - NSMaxY(_pageRects[1]) forKey:[prefix stringByAppendingString:@"SourceFromGap"]];
    if (self.pageLabel)
        [coder encodeObject:self.pageLabel forKey:[prefix stringByAppendingString:@"Label"]];
}

// The part in view moved, and if needed made smaller keeping its proportions, to lie within
// `bounds`: the popup then shows its text and figures as before, never stretched.
static NSRect TSLinkPreviewFitSource(NSRect source, NSRect bounds)
{
    if (!(NSWidth(source) > 0 && NSHeight(source) > 0 && NSWidth(bounds) > 0 && NSHeight(bounds) > 0)) return NSZeroRect;
    CGFloat scale = MIN(1, MIN(NSWidth(bounds) / NSWidth(source), NSHeight(bounds) / NSHeight(source)));
    NSSize part = NSMakeSize(NSWidth(source) * scale, NSHeight(source) * scale);
    CGFloat x = MIN(MAX(NSMinX(source), NSMinX(bounds)), NSMaxX(bounds) - part.width);
    CGFloat y = MIN(MAX(NSMinY(source), NSMinY(bounds)), NSMaxY(bounds) - part.height);
    return NSMakeRect(x, y, part.width, part.height);
}

+ (TSLinkPreviewView *)linkPreviewWithCoder:(NSCoder *)coder prefix:(NSString *)prefix
                                    document:(PDFDocument *)document frame:(NSRect)frame
{
    NSArray *indices = [coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [NSNumber class], nil]
                                             forKey:[prefix stringByAppendingString:@"Pages"]];
    if (![indices isKindOfClass:[NSArray class]] || indices.count < 1 || indices.count > TSLinkPreviewMaximumPages)
        return nil;
    NSMutableArray<PDFPage *> *pages = [NSMutableArray array];
    NSSize sizes[TSLinkPreviewMaximumPages];
    for (id index in indices) {
        BOOL there = [index isKindOfClass:[NSNumber class]] && [index integerValue] >= 0
            && (NSUInteger)[index integerValue] < document.pageCount;
        // Without the linked page there is nothing to show; without the next one, the linked
        // page is shown alone, as when a popup first appears at the end of the PDF.
        if (!there) {
            if (pages.count == 0) return nil;
            break;
        }
        PDFPage *page = [document pageAtIndex:[index integerValue]];
        CGAffineTransform transform;
        if (!TSLinkPreviewPageGeometry(page, &sizes[pages.count], &transform)) {
            if (pages.count == 0) return nil;
            break;
        }
        [pages addObject:page];
    }
    // Drawn as when the popup first appeared: the linked page, or it above the next one.
    NSRect rects[TSLinkPreviewMaximumPages] = {NSZeroRect, NSZeroRect};
    NSSize size;
    NSImage *image;
    if (pages.count == 2) {
        size = TSLinkPreviewStrip(sizes[0], sizes[1], &rects[0], &rects[1]);
        image = TSLinkPreviewStripImage(pages, rects, size);
    } else {
        size = sizes[0];
        rects[0] = NSMakeRect(0, 0, size.width, size.height);
        image = TSLinkPreviewImage(pages[0], size);
    }
    NSRect onPage = [coder decodeRectForKey:[prefix stringByAppendingString:@"SourceOnPage"]];
    NSInteger anchor = [coder decodeIntegerForKey:[prefix stringByAppendingString:@"SourcePage"]];
    // Without the next page, the part in view goes onto the linked page.
    if (anchor < 0 || (NSUInteger)anchor >= pages.count) anchor = 0;
    NSRect source = NSOffsetRect(onPage, NSMinX(rects[anchor]), NSMinY(rects[anchor]));
    BOOL same = pages.count == indices.count;
    for (NSUInteger i = 0; same && i < pages.count; i++) {
        NSString *key = [prefix stringByAppendingFormat:@"PageSize%lu", (unsigned long)i];
        same = [coder containsValueForKey:key] && NSEqualSizes([coder decodeSizeForKey:key], rects[i].size);
    }
    NSRect bounds;
    if (same)
        // The same pages: the part in view is the one shown before, wherever it was scrolled to.
        bounds = NSMakeRect(0, 0, size.width, size.height);
    else if ([coder decodeBoolForKey:[prefix stringByAppendingString:@"SourceWithinPage"]])
        // Pages of another size: on the page it showed, which in the strip may be narrower or lower
        // than the other one and lie beside gray margins.
        bounds = rects[anchor];
    else {
        // A part that went on across the gap: across the width of its page, down the whole strip,
        // still straddling the gap.
        bounds = NSMakeRect(NSMinX(rects[anchor]), 0, NSWidth(rects[anchor]), size.height);
        NSString *gap = [prefix stringByAppendingString:@"SourceFromGap"];
        if (pages.count == 2 && [coder containsValueForKey:gap])
            source.origin.y = NSMaxY(rects[1]) + [coder decodeDoubleForKey:gap];
    }
    source = TSLinkPreviewFitSource(source, bounds);
    if (!image || NSIsEmptyRect(source)) return nil;
    TSLinkPreviewView *preview = [[self alloc] initWithFrame:frame image:image source:source pageSize:size
                                                       pages:pages pageRects:rects];
    preview.pageLabel = [coder decodeObjectOfClass:[NSString class] forKey:[prefix stringByAppendingString:@"Label"]];
    return preview;
}

- (PDFPage *)awayPlaceOnPage:(NSRect *)rect
{
    if (!_awayFromPlace || !_placePage) return nil;
    if (rect) *rect = _placeOnPage;
    return _placePage;
}

- (void)setAwayPlaceOnPage:(PDFPage *)page rect:(NSRect)rect
{
    _placePage = page;
    _placeOnPage = rect;
    _awayFromPlace = page != nil;
}

- (BOOL)returnToPlaceIfAway
{
    return _awayFromPlace && [self returnToPlaceOnPage];
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
    if (!NSPointInRect(point, self.frame) || !NSPointInRect(point, [self visibleRectOfPreview])) return nil;
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
    // A view that does not clip has a visible rect beyond its bounds, up to the toolbar, and
    // on macOS 26 and later the preview itself runs under the toolbar (#44).
    if (owner && owner.window == event.window && NSPointInRect(point, NSIntersectionRect(owner.bounds, owner.visibleRect))
        && !TSDocumentWindowPointIsUnderToolbar(event.window, event.locationInWindow)
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
    // Moved or resized by hand: where it is now is its place. A drag held at an edge, which
    // changes nothing, leaves the place it is away from.
    if (!NSEqualRects(frame, self.frame) || !NSEqualRects(source, _source)) _awayFromPlace = NO;
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
    // Its place, size and the part in view are kept for the next launch of TeXShop (#71).
    [self.window invalidateRestorableState];
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
    [self.window invalidateRestorableState];
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
