// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSTeXRootSearchResultsList.h"
#import "TSAdvancedFindController.h"

#define TSLocalized TSAdvancedFindLocalized

static const NSUInteger TSShownLines = TSTeXRootSearchMaximumShownLines;
/// A wait before the whole change is built, set by the tests to change the list meanwhile.
static NSTimeInterval TSWholeChangeTestDelay;
/// Characters kept before a match whose line starts are cut so that the match shows in its column ("…" in their place).
static const NSUInteger TSLeadKept = 8;

NSString *TSTeXRootSearchOnlyReasonText(TSTeXRootSearchOnlyReason reason)
{
    switch ((NSInteger)reason) {
        case TSTeXRootSearchOnlyReasonUndecodable:
            return TSLocalized(@"TeXRootSearch.Reason.Undecodable", @"Cannot be replaced in: the file does not read in its encoding.");
        case TSTeXRootSearchOnlyReasonRoundTrip:
            return TSLocalized(@"TeXRootSearch.Reason.RoundTrip", @"Cannot be replaced in: saving the file in its encoding would change it.");
        case TSTeXRootSearchOnlyReasonHardLink:
            return TSLocalized(@"TeXRootSearch.Reason.HardLink", @"Cannot be replaced in: the file has other names (hard links).");
        case TSTeXRootSearchOnlyReasonNotWritable:
            return TSLocalized(@"TeXRootSearch.Reason.NotWritable", @"Cannot be replaced in: the file cannot be written.");
        case 100: // TSTeXRootSearchOnlyReasonUnencodable
            return TSLocalized(@"TeXRootSearch.Reason.Unencodable", @"Cannot be replaced in: the replaced text cannot be written in the file’s encoding.");
        case 101: // TSTeXRootSearchOnlyReasonNotEditable
            return TSLocalized(@"TeXRootSearch.Reason.NotEditable", @"Cannot be replaced in: the document cannot be edited.");
        case 102: // TSTeXRootSearchOnlyReasonOpenTwice
            return TSLocalized(@"TeXRootSearch.Reason.OpenTwice", @"Cannot be replaced in: the file is open in more than one document.");
        default:
            return @"";
    }
}

/// The check box of an item's row, which knows its item.
@interface TSTeXRootSearchCheckButton : NSButton
@property (nonatomic, weak) TSTeXRootSearchFileResult *file;
@property (nonatomic, weak) TSTeXRootSearchItem *item;
@end

@implementation TSTeXRootSearchCheckButton
@end

/// Space turns the selected items on or off, Return shows the selected item.
@interface TSTeXRootSearchResultsTableView : NSTableView
@property (nonatomic, copy, nullable) void (^spaceHandler)(void);
@property (nonatomic, copy, nullable) void (^returnHandler)(void);
@property (nonatomic, copy, nullable) void (^wholeHandler)(void);
@end

@implementation TSTeXRootSearchResultsTableView

- (void)keyDown:(NSEvent *)event
{
    NSString *characters = event.charactersIgnoringModifiers;
    NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask & ~(NSEventModifierFlagNumericPad | NSEventModifierFlagFunction);
    if (modifiers == 0 && [characters isEqualToString:@" "] && self.spaceHandler) {
        self.spaceHandler();
        return;
    }
    if (modifiers == 0 && ([characters isEqualToString:@"\r"] || [characters isEqualToString:@"\x03"]) && self.returnHandler) {
        self.returnHandler();
        return;
    }
    if (modifiers == NSEventModifierFlagCommand && [characters.lowercaseString isEqualToString:@"y"] && self.wholeHandler) {
        self.wholeHandler();
        return;
    }
    [super keyDown:event];
}

@end

/// The row of an item, read by VoiceOver as one line.
@interface TSTeXRootSearchRowView : NSTableRowView
@property (nonatomic, copy, nullable) NSString *spokenLabel;
@end

@implementation TSTeXRootSearchRowView
- (NSString *)accessibilityLabel { return self.spokenLabel ?: [super accessibilityLabel]; }
@end

@interface TSTeXRootSearchResultsList ()
@property (nonatomic, readonly) TSTeXRootSearchModel *model;
@property (nonatomic, readwrite) NSScrollView *scrollView;
@property (nonatomic, readwrite) NSTableView *tableView;
@property (nonatomic, copy) NSArray<TSTeXRootSearchFileResult *> *files;
/// The row of each file's heading (NSUInteger each); its items follow it.
@property (nonatomic, strong) NSMutableData *starts;
@property (nonatomic) NSInteger rowCount;
@property (nonatomic) TSTeXRootSearchMode shownMode;
@property (nonatomic) BOOL fitting;
@property (nonatomic, strong, nullable) NSPopover *wholePopover;
@property (nonatomic) NSUInteger wholeRequest;
/// The generation the whole change shown, or being made, was asked for.
@property (nonatomic) NSUInteger wholeGeneration;
@end

