// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneLayout.h"

@implementation TSPrefPaneLayout
+ (NSStackView *)stackWithViews:(NSArray<NSView *> *)views orientation:(NSUserInterfaceLayoutOrientation)orientation
{
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = orientation;
    stack.alignment = orientation == NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.detachesHiddenViews = YES;
    return stack;
}
+ (void)prepareControl:(NSView *)view
{
    view.translatesAutoresizingMaskIntoConstraints = NO;
    if ([view isKindOfClass:NSTextField.class]) {
        NSTextField *field = (NSTextField *)view;
        if (!field.editable) {
            field.cell.wraps = YES;
            field.cell.scrollable = NO;
            field.maximumNumberOfLines = 0;
            [field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        } else {
            [field.widthAnchor constraintGreaterThanOrEqualToConstant:100].active = YES;
            [field setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        }
    } else if ([view isKindOfClass:NSMatrix.class]) {
        NSMatrix *matrix = (NSMatrix *)view;
        CGFloat height = matrix.numberOfRows * matrix.cellSize.height + MAX(0, matrix.numberOfRows - 1) * matrix.intercellSpacing.height;
        [matrix.heightAnchor constraintEqualToConstant:height].active = YES;
        matrix.autosizesCells = YES;
        CGFloat width = MAX(0, matrix.numberOfColumns - 1) * matrix.intercellSpacing.width;
        for (NSInteger column = 0; column < matrix.numberOfColumns; column++) {
            CGFloat ideal = 0;
            for (NSInteger row = 0; row < matrix.numberOfRows; row++) ideal = MAX(ideal, [matrix cellAtRow:row column:column].cellSize.width);
            width += ceil(ideal);
        }
        [matrix.widthAnchor constraintGreaterThanOrEqualToConstant:MAX(width, NSWidth(matrix.frame))].active = YES;
    } else if ([view isKindOfClass:NSColorWell.class]) {
        [view.widthAnchor constraintEqualToConstant:60].active = YES;
        [view.heightAnchor constraintEqualToConstant:24].active = YES;
    }
}
// Preserve the shared row/column meaning of color headings and wells.
+ (BOOL)arrangeColorGrid:(NSView *)view
{
    NSArray<NSView *> *children = [view.subviews copy];
    NSMutableArray<NSNumber *> *centers = [NSMutableArray array];
    NSUInteger wells = 0;
    for (NSView *child in children) {
        if (![child isKindOfClass:NSColorWell.class] && ![child isKindOfClass:NSTextField.class]) return NO;
        if ([child isKindOfClass:NSColorWell.class]) {
            wells++;
            CGFloat center = NSMidX(child.frame);
            BOOL known = NO;
            for (NSNumber *number in centers) if (fabs(number.doubleValue - center) < 10) known = YES;
            if (!known) [centers addObject:@(center)];
        }
    }
    if (wells < 3) return NO;
    [centers sortUsingSelector:@selector(compare:)];
    CGFloat first = centers.firstObject.doubleValue;
    BOOL rowLabels = NO;
    for (NSView *child in children) if (NSMidX(child.frame) < first - 45) rowLabels = YES;
    if (rowLabels) [centers insertObject:@(first - 90) atIndex:0];
    NSArray<NSView *> *ordered = [children sortedArrayUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
        if (NSMidY(a.frame) != NSMidY(b.frame)) return NSMidY(a.frame) > NSMidY(b.frame) ? NSOrderedAscending : NSOrderedDescending;
        return NSMidX(a.frame) < NSMidX(b.frame) ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<NSMutableArray<NSView *> *> *rows = [NSMutableArray array];
    CGFloat rowY = CGFLOAT_MAX;
    for (NSView *child in ordered) {
        CGFloat y = NSMidY(child.frame), x = NSMidX(child.frame);
        if (fabs(y - rowY) > 10) {
            NSMutableArray *row = [NSMutableArray array];
            for (NSUInteger index = 0; index < centers.count; index++) [row addObject:NSGridCell.emptyContentView];
            [rows addObject:row]; rowY = y;
        }
        NSUInteger column = 0; CGFloat distance = CGFLOAT_MAX;
        for (NSUInteger index = 0; index < centers.count; index++) {
            CGFloat candidate = fabs(x - centers[index].doubleValue);
            if (candidate < distance) { column = index; distance = candidate; }
        }
        NSAssert(rows.lastObject[column] == NSGridCell.emptyContentView, @"Color grid cells must be unique");
        rows.lastObject[column] = child;
        [child removeFromSuperview]; [self prepareControl:child];
        if ([child isKindOfClass:NSTextField.class]) {
            [child.widthAnchor constraintEqualToConstant:120].active = YES;
            ((NSTextField *)child).preferredMaxLayoutWidth = 120;
        }
    }
    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.columnSpacing = 8; grid.rowSpacing = 8;
    grid.xPlacement = NSGridCellPlacementLeading; grid.yPlacement = NSGridCellPlacementCenter;
    for (NSInteger index = 0; index < grid.numberOfColumns; index++) [grid columnAtIndex:index].width = 120;
    [view addSubview:grid]; view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:8],
        [grid.trailingAnchor constraintLessThanOrEqualToAnchor:view.trailingAnchor constant:-8],
        [grid.topAnchor constraintEqualToAnchor:view.topAnchor constant:8],
        [grid.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-8]]];
    return YES;
}
+ (void)arrangeView:(NSView *)view
{
    if ([self arrangeColorGrid:view]) return;
    NSArray<NSView *> *children = [view.subviews sortedArrayUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
        CGFloat difference = NSMidY(b.frame) - NSMidY(a.frame);
        if (difference != 0) return difference < 0 ? NSOrderedAscending : NSOrderedDescending;
        if (NSMinX(a.frame) == NSMinX(b.frame)) return NSOrderedSame;
        return NSMinX(a.frame) < NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    NSMutableArray<NSView *> *row = [NSMutableArray array];
    CGFloat rowY = CGFLOAT_MAX;
    void (^flush)(void) = ^{
        if (row.count == 0) return;
        [row sortUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
            if (NSMinX(a.frame) == NSMinX(b.frame)) return NSOrderedSame;
            return NSMinX(a.frame) < NSMinX(b.frame) ? NSOrderedAscending : NSOrderedDescending;
        }];
        [rows addObject:[self stackWithViews:[row copy] orientation:NSUserInterfaceLayoutOrientationHorizontal]];
        [row removeAllObjects];
    };
    for (NSView *child in children) {
        CGFloat centerY = NSMidY(child.frame);
        [child removeFromSuperview];
        if ([child isKindOfClass:NSBox.class]) {
            flush(); rowY = CGFLOAT_MAX;
            NSBox *box = (NSBox *)child;
            NSView *content = box.contentView;
            if (content == nil) continue;
            [self arrangeView:content];
            NSString *title = box.title;
            box.titlePosition = NSNoTitle;
            box.translatesAutoresizingMaskIntoConstraints = NO;
            box.boxType = NSBoxCustom;
            box.borderWidth = 0;
            box.fillColor = NSColor.controlBackgroundColor;
            box.cornerRadius = 8;
            if (@available(macOS 26.0, *)) { box.cornerRadius = 12; }
            box.contentViewMargins = NSMakeSize(16, 12);
            [NSLayoutConstraint activateConstraints:@[
                [content.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:8],
                [content.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-8],
                [content.topAnchor constraintEqualToAnchor:box.topAnchor constant:8],
                [content.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8]]];
            NSStackView *body = [content.subviews.firstObject isKindOfClass:NSStackView.class] ? (NSStackView *)content.subviews.firstObject : nil;
            NSTextField *heading = [NSTextField wrappingLabelWithString:title];
            heading.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
            heading.translatesAutoresizingMaskIntoConstraints = NO;
            if (title.length && body) {
                [body insertArrangedSubview:heading atIndex:0];
                [heading.widthAnchor constraintEqualToAnchor:body.widthAnchor].active = YES;
            }
            [rows addObject:box];
        } else if ([child isKindOfClass:NSTabView.class]) {
            flush(); rowY = CGFLOAT_MAX;
            for (NSTabViewItem *item in ((NSTabView *)child).tabViewItems) {
                NSView *content = item.view;
                [content removeFromSuperview];
                [self arrangeView:content];
                NSTextField *heading = [NSTextField labelWithString:item.label];
                heading.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
                [rows addObject:heading];
                [rows addObject:content];
            }
        } else {
            if (fabs(centerY - rowY) > 10) { flush(); rowY = centerY; }
            [self prepareControl:child];
            [row addObject:child];
        }
    }
    flush();
    NSStackView *stack = [self stackWithViews:rows orientation:NSUserInterfaceLayoutOrientationVertical];
    [view addSubview:stack];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-16]]];
    for (NSView *rowView in rows) {
        [rowView.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
}
@end
