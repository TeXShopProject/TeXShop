// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindResultsView.h"
#import "TSAdvancedFindHighlights.h"
#import "TSAdvancedFindController.h"

#define TSLocalized TSAdvancedFindLocalized

static NSUserInterfaceItemIdentifier const TSLineColumn = @"line";
static NSUserInterfaceItemIdentifier const TSTextColumn = @"text";

@interface TSAdvancedFindResultsView ()
@property (nonatomic, readwrite, nullable) TSAdvancedFindResults *results;
@property (nonatomic, readwrite, weak) NSTextView *textView;
@property (nonatomic, readwrite) NSTableView *tableView;
@property (nonatomic, readwrite) NSTextField *countField;
@property (nonatomic, readwrite) NSButton *liveUpdateBox;
@property (nonatomic, readwrite) NSButton *closeButton;
@property (nonatomic) NSTextField *findStringField;
@property (nonatomic) TSAdvancedFindSettings *settings;
@property (nonatomic, weak, nullable) NSWindow *documentWindow;
@property (nonatomic) NSStackView *content;
@end

@implementation TSAdvancedFindResultsView

+ (NSArray<NSColor *> *)groupColors
{
    NSArray<NSColor *> *base = @[NSColor.systemTealColor, NSColor.systemPinkColor, NSColor.systemPurpleColor, NSColor.systemOrangeColor, NSColor.systemBlueColor];
    NSMutableArray<NSColor *> *colors = [NSMutableArray array];
    for (NSColor *color in base)
        [colors addObject:[color colorWithAlphaComponent:0.35]];
    return colors;
}

- (instancetype)initWithSettings:(TSAdvancedFindSettings *)settings
{
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, 600, 240)]))
        return nil;
    _settings = settings;
    _beepHandler = ^{ NSBeep(); };
    self.translatesAutoresizingMaskIntoConstraints = NO;
    [self buildContent];
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark Building

- (NSTextField *)smallLabel:(BOOL)secondary
{
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:secondary ? NSFontWeightRegular : NSFontWeightSemibold];
    label.textColor = secondary ? NSColor.secondaryLabelColor : NSColor.labelColor;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

- (NSTableView *)makeTable
{
    NSTableView *table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 600, 200)];
    table.style = NSTableViewStyleFullWidth;
    table.usesAlternatingRowBackgroundColors = YES;
    table.allowsMultipleSelection = NO;
    table.allowsEmptySelection = YES;
    table.rowHeight = 20;
    table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    NSTableColumn *line = [[NSTableColumn alloc] initWithIdentifier:TSLineColumn];
    line.title = TSLocalized(@"AdvancedFind.Results.Line", @"Line");
    line.width = 64;
    line.minWidth = 40;
    line.headerCell.alignment = NSTextAlignmentRight;
    NSTextFieldCell *lineCell = [[NSTextFieldCell alloc] initTextCell:@""];
    lineCell.alignment = NSTextAlignmentRight;
    lineCell.font = [NSFont monospacedDigitSystemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular];
    line.dataCell = lineCell;
    NSTableColumn *text = [[NSTableColumn alloc] initWithIdentifier:TSTextColumn];
    text.title = TSLocalized(@"AdvancedFind.Results.Text", @"Matched Text");
    text.width = 520;
    text.resizingMask = NSTableColumnAutoresizingMask;
    NSTextFieldCell *textCell = [[NSTextFieldCell alloc] initTextCell:@""];
    textCell.lineBreakMode = NSLineBreakByTruncatingTail;
    text.dataCell = textCell;
    [table addTableColumn:line];
    [table addTableColumn:text];
    table.dataSource = self;
    table.delegate = self;
    table.target = self;
    table.action = @selector(rowClicked:);
    table.doubleAction = @selector(goToDocument:);
    return table;
}

