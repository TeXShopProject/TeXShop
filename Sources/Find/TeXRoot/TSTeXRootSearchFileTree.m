// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootSearchFileTree.h"
#import "TSTeXRootSearchResultsList.h"
#import "TSAdvancedFindController.h"

#define TSLocalized TSAdvancedFindLocalized

@interface TSTeXRootTreeNode : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong, nullable) TSTeXRootProjectFile *file;
@property (nonatomic, strong) NSMutableArray<TSTeXRootTreeNode *> *children;
@end

@implementation TSTeXRootTreeNode

- (instancetype)init
{
    if (!(self = [super init]))
        return nil;
    _name = @"";
    _children = [NSMutableArray array];
    return self;
}

- (NSArray<TSTeXRootProjectFile *> *)files
{
    if (self.file)
        return @[(TSTeXRootProjectFile *_Nonnull)self.file];
    NSMutableArray<TSTeXRootProjectFile *> *files = [NSMutableArray array];
    for (TSTeXRootTreeNode *child in self.children)
        [files addObjectsFromArray:[child files]];
    return files;
}

- (nullable TSTeXRootTreeNode *)folderNamed:(NSString *)name
{
    for (TSTeXRootTreeNode *child in self.children)
        if (!child.file && [child.name isEqualToString:name])
            return child;
    return nil;
}

@end

/// Space turns the selected rows on or off.
@interface TSTeXRootTreeOutlineView : NSOutlineView
@property (nonatomic, copy, nullable) void (^spaceHandler)(void);
@end

@implementation TSTeXRootTreeOutlineView
- (void)keyDown:(NSEvent *)event
{
    NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask & ~(NSEventModifierFlagNumericPad | NSEventModifierFlagFunction);
    if (modifiers == 0 && [event.charactersIgnoringModifiers isEqualToString:@" "] && self.spaceHandler) {
        self.spaceHandler();
        return;
    }
    [super keyDown:event];
}
@end

@interface TSTeXRootTreeRowView : NSTableRowView
@property (nonatomic, copy, nullable) NSString *spokenLabel;
@end

@implementation TSTeXRootTreeRowView
- (NSString *)accessibilityLabel { return self.spokenLabel ?: [super accessibilityLabel]; }
@end

/// The name of a row in its own colors: the counts and marks in it keep theirs over the sidebar's material.
@interface TSTeXRootTreeLabel : NSTextField
@end

@implementation TSTeXRootTreeLabel
- (BOOL)allowsVibrancy { return NO; }
@end

/// A row: the check box, which knows its node, and the name with the count after it.
@interface TSTeXRootTreeCell : NSTableCellView
@property (nonatomic, strong) NSButton *box;
@property (nonatomic, strong) NSTextField *label;
@property (nonatomic, weak, nullable) TSTeXRootTreeNode *node;
@end

@implementation TSTeXRootTreeCell
@end

@interface TSTeXRootSearchFileTree ()
@property (nonatomic, readonly) TSTeXRootSearchModel *model;
@property (nonatomic, readwrite) NSScrollView *scrollView;
@property (nonatomic, readwrite) NSOutlineView *outlineView;
@property (nonatomic, strong, nullable) TSTeXRootTreeNode *root;
@property (nonatomic, weak, nullable) TSTeXRootProject *shownProject;
@property (nonatomic) BOOL fitting;
@end

@implementation TSTeXRootSearchFileTree

- (instancetype)initWithModel:(TSTeXRootSearchModel *)model
{
    if (!(self = [super init]))
        return nil;
    _model = model;
    TSTeXRootTreeOutlineView *outline = [[TSTeXRootTreeOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
    __weak typeof(self) weakSelf = self;
    outline.spaceHandler = ^{ [weakSelf toggleSelectedRows]; };
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    column.editable = NO;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [outline addTableColumn:column];
    outline.outlineTableColumn = column;
    outline.headerView = nil;
    outline.style = NSTableViewStyleSourceList;
    outline.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    outline.rowHeight = 22;
    outline.allowsMultipleSelection = YES;
    outline.dataSource = self;
    outline.delegate = self;
    outline.accessibilityLabel = TSLocalized(@"TeXRootSearch.AX.Files", @"Files");
    _outlineView = outline;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
    scroll.documentView = outline;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.drawsBackground = NO;
    _scrollView = scroll;
    // The names take the visible width, never more, whatever the width of the tree (as the sets of Multiple Replace).
    scroll.contentView.postsFrameChangedNotifications = YES;
    outline.postsFrameChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fitColumn) name:NSViewFrameDidChangeNotification object:scroll.contentView];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fitColumn) name:NSViewFrameDidChangeNotification object:outline];
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)fitColumn
{
    NSTableColumn *column = self.outlineView.tableColumns.firstObject;
    NSClipView *clip = self.scrollView.contentView;
    if (!column || self.fitting)
        return;
    self.fitting = YES;
    CGFloat visible = NSWidth(clip.bounds);
    CGFloat width = MAX(column.minWidth, visible - self.outlineView.intercellSpacing.width);
    if (fabs(column.width - width) > 0.5)
        column.width = width;
    if (fabs(NSWidth(self.outlineView.frame) - visible) > 0.5)
        [self.outlineView setFrameSize:NSMakeSize(visible, NSHeight(self.outlineView.frame))];
    self.fitting = NO;
}

