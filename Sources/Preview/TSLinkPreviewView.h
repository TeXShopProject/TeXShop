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

// The cursor for a point in the superview's coordinates, or nil outside a pinned popup.
- (NSCursor *)cursorAtPoint:(NSPoint)point;

@end