@implementation TSTeXRootSearchResultsList

- (instancetype)initWithModel:(TSTeXRootSearchModel *)model
{
    if (!(self = [super init]))
        return nil;
    _model = model;
    _files = @[];
    _starts = [NSMutableData data];
    _font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    TSTeXRootSearchResultsTableView *table = [[TSTeXRootSearchResultsTableView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    __weak typeof(self) weakSelf = self;
    table.spaceHandler = ^{ [weakSelf toggleSelectedItems]; };
    table.returnHandler = ^{ [weakSelf showClickedItem:NO selected:YES]; };
    table.wholeHandler = ^{ [weakSelf showWholeChangeOfRow:weakSelf.tableView.selectedRow]; };
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *whole = [menu addItemWithTitle:TSLocalized(@"TeXRootSearch.ShowAll", @"Show All Lines") action:@selector(showWholeChange:) keyEquivalent:@"y"];
    whole.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    whole.target = self;
    table.menu = menu;
    for (NSString *identifier in @[@"check", @"line", @"before", @"after"]) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
        column.editable = NO;
        if ([identifier isEqualToString:@"check"]) {
            column.width = column.minWidth = column.maxWidth = 22;
            column.resizingMask = NSTableColumnNoResizing;
        } else if ([identifier isEqualToString:@"line"]) {
            column.width = column.minWidth = column.maxWidth = 44;
            column.resizingMask = NSTableColumnNoResizing;
        } else {
            // Before and after share the rest of the width.
            column.width = 200;
            column.minWidth = 80;
            column.resizingMask = NSTableColumnAutoresizingMask;
        }
        [table addTableColumn:column];
    }
    table.headerView = nil;
    table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    table.allowsMultipleSelection = YES;
    table.usesAlternatingRowBackgroundColors = NO;
    table.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    table.style = NSTableViewStylePlain;
    table.floatsGroupRows = YES;
    table.dataSource = self;
    table.delegate = self;
    table.target = self;
    table.action = @selector(rowClicked:);
    table.doubleAction = @selector(rowDoubleClicked:);
    table.accessibilityLabel = TSLocalized(@"TeXRootSearch.AX.Results", @"Results");
    _tableView = table;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
    scroll.documentView = table;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    _scrollView = scroll;
    // Before and after share the visible width equally; the list never scrolls sideways.
    scroll.contentView.postsFrameChangedNotifications = YES;
    table.postsFrameChangedNotifications = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fitColumns) name:NSViewFrameDidChangeNotification object:scroll.contentView];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fitColumns) name:NSViewFrameDidChangeNotification object:table];
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)fitColumns
{
    if (self.fitting)
        return;
    self.fitting = YES;
    NSTableView *table = self.tableView;
    CGFloat visible = NSWidth(self.scrollView.contentView.bounds);
    NSArray<NSTableColumn *> *columns = table.tableColumns;
    CGFloat fixed = 0;
    NSUInteger shown = 0;
    NSMutableArray<NSTableColumn *> *text = [NSMutableArray array];
    for (NSTableColumn *column in columns) {
        if (column.hidden)
            continue;
        shown++;
        if ([column.identifier isEqualToString:@"before"] || [column.identifier isEqualToString:@"after"])
            [text addObject:column];
        else
            fixed += column.width;
    }
    CGFloat each = text.count ? MAX(80, floor((visible - fixed - table.intercellSpacing.width * (CGFloat)shown) / (CGFloat)text.count)) : 0;
    BOOL changed = NO;
    for (NSTableColumn *column in text)
        if (fabs(column.width - each) > 0.5) {
            column.width = each;
            changed = YES;
        }
    if (fabs(NSWidth(table.frame) - visible) > 0.5)
        [table setFrameSize:NSMakeSize(visible, NSHeight(table.frame))];
    self.fitting = NO;
    // Where a long line is cut depends on the width.
    NSRange rows = [table rowsInRect:table.visibleRect];
    if (changed && rows.length > 0)
        [self refreshRows:[NSIndexSet indexSetWithIndexesInRange:rows]];
}

#pragma mark Rows

