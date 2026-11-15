// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSTextStatisticsPopover.m
 */

#import "TSTextStatisticsPopover.h"

static NSString *TSFormatCount(NSUInteger value)
{
    static NSNumberFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSNumberFormatter new];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.locale = NSLocale.autoupdatingCurrentLocale;
    });
    return value == NSNotFound ? @"" : [formatter stringFromNumber:@(value)];
}

static NSTextField *TSLabel(NSString *text, NSFont *font, NSColor *color)
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = font;
    label.textColor = color;
    return label;
}

static NSFont *TSDigits(CGFloat size, NSFontWeight weight)
{
    return [NSFont monospacedDigitSystemFontOfSize:size weight:weight];
}

// The table, with a thin line between its rows.
@interface TSStatisticsGrid : NSGridView
@property (nonatomic, copy) NSArray<NSView *> *rowViews;
@end

@implementation TSStatisticsGrid

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    CGFloat scale = self.window.backingScaleFactor > 0 ? self.window.backingScaleFactor : 2;
    [NSColor.separatorColor setFill];
    for (NSUInteger i = 1; i < self.rowViews.count; i++) {
        NSRect above = self.rowViews[i - 1].frame, below = self.rowViews[i].frame;
        CGFloat y = self.isFlipped ? (NSMaxY(above) + NSMinY(below)) / 2 : (NSMinY(above) + NSMaxY(below)) / 2;
        NSRectFill(NSMakeRect(0, round(y * scale) / scale, NSWidth(self.bounds), 1 / scale));
    }
}

@end

@interface TSTextStatisticsViewController ()
@property (nonatomic, strong) NSTextField *headingLabel, *timeLabel, *countingLabel, *warningLabel;
@property (nonatomic, strong) NSButton *refreshButton;
@property (nonatomic, strong) TSStatisticsGrid *grid;
@property (nonatomic, strong) NSStackView *countingView, *warningView, *tableView;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, strong) NSImageView *info;
@property (nonatomic, strong) NSArray<NSTextField *> *names, *sourceValues, *textValues;
@property (nonatomic, readwrite, getter=isCounting) BOOL counting;
@end

@implementation TSTextStatisticsViewController

