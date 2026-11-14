// TSSplitToggleCue.h
//
// The Split Source and Split Preview toolbar buttons show a window split top and
// bottom. While Option is held with the pointer over the button of a window that is
// not split, the button shows the side-by-side split that a click then makes.

#import <Cocoa/Cocoa.h>

// Option splits side by side, with or without Shift. Command and Control belong to
// dragging toolbar items and to the toolbar's contextual menu.
static inline BOOL TSSplitToggleOptionHeld(NSEventModifierFlags flags)
{
    return (flags & NSEventModifierFlagOption) != 0 &&
           (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) == 0;
}

// In a split window the button unsplits, whatever the modifiers.
static inline BOOL TSSplitToggleShowsSideBySide(NSEventModifierFlags flags, BOOL windowIsSplit, BOOL pointerOverButton)
{
    return TSSplitToggleOptionHeld(flags) && !windowIsSplit && pointerOverButton;
}

// Two parts side by side: the button's own symbol, rectangle.split.1x2, divided the
// other way. Both are SF symbols of the same size, so the toolbar draws them alike on
// every system and neither the button nor the toolbar changes its size.
static NSString * const TSSplitToggleSideBySideSymbolName = @"rectangle.split.2x1";

static inline NSImage *TSSplitToggleSideBySideImage(NSImage *image)
{
    return [NSImage imageWithSystemSymbolName:TSSplitToggleSideBySideSymbolName
                     accessibilityDescription:image.accessibilityDescription];
}

// AppKit draws an image toolbar item with a button that carries the item's target
// and action.
static NSButton *TSSplitToggleButtonInView(NSView *view, NSToolbarItem *item)
{
    if ([view isKindOfClass:[NSButton class]] && ((NSButton *)view).action == item.action &&
        ((NSButton *)view).target == item.target)
        return (NSButton *)view;
    for (NSView *subview in view.subviews) {
        NSButton *button = TSSplitToggleButtonInView(subview, item);
        if (button)
            return button;
    }
    return nil;
}

// YES when the point, in the window's coordinates, is on the item's button and
// nothing covers the button there.
static inline BOOL TSSplitTogglePointOnItem(NSWindow *window, NSToolbarItem *item, NSPoint point)
{
    NSView *frameView = window.contentView.superview;
    if (!frameView || !item.action)
        return NO;
    NSView *hit = [frameView hitTest: frameView.superview ? [frameView.superview convertPoint:point fromView:nil] : point];
    NSButton *button = TSSplitToggleButtonInView(frameView, item);
    if (!hit || !button || button.hiddenOrHasHiddenAncestor)
        return NO;
    if (!([button isDescendantOf:hit] || [hit isDescendantOf:button]))
        return NO;
    return NSPointInRect([button convertPoint:point fromView:nil], button.bounds);
}