- (void)reload
{
    NSArray<TSTeXRootSearchFileResult *> *files = self.model.results;
    BOOL sameFiles = files.count == self.files.count;
    for (NSUInteger i = 0; sameFiles && i < files.count; i++)
        sameFiles = [files[i].source.file.identifier isEqual:self.files[i].source.file.identifier];
    NSPoint origin = self.scrollView.contentView.bounds.origin;
    self.files = files;
    self.starts.length = files.count * sizeof(NSUInteger);
    NSUInteger *starts = self.starts.mutableBytes;
    NSInteger row = 0;
    for (NSUInteger index = 0; index < files.count; index++) {
        starts[index] = (NSUInteger)row;
        row += 1 + (NSInteger)files[index].items.count;
    }
    self.rowCount = row;
    self.shownMode = self.model.mode;
    BOOL replacing = self.shownMode != TSTeXRootSearchModeFind;
    [self.tableView tableColumnWithIdentifier:@"check"].hidden = !replacing;
    [self.tableView tableColumnWithIdentifier:@"after"].hidden = !replacing;
    // A whole change shown or being made belongs to the list before.
    self.wholeRequest++;
    [self.wholePopover close];
    self.wholePopover = nil;
    [self fitColumns];
    [self.tableView reloadData];
    if (sameFiles)
        [self.scrollView.contentView scrollToPoint:origin];
    else
        [self.tableView scrollRowToVisible:0];
    [self.scrollView reflectScrolledClipView:self.scrollView.contentView];
}

/// The index of the file whose heading is at or before `row`.
- (NSUInteger)fileIndexOfRow:(NSInteger)row
{
    const NSUInteger *starts = self.starts.bytes;
    NSUInteger low = 0, high = self.files.count;
    while (high - low > 1) {
        NSUInteger middle = (low + high) / 2;
        if (starts[middle] <= (NSUInteger)row)
            low = middle;
        else
            high = middle;
    }
    return low;
}

- (nullable id)objectAtRow:(NSInteger)row
{
    if (row < 0 || row >= self.rowCount || self.files.count == 0)
        return nil;
    NSUInteger index = [self fileIndexOfRow:row];
    NSUInteger start = ((const NSUInteger *)self.starts.bytes)[index];
    TSTeXRootSearchFileResult *file = self.files[index];
    return (NSUInteger)row == start ? file : file.items[(NSUInteger)row - start - 1];
}

- (nullable TSTeXRootSearchFileResult *)fileOfRow:(NSInteger)row
{
    if (row < 0 || row >= self.rowCount || self.files.count == 0)
        return nil;
    return self.files[[self fileIndexOfRow:row]];
}

- (NSInteger)rowOfItem:(TSTeXRootSearchItem *)item inFile:(TSTeXRootSearchFileResult *)file
{
    NSUInteger index = [self.files indexOfObjectIdenticalTo:file];
    if (index == NSNotFound)
        return -1;
    NSUInteger position = [file.items indexOfObjectIdenticalTo:item];
    return position == NSNotFound ? -1 : (NSInteger)(((const NSUInteger *)self.starts.bytes)[index] + 1 + position);
}

- (NSInteger)rowOfObject:(id)object
{
    NSUInteger index = [self.files indexOfObjectIdenticalTo:object];
    if (index != NSNotFound)
        return (NSInteger)((const NSUInteger *)self.starts.bytes)[index];
    for (TSTeXRootSearchFileResult *file in self.files) {
        NSInteger row = [self rowOfItem:object inFile:file];
        if (row >= 0)
            return row;
    }
    return -1;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.rowCount;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
    return [[self objectAtRow:row] isKindOfClass:[TSTeXRootSearchFileResult class]];
}

#pragma mark Texts

/// About how many characters of the font a text column shows.
- (NSUInteger)shownColumns
{
    NSTableColumn *column = [self.tableView tableColumnWithIdentifier:@"before"];
    CGFloat advance = [@"0" sizeWithAttributes:@{NSFontAttributeName: self.font}].width;
    if (!column || advance <= 0)
        return NSUIntegerMax;
    return (NSUInteger)MAX(10, floor((column.width - 8) / advance) - 1);
}