#pragma mark Building

- (void)buildTree
{
    TSTeXRootProject *project = self.model.project;
    self.shownProject = project;
    if (!project) {
        self.root = nil;
        return;
    }
    TSTeXRootTreeNode *root = [TSTeXRootTreeNode new];
    root.name = project.folderURL.lastPathComponent ?: @"";
    for (TSTeXRootProjectFile *file in project.files) {
        NSArray<NSString *> *components = file.relativePath.pathComponents;
        TSTeXRootTreeNode *folder = root;
        for (NSUInteger i = 0; i + 1 < components.count; i++) {
            TSTeXRootTreeNode *next = [folder folderNamed:components[i]];
            if (!next) {
                next = [TSTeXRootTreeNode new];
                next.name = components[i];
                [folder.children addObject:next];
            }
            folder = next;
        }
        TSTeXRootTreeNode *leaf = [TSTeXRootTreeNode new];
        leaf.name = components.lastObject ?: file.relativePath;
        leaf.file = file;
        [folder.children addObject:leaf];
    }
    // The root first; then, in each folder, files and folders in the order of the Finder.
    __block void (^sort)(TSTeXRootTreeNode *) = nil;
    void (^sorter)(TSTeXRootTreeNode *) = ^(TSTeXRootTreeNode *node) {
        [node.children sortUsingComparator:^NSComparisonResult(TSTeXRootTreeNode *a, TSTeXRootTreeNode *b) {
            if (a.file.isRoot != b.file.isRoot)
                return a.file.isRoot ? NSOrderedAscending : NSOrderedDescending;
            return [a.name localizedStandardCompare:b.name];
        }];
        for (TSTeXRootTreeNode *child in node.children)
            if (!child.file)
                sort(child);
    };
    sort = sorter;
    sorter(root);
    sort = nil;
    self.root = root;
}

- (void)reload
{
    if (self.shownProject != self.model.project || (!self.root && self.model.project)) {
        [self buildTree];
        [self.outlineView reloadData];
        [self.outlineView expandItem:nil expandChildren:YES];
        [self fitColumn];
        return;
    }
    // Same files: only the checks, counts and marks change.
    for (NSInteger row = 0; row < self.outlineView.numberOfRows; row++) {
        TSTeXRootTreeCell *cell = [self.outlineView viewAtColumn:0 row:row makeIfNecessary:NO];
        TSTeXRootTreeNode *node = [self.outlineView itemAtRow:row];
        if ([cell isKindOfClass:[TSTeXRootTreeCell class]])
            [self configureCell:cell node:node];
        TSTeXRootTreeRowView *view = (TSTeXRootTreeRowView *)[self.outlineView rowViewAtRow:row makeIfNecessary:NO];
        if ([view isKindOfClass:[TSTeXRootTreeRowView class]])
            view.spokenLabel = [self accessibilityLabelOfRow:row];
    }
}

