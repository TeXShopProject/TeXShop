// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSDialogButtonLayout.h"

const CGFloat TSDialogButtonSpacing = 12, TSDialogMargin = 20;
static const CGFloat TSDialogMinimumButtonWidth = 80;

static NSRect TSFittingFrame(NSButton *button, CGFloat width)
{
    NSRect frame = button.frame;
    CGFloat center = NSMidY(frame);
    NSSize fitting = button.fittingSize;
    frame.size.width = width;
    frame.size.height = MAX(NSHeight(frame), fitting.height);
    frame.origin.y = round(center - NSHeight(frame) / 2);
    return frame;
}

static void TSGrowWindowToFit(NSView *host, CGFloat needed)
{
    NSWindow *window = host.window;
    if (window == nil || host != window.contentView) return;
    if (NSWidth(host.bounds) < needed) {
        NSRect frame = window.frame;
        frame.size.width += needed - NSWidth(host.bounds);
        [window setFrame:frame display:NO];
    }
    NSSize minimum = window.contentMinSize;
    if (minimum.width < needed) { minimum.width = needed; window.contentMinSize = minimum; }
}

void TSLayoutTrailingButtons(NSView *host, NSArray<NSButton *> *rightToLeft)
{
    CGFloat needed = TSDialogMargin * 2 + MAX(0, (NSInteger)rightToLeft.count - 1) * TSDialogButtonSpacing;
    for (NSButton *button in rightToLeft) needed += MAX(TSDialogMinimumButtonWidth, ceil(button.fittingSize.width));
    TSGrowWindowToFit(host, needed);
    CGFloat x = NSWidth(host.bounds) - TSDialogMargin;
    for (NSButton *button in rightToLeft) {
        CGFloat width = MAX(TSDialogMinimumButtonWidth, ceil(button.fittingSize.width));
        NSRect frame = TSFittingFrame(button, width);
        x -= width; frame.origin.x = x; x -= TSDialogButtonSpacing;
        button.frame = frame;
        button.autoresizingMask = NSViewMinXMargin | (button.autoresizingMask & (NSViewMinYMargin | NSViewMaxYMargin));
    }
}

void TSLayoutDialogButtons(NSView *host, NSArray<NSButton *> *trailing, NSArray<NSButton *> *leading)
{
    CGFloat shared = TSDialogMinimumButtonWidth;
    for (NSButton *button in trailing) shared = MAX(shared, ceil(button.fittingSize.width));
    NSMutableArray<NSNumber *> *leadingWidths = [NSMutableArray array];
    CGFloat needed = TSDialogMargin * 2 + trailing.count * shared + MAX(0, (NSInteger)trailing.count - 1) * TSDialogButtonSpacing;
    for (NSButton *button in leading) {
        CGFloat width = MAX(TSDialogMinimumButtonWidth, ceil(button.fittingSize.width));
        [leadingWidths addObject:@(width)];
        needed += width + TSDialogButtonSpacing;
    }
    if (leading.count && trailing.count) needed += TSDialogButtonSpacing; // keep the two groups apart
    TSGrowWindowToFit(host, needed);
    CGFloat x = NSWidth(host.bounds) - TSDialogMargin;
    for (NSButton *button in trailing) {
        NSRect frame = TSFittingFrame(button, shared);
        x -= shared; frame.origin.x = x; x -= TSDialogButtonSpacing;
        button.frame = frame;
        button.autoresizingMask = NSViewMinXMargin | (button.autoresizingMask & (NSViewMinYMargin | NSViewMaxYMargin));
    }
    x = TSDialogMargin;
    for (NSUInteger index = 0; index < leading.count; index++) {
        NSRect frame = TSFittingFrame(leading[index], leadingWidths[index].doubleValue);
        frame.origin.x = x; x += NSWidth(frame) + TSDialogButtonSpacing;
        leading[index].frame = frame;
        leading[index].autoresizingMask = NSViewMaxXMargin | (leading[index].autoresizingMask & (NSViewMinYMargin | NSViewMaxYMargin));
    }
}

static BOOL TSIsPushButton(NSView *view)
{
    if (![view isKindOfClass:NSButton.class] || [view isKindOfClass:NSPopUpButton.class] || view.hidden) return NO;
    NSButton *button = (NSButton *)view;
    return button.bordered && button.bezelStyle == NSBezelStylePush;
}

static NSArray<NSButton *> *TSBottomPushButtons(NSWindow *window)
{
    NSView *host = window.contentView;
    NSButton *lowest = nil;
    for (NSView *view in host.subviews)
        if (TSIsPushButton(view) && (lowest == nil || NSMinY(view.frame) < NSMinY(lowest.frame))) lowest = (NSButton *)view;
    NSMutableArray<NSButton *> *row = [NSMutableArray array];
    if (lowest == nil) return row;
    for (NSView *view in host.subviews)
        if (TSIsPushButton(view) && fabs(NSMidY(view.frame) - NSMidY(lowest.frame)) < NSHeight(lowest.frame) / 2) [row addObject:(NSButton *)view];
    return row;
}

void TSLayoutBottomActionRow(NSWindow *window)
{
    NSArray<NSButton *> *row = [TSBottomPushButtons(window) sortedArrayUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(a.frame) > NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    if (row.count) TSLayoutTrailingButtons(window.contentView, row);
}

void TSLayoutDialogButtonRow(NSWindow *window)
{
    NSView *host = window.contentView;
    NSArray<NSButton *> *row = TSBottomPushButtons(window);
    if (row.count == 0) return;
    NSButton *defaultButton = nil, *cancelButton = nil;
    for (NSButton *button in row) {
        if ([button.keyEquivalent isEqualToString:@"\r"]) defaultButton = button;
        else if ([button.keyEquivalent isEqualToString:@"\033"]) cancelButton = button;
    }
    NSMutableArray<NSButton *> *trailing = [NSMutableArray array];
    if (defaultButton) [trailing addObject:defaultButton];
    if (cancelButton) [trailing addObject:cancelButton];
    NSMutableArray<NSButton *> *leading = [row mutableCopy];
    [leading removeObjectsInArray:trailing];
    if (trailing.count == 0) {
        // Without key equivalents, the buttons right of center are the dismissal group.
        for (NSButton *button in [row sortedArrayUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(a.frame) > NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending; }])
            if (NSMidX(button.frame) > NSMidX(host.bounds)) [trailing addObject:button];
        [leading removeObjectsInArray:trailing];
    }
    [leading sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(a.frame) < NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    TSLayoutDialogButtons(host, trailing, leading);
}
