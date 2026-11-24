#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>

// The popup that shows the target of an internal link. Once pinned, it can be moved
// by dragging, resized from its edges and corners, and its page scrolled; until then
// it ignores the mouse so that hovering works as before. With any tool but the hand,
// dragging over text in a pinned popup selects it, as in the preview.
@interface TSLinkPreviewView : NSView

// `transform` maps page space to the image, whose size is `pageSize`.
- (instancetype)initWithFrame:(NSRect)frame image:(NSImage *)image source:(NSRect)source
                     pageSize:(NSSize)pageSize page:(PDFPage *)page
                    transform:(CGAffineTransform)transform;
// An image of one or two pages, such as a page and the next one below it (#14). Each page
// occupies its rectangle in the image, whose size is `pageSize`.
- (instancetype)initWithFrame:(NSRect)frame image:(NSImage *)image source:(NSRect)source
                     pageSize:(NSSize)pageSize pages:(NSArray<PDFPage *> *)pages
                    pageRects:(const NSRect *)pageRects;

@property (nonatomic) BOOL pinned;
@property (readonly) NSRect source;
// Whether the preview's tool is the hand; with the hand, dragging always moves the popup.
@property (copy) BOOL (^usesHandTool)(void);
@property (readonly) PDFSelection *selection;
// Set when text is selected in the popup; the preview clears it when it is clicked.
@property BOOL selectionIsRecent;

// Shown in the lower right corner at a fixed size on screen, such as "Page 12" with the
// page's label (#17).
@property (copy, nonatomic) NSString *pageLabel;

// The cursor for a point in the superview's coordinates, or nil outside the part of a pinned
// popup that is in view.
- (NSCursor *)cursorAtPoint:(NSPoint)point;
// Moves the popup back into view as far as dragging it would allow, keeping its size.
- (void)keepInView;
// A popup lies on a page of its preview, as the text there does: it grows and shrinks with
// the page and scrolls with it. A new display format or arrangement of the pages puts the
// pages elsewhere; the popup remembers its place on the page under its upper left corner
// before, and goes back to it after. It returns NO, and stays where it is, when that page is
// no longer shown, as in Single Page display showing another page (#56).
- (void)rememberPlaceOnPage;
// Another popup showing the same pages, selection and label, for another preview; the
// caller places and pins it (#66).
- (TSLinkPreviewView *)copyWithFrame:(NSRect)frame;
- (BOOL)returnToPlaceOnPage;
- (BOOL)returnToPlaceIfAway;
// What the popup shows, kept for the next launch of TeXShop (#71): its pages, the part of them
// in view and its label, under keys starting with prefix.
- (void)encodeContentWithCoder:(NSCoder *)coder prefix:(NSString *)prefix;
// A popup showing the same part of the same pages of document, drawn again: the linked page alone
// when the next one is gone, and the part in view moved and kept in proportion when the pages
// changed size. nil when the coder holds none or the linked page is no longer there.
+ (TSLinkPreviewView *)linkPreviewWithCoder:(NSCoder *)coder prefix:(NSString *)prefix
                                    document:(PDFDocument *)document frame:(NSRect)frame;
// While the popup is away from its place because its page is not shown (#35), the page and the
// rectangle on it it goes back to; nil otherwise. Kept for the next launch of TeXShop (#71).
- (PDFPage *)awayPlaceOnPage:(NSRect *)rect;
- (void)setAwayPlaceOnPage:(PDFPage *)page rect:(NSRect)rect;

@end

// PDFKit shows "Go to page n", with the page's index, as a tool tip over a link. Once this
// is installed, a PDFView that implements -showsLinkPreviewForAnnotation: and returns YES
// for the link under the pointer gets no such tool tip, since its popup shows the target and
// its page label (#17). Without the private class or method it relies on, or when PDFKit
// passes something other than that link, tool tips stay as they are.
@interface PDFView (TSLinkPreviewToolTips)
- (BOOL)showsLinkPreviewForAnnotation:(PDFAnnotation *)annotation;
@end
BOOL TSLinkPreviewInstallToolTipFilter(void);

// A PDFView that implements this shows its tool's cursor for the event's location when the
// pointer has left its pinned popup, also when a drag of the popup ends outside it.
@interface PDFView (TSLinkPreviewCursor)
- (void)showToolCursorOutsideLinkPreviewWithEvent:(NSEvent *)event;
@end