/// The lines of an item as shown: the highlight on the match (or a thin mark for an empty one), the start of a
/// long line cut, and at most TSShownLines lines.
- (NSAttributedString *)displayText:(NSString *)text highlight:(NSRange)highlight color:(nullable NSColor *)color textColor:(NSColor *)textColor
{
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *base = @{NSFontAttributeName: self.font, NSForegroundColorAttributeName: textColor, NSParagraphStyleAttributeName: paragraph};
    NSMutableAttributedString *shown = [[NSMutableAttributedString alloc] initWithString:text attributes:base];
    if (NSMaxRange(highlight) > text.length) // never, as the items are made; kept inside the text all the same
        highlight = NSMakeRange(MIN(highlight.location, text.length), 0);
    if (color && highlight.length > 0)
        [shown addAttribute:NSBackgroundColorAttributeName value:(NSColor *_Nonnull)color range:highlight];
    NSUInteger lineStart = 0;
    [text getLineStart:&lineStart end:NULL contentsEnd:NULL forRange:NSMakeRange(highlight.location, 0)];
    NSUInteger mark = highlight.location;
    if (color && highlight.length == 0) {
        NSDictionary *markAttributes = @{NSFontAttributeName: self.font, NSForegroundColorAttributeName: [(NSColor *_Nonnull)color colorWithAlphaComponent:1],
                                         NSParagraphStyleAttributeName: paragraph};
        [shown insertAttributedString:[[NSAttributedString alloc] initWithString:@"▏" attributes:markAttributes] atIndex:mark];
    }
    // A match that would end past the column's width: the start of its line is cut, so that the match shows.
    NSUInteger columns = [self shownColumns];
    NSUInteger lineEnd = 0, contentsEnd = 0;
    [text getLineStart:NULL end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(highlight.location, 0)];
    NSUInteger matchEnd = MIN(NSMaxRange(highlight) + (highlight.length == 0 ? 1 : 0), contentsEnd);
    if (matchEnd > lineStart + columns && highlight.location - lineStart > TSLeadKept + 1) {
        NSRange cut = NSMakeRange(lineStart, highlight.location - lineStart - TSLeadKept);
        cut = [text rangeOfComposedCharacterSequencesForRange:cut];
        cut.length = MIN(cut.length, highlight.location - lineStart);
        [shown replaceCharactersInRange:cut withAttributedString:[[NSAttributedString alloc] initWithString:@"…" attributes:base]];
    }
    NSString *string = shown.string;
    NSUInteger end = 0, lines = 0;
    while (end < string.length && lines < TSShownLines) {
        NSUInteger next = 0;
        [string getLineStart:NULL end:&next contentsEnd:NULL forRange:NSMakeRange(end, 0)];
        end = next;
        lines++;
    }
    // The lines past the 20th are cut, and the last line says how many more there are (the whole change: ⌘Y); one
    // line more fits where its count would go, so 21 lines are shown whole.
    NSUInteger more = 0;
    for (NSUInteger location = end; location < string.length; more++) {
        NSUInteger next = 0;
        [string getLineStart:NULL end:&next contentsEnd:NULL forRange:NSMakeRange(location, 0)];
        location = next;
    }
    if (more >= 2) {
        [shown deleteCharactersInRange:NSMakeRange(end, string.length - end)];
        NSString *rest = [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.MoreLines", @"⋯ %lu more lines"), (unsigned long)more];
        NSMutableDictionary *restAttributes = [base mutableCopy];
        restAttributes[NSForegroundColorAttributeName] = NSColor.secondaryLabelColor;
        [shown appendAttributedString:[[NSAttributedString alloc] initWithString:rest attributes:restAttributes]];
    }
    return shown;
}

- (nullable NSAttributedString *)shownTextOfItem:(TSTeXRootSearchItem *)item inFile:(TSTeXRootSearchFileResult *)file after:(BOOL)after
{
    BOOL replacing = self.model.mode != TSTeXRootSearchModeFind;
    BOOL replaceable = replacing && file.searchOnlyReason == TSTeXRootSearchOnlyReasonNone;
    BOOL on = replaceable && [self.model isItemIncluded:item inFile:file];
    NSColor *muted = NSColor.secondaryLabelColor;
    if (!after) {
        NSColor *color = !replacing ? [NSColor.systemYellowColor colorWithAlphaComponent:0.45]
                       : on ? [NSColor.systemRedColor colorWithAlphaComponent:0.25] : nil;
        return [self displayText:item.beforeText highlight:item.beforeHighlight color:color textColor:replaceable && !on ? muted : NSColor.labelColor];
    }
    if (!replacing || !replaceable)
        return nil;
    if (!on) // what stays: the lines as they are
        return [self displayText:item.beforeText highlight:item.beforeHighlight color:nil textColor:muted];
    return [self displayText:item.afterText ?: @"" highlight:item.afterHighlight color:[NSColor.systemGreenColor colorWithAlphaComponent:0.3]
                   textColor:NSColor.labelColor];
}

/// The line numbers of the lines an item shows, one under the other.
- (NSString *)lineNumbersOfItem:(TSTeXRootSearchItem *)item
{
    // As many as the lines shown: all of 21, otherwise 20 at most (the 21st line then says how many more).
    NSUInteger lines = 0, location = 0, length = item.beforeText.length;
    while (location < length && lines <= TSShownLines + 1) {
        NSUInteger next = 0;
        [item.beforeText getLineStart:NULL end:&next contentsEnd:NULL forRange:NSMakeRange(location, 0)];
        location = next;
        lines++;
    }
    lines = MAX((NSUInteger)1, lines > TSShownLines + 1 ? TSShownLines : lines);
    NSMutableArray<NSString *> *numbers = [NSMutableArray array];
    for (NSUInteger k = 0; k < lines; k++)
        [numbers addObject:[NSString stringWithFormat:@"%lu", (unsigned long)(item.lineNumber + k)]];
    return [numbers componentsJoinedByString:@"\n"];
}

#pragma mark Views

- (NSTextField *)labelInView:(NSTableCellView *)cell
{
    if (!cell.textField) {
        NSTextField *label = [NSTextField labelWithString:@""];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.maximumNumberOfLines = 0;
        label.cell.wraps = NO;
        label.cell.truncatesLastVisibleLine = YES;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
            [label.topAnchor constraintEqualToAnchor:cell.topAnchor constant:3],
        ]];
        cell.textField = label;
    }
    return cell.textField;
}

