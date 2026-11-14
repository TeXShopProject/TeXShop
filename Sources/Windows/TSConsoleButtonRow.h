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

static inline CGFloat TSConsoleButtonWidth(NSButton *button)
{
    return ceil(button.fittingSize.width);
}

// Lays out the buttons as push buttons along the top edge of host: leading from
// left to right, trailing from right to left. The output view keeps its bottom
// edge and ends under the row. The window cannot be narrowed so far that the two
// groups come closer than twice the space between buttons, nor made so low that
// the output loses its last two lines, and it grows if it is smaller now.
static inline void TSLayoutConsoleButtons(NSView *host, NSArray<NSButton *> *leading, NSArray<NSButton *> *trailingRightToLeft, NSView *output)
{
    CGFloat height = 0, needed = TSConsoleButtonSideMargin * 2;
    for (NSArray<NSButton *> *group in @[leading, trailingRightToLeft]) {
        for (NSButton *button in group) {
            button.bezelStyle = NSBezelStylePush;
            button.controlSize = NSControlSizeRegular;
            button.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeRegular]];
            height = MAX(height, ceil(button.fittingSize.height));
            needed += TSConsoleButtonWidth(button);
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
        CGFloat width = TSConsoleButtonWidth(button);
        button.frame = NSMakeRect(x, top - height, width, height);
        button.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
        x += width + TSConsoleButtonSpacing;
    }
    x = NSWidth(host.bounds) - TSConsoleButtonSideMargin;
    for (NSButton *button in trailingRightToLeft) {
        CGFloat width = TSConsoleButtonWidth(button);
        x -= width;
        button.frame = NSMakeRect(x, top - height, width, height);
        button.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
        x -= TSConsoleButtonSpacing;
    }
    if (output) {
        NSRect frame = output.frame;
        frame.size.height = MAX(0, top - height - TSConsoleButtonRowMargin - NSMinY(frame));
        output.frame = frame;
    }
}

// The console of a document, loaded from TSDocument.nib in any language: the
// buttons along its top edge, those left of the middle leading, and the output
// (the scroll view) under them.
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
        return NSMinY(button.frame) >= NSMaxY(output.frame) - 1;
    }]];
    NSMutableArray<NSButton *> *leading = [NSMutableArray array], *trailing = [NSMutableArray array];
    for (NSButton *button in row)
        [(NSMidX(button.frame) < NSMidX(host.bounds) ? leading : trailing) addObject:button];
    [leading sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(a.frame) < NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    [trailing sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(a.frame) > NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    TSLayoutConsoleButtons(host, leading, trailing, output);
}
