// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPrefPaneLayout.h"

typedef NS_ENUM(NSInteger, TSSettingsRowKind) {
    TSSettingsRowControls, TSSettingsRowField, TSSettingsRowSection
};
@interface TSSettingsLayoutRow : NSObject
@property (copy, readonly) NSArray<NSString *> *identifiers;
@property (readonly) TSSettingsRowKind kind;
@property (readonly) NSUInteger indentation;
+ (instancetype)controls:(NSArray<NSString *> *)identifiers kind:(TSSettingsRowKind)kind indentation:(NSUInteger)indentation;
@end
@implementation TSSettingsLayoutRow
+ (instancetype)controls:(NSArray<NSString *> *)identifiers kind:(TSSettingsRowKind)kind indentation:(NSUInteger)indentation
{
    TSSettingsLayoutRow *row = [self new];
    row->_identifiers = [identifiers copy]; row->_kind = kind; row->_indentation = indentation;
    return row;
}
@end
@interface TSSettingsLayoutGroup : NSObject
@property (copy, readonly) NSArray<TSSettingsLayoutRow *> *rows;
@property (copy, readonly) NSArray<NSArray<NSString *> *> *cells;
+ (instancetype)rows:(NSArray<TSSettingsLayoutRow *> *)rows;
+ (instancetype)grid:(NSArray<NSArray<NSString *> *> *)cells;
@end
@implementation TSSettingsLayoutGroup
+ (instancetype)rows:(NSArray<TSSettingsLayoutRow *> *)rows
{
    TSSettingsLayoutGroup *group = [self new]; group->_rows = [rows copy]; group->_cells = @[]; return group;
}
+ (instancetype)grid:(NSArray<NSArray<NSString *> *> *)cells
{
    TSSettingsLayoutGroup *group = [self new]; group->_rows = @[]; group->_cells = [cells copy]; return group;
}
@end
@implementation TSSettingsGroupStyle
+ (CGFloat)cornerRadiusForMajorVersion:(NSInteger)version { return version >= 26 ? 12 : 10; }
+ (void)applyToBox:(NSBox *)box
{
    box.titlePosition = NSNoTitle;
    box.boxType = NSBoxCustom;
    box.borderWidth = 0;
    box.fillColor = NSColor.controlBackgroundColor;
    box.cornerRadius = [self cornerRadiusForMajorVersion:NSProcessInfo.processInfo.operatingSystemVersion.majorVersion];
    box.translatesAutoresizingMaskIntoConstraints = NO;
}
@end
@implementation TSPrefPaneLayout
#include "TSSettingsPaneComposition.inc"
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
        [matrix.widthAnchor constraintGreaterThanOrEqualToConstant:width].active = YES;
    } else if ([view isKindOfClass:NSColorWell.class]) {
        [view.widthAnchor constraintEqualToConstant:60].active = YES;
        [view.heightAnchor constraintEqualToConstant:24].active = YES;
    }
}
+ (NSTextField *)heading:(NSString *)title identifier:(NSString *)identifier
{
    NSTextField *heading = [NSTextField wrappingLabelWithString:title];
    heading.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    heading.identifier = identifier;
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    return heading;
}
+ (void)attachRows:(NSArray<NSView *> *)rows toView:(NSView *)view
{
    NSStackView *stack = [self stackWithViews:rows orientation:NSUserInterfaceLayoutOrientationVertical];
    [view addSubview:stack]; view.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-12]]];
    for (NSView *row in rows) [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}