- (NSTableCellView *)cellWithIdentifier:(NSString *)identifier
{
    NSTableCellView *cell = [self.tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        cell.identifier = identifier;
    }
    return cell;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{
    id object = [self objectAtRow:row];
    TSTeXRootSearchFileResult *file = [self fileOfRow:row];
    if (!object || !file)
        return nil;
    if (object == file) {
        if (tableColumn) // a group row is one cell, across the columns
            return nil;
        NSTableCellView *cell = [self cellWithIdentifier:@"file"];
        NSTextField *label = [self labelInView:cell];
        NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:file.source.file.relativePath
                                                                                  attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightSemibold]}];
        NSString *count = [NSString stringWithFormat:@"  %lu", (unsigned long)file.items.count];
        if (file.truncated)
            count = [count stringByAppendingString:@"+"];
        [title appendAttributedString:[[NSAttributedString alloc] initWithString:count attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize], NSForegroundColorAttributeName: NSColor.secondaryLabelColor}]];
        BOOL searchOnly = self.model.mode != TSTeXRootSearchModeFind && file.searchOnlyReason != TSTeXRootSearchOnlyReasonNone;
        if (searchOnly)
            [title appendAttributedString:[[NSAttributedString alloc] initWithString:@"  ⊘" attributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize], NSForegroundColorAttributeName: NSColor.secondaryLabelColor}]];
        label.attributedStringValue = title;
        label.toolTip = searchOnly ? TSTeXRootSearchOnlyReasonText(file.searchOnlyReason) : file.source.file.url.path;
        return cell;
    }
    TSTeXRootSearchItem *entry = object;
    NSString *column = tableColumn.identifier;
    if ([column isEqualToString:@"check"]) {
        if (file.searchOnlyReason != TSTeXRootSearchOnlyReasonNone) {
            NSTableCellView *cell = [self cellWithIdentifier:@"searchOnly"];
            NSTextField *label = [self labelInView:cell];
            label.stringValue = @"⊘";
            label.textColor = NSColor.secondaryLabelColor;
            label.toolTip = TSTeXRootSearchOnlyReasonText(file.searchOnlyReason);
            label.accessibilityLabel = label.toolTip;
            return cell;
        }
        TSTeXRootSearchCheckButton *box = [tableView makeViewWithIdentifier:@"checkBox" owner:self];
        if (!box) {
            box = [TSTeXRootSearchCheckButton checkboxWithTitle:@"" target:self action:@selector(checkBoxClicked:)];
            box.identifier = @"checkBox";
            box.controlSize = NSControlSizeSmall;
        }
        box.file = file;
        box.item = entry;
        box.state = [self.model isItemIncluded:entry inFile:file] ? NSControlStateValueOn : NSControlStateValueOff;
        box.accessibilityLabel = TSLocalized(@"TeXRootSearch.AX.Replace", @"Replace");
        return box;
    }
    NSTableCellView *cell = [self cellWithIdentifier:column];
    NSTextField *label = [self labelInView:cell];
    label.toolTip = nil;
    if ([column isEqualToString:@"line"]) {
        label.font = [NSFont monospacedDigitSystemFontOfSize:self.font.pointSize - 1 weight:NSFontWeightRegular];
        label.textColor = NSColor.secondaryLabelColor;
        label.alignment = NSTextAlignmentRight;
        label.stringValue = [self lineNumbersOfItem:entry];
        return cell;
    }
    NSAttributedString *text = [self shownTextOfItem:entry inFile:file after:[column isEqualToString:@"after"]];
    label.attributedStringValue = text ?: [NSAttributedString new];
    return cell;
}

/// The height of an item's row comes from the lines worked out with the search: nothing is measured here.
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    if (row < 0 || row >= self.rowCount || self.files.count == 0)
        return 20;
    NSUInteger index = [self fileIndexOfRow:row];
    NSUInteger start = ((const NSUInteger *)self.starts.bytes)[index];
    if ((NSUInteger)row == start)
        return 22;
    CGFloat line = ceil(self.font.ascender - self.font.descender + self.font.leading) + 1;
    NSUInteger lines = [self.model shownLinesOfItemAtIndex:(NSUInteger)row - start - 1 inFile:self.files[index]];
    return MAX(20, line * (CGFloat)lines + 6);
}

- (nullable NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
    TSTeXRootSearchRowView *view = [TSTeXRootSearchRowView new];
    view.spokenLabel = [self accessibilityLabelOfRow:row];
    return view;
}