#pragma mark Data

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item
{
    if (!item)
        return self.root ? 1 : 0;
    return (NSInteger)((TSTeXRootTreeNode *)item).children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item
{
    if (!item)
        return (TSTeXRootTreeNode *_Nonnull)self.root;
    return ((TSTeXRootTreeNode *)item).children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return ((TSTeXRootTreeNode *)item).file == nil;
}

- (NSControlStateValue)stateOfNode:(TSTeXRootTreeNode *)node
{
    NSUInteger on = 0, all = 0;
    for (TSTeXRootProjectFile *file in [node files]) {
        all++;
        if ([self.model isFileIncluded:file])
            on++;
    }
    return on == 0 ? NSControlStateValueOff : on == all ? NSControlStateValueOn : NSControlStateValueMixed;
}

- (NSUInteger)countOfNode:(TSTeXRootTreeNode *)node
{
    NSUInteger count = 0;
    for (TSTeXRootProjectFile *file in [node files])
        count += [self.model numberOfItemsInFile:file];
    return count;
}

- (TSTeXRootSearchOnlyReason)reasonOfNode:(TSTeXRootTreeNode *)node
{
    if (!node.file || self.model.mode == TSTeXRootSearchModeFind)
        return TSTeXRootSearchOnlyReasonNone;
    return [self.model searchOnlyReasonOfFile:(TSTeXRootProjectFile *_Nonnull)node.file];
}

- (void)configureCell:(TSTeXRootTreeCell *)cell node:(TSTeXRootTreeNode *)node
{
    cell.node = node;
    NSControlStateValue state = [self stateOfNode:node];
    cell.box.allowsMixedState = node.file == nil;
    cell.box.state = state;
    // The name in the field's own color (as the sets of Multiple Replace), the count and the mark in the secondary one.
    cell.label.textColor = state == NSControlStateValueOff ? NSColor.secondaryLabelColor : NSColor.labelColor;
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:node.name
                                                                             attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:NSFont.systemFontSize]}];
    NSDictionary *secondary = @{NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize], NSForegroundColorAttributeName: NSColor.secondaryLabelColor};
    NSUInteger count = [self countOfNode:node];
    if (count > 0)
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"  %lu", (unsigned long)count] attributes:secondary]];
    TSTeXRootSearchOnlyReason reason = [self reasonOfNode:node];
    if (reason != TSTeXRootSearchOnlyReasonNone)
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"  ⊘" attributes:secondary]];
    cell.label.attributedStringValue = text;
    cell.label.toolTip = reason != TSTeXRootSearchOnlyReasonNone ? TSTeXRootSearchOnlyReasonText(reason) : node.file.url.path;
    cell.box.accessibilityLabel = node.name;
}

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item
{
    TSTeXRootTreeCell *cell = [outlineView makeViewWithIdentifier:@"node" owner:self];
    if (!cell) {
        cell = [[TSTeXRootTreeCell alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
        cell.identifier = @"node";
        cell.box = [NSButton checkboxWithTitle:@"" target:self action:@selector(boxClicked:)];
        cell.label = [TSTeXRootTreeLabel labelWithString:@""];
        cell.label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        for (NSView *view in @[cell.box, cell.label]) {
            view.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:view];
        }
        [cell.label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [cell.label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [cell.box setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [cell.box setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [NSLayoutConstraint activateConstraints:@[
            [cell.box.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor],
            [cell.box.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [cell.label.leadingAnchor constraintEqualToAnchor:cell.box.trailingAnchor constant:2],
            [cell.label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor],
            [cell.label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
        cell.textField = cell.label;
    }
    [self configureCell:cell node:item];
    return cell;
}

- (nullable NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item
{
    TSTeXRootTreeRowView *row = [TSTeXRootTreeRowView new];
    NSInteger index = [outlineView rowForItem:item];
    row.spokenLabel = index >= 0 ? [self accessibilityLabelOfRow:index] : nil;
    return row;
}

#pragma mark Toggling

- (void)setNodes:(NSArray<TSTeXRootTreeNode *> *)nodes on:(BOOL)on
{
    NSMutableArray<TSTeXRootProjectFile *> *files = [NSMutableArray array];
    for (TSTeXRootTreeNode *node in nodes)
        [files addObjectsFromArray:[node files]];
    [self.model setFiles:files included:on];
    [self reload];
}

- (void)boxClicked:(NSButton *)sender
{
    TSTeXRootTreeCell *cell = (TSTeXRootTreeCell *)sender.superview;
    TSTeXRootTreeNode *node = [cell isKindOfClass:[TSTeXRootTreeCell class]] ? cell.node : nil;
    if (!node)
        return;
    // A mixed folder turns all on; an on one all off.
    [self setNodes:@[node] on:[self stateOfNode:node] != NSControlStateValueOn];
}

- (void)toggleSelectedRows
{
    NSMutableArray<TSTeXRootTreeNode *> *nodes = [NSMutableArray array];
    BOOL allOn = YES;
    NSIndexSet *rows = self.outlineView.selectedRowIndexes;
    for (NSUInteger row = rows.firstIndex; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
        TSTeXRootTreeNode *node = [self.outlineView itemAtRow:(NSInteger)row];
        [nodes addObject:node];
        if ([self stateOfNode:node] != NSControlStateValueOn)
            allOn = NO;
    }
    if (nodes.count)
        [self setNodes:nodes on:!allOn];
}

- (void)toggleRow:(NSInteger)row
{
    TSTeXRootTreeNode *node = [self.outlineView itemAtRow:row];
    if (node)
        [self setNodes:@[node] on:[self stateOfNode:node] != NSControlStateValueOn];
}

- (NSControlStateValue)stateOfRow:(NSInteger)row
{
    TSTeXRootTreeNode *node = [self.outlineView itemAtRow:row];
    return node ? [self stateOfNode:node] : NSControlStateValueOff;
}

- (NSArray<TSTeXRootProjectFile *> *)filesOfRow:(NSInteger)row
{
    TSTeXRootTreeNode *node = [self.outlineView itemAtRow:row];
    return node ? [node files] : @[];
}

- (NSString *)accessibilityLabelOfRow:(NSInteger)row
{
    TSTeXRootTreeNode *node = [self.outlineView itemAtRow:row];
    if (!node)
        return @"";
    NSControlStateValue state = [self stateOfNode:node];
    NSString *stateText = state == NSControlStateValueOn ? TSLocalized(@"TeXRootSearch.AX.Searched", @"searched")
                        : state == NSControlStateValueOff ? TSLocalized(@"TeXRootSearch.AX.NotSearched", @"not searched")
                        : TSLocalized(@"TeXRootSearch.AX.PartlySearched", @"partly searched");
    NSString *label = [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.AX.Node", @"%1$@, items: %2$lu, %3$@"),
                       node.name, (unsigned long)[self countOfNode:node], stateText];
    TSTeXRootSearchOnlyReason reason = [self reasonOfNode:node];
    if (reason != TSTeXRootSearchOnlyReasonNone)
        label = [NSString stringWithFormat:@"%@, %@", label, TSTeXRootSearchOnlyReasonText(reason)];
    return label;
}

@end
