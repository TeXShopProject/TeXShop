#import <Cocoa/Cocoa.h>

// The popup that shows the target of an internal link. Once pinned, it can be moved
// by dragging, resized from its edges and corners, and its page scrolled; until then
// it ignores the mouse so that hovering works as before.
@interface TSLinkPreviewView : NSView

- (instancetype)initWithFrame:(NSRect)frame image:(NSImage *)image source:(NSRect)source
                     pageSize:(NSSize)pageSize;

@property (nonatomic) BOOL pinned;
@property (readonly) NSRect source;

// The cursor for a point in the superview's coordinates, or nil outside a pinned popup.
- (NSCursor *)cursorAtPoint:(NSPoint)point;

@end