- (NSString *)accessibilityLabelOfRow:(NSInteger)row
{
    id object = [self objectAtRow:row];
    TSTeXRootSearchFileResult *file = [self fileOfRow:row];
    if (!object || !file)
        return @"";
    if (object == file) {
        NSString *label = [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.AX.File", @"%1$@, items: %2$lu"), file.source.file.relativePath, (unsigned long)file.items.count];
        if (self.model.mode != TSTeXRootSearchModeFind && file.searchOnlyReason != TSTeXRootSearchOnlyReasonNone)
            label = [NSString stringWithFormat:@"%@, %@", label, TSTeXRootSearchOnlyReasonText(file.searchOnlyReason)];
        return label;
    }
    TSTeXRootSearchItem *entry = object;
    NSString *before = [[self shownTextOfItem:entry inFile:file after:NO].string stringByReplacingOccurrencesOfString:@"\u258F" withString:@""] ?: @"";
    if (self.model.mode == TSTeXRootSearchModeFind || file.searchOnlyReason != TSTeXRootSearchOnlyReasonNone)
        return [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.AX.FindRow", @"Line %1$lu: %2$@"), (unsigned long)entry.lineNumber, before];
    NSString *after = [[self shownTextOfItem:entry inFile:file after:YES].string stringByReplacingOccurrencesOfString:@"\u258F" withString:@""] ?: @"";
    NSString *state = [self.model isItemIncluded:entry inFile:file] ? TSLocalized(@"TeXRootSearch.AX.On", @"replaced")
                                                                    : TSLocalized(@"TeXRootSearch.AX.Off", @"not replaced");
    return [NSString stringWithFormat:TSLocalized(@"TeXRootSearch.AX.ReplaceRow", @"Line %1$lu: %2$@, after: %3$@, %4$@"),
            (unsigned long)entry.lineNumber, before, after, state];
}

#pragma mark Actions

- (void)refreshRows:(NSIndexSet *)rows
{
    if (rows.count == 0)
        return;
    [self.tableView reloadDataForRowIndexes:rows columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)self.tableView.numberOfColumns)]];
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        TSTeXRootSearchRowView *view = (TSTeXRootSearchRowView *)[self.tableView rowViewAtRow:(NSInteger)row makeIfNecessary:NO];
        if ([view isKindOfClass:[TSTeXRootSearchRowView class]])
            view.spokenLabel = [self accessibilityLabelOfRow:(NSInteger)row];
    }];
}

- (void)checkBoxClicked:(TSTeXRootSearchCheckButton *)sender
{
    TSTeXRootSearchItem *item = sender.item;
    TSTeXRootSearchFileResult *file = sender.file;
    if (!item || !file)
        return;
    [self.model setItems:@[item] inFile:file included:sender.state == NSControlStateValueOn];
    NSInteger row = [self rowOfItem:item inFile:file];
    if (row >= 0)
        [self refreshRows:[NSIndexSet indexSetWithIndex:(NSUInteger)row]];
}

/// Space: the selected items (and the items of selected headings) go off when all are on, on otherwise.
- (void)toggleSelectedItems
{
    if (self.model.mode == TSTeXRootSearchModeFind)
        return;
    NSMapTable<TSTeXRootSearchFileResult *, NSMutableArray<TSTeXRootSearchItem *> *> *byFile = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableIndexSet *changed = [NSMutableIndexSet indexSet];
    BOOL allOn = YES;
    NSIndexSet *rows = self.tableView.selectedRowIndexes;
    for (NSUInteger row = rows.firstIndex; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
        id object = [self objectAtRow:(NSInteger)row];
        TSTeXRootSearchFileResult *file = [self fileOfRow:(NSInteger)row];
        if (!file || file.searchOnlyReason != TSTeXRootSearchOnlyReasonNone)
            continue;
        BOOL heading = object == file;
        NSArray<TSTeXRootSearchItem *> *items = heading ? file.items : @[object];
        NSMutableArray<TSTeXRootSearchItem *> *list = [byFile objectForKey:file] ?: [NSMutableArray array];
        [byFile setObject:list forKey:file];
        [list addObjectsFromArray:items];
        NSUInteger first = heading ? row + 1 : row;
        [changed addIndexesInRange:NSMakeRange(first, items.count)];
        for (TSTeXRootSearchItem *entry in items)
            if (![self.model isItemIncluded:entry inFile:file])
                allOn = NO;
    }
    for (TSTeXRootSearchFileResult *file in byFile)
        [self.model setItems:(NSArray *_Nonnull)[byFile objectForKey:file] inFile:file included:!allOn];
    NSRange visible = [self.tableView rowsInRect:self.tableView.visibleRect];
    NSMutableIndexSet *shown = [NSMutableIndexSet indexSet];
    [changed enumerateIndexesInRange:visible options:0 usingBlock:^(NSUInteger row, BOOL *stop) { [shown addIndex:row]; }];
    [self refreshRows:shown];
}

