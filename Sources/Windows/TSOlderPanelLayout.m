// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSOlderPanelLayout.h"
#import "TSDialogButtonLayout.h"

static const CGFloat TSColumnSpacing = 20;

static BOOL TSIsLabel(NSView *view)
{
    if (![view isKindOfClass:NSTextField.class] || view.hidden) return NO;
    NSTextField *field = (NSTextField *)view;
    return !field.editable && !field.bezeled && field.stringValue.length > 0;
}

static BOOL TSSameRow(NSRect a, NSRect b)
{
    return NSMaxY(a) > NSMinY(b) && NSMinY(a) < NSMaxY(b);
}

static void TSGrowContentWidth(NSWindow *window, CGFloat width)
{
    NSView *content = window.contentView;
    if (NSWidth(content.bounds) < width) {
        BOOL autoresizes = content.autoresizesSubviews;
        content.autoresizesSubviews = NO;
        [window setContentSize:NSMakeSize(width, NSHeight(content.bounds))];
        content.autoresizesSubviews = autoresizes;
    }
    NSSize minimum = window.contentMinSize;
    if (minimum.width < width && (window.styleMask & NSWindowStyleMaskResizable)) {
        minimum.width = width;
        window.contentMinSize = minimum;
    }
}

void TSLayoutLogWindow(NSWindow *window)
{
    NSView *content = window.contentView;
    NSScrollView *scroll = nil;
    for (NSView *view in content.subviews)
        if ([view isKindOfClass:NSScrollView.class] && !view.hidden) scroll = (NSScrollView *)view;
    if (scroll == nil) return;
    CGFloat top = NSMaxY(scroll.frame);
    NSMutableArray<NSButton *> *controls = [NSMutableArray array];
    for (NSView *view in content.subviews)
        if ([view isKindOfClass:NSButton.class] && !view.hidden && NSMinY(view.frame) >= top - 2) [controls addObject:(NSButton *)view];
    [controls sortUsingComparator:^NSComparisonResult(NSButton *a, NSButton *b) { return NSMinX(a.frame) < NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    // Check boxes whose leading edges are within a few points of each other form a
    // column; push buttons (Refresh) go in the last column, under its check boxes.
    NSMutableArray<NSMutableArray<NSButton *> *> *columns = [NSMutableArray array];
    for (NSButton *control in controls) {
        if (control.bordered) continue;
        if (columns.count == 0 || NSMinX(control.frame) - NSMinX(columns.lastObject.firstObject.frame) > 12) [columns addObject:[NSMutableArray array]];
        [columns.lastObject addObject:control];
    }
    for (NSButton *control in controls)
        if (control.bordered) {
            if (columns.count == 0) [columns addObject:[NSMutableArray array]];
            [columns.lastObject addObject:control];
        }
    CGFloat x = TSDialogMargin;
    for (NSArray<NSButton *> *column in columns) {
        CGFloat width = 0;
        for (NSButton *control in column)
            width = MAX(width, control.bordered ? MAX(80, ceil(control.fittingSize.width)) : ceil(control.fittingSize.width));
        for (NSButton *control in column) {
            NSRect frame = control.frame;
            NSSize size = control.fittingSize;
            frame.origin.x = x;
            frame.size.width = control.bordered ? width : ceil(size.width);
            if (control.bordered) {
                CGFloat middle = NSMidY(frame);
                frame.size.height = ceil(size.height);
                frame.origin.y = round(middle - NSHeight(frame) / 2);
            }
            control.frame = frame;
            control.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
        }
        x += width + TSColumnSpacing;
    }
    TSGrowContentWidth(window, x - TSColumnSpacing + TSDialogMargin);
    // The log meets the window's edges; only its top border shows, under the controls.
    scroll.frame = NSMakeRect(-1, -1, NSWidth(content.bounds) + 2, top + 1);
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
}

static BOOL TSIsCJK(unichar c)
{
    return (c >= 0x3000 && c <= 0x9FFF) || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFF00 && c <= 0xFFEF);
}

// A label written over several lines, as one line: a space between words,
// nothing between Chinese or Japanese characters.
static NSString *TSOneLine(NSString *text)
{
    NSMutableString *result = [NSMutableString string];
    NSArray<NSString *> *lines = [[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                                  componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *raw in lines) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (line.length == 0) continue;
        if (result.length && !(TSIsCJK([result characterAtIndex:result.length - 1]) && TSIsCJK([line characterAtIndex:0])))
            [result appendString:@" "];
        [result appendString:line];
    }
    return result;
}

static void TSCollectNotice(NSView *view, NSMutableArray<NSTextField *> *labels, NSButton * __strong *button)
{
    for (NSView *child in view.subviews) {
        if (child.hidden) continue;
        if (TSIsLabel(child)) [labels addObject:(NSTextField *)child];
        else if ([child isKindOfClass:NSButton.class] && [((NSButton *)child).keyEquivalent isEqualToString:@"\r"]) *button = (NSButton *)child;
        else TSCollectNotice(child, labels, button);
    }
}

NSAlert *TSAlertForNoticePanel(NSWindow *panel)
{
    NSMutableArray<NSTextField *> *labels = [NSMutableArray array];
    NSButton *button = nil;
    TSCollectNotice(panel.contentView, labels, &button);
    [labels sortUsingComparator:^NSComparisonResult(NSTextField *a, NSTextField *b) { return NSMaxY(a.frame) > NSMaxY(b.frame) ? NSOrderedAscending : NSOrderedDescending; }];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSTextField *label in labels) [texts addObject:TSOneLine(label.stringValue)];
    NSAlert *alert = [NSAlert new];
    alert.messageText = [texts componentsJoinedByString:@" "];
    [alert addButtonWithTitle:button.title.length ? button.title : NSLocalizedString(@"OK", @"")];
    return alert;
}

