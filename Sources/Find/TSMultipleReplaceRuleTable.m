// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSMultipleReplaceRuleTable.h"
#import "TSAdvancedFindOptionsForm.h"
#import "TSAdvancedFindController.h"

static NSPasteboardType const TSRuleRowType = @"org.texshop.advancedfind.rule-row";
static NSString *const TSColumnEnabled = @"enabled";
static NSString *const TSColumnFind = @"find";
static NSString *const TSColumnReplace = @"replace";
static NSString *const TSColumnRegex = @"regex";
static NSString *const TSColumnCase = @"case";
static NSString *const TSColumnNote = @"note";
static NSString *const TSColumnCount = @"count";

NSDictionary<NSNumber *, NSError *> *TSMultipleReplaceProblems(TSRegexMultipleReplace *set)
{
    NSMutableDictionary<NSNumber *, NSError *> *problems = [NSMutableDictionary dictionary];
    [set.rules enumerateObjectsUsingBlock:^(TSRegexReplacementRule *rule, NSUInteger index, BOOL *stop) {
        if (!rule.enabled)
            return;
        NSError *error = nil;
        if (![[TSRegexFindPattern alloc] initWithFindString:rule.findString options:[set optionsForRule:rule] error:&error])
            problems[@(index)] = error;
    }];
    return problems;
}

static TSRegexReplacementRule *TSRuleWith(TSRegexReplacementRule *rule, NSString *_Nullable find, NSString *_Nullable replace,
                                          NSNumber *_Nullable regex, NSNumber *_Nullable ignoresCase, NSNumber *_Nullable enabled,
                                          NSString *_Nullable note)
{
    NSString *newNote = note ? (note.length > 0 ? note : nil) : rule.note;
    return [[TSRegexReplacementRule alloc] initWithFindString:find ?: rule.findString
                                                replaceString:replace ?: rule.replaceString
                                        usesRegularExpression:regex ? regex.boolValue : rule.usesRegularExpression
                                                  ignoresCase:ignoresCase ? ignoresCase.boolValue : rule.ignoresCase
                                                      enabled:enabled ? enabled.boolValue : rule.enabled
                                                         note:newNote];
}

@interface TSMultipleReplaceRuleTable ()
@property (nonatomic, readwrite) NSTableView *tableView;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSError *> *problems;
@end

@implementation TSMultipleReplaceRuleTable

- (instancetype)init
{
    if ((self = [super init])) {
        _problems = @{};
        _tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
        _tableView.allowsMultipleSelection = YES;
        _tableView.usesAlternatingRowBackgroundColors = YES;
        _tableView.style = NSTableViewStyleFullWidth;
        _tableView.rowHeight = 24;
        _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle; // find, replace and description share the width
        [self addColumn:TSColumnEnabled title:@"" width:22 tip:@"MultipleReplace.Column.EnabledTip" english:@"Use this rule"];
        [self addColumn:TSColumnFind title:TSAdvancedFindLocalized(@"MultipleReplace.Column.Find", @"Find") width:150 tip:nil english:nil];
        [self addColumn:TSColumnReplace title:TSAdvancedFindLocalized(@"MultipleReplace.Column.Replace", @"Replace") width:150 tip:nil english:nil];
        // Short headers, as in CotEditor; the header's tooltip names the option.
        [self addColumn:TSColumnRegex title:@"RE" width:32 tip:@"AdvancedFind.RegularExpression" english:@"Regular expression"];
        [self addColumn:TSColumnCase title:@"IC" width:32 tip:@"AdvancedFind.IgnoreCase" english:@"Ignore case"];
        [self addColumn:TSColumnCount title:TSAdvancedFindLocalized(@"MultipleReplace.Column.Count", @"Count") width:44 tip:@"MultipleReplace.Column.CountTip" english:@"Matches replaced by the last run"];
        [self addColumn:TSColumnNote title:TSAdvancedFindLocalized(@"MultipleReplace.Column.Note", @"Description") width:120 tip:nil english:nil];
        _tableView.dataSource = self;
        _tableView.delegate = self;
        [_tableView registerForDraggedTypes:@[TSRuleRowType]];
        [_tableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    }
    return self;
}

- (void)addColumn:(NSString *)identifier title:(NSString *)title width:(CGFloat)width tip:(nullable NSString *)tipKey english:(nullable NSString *)english
{
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.width = width;
    BOOL fixed = width < 50;
    column.minWidth = fixed ? width : 60;
    column.maxWidth = fixed ? width : 2000;
    column.resizingMask = fixed ? NSTableColumnNoResizing : NSTableColumnUserResizingMask | NSTableColumnAutoresizingMask;
    if (tipKey)
        column.headerToolTip = TSAdvancedFindLocalized((NSString *_Nonnull)tipKey, english ?: @"");
    if (fixed)
        column.headerCell.alignment = NSTextAlignmentCenter;
    [self.tableView addTableColumn:column];
}

#pragma mark Model

- (void)setSet:(nullable TSRegexMultipleReplace *)set
{
    _set = set;
    _counts = nil;
    self.problems = set ? TSMultipleReplaceProblems((TSRegexMultipleReplace *_Nonnull)set) : @{};
    [self.tableView reloadData];
}

- (void)setCounts:(nullable NSArray<NSNumber *> *)counts
{
    _counts = [counts copy];
    [self.tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)self.tableView.numberOfRows)]
                              columnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[self.tableView columnWithIdentifier:TSColumnCount]]];
}