- (void)showClickedItem:(BOOL)front selected:(BOOL)selected
{
    NSInteger row = selected ? self.tableView.selectedRow : self.tableView.clickedRow;
    id object = [self objectAtRow:row];
    TSTeXRootSearchFileResult *file = [self fileOfRow:row];
    if (![object isKindOfClass:[TSTeXRootSearchItem class]] || !file || !self.showItemHandler)
        return;
    self.showItemHandler(file, object, front);
}

#pragma mark The whole change

/// Every line of a text with its highlight (or the thin mark of an empty one), nothing cut. Pure: built on a background
/// queue, as the whole change of a long item can have many thousands of lines (spec §2.9).
static NSAttributedString *TSWholeText(NSString *text, NSRange highlight, NSColor *_Nullable color, NSColor *textColor, NSFont *font)
{
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByClipping;
    NSDictionary *base = @{NSFontAttributeName: font, NSForegroundColorAttributeName: textColor, NSParagraphStyleAttributeName: paragraph};
    NSMutableAttributedString *whole = [[NSMutableAttributedString alloc] initWithString:text attributes:base];
    if (NSMaxRange(highlight) > text.length)
        highlight = NSMakeRange(MIN(highlight.location, text.length), 0);
    if (color && highlight.length > 0)
        [whole addAttribute:NSBackgroundColorAttributeName value:(NSColor *_Nonnull)color range:highlight];
    if (color && highlight.length == 0)
        [whole insertAttributedString:[[NSAttributedString alloc] initWithString:@"\u258F" attributes:@{
            NSFontAttributeName: font, NSForegroundColorAttributeName: [(NSColor *_Nonnull)color colorWithAlphaComponent:1], NSParagraphStyleAttributeName: paragraph}]
                              atIndex:highlight.location];
    return whole;
}

/// What the whole change of an item shows, decided on the main thread: for before and after, the text, its highlight
/// and colors, as the row shows them.
- (NSArray<NSArray *> *)wholeChangePartsOfItem:(TSTeXRootSearchItem *)item inFile:(TSTeXRootSearchFileResult *)file
{
    BOOL replacing = self.model.mode != TSTeXRootSearchModeFind;
    BOOL replaceable = replacing && file.searchOnlyReason == TSTeXRootSearchOnlyReasonNone;
    BOOL on = replaceable && [self.model isItemIncluded:item inFile:file];
    NSColor *muted = NSColor.secondaryLabelColor;
    NSNull *none = [NSNull null];
    NSMutableArray<NSArray *> *parts = [NSMutableArray array];
    NSColor *beforeColor = !replacing ? [NSColor.systemYellowColor colorWithAlphaComponent:0.45] : on ? [NSColor.systemRedColor colorWithAlphaComponent:0.25] : nil;
    [parts addObject:@[@NO, item.beforeText, [NSValue valueWithRange:item.beforeHighlight], beforeColor ?: none, replaceable && !on ? muted : NSColor.labelColor]];
    if (replaceable) {
        if (on)
            [parts addObject:@[@YES, item.afterText ?: @"", [NSValue valueWithRange:item.afterHighlight], [NSColor.systemGreenColor colorWithAlphaComponent:0.3], NSColor.labelColor]];
        else
            [parts addObject:@[@YES, item.beforeText, [NSValue valueWithRange:item.beforeHighlight], none, muted]];
    }
    return parts;
}

/// Two scrolling texts, laid out only where they are seen (non-contiguous layout), so that showing even a very long
/// change takes little time on the main thread.
- (NSViewController *)wholeChangeViewControllerWithTexts:(NSArray<NSArray *> *)texts
{
    NSMutableArray<NSView *> *columns = [NSMutableArray array];
    for (NSArray *pair in texts) {
        BOOL after = [pair[0] boolValue];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 320, 360)];
        scroll.hasVerticalScroller = YES;
        scroll.hasHorizontalScroller = YES;
        scroll.borderType = NSBezelBorder;
        NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 320, 360)];
        view.layoutManager.allowsNonContiguousLayout = YES;
        view.editable = NO;
        view.selectable = YES;
        view.horizontallyResizable = YES;
        view.textContainer.widthTracksTextView = NO;
        view.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        view.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        view.autoresizingMask = NSViewWidthSizable;
        [view.textStorage setAttributedString:pair[1]];
        view.accessibilityLabel = after ? TSLocalized(@"TeXRootSearch.After", @"After") : TSLocalized(@"TeXRootSearch.Before", @"Before");
        scroll.documentView = view;
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        [scroll.widthAnchor constraintEqualToConstant:320].active = YES;
        [scroll.heightAnchor constraintEqualToConstant:360].active = YES;
        [columns addObject:scroll];
    }
    NSStackView *stack = [NSStackView stackViewWithViews:columns];
    stack.spacing = 8;
    stack.edgeInsets = NSEdgeInsetsMake(10, 10, 10, 10);
    NSSize size = NSMakeSize(10 + 320 * (CGFloat)columns.count + 8 * (CGFloat)(MAX(columns.count, (NSUInteger)1) - 1) + 10, 10 + 360 + 10);
    NSViewController *controller = [NSViewController new];
    controller.preferredContentSize = size;
    [stack setFrameSize:size];
    controller.view = stack;
    return controller;
}