- (void)buildContent
{
    NSImage *chevron = [NSImage imageWithSystemSymbolName:@"chevron.up" accessibilityDescription:TSLocalized(@"AdvancedFind.Results.Close", @"Close the list")] ?: [NSImage new];
    self.closeButton = [NSButton buttonWithImage:chevron target:self action:@selector(closeList:)];
    self.closeButton.controlSize = NSControlSizeSmall;
    self.closeButton.toolTip = TSLocalized(@"AdvancedFind.Results.Close", @"Close the list");
    // The count wraps to a second line rather than being cut where the panel is narrow (a long translation, many
    // matches, a stale count); a very long document name is cut at its end.
    self.countField = [self smallLabel:NO];
    self.countField.lineBreakMode = NSLineBreakByWordWrapping;
    self.countField.usesSingleLineMode = NO;
    self.countField.maximumNumberOfLines = 2;
    self.countField.cell.truncatesLastVisibleLine = YES;
    self.findStringField = [self smallLabel:YES];
    self.findStringField.selectable = YES;
    self.liveUpdateBox = [NSButton checkboxWithTitle:TSLocalized(@"AdvancedFind.Results.LiveUpdate", @"Live Update") target:self action:@selector(liveUpdateChanged:)];
    self.liveUpdateBox.controlSize = NSControlSizeSmall;
    self.liveUpdateBox.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    self.liveUpdateBox.state = self.settings.updatesResultsLive ? NSControlStateValueOn : NSControlStateValueOff;
    // The count takes all the room between the close button and Live Update, whatever its text, so its width (and
    // the line it wraps at) never depends on its own text.
    NSView *titleRow = [NSView new];
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *view in @[self.closeButton, self.countField, self.liveUpdateBox]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [titleRow addSubview:view];
        [NSLayoutConstraint activateConstraints:@[
            [view.centerYAnchor constraintEqualToAnchor:titleRow.centerYAnchor],
            [view.topAnchor constraintGreaterThanOrEqualToAnchor:titleRow.topAnchor],
            [view.bottomAnchor constraintLessThanOrEqualToAnchor:titleRow.bottomAnchor],
        ]];
    }
    NSLayoutConstraint *snug = [titleRow.heightAnchor constraintEqualToConstant:0];
    snug.priority = NSLayoutPriorityDefaultLow;
    [self.liveUpdateBox setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    for (NSView *view in @[self.closeButton, self.liveUpdateBox])
        [view setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.countField setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        snug,
        [self.closeButton.leadingAnchor constraintEqualToAnchor:titleRow.leadingAnchor],
        [self.countField.leadingAnchor constraintEqualToAnchor:self.closeButton.trailingAnchor constant:8],
        [self.liveUpdateBox.leadingAnchor constraintEqualToAnchor:self.countField.trailingAnchor constant:12],
        [self.liveUpdateBox.trailingAnchor constraintEqualToAnchor:titleRow.trailingAnchor],
    ]];
    NSStackView *header = [NSStackView stackViewWithViews:@[titleRow, self.findStringField]];
    header.orientation = NSUserInterfaceLayoutOrientationVertical;
    header.alignment = NSLayoutAttributeLeading;
    header.spacing = 4;
    header.edgeInsets = NSEdgeInsetsMake(10, 20, 8, 20);
    [titleRow.widthAnchor constraintEqualToAnchor:header.widthAnchor constant:-40].active = YES;

    self.tableView = [self makeTable];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 600, 200)];
    scroll.documentView = self.tableView;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    [scroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    // Below the fields' kept height: while the panel grows, the list is the one squeezed, not the fields.
    NSLayoutConstraint *minimum = [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:100];
    minimum.priority = 700;
    minimum.active = YES;

    NSBox *top = [NSBox new], *bottom = [NSBox new];
    top.boxType = bottom.boxType = NSBoxSeparator;
    NSStackView *content = [NSStackView stackViewWithViews:@[top, header, scroll, bottom]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.spacing = 0;
    content.edgeInsets = NSEdgeInsetsMake(0, 0, 14, 0); // the room above the buttons is the list's own: it goes with it
    content.translatesAutoresizingMaskIntoConstraints = NO;
    self.content = content;
    for (NSView *view in content.arrangedSubviews) {
        [view.widthAnchor constraintEqualToAnchor:content.widthAnchor].active = YES;
        if (view != scroll)
            [view setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    }
    [self addSubview:content];
    // While the panel opens or closes the list, the view is shorter than its content: the content stays at the top
    // and is cut off at the bottom, as a lid closing over it.
    // Below NSLayoutPriorityWindowSizeStayPut (500): above it, the content's own height would hold the window's size
    // and stop the window from shrinking past it.
    NSLayoutConstraint *bottomEdge = [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor];
    bottomEdge.priority = NSLayoutPriorityWindowSizeStayPut - 10;
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:self.topAnchor], bottomEdge,
    ]];
    self.clipsToBounds = YES;
    [self setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
}

- (CGFloat)minimumHeight
{
    return self.content.fittingSize.height;
}

#pragma mark Results

- (void)setResults:(TSAdvancedFindResults *)results textView:(NSTextView *)textView
{
    [self clear];
    self.results = results;
    self.textView = textView;
    __weak typeof(self) weakSelf = self;
    results.changeHandler = ^(TSAdvancedFindResults *changed) { [weakSelf resultsDidChange]; };
    results.updatesLive = self.settings.updatesResultsLive;
    // Any window: the text view may move to another window of its document (the single-window mode) meanwhile.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(documentWindowWillClose:) name:NSWindowWillCloseNotification object:nil];
    self.documentWindow = textView.window;
    NSString *shown = [results.findString stringByReplacingOccurrencesOfString:@"\n" withString:@"⏎"];
    self.findStringField.stringValue = [NSString stringWithFormat:TSLocalized(@"AdvancedFind.Results.FindString", @"Find string: %@"), shown];
    self.findStringField.toolTip = results.findString;
    [self.tableView deselectAll:nil];
    [self resultsDidChange];
    [self.tableView scrollRowToVisible:0];
}