- (void)loadView
{
    NSFont *body = [NSFont systemFontOfSize:NSFont.systemFontSize];
    NSFont *small = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    self.headingLabel = TSLabel(NSLocalizedString(@"Whole Document", @"Text Statistics: the heading when the whole document is counted"),
                                [NSFont boldSystemFontOfSize:NSFont.systemFontSize], NSColor.labelColor);
    self.timeLabel = TSLabel(@"", TSDigits(NSFont.smallSystemFontSize, NSFontWeightRegular), NSColor.secondaryLabelColor);
    NSImage *arrow = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:NSLocalizedString(@"Refresh", @"Text Statistics: count again")] ?: [NSImage new];
    self.refreshButton = [NSButton buttonWithImage:arrow target:self action:@selector(refresh:)];
    self.refreshButton.bordered = NO;
    self.refreshButton.toolTip = NSLocalizedString(@"Refresh", @"Text Statistics: count again");
    self.refreshButton.accessibilityLabel = self.refreshButton.toolTip;
    [self.refreshButton.widthAnchor constraintEqualToConstant:20].active = YES;
    [self.headingLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    // The heading at the left; the time of the count and the refresh button at the right.
    NSStackView *top = [NSStackView new];
    top.spacing = 6;
    [top addView:self.headingLabel inGravity:NSStackViewGravityLeading];
    [top addView:self.timeLabel inGravity:NSStackViewGravityTrailing];
    [top addView:self.refreshButton inGravity:NSStackViewGravityTrailing];
    [top setCustomSpacing:4 afterView:self.timeLabel];

    // The table: the names, Source (as the status bar counts) and Text (what detex leaves).
    NSTextField *sourceHeading = TSLabel(NSLocalizedString(@"Source", @"Source"), small, NSColor.secondaryLabelColor);
    NSTextField *textHeading = TSLabel(NSLocalizedString(@"Text", @"Text Statistics: the column of what detex leaves of the source"),
                                       [NSFont systemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightSemibold], NSColor.controlAccentColor);
    NSString *about = NSLocalizedString(@"Counted by detex without the TeX commands, with the files read by \\input and \\include.",
                                        @"Text Statistics: the tool tip of the info mark beside the Text column");
    self.info = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:about] ?: [NSImage new]];
    self.info.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
    self.info.contentTintColor = NSColor.secondaryLabelColor;
    self.info.toolTip = about;
    self.info.accessibilityElement = YES;
    self.info.accessibilityRole = NSAccessibilityImageRole;
    self.info.accessibilityLabel = about;
    NSStackView *textHeader = [NSStackView stackViewWithViews:@[textHeading, self.info]];
    textHeader.spacing = 3;

    NSMutableArray *names = [NSMutableArray array], *sources = [NSMutableArray array], *texts = [NSMutableArray array];
    NSArray *keys = @[NSLocalizedString(@"Characters", @"status bar: the number of characters"),
                      NSLocalizedString(@"Words", @"status bar: the number of words"),
                      NSLocalizedString(@"Lines", @"status bar: the number of lines")];
    NSMutableArray *rows = [NSMutableArray arrayWithObject:@[NSGridCell.emptyContentView, sourceHeading, textHeader]];
    for (NSString *key in keys) {
        NSTextField *name = TSLabel(key, body, NSColor.labelColor);
        NSTextField *source = TSLabel(@"", TSDigits(NSFont.systemFontSize, NSFontWeightRegular), NSColor.secondaryLabelColor);
        NSTextField *text = TSLabel(@"", TSDigits(NSFont.systemFontSize + 3, NSFontWeightMedium), NSColor.labelColor);
        [names addObject:name]; [sources addObject:source]; [texts addObject:text];
        [rows addObject:@[name, source, text]];
    }
    self.names = names; self.sourceValues = sources; self.textValues = texts;
    self.grid = [TSStatisticsGrid gridViewWithViews:rows];
    self.grid.rowViews = [@[sourceHeading] arrayByAddingObjectsFromArray:names];
    self.grid.rowSpacing = 12;
    self.grid.columnSpacing = 18;
    for (NSInteger column = 1; column < 3; column++)
        [self.grid columnAtIndex:column].xPlacement = NSGridCellPlacementTrailing;
    [self.grid rowAtIndex:0].yPlacement = NSGridCellPlacementBottom;
    [self.grid rowAtIndex:0].bottomPadding = -4;
    for (NSInteger row = 1; row < self.grid.numberOfRows; row++)
        [self.grid rowAtIndex:row].rowAlignment = NSGridRowAlignmentFirstBaseline;

    // In place of the Text column when detex is missing or fails.
    NSImageView *caution = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"exclamationmark.triangle" accessibilityDescription:nil] ?: [NSImage new]];
    caution.contentTintColor = NSColor.systemOrangeColor;
    self.warningLabel = TSLabel(@"", small, NSColor.secondaryLabelColor);
    self.warningLabel.maximumNumberOfLines = 3;
    self.warningLabel.preferredMaxLayoutWidth = 120;
    self.warningView = [NSStackView stackViewWithViews:@[caution, self.warningLabel]];
    self.warningView.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.warningView.spacing = 4;
    self.warningView.hidden = YES;
    self.tableView = [NSStackView stackViewWithViews:@[self.grid, self.warningView]];
    self.tableView.alignment = NSLayoutAttributeCenterY;
    self.tableView.spacing = 18;

    // In place of the table while counting.
    self.spinner = [NSProgressIndicator new];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.countingLabel = TSLabel(NSLocalizedString(@"Counting…", @"Text Statistics: while detex runs"), body, NSColor.secondaryLabelColor);
    self.countingView = [NSStackView stackViewWithViews:@[self.spinner, self.countingLabel]];
    self.countingView.spacing = 6;
    self.countingView.hidden = YES;

    NSStackView *content = [NSStackView stackViewWithViews:@[top, self.tableView, self.countingView]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeLeading;
    content.spacing = 12;
    content.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    [top.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-32].active = YES;
    [content.widthAnchor constraintGreaterThanOrEqualToConstant:250].active = YES;
    self.view = content;
}

- (NSView *)infoMark
{
    [self view];
    return self.info;
}

- (void)refresh:(id)sender
{
    if (self.refresh)
        self.refresh();
}

- (void)setHeadingForSelection:(BOOL)selection
{
    self.headingLabel.stringValue = selection ? NSLocalizedString(@"Selection", @"Text Statistics: the heading when the selection is counted")
                                              : NSLocalizedString(@"Whole Document", @"Text Statistics: the heading when the whole document is counted");
}

- (void)showCountingSelection:(BOOL)selection
{
    [self view];
    [self setHeadingForSelection:selection];
    self.counting = YES;
    self.tableView.hidden = YES;
    self.countingView.hidden = NO;
    [self.spinner startAnimation:nil];
}