- (void)changeRules:(NSArray<TSRegexReplacementRule *> *)rules
{
    TSRegexMultipleReplace *old = self.set;
    if (!old)
        return;
    TSRegexMultipleReplace *set = [[TSRegexMultipleReplace alloc] initWithRules:rules textualOptions:old.textualOptions
                                                       regularExpressionOptions:old.regularExpressionOptions replacementSyntax:old.replacementSyntax];
    NSIndexSet *selection = self.tableView.selectedRowIndexes;
    self.set = set;
    [self.tableView selectRowIndexes:selection byExtendingSelection:NO];
    if (self.setChangedHandler)
        self.setChangedHandler(set);
}

- (void)replaceRuleAtIndex:(NSUInteger)index withRule:(TSRegexReplacementRule *)rule
{
    NSMutableArray<TSRegexReplacementRule *> *rules = [self.set.rules mutableCopy];
    if (index >= rules.count || [rules[index] isEqual:rule])
        return;
    rules[index] = rule;
    [self changeRules:rules];
}

- (void)addRule
{
    if (!self.set)
        return;
    NSInteger after = self.tableView.selectedRowIndexes.lastIndex;
    NSUInteger index = after == NSNotFound ? self.set.rules.count : (NSUInteger)after + 1;
    NSMutableArray<TSRegexReplacementRule *> *rules = [self.set.rules mutableCopy];
    [rules insertObject:[[TSRegexReplacementRule alloc] initWithFindString:@"" replaceString:@"" usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil] atIndex:index];
    [self changeRules:rules];
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    if (self.tableView.window)
        [self.tableView editColumn:[self.tableView columnWithIdentifier:TSColumnFind] row:(NSInteger)index withEvent:nil select:YES];
}

- (void)removeSelectedRules
{
    NSIndexSet *selected = self.tableView.selectedRowIndexes;
    if (selected.count == 0 || !self.set)
        return;
    NSMutableArray<TSRegexReplacementRule *> *rules = [self.set.rules mutableCopy];
    [rules removeObjectsAtIndexes:selected];
    [self.tableView deselectAll:nil];
    [self changeRules:rules];
}

- (void)moveRulesAtIndexes:(NSIndexSet *)indexes toRow:(NSInteger)row
{
    if (!self.set || indexes.count == 0)
        return;
    NSMutableArray<TSRegexReplacementRule *> *rules = [self.set.rules mutableCopy];
    NSArray<TSRegexReplacementRule *> *moving = [rules objectsAtIndexes:indexes];
    NSUInteger destination = (NSUInteger)row - [indexes countOfIndexesInRange:NSMakeRange(0, (NSUInteger)row)];
    [rules removeObjectsAtIndexes:indexes];
    [rules insertObjects:moving atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(destination, moving.count)]];
    [self changeRules:rules];
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(destination, moving.count)] byExtendingSelection:NO];
}

#pragma mark Cells

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.set.rules.count;
}