void TSFitLabelsBeforePopUps(NSView *view)
{
    for (NSView *child in view.subviews) {
        if (![child isKindOfClass:NSPopUpButton.class] || child.hidden) continue;
        NSPopUpButton *popUp = (NSPopUpButton *)child;
        // The label starts left of the pop-up; in some localizations its frame runs under it.
        NSTextField *nearest = nil;
        for (NSView *other in view.subviews)
            if (TSIsLabel(other) && NSMinX(other.frame) < NSMinX(popUp.frame) && NSMaxX(other.frame) < NSMidX(popUp.frame)
                && TSSameRow(other.frame, popUp.frame) && (nearest == nil || NSMaxX(other.frame) > NSMaxX(nearest.frame)))
                nearest = (NSTextField *)other;
        if (nearest == nil) continue;
        nearest.font = [NSFont systemFontOfSize:popUp.font.pointSize ?: NSFont.systemFontSize];
        nearest.alignment = NSTextAlignmentRight;
        NSSize size = nearest.fittingSize;
        CGFloat width = ceil(size.width), right = MIN(NSMaxX(nearest.frame), NSMinX(popUp.frame) - 8);
        CGFloat shift = MAX(0, TSDialogMargin - (right - width));
        if (shift > 0) {
            // Too long for the room before the pop-up: move the pop-up and widen the view.
            BOOL autoresizes = view.autoresizesSubviews;
            view.autoresizesSubviews = NO;
            [view setFrameSize:NSMakeSize(NSWidth(view.frame) + shift, NSHeight(view.frame))];
            view.autoresizesSubviews = autoresizes;
            [popUp setFrameOrigin:NSMakePoint(NSMinX(popUp.frame) + shift, NSMinY(popUp.frame))];
            right += shift;
        }
        nearest.frame = NSMakeRect(right - width, round(NSMidY(popUp.frame) - ceil(size.height) / 2), width, ceil(size.height));
    }
}

void TSFitToolbarPullDown(NSPopUpButton *button, NSString *title)
{
    if (button.numberOfItems == 0) [button addItemWithTitle:title];
    else [[button itemAtIndex:0] setTitle:title];
    // The title takes the room the arrow leaves. TSToolbarController gives the buttons of
    // the toolbar the toolbar bezel, so the room is measured with the nib's and with that one.
    CGFloat missing = 0;
    for (NSNumber *bezel in @[@(button.bezelStyle), @(NSBezelStyleToolbar)]) {
        NSPopUpButtonCell *cell = [(NSPopUpButtonCell *)button.cell copy];
        cell.bezelStyle = bezel.unsignedIntegerValue;
        [cell removeAllItems]; [cell addItemWithTitle:title]; [cell selectItemAtIndex:0];
        NSRect bounds = NSMakeRect(0, 0, NSWidth(button.frame), NSHeight(button.frame));
        missing = MAX(missing, cell.attributedTitle.size.width - [cell titleRectForBounds:bounds].size.width);
    }
    if (missing > 0) [button setFrameSize:NSMakeSize(NSWidth(button.frame) + ceil(missing), NSHeight(button.frame))];
}