+ (void)arrangeView:(NSView *)view
{
    NSString *identifier = view.identifier;
    TSSettingsLayoutGroup *model = identifier ? [self groups][identifier] : nil;
    if (model == nil) [NSException raise:NSInternalInconsistencyException format:@"Missing settings composition for %@", identifier];
    NSMutableDictionary<NSString *, NSView *> *controls = [NSMutableDictionary dictionary];
    for (NSView *child in [view.subviews copy]) {
        NSString *key = child.identifier;
        if (key == nil || controls[key] != nil) [NSException raise:NSInternalInconsistencyException format:@"Duplicate or missing settings control identifier %@", key];
        controls[key] = child;
    }
    NSMutableSet<NSString *> *used = [NSMutableSet set];
    NSView *(^take)(NSString *) = ^NSView *(NSString *key) {
        NSView *control = controls[key];
        if (control == nil || [used containsObject:key]) [NSException raise:NSInternalInconsistencyException format:@"Missing or repeated settings control %@", key];
        [used addObject:key]; [control removeFromSuperview]; return control;
    };
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    if (model.cells.count) {
        NSMutableArray<NSArray<NSView *> *> *cells = [NSMutableArray array];
        for (NSArray<NSString *> *row in model.cells) {
            NSMutableArray<NSView *> *items = [NSMutableArray array];
            for (NSString *key in row) {
                if (!key.length) { [items addObject:NSGridCell.emptyContentView]; continue; }
                NSView *child = take(key); [self prepareControl:child];
                if ([child isKindOfClass:NSTextField.class]) {
                    [child.widthAnchor constraintEqualToConstant:120].active = YES;
                    ((NSTextField *)child).preferredMaxLayoutWidth = 120;
                }
                [items addObject:child];
            }
            [cells addObject:items];
        }
        NSGridView *grid = [NSGridView gridViewWithViews:cells];
        grid.translatesAutoresizingMaskIntoConstraints = NO;
        grid.columnSpacing = 8; grid.rowSpacing = 8;
        grid.xPlacement = NSGridCellPlacementLeading; grid.yPlacement = NSGridCellPlacementCenter;
        for (NSInteger index = 0; index < grid.numberOfColumns; index++) [grid columnAtIndex:index].width = 120;
        [rows addObject:grid];
    }
    for (TSSettingsLayoutRow *row in model.rows) {
        NSMutableArray<NSView *> *items = [NSMutableArray array];
        for (NSString *key in row.identifiers) [items addObject:take(key)];
        NSView *first = items.firstObject;
        if (row.kind == TSSettingsRowSection) {
            if ([first isKindOfClass:NSBox.class]) {
                NSBox *box = (NSBox *)first;
                NSView *content = box.contentView;
                if (content == nil) [NSException raise:NSInternalInconsistencyException format:@"Missing settings group content %@", row.identifiers.firstObject];
                [self arrangeView:content]; [TSSettingsGroupStyle applyToBox:box];
                box.contentViewMargins = NSMakeSize(16, 12);
                box.accessibilityLabel = box.title;
                [NSLayoutConstraint activateConstraints:@[
                    [content.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:8],
                    [content.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-8],
                    [content.topAnchor constraintEqualToAnchor:box.topAnchor constant:8],
                    [content.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8]]];
                NSStackView *body = (NSStackView *)content.subviews.firstObject;
                if (box.title.length) {
                    NSTextField *heading = [self heading:box.title identifier:[@"heading." stringByAppendingString:box.identifier ?: @""]];
                    [body insertArrangedSubview:heading atIndex:0];
                    [heading.widthAnchor constraintEqualToAnchor:body.widthAnchor].active = YES;
                }
                [rows addObject:box];
            } else if ([first isKindOfClass:NSTabView.class]) {
                for (NSTabViewItem *item in ((NSTabView *)first).tabViewItems) {
                    NSView *content = item.view;
                    if (content == nil) continue;
                    [content removeFromSuperview]; [self arrangeView:content];
                    [rows addObject:[self heading:item.label identifier:[@"heading." stringByAppendingString:content.identifier ?: @""]]];
                    [rows addObject:content];
                }
            } else [NSException raise:NSInternalInconsistencyException format:@"Invalid settings section %@", first];
            continue;
        }
        for (NSView *child in items) [self prepareControl:child];
        NSStackView *body = [self stackWithViews:items orientation:NSUserInterfaceLayoutOrientationHorizontal];
        NSView *container = [NSView new]; container.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:body];
        [NSLayoutConstraint activateConstraints:@[
            [body.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:24 * row.indentation],
            [body.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [body.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
            [container.heightAnchor constraintGreaterThanOrEqualToAnchor:body.heightAnchor],
            [container.heightAnchor constraintGreaterThanOrEqualToConstant:38]]];
        if (row.kind == TSSettingsRowField) [first.widthAnchor constraintEqualToConstant:170].active = YES;
        [rows addObject:container];
    }
    if (used.count != controls.count) [NSException raise:NSInternalInconsistencyException format:@"Unplaced settings controls in %@", identifier];
    [self attachRows:rows toView:view];
}
@end