- (void)makeWholeChangeViewControllerForRow:(NSInteger)row completion:(void (^)(NSViewController *_Nullable controller))completion
{
    id object = [self objectAtRow:row];
    TSTeXRootSearchFileResult *file = [self fileOfRow:row];
    if (![object isKindOfClass:[TSTeXRootSearchItem class]] || !file) {
        completion(nil);
        return;
    }
    NSArray<NSArray *> *parts = [self wholeChangePartsOfItem:object inFile:file];
    NSFont *font = self.font;
    NSTimeInterval delay = TSWholeChangeTestDelay;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (delay > 0)
            usleep((useconds_t)(delay * 1000000));
        NSMutableArray<NSArray *> *texts = [NSMutableArray array];
        for (NSArray *part in parts)
            [texts addObject:@[part[0], TSWholeText(part[1], [part[2] rangeValue], part[3] == [NSNull null] ? nil : part[3], part[4], font)]];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(weakSelf ? [weakSelf wholeChangeViewControllerWithTexts:texts] : nil);
        });
    });
}

- (nullable NSViewController *)wholeChangeViewControllerForRow:(NSInteger)row
{
    id object = [self objectAtRow:row];
    TSTeXRootSearchFileResult *file = [self fileOfRow:row];
    if (![object isKindOfClass:[TSTeXRootSearchItem class]] || !file)
        return nil;
    NSMutableArray<NSArray *> *texts = [NSMutableArray array];
    for (NSArray *part in [self wholeChangePartsOfItem:object inFile:file])
        [texts addObject:@[part[0], TSWholeText(part[1], [part[2] rangeValue], part[3] == [NSNull null] ? nil : part[3], part[4], self.font)]];
    return [self wholeChangeViewControllerWithTexts:texts];
}

+ (NSTimeInterval)testDelayBeforeWholeChange { return TSWholeChangeTestDelay; }
+ (void)setTestDelayBeforeWholeChange:(NSTimeInterval)delay { TSWholeChangeTestDelay = delay; }

/// The whole change shown belongs to the list it was asked from: a new list, or any change of what Replace All would
/// do (the generation), closes it, and one still being made is not shown (Codex 3b F6).
- (void)modelDidChange
{
    if (self.model.generation != self.wholeGeneration) {
        self.wholeRequest++;
        [self.wholePopover close];
        self.wholePopover = nil;
    }
}

- (void)showWholeChangeOfRow:(NSInteger)row
{
    NSUInteger request = ++self.wholeRequest;
    NSUInteger generation = self.model.generation;
    id item = [self objectAtRow:row];
    self.wholeGeneration = generation;
    __weak typeof(self) weakSelf = self;
    [self makeWholeChangeViewControllerForRow:row completion:^(NSViewController *controller) {
        typeof(self) list = weakSelf;
        if (!list || list.wholeRequest != request || list.model.generation != generation || [list objectAtRow:row] != item)
            return; // asked again, or the list is no longer the one it was asked from
        if (!controller) {
            NSBeep();
            return;
        }
        if (list.wholeChangeShowHandler) {
            list.wholeChangeShowHandler(controller, row);
            return;
        }
        [list.wholePopover close];
        list.wholePopover = [NSPopover new];
        list.wholePopover.behavior = NSPopoverBehaviorTransient;
        list.wholePopover.contentViewController = controller;
        list.wholePopover.contentSize = controller.preferredContentSize;
        if (list.tableView.window.isVisible && row < list.tableView.numberOfRows)
            [list.wholePopover showRelativeToRect:[list.tableView rectOfRow:row] ofView:list.tableView preferredEdge:NSRectEdgeMaxY];
    }];
}

- (void)showWholeChange:(id)sender
{
    NSInteger row = self.tableView.clickedRow >= 0 ? self.tableView.clickedRow : self.tableView.selectedRow;
    [self showWholeChangeOfRow:row];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(showWholeChange:)) {
        NSInteger row = self.tableView.clickedRow >= 0 ? self.tableView.clickedRow : self.tableView.selectedRow;
        return [[self objectAtRow:row] isKindOfClass:[TSTeXRootSearchItem class]];
    }
    return YES;
}

- (void)rowClicked:(id)sender { [self showClickedItem:NO selected:NO]; }
- (void)rowDoubleClicked:(id)sender { [self showClickedItem:YES selected:NO]; }

@end
