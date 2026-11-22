// TSSplitToggleCue.h
//
// The Split Source and Split Preview toolbar buttons show a window split top and
// bottom. While Option is held in a window that is not split, wherever the pointer
// is, the buttons show the side-by-side split that a click then makes. In a split
// window the button shows how the window is split.

#import <Cocoa/Cocoa.h>

// Option splits side by side, with or without Shift. Command and Control belong to
// dragging toolbar items and to the toolbar's contextual menu.
static inline BOOL TSSplitToggleOptionHeld(NSEventModifierFlags flags)
{
    return (flags & NSEventModifierFlagOption) != 0 &&
           (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) == 0;
}

// In a split window the button unsplits, whatever the modifiers, and shows the split
// that is there.
static inline BOOL TSSplitToggleShowsSideBySide(NSEventModifierFlags flags, BOOL windowIsSplit, BOOL splitSideBySide)
{
    if (windowIsSplit)
        return splitSideBySide;
    return TSSplitToggleOptionHeld(flags);
}

// The tool tip of a split button: what a click does. With pages one below the other,
// the Preview's tool tip also tells that a Shift-click continues the pages in the bottom
// part (#66); in the other display formats a Shift-click is not offered.
static inline NSString *TSSplitToggleToolTip(BOOL preview, BOOL windowIsSplit, BOOL continuousPages)
{
    if (windowIsSplit)
        return preview ? NSLocalizedStringFromTable(@"tiToolTipUnsplitKIT", @"ToolbarItems", @"Unsplit the preview")
                       : NSLocalizedStringFromTable(@"tiToolTipUnsplit", @"ToolbarItems", @"Unsplit the source");
    if (preview && continuousPages)
        return NSLocalizedStringFromTable(@"tiToolTipSplitKITContinuous", @"ToolbarItems", @"Toggle preview split; Option-click to split vertically, Shift-click to continue the pages below");
    return preview ? NSLocalizedStringFromTable(@"tiToolTipSplitKIT", @"ToolbarItems", @"Toggle preview split; Option-click to split vertically")
                   : NSLocalizedStringFromTable(@"tiToolTipSplit", @"ToolbarItems", @"Toggle source split; Option-click to split vertically");
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