- (void)clear
{
    self.results.updatesLive = NO;
    self.results.changeHandler = nil;
    self.results = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowWillCloseNotification object:nil];
    self.documentWindow = nil;
    [self.tableView reloadData];
}

- (void)resultsDidChange
{
    NSInteger selected = self.tableView.selectedRow;
    [self.tableView reloadData];
    if (selected >= 0 && selected < (NSInteger)self.results.items.count)
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)selected] byExtendingSelection:NO];
    NSUInteger count = self.results.items.count, stale = self.results.staleCount;
    NSString *name = [self documentName];
    NSString *message = stale > 0
        ? [NSString stringWithFormat:TSLocalized(@"AdvancedFind.Results.CountStale", @"%2$lu found in “%1$@” (%3$lu changed since)"), name, (unsigned long)count, (unsigned long)stale]
        : [NSString stringWithFormat:TSLocalized(@"AdvancedFind.Results.Count", @"%2$lu found in “%1$@”"), name, (unsigned long)count];
    self.countField.stringValue = message;
    self.countField.toolTip = message;
}

/// The name of the list's document as its window shows it ("Untitled" too); the window's title for the console and
/// the log, which have no document.
- (NSString *)documentName
{
    NSWindow *window = self.textView.window ?: self.documentWindow;
    NSDocument *document = window ? [NSDocumentController.sharedDocumentController documentForWindow:(NSWindow *_Nonnull)window] : nil;
    return document.displayName ?: window.title ?: @"";
}

- (void)liveUpdateChanged:(NSButton *)sender
{
    BOOL on = sender.state == NSControlStateValueOn;
    self.settings.updatesResultsLive = on;
    self.results.updatesLive = on;
}

- (void)closeList:(id)sender
{
    if (self.closeHandler)
        self.closeHandler();
}

/// The list goes with the window of its text view: the document was closed.
- (void)documentWindowWillClose:(NSNotification *)notification
{
    NSWindow *closing = notification.object;
    if (!closing || closing != (self.textView.window ?: self.documentWindow))
        return;
    [self clear];
    if (self.closeHandler)
        self.closeHandler();
}

#pragma mark Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)self.results.items.count;
}

- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)column row:(NSInteger)row
{
    TSAdvancedFindResults *results = self.results;
    if (!results || row < 0 || row >= (NSInteger)results.items.count)
        return nil;
    TSAdvancedFindResultItem *item = results.items[(NSUInteger)row];
    if ([column.identifier isEqualToString:TSLineColumn]) {
        NSString *number = [NSString stringWithFormat:@"%lu", (unsigned long)[results lineNumberOfItem:item]];
        if (!item.isStale)
            return number;
        NSMutableParagraphStyle *right = [NSMutableParagraphStyle new];
        right.alignment = NSTextAlignmentRight;
        return [[NSAttributedString alloc] initWithString:number attributes:@{NSForegroundColorAttributeName: NSColor.tertiaryLabelColor, NSParagraphStyleAttributeName: right,
                                                                               NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:NSFont.systemFontSize weight:NSFontWeightRegular]}];
    }
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:NSFont.systemFontSize], NSParagraphStyleAttributeName: paragraph};
    return [results lineTextOfItem:item attributes:attributes matchColor:TSAdvancedFindHighlights.color groupColors:TSAdvancedFindResultsView.groupColors];
}

/// Moving through the list with the arrow keys jumps to each match.
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    NSEventType type = NSApp.currentEvent.type;
    BOOL click = type == NSEventTypeLeftMouseDown || type == NSEventTypeLeftMouseUp || type == NSEventTypeLeftMouseDragged;
    if (self.tableView.selectedRow >= 0 && !click) // a click is handled by -rowClicked:
        [self showItemAtRow:self.tableView.selectedRow];
}

/// A click jumps to the match, also on the row already selected; the list keeps the keyboard.
- (void)rowClicked:(id)sender
{
    if (self.tableView.clickedRow >= 0)
        [self showItemAtRow:self.tableView.clickedRow];
}

- (BOOL)showItemAtRow:(NSInteger)row
{
    NSTextView *textView = self.textView;
    if (row < 0 || row >= (NSInteger)self.results.items.count || !textView)
        return NO;
    TSAdvancedFindResultItem *item = self.results.items[(NSUInteger)row];
    if (NSMaxRange(item.currentRange) > textView.string.length) {
        self.beepHandler();
        return NO;
    }
    textView.selectedRange = item.currentRange;
    [textView scrollRangeToVisible:item.currentRange];
    if (textView.window.isVisible)
        [textView showFindIndicatorForRange:item.currentRange];
    return YES;
}

/// Double click: jumps, then brings the document to the front to go on editing there.
- (void)goToDocument:(id)sender
{
    if (![self showItemAtRow:self.tableView.clickedRow])
        return;
    NSTextView *textView = self.textView;
    [textView.window makeKeyAndOrderFront:nil];
    if (textView)
        [textView.window makeFirstResponder:textView];
}

@end
