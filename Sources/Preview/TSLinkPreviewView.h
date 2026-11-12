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
