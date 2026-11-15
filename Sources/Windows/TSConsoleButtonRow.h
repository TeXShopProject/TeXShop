// SPDX-License-Identifier: GPL-2.0-or-later
// TSConsoleButtonRow.h
//
// The row of buttons along the top of a console: the console of a document
// (Goto Error, Abort, Trash Aux Files) and the Experiment console (Stop
// Experiment). They are push buttons sized to their titles, as in the other
// windows of the application: one group from the left edge, the other from the
// right edge, and the output starts under them.

#import <Cocoa/Cocoa.h>

// From the sides and between buttons as in the Human Interface Guidelines and the
// dialogs (TSDialogButtonLayout); above and below the row, as little as keeps
// the output tall.
static const CGFloat TSConsoleButtonSideMargin = 20, TSConsoleButtonSpacing = 12, TSConsoleButtonRowMargin = 8;
// At its smallest the output still shows two lines, as it did under the earlier row of square buttons.
static const CGFloat TSConsoleMinimumOutputHeight = 28;

// What a button draws when it fits its title (its alignment rectangle): on macOS
// 26 and later the same as its frame, on earlier systems a little inside it.
static inline NSSize TSConsoleButtonDrawnSize(NSButton *button)
{
    NSSize fitting = button.fittingSize;
    NSSize drawn = [button alignmentRectForFrame:NSMakeRect(0, 0, fitting.width, fitting.height)].size;
    return NSMakeSize(ceil(drawn.width), ceil(drawn.height));
}

// Places what a button draws at a rectangle.
static inline void TSConsoleButtonPlace(NSButton *button, NSRect drawn, NSAutoresizingMaskOptions mask)
{
    button.frame = [button frameForAlignmentRect:drawn];
    button.autoresizingMask = mask;
}

// Lays out the buttons as push buttons along the top edge of host: leading from
// left to right, trailing from right to left. Margins and spaces are measured
// between what the buttons draw, so they are the same on every system. The output view keeps its bottom
// edge and ends under the row. The window cannot be narrowed so far that the two
// groups come closer than twice the space between buttons, nor made so low that
// the output loses its last two lines, and it grows if it is smaller now.
static inline void TSLayoutConsoleButtons(NSView *host, NSArray<NSButton *> *leading, NSArray<NSButton *> *trailingRightToLeft, NSView *output)
{
    CGFloat height = 0, needed = TSConsoleButtonSideMargin * 2;
    for (NSArray<NSButton *> *group in @[leading, trailingRightToLeft]) {
        for (NSButton *button in group) {
            button.bezelStyle = NSBezelStylePush;
            button.bordered = YES;
            button.controlSize = NSControlSizeRegular;
            button.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeRegular]];
            NSSize drawn = TSConsoleButtonDrawnSize(button);
            height = MAX(height, drawn.height);
            needed += drawn.width;
        }
        if (group.count > 1) needed += (group.count - 1) * TSConsoleButtonSpacing;
    }
    if (leading.count && trailingRightToLeft.count) needed += TSConsoleButtonSpacing * 2;
    NSWindow *window = host.window;
    if (window && host == window.contentView) {
        NSSize minimum = window.contentMinSize;
        CGFloat lowest = TSConsoleButtonRowMargin * 2 + height + (output ? NSMinY(output.frame) + TSConsoleMinimumOutputHeight : 0);
        if (minimum.width < needed || minimum.height < lowest) {
            window.contentMinSize = NSMakeSize(MAX(minimum.width, needed), MAX(minimum.height, lowest));
        }
        NSSize size = host.bounds.size;
        if (size.width < needed || size.height < lowest)
            [window setContentSize:NSMakeSize(MAX(size.width, needed), MAX(size.height, lowest))];
    }
    CGFloat top = NSHeight(host.bounds) - TSConsoleButtonRowMargin;
    CGFloat x = TSConsoleButtonSideMargin;
    for (NSButton *button in leading) {
        CGFloat width = TSConsoleButtonDrawnSize(button).width;
        TSConsoleButtonPlace(button, NSMakeRect(x, top - height, width, height), NSViewMaxXMargin | NSViewMinYMargin);
        x += width + TSConsoleButtonSpacing;
    }
    x = NSWidth(host.bounds) - TSConsoleButtonSideMargin;
    for (NSButton *button in trailingRightToLeft) {
        CGFloat width = TSConsoleButtonDrawnSize(button).width;
        x -= width;
        TSConsoleButtonPlace(button, NSMakeRect(x, top - height, width, height), NSViewMinXMargin | NSViewMinYMargin);
        x -= TSConsoleButtonSpacing;
    }
    if (output) {
        NSRect frame = output.frame;
        frame.size.height = MAX(0, top - height - TSConsoleButtonRowMargin - NSMinY(frame));
        output.frame = frame;
    }
}

// The console of a document, loaded from TSDocument.nib in any language: the
// buttons along its top edge, those held to the left edge leading and those held
// to the right edge trailing, and the output (the scroll view) under them.
static inline void TSLayoutConsoleButtonRow(NSWindow *console)
{
    NSView *host = console.contentView;
    NSMutableArray<NSButton *> *row = [NSMutableArray array];
    NSScrollView *output = nil;
    for (NSView *view in host.subviews) {
        if ([view isKindOfClass:NSScrollView.class] && (output == nil || NSMaxY(view.frame) > NSMaxY(output.frame)))
            output = (NSScrollView *)view;
        else if ([view isKindOfClass:NSButton.class] && ![view isKindOfClass:NSPopUpButton.class] && !view.hidden)
            [row addObject:(NSButton *)view];
    }
    if (output == nil) return;
    [row filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSButton *button, NSDictionary *bindings) {
        return NSMinY([button alignmentRectForFrame:button.frame]) >= NSMaxY(output.frame) - 1;
    }]];
    NSMutableArray<NSButton *> *leading = [NSMutableArray array], *trailing = [NSMutableArray array];
    // A button keeps its group however wide the window is when this runs (a saved
    // frame may be narrow) and however often it runs: the group is where the button
    // is held, the left or the right edge, as the nib or an earlier layout sets it.
    // A button held to neither edge joins the side of the middle it is on.
    for (NSButton *button in row) {
        NSAutoresizingMaskOptions mask = button.autoresizingMask & (NSViewMinXMargin | NSViewMaxXMargin);
        BOOL right = mask == NSViewMinXMargin || (mask != NSViewMaxXMargin && NSMidX(button.frame) >= NSMidX(host.bounds));
        [(right ? trailing : leading) addObject:button];
    }
    [leading sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(a.frame) < NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    [trailing sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(a.frame) > NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    TSLayoutConsoleButtons(host, leading, trailing, output);
}