/// A cell holding one control, centered in the row's height (and in the column's width for a check box).
+ (NSTableCellView *)cellWithControl:(NSControl *)control
{
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:control];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithObject:[control.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]];
    if ([control isKindOfClass:[NSTextField class]]) {
        cell.textField = (NSTextField *)control;
        [constraints addObjectsFromArray:@[[control.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
                                           [control.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2]]];
    } else {
        [constraints addObject:[control.centerXAnchor constraintEqualToAnchor:cell.centerXAnchor]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return cell;
}

- (NSTableCellView *)checkBoxIdentifier:(NSString *)identifier on:(BOOL)on
{
    NSButton *box = [NSButton checkboxWithTitle:@"" target:self action:@selector(checkBoxChanged:)];
    box.identifier = identifier;
    box.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    return [TSMultipleReplaceRuleTable cellWithControl:box];
}

- (NSTextField *)fieldIdentifier:(NSString *)identifier
{
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.identifier = identifier;
    field.bordered = NO;
    field.drawsBackground = NO;
    field.editable = YES;
    field.delegate = self;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    // A cut text shows in full while the pointer rests on it.
    field.allowsExpansionToolTips = YES;
    field.font = [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    return field;
}

/// The text of a find or replacement cell: plain, or as `fieldStyler` colors it.
- (NSAttributedString *)styledString:(NSString *)string ofRule:(TSRegexReplacementRule *)rule field:(TSMultipleReplaceRuleField)field
                             options:(TSRegexFindOptions)options attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes
{
    NSAttributedString *_Nullable (^styler)(NSString *, TSRegexReplacementRule *, TSMultipleReplaceRuleField, TSRegexFindOptions, NSDictionary *) = self.fieldStyler;
    NSAttributedString *styled = styler ? styler(string, rule, field, options, attributes) : nil;
    return styled ?: [[NSAttributedString alloc] initWithString:string attributes:attributes];
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)column row:(NSInteger)row
{
    TSRegexReplacementRule *rule = self.set.rules[(NSUInteger)row];
    NSString *identifier = column.identifier;
    TSRegexFindOptions options = [self.set optionsForRule:rule];
    NSDictionary *plain = @{NSFontAttributeName: [NSFont monospacedSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular],
                            NSForegroundColorAttributeName: rule.enabled ? NSColor.labelColor : NSColor.tertiaryLabelColor};
    if ([identifier isEqualToString:TSColumnEnabled])
        return [self checkBoxIdentifier:identifier on:rule.enabled];
    if ([identifier isEqualToString:TSColumnRegex])
        return [self checkBoxIdentifier:identifier on:rule.usesRegularExpression];
    if ([identifier isEqualToString:TSColumnCase])
        return [self checkBoxIdentifier:identifier on:rule.ignoresCase];
    if ([identifier isEqualToString:TSColumnFind]) {
        NSTextField *field = [self fieldIdentifier:identifier];
        field.attributedStringValue = [self styledString:rule.findString ofRule:rule field:TSMultipleReplaceRuleFieldFind options:options attributes:plain];
        field.placeholderString = TSAdvancedFindLocalized(@"MultipleReplace.Column.Find", @"Find");
        return [TSMultipleReplaceRuleTable cellWithControl:field];
    }
    if ([identifier isEqualToString:TSColumnReplace]) {
        NSTextField *field = [self fieldIdentifier:identifier];
        field.attributedStringValue = [self styledString:rule.replaceString ofRule:rule field:TSMultipleReplaceRuleFieldReplace options:options attributes:plain];
        return [TSMultipleReplaceRuleTable cellWithControl:field];
    }
    if ([identifier isEqualToString:TSColumnNote]) {
        NSTextField *field = [self fieldIdentifier:identifier];
        field.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        field.stringValue = rule.note ?: @"";
        field.textColor = NSColor.secondaryLabelColor;
        return [TSMultipleReplaceRuleTable cellWithControl:field];
    }
    // The count of the last run, or a mark for a rule that cannot be used.
    NSTextField *label = [NSTextField labelWithString:@""];
    label.alignment = NSTextAlignmentRight;
    label.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    NSError *problem = self.problems[@(row)];
    if (problem) {
        label.stringValue = @"⚠︎";
        label.textColor = NSColor.systemRedColor;
        label.toolTip = problem.localizedDescription;
    } else if (self.counts && (NSUInteger)row < self.counts.count && rule.enabled) {
        label.stringValue = self.counts[(NSUInteger)row].stringValue ?: @"";
        label.textColor = self.counts[(NSUInteger)row].unsignedIntegerValue > 0 ? NSColor.labelColor : NSColor.tertiaryLabelColor;
    }
    return [TSMultipleReplaceRuleTable cellWithControl:label];
}

- (void)checkBoxChanged:(NSButton *)box
{
    NSInteger row = [self.tableView rowForView:box];
    if (row < 0)
        return;
    NSNumber *on = @(box.state == NSControlStateValueOn);
    TSRegexReplacementRule *rule = self.set.rules[(NSUInteger)row];
    NSString *identifier = box.identifier;
    [self replaceRuleAtIndex:(NSUInteger)row withRule:TSRuleWith(rule, nil, nil,
        [identifier isEqualToString:TSColumnRegex] ? on : nil,
        [identifier isEqualToString:TSColumnCase] ? on : nil,
        [identifier isEqualToString:TSColumnEnabled] ? on : nil, nil)];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    NSInteger row = [self.tableView rowForView:field];
    if (row < 0 || (NSUInteger)row >= self.set.rules.count)
        return;
    TSRegexReplacementRule *rule = self.set.rules[(NSUInteger)row];
    NSString *text = field.stringValue, *identifier = field.identifier;
    [self replaceRuleAtIndex:(NSUInteger)row withRule:TSRuleWith(rule,
        [identifier isEqualToString:TSColumnFind] ? text : nil,
        [identifier isEqualToString:TSColumnReplace] ? text : nil, nil, nil, nil,
        [identifier isEqualToString:TSColumnNote] ? text : nil)];
}

#pragma mark Dragging

- (nullable id<NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row
{
    NSPasteboardItem *item = [NSPasteboardItem new];
    [item setString:@(row).stringValue forType:TSRuleRowType];
    return item;
}

- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
    if (info.draggingSource != tableView)
        return NSDragOperationNone;
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NSPasteboardItem *item in info.draggingPasteboard.pasteboardItems) {
        NSString *value = [item stringForType:TSRuleRowType];
        if (value)
            [indexes addIndex:(NSUInteger)value.integerValue];
    }
    [self moveRulesAtIndexes:indexes toRow:row];
    return indexes.count > 0;
}

@end