- (void)showResult:(TSTextStatisticsResult *)result
{
    [self view];
    [self setHeadingForSelection:result.selection];
    self.timeLabel.stringValue = [NSDateFormatter localizedStringFromDate:result.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterShortStyle];
    TSStatusBarCounts s = result.source, t = result.text;
    NSUInteger sources[] = {s.characters, s.words, s.lines}, texts[] = {t.characters, t.words, t.lines};
    for (NSUInteger i = 0; i < 3; i++) {
        self.sourceValues[i].stringValue = TSFormatCount(sources[i]);
        self.textValues[i].stringValue = TSFormatCount(texts[i]);
    }
    BOOL failed = result.state == TSTextStatisticsDetexMissing || result.state == TSTextStatisticsDetexFailed;
    self.warningLabel.stringValue = result.state == TSTextStatisticsDetexMissing
        ? NSLocalizedString(@"detex was not found.", @"Text Statistics: detex is not in the TeX bin folder")
        : NSLocalizedString(@"detex failed.", @"Text Statistics: detex did not finish");
    [self.grid columnAtIndex:2].hidden = failed;
    self.warningView.hidden = !failed;
    self.counting = NO;
    [self.spinner stopAnimation:nil];
    self.countingView.hidden = YES;
    self.tableView.hidden = NO;
}

- (NSString *)heading
{
    return self.headingLabel.stringValue;
}

- (NSString *)time
{
    return self.timeLabel.stringValue;
}

- (NSArray<NSString *> *)rows
{
    NSMutableArray *rows = [NSMutableArray array];
    BOOL text = ![self.grid columnAtIndex:2].hidden;
    for (NSUInteger i = 0; i < 3; i++)
        [rows addObject:[NSString stringWithFormat:@"%@|%@|%@", self.names[i].stringValue, self.sourceValues[i].stringValue,
                         text ? self.textValues[i].stringValue : @""]];
    return rows;
}

- (nullable NSString *)warning
{
    return self.warningView.hidden ? nil : self.warningLabel.stringValue;
}

@end

@interface TSTextStatisticsPopover ()
@property (nonatomic, copy) void (^source)(NSString *_Nullable *, NSArray<NSValue *> *_Nullable *, NSURL *_Nullable *, NSStringEncoding *);
@property (nonatomic, readwrite) NSPopover *popover;
@property (nonatomic, readwrite) TSTextStatisticsViewController *contentController;
@property (nonatomic, readwrite) TSTextStatistics *statistics;
@property (nonatomic, readwrite) NSUInteger countsStarted;
@end

@implementation TSTextStatisticsPopover

- (instancetype)initWithSource:(void (^)(NSString **, NSArray<NSValue *> **, NSURL **, NSStringEncoding *))source
{
    if ((self = [super init])) {
        _source = [source copy];
        _statistics = [TSTextStatistics new];
        _contentController = [TSTextStatisticsViewController new];
        __weak TSTextStatisticsPopover *weakSelf = self;
        _contentController.refresh = ^{ [weakSelf refresh]; };
        _popover = [NSPopover new];
        _popover.behavior = NSPopoverBehaviorTransient;
        _popover.contentViewController = _contentController;
        _popover.delegate = self;
        _detex = ^NSURL *{ return [TSTextStatistics detexInFolder:[NSUserDefaults.standardUserDefaults stringForKey:@"TetexBinPath"]]; };
    }
    return self;
}

- (void)showRelativeToRect:(NSRect)rect ofView:(NSView *)view preferredEdge:(NSRectEdge)edge
{
    if (!self.popover.shown)
        [self.popover showRelativeToRect:rect ofView:view preferredEdge:edge];
    [self refresh];
}

- (void)close
{
    [self.popover close];
    [self.statistics stop];
}

- (void)refresh
{
    NSString *text = nil;
    NSArray<NSValue *> *ranges = nil;
    NSURL *folder = nil;
    NSStringEncoding encoding = NSUTF8StringEncoding;
    self.source(&text, &ranges, &folder, &encoding);
    if (!text)
        return;
    BOOL selection = NO;
    for (NSValue *value in ranges ?: @[])
        if (value.rangeValue.length > 0)
            selection = YES;
    [self.contentController showCountingSelection:selection];
    self.countsStarted++;
    __weak TSTextStatisticsPopover *weakSelf = self;
    [self.statistics countString:text ranges:ranges ?: @[] folder:folder detex:self.detex ? self.detex() : nil encoding:encoding
                      completion:^(TSTextStatisticsResult *result) {
        [weakSelf.contentController showResult:result];
    }];
}

- (void)popoverDidClose:(NSNotification *)notification
{
    [self.statistics stop];
}

@end
