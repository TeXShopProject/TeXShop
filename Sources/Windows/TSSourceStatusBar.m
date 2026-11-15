// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSSourceStatusBar.m
 */

#import "TSSourceStatusBar.h"
#import <stdatomic.h>

NSNotificationName const TSSourceStatusBarShownDidChangeNotification = @"TSSourceStatusBarShownDidChangeNotification";
static NSString *const TSShowStatusBarKey = @"ShowStatusBar";

// The space between two items, and before the file size.
static const CGFloat TSItemGap = 10;
static const CGFloat TSSizeGap = 16;

// One count, which a newer one cancels.
@interface TSStatusBarJob : NSObject
{
@public
    atomic_bool cancelled;
}
@end

@implementation TSStatusBarJob
@end

@interface TSSourceStatusBar ()
@property (nonatomic, weak) NSTextStorage *textStorage;
@property (nonatomic, copy) NSArray<NSTextView *> *textViews;
@property (nonatomic, copy) NSTextView *_Nullable (^activeTextView)(void);
@property (nonatomic, weak) NSView *sourceView;
@property (nonatomic, readwrite) TSStatusBarCounts counts;
@property (nonatomic, readwrite, nullable) NSNumber *fileSize;
@property (nonatomic, strong, nullable) TSStatusBarJob *job;
@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic) BOOL contentNeedsCount, waiting, stopped;
@property (nonatomic) NSUInteger contentVersion;
@end

@implementation TSSourceStatusBar

#pragma mark Showing

+ (BOOL)shown
{
    // On unless it was turned off, also before the factory defaults are registered.
    id value = [NSUserDefaults.standardUserDefaults objectForKey:TSShowStatusBarKey];
    return value == nil || [NSUserDefaults.standardUserDefaults boolForKey:TSShowStatusBarKey];
}

+ (void)setShown:(BOOL)shown
{
    [NSUserDefaults.standardUserDefaults setBool:shown forKey:TSShowStatusBarKey];
    [NSNotificationCenter.defaultCenter postNotificationName:TSSourceStatusBarShownDidChangeNotification object:nil];
}

+ (CGFloat)barHeight
{
    if (@available(macOS 26.0, *))
        return 28;
    return 22;
}

static CGFloat TSEdgePadding(void)
{
    // Keeps the text clear of the larger rounded corners of the windows of macOS 26 and later.
    if (@available(macOS 26.0, *))
        return 16;
    return 12;
}

#pragma mark Making

- (instancetype)initWithTextStorage:(NSTextStorage *)textStorage textViews:(NSArray<NSTextView *> *)textViews
                     activeTextView:(NSTextView *_Nullable (^)(void))activeTextView
{
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 400, TSSourceStatusBar.barHeight)])) {
        _textStorage = textStorage;
        _textViews = [textViews copy];
        _activeTextView = [activeTextView copy];
        _counts = TSStatusBarCountsUnknown();
        _contentNeedsCount = YES;
        _queue = dispatch_queue_create("TeXShop.statusBar", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        self.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        self.accessibilityElement = YES;
        self.accessibilityRole = NSAccessibilityGroupRole;
        self.accessibilityLabel = NSLocalizedString(@"Status Bar", @"accessibility label of the status bar under the source");
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(textStorageDidProcessEditing:) name:NSTextStorageDidProcessEditingNotification object:textStorage];
        for (NSTextView *view in textViews)
            [center addObserver:self selector:@selector(textViewDidChangeSelection:) name:NSTextViewDidChangeSelectionNotification object:view];
        [center addObserver:self selector:@selector(shownDidChange:) name:TSSourceStatusBarShownDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)stop
{
    self.stopped = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startCount) object:nil];
    [self cancelJob];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    self.waiting = NO;
}

#pragma mark Placing

- (void)placeBelowView:(NSView *)sourceView
{
    NSView *parent = sourceView.superview;
    self.sourceView = sourceView;
    if (!parent)
        return;
    if (!TSSourceStatusBar.shown || self.stopped) {
        [self removeFromSuperview];
        sourceView.frame = parent.bounds;
        return;
    }
    NSRect bar, source;
    BOOL flipped = parent.isFlipped;
    NSDivideRect(parent.bounds, &bar, &source, TSSourceStatusBar.barHeight, flipped ? NSMaxYEdge : NSMinYEdge);
    self.autoresizingMask = NSViewWidthSizable | (flipped ? NSViewMinYMargin : NSViewMaxYMargin);
    if (self.superview != parent) {
        [self removeFromSuperview];
        [parent addSubview:self positioned:NSWindowAbove relativeTo:sourceView];
    }
    self.frame = bar;
    sourceView.frame = source;
    self.needsDisplay = YES;
    [self invalidateContent];
}

- (void)shownDidChange:(NSNotification *)notification
{
    NSView *source = self.sourceView;
    if (source)
        [self placeBelowView:source];
}

#pragma mark Watching

- (void)textStorageDidProcessEditing:(NSNotification *)notification
{
    // Coloring changes only attributes; the numbers stay.
    if (!(self.textStorage.editedMask & NSTextStorageEditedCharacters))
        return;
    [self invalidateContent];
}

- (void)textViewDidChangeSelection:(NSNotification *)notification
{
    [self selectionDidChange];
}

- (void)selectionDidChange
{
    [self schedule];
}

- (void)invalidateContent
{
    self.contentNeedsCount = YES;
    self.contentVersion++;
    [self schedule];
}

- (BOOL)isCounting
{
    return self.waiting || self.job != nil;
}

#pragma mark Counting

// Waits a short moment so that a run of keystrokes or of selection changes is counted once; longer for a long text.
- (void)schedule
{
    if (self.stopped || !self.superview)
        return;
    NSUInteger length = self.textStorage.length;
    NSTimeInterval delay = length >= 1000000 ? 0.25 : length >= 200000 ? 0.1 : 0.03;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startCount) object:nil];
    [self performSelector:@selector(startCount) withObject:nil afterDelay:delay inModes:@[NSRunLoopCommonModes]];
    self.waiting = YES;
}

- (void)cancelJob
{
    if (self.job)
        atomic_store(&self.job->cancelled, true);
    self.job = nil;
}

- (NSArray<NSValue *> *)currentRanges
{
    NSTextView *view = self.activeTextView ? self.activeTextView() : nil;
    if (!view || view.textStorage != self.textStorage)
        view = self.textViews.firstObject;
    return view.selectedRanges ?: @[[NSValue valueWithRange:NSMakeRange(0, 0)]];
}

- (void)startCount
{
    self.waiting = NO;
    NSTextStorage *storage = self.textStorage;
    if (self.stopped || !storage || !self.superview)
        return;
    [self cancelJob];
    TSStatusBarJob *job = [TSStatusBarJob new];
    self.job = job;
    // A copy of the text, so that typing goes on while the copy is counted.
    NSString *text = [storage.string copy];
    NSArray<NSValue *> *ranges = [self currentRanges];
    BOOL content = self.contentNeedsCount;
    NSUInteger version = self.contentVersion;
    TSStatusBarCounts start = self.counts;
    __weak TSSourceStatusBar *weakSelf = self;
    dispatch_async(self.queue, ^{
        TSStatusBarCounts counts = start;
        BOOL done = TSStatusBarCount(text, ranges, content, YES, &counts, ^BOOL{ return atomic_load(&job->cancelled); });
        if (!done)
            return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf finishJob:job counts:counts content:content version:version];
        });
    });
}

- (void)finishJob:(TSStatusBarJob *)job counts:(TSStatusBarCounts)counts content:(BOOL)content version:(NSUInteger)version
{
    if (atomic_load(&job->cancelled) || job != self.job)
        return;
    self.job = nil;
    [self applyCounts:counts content:content version:version];
}

- (void)applyCounts:(TSStatusBarCounts)counts content:(BOOL)content version:(NSUInteger)version
{
    TSStatusBarCounts shown = self.counts;
    if (content) {
        shown.lines = counts.lines;
        shown.characters = counts.characters;
        shown.words = counts.words;
        if (version == self.contentVersion)
            self.contentNeedsCount = NO;
    }
    shown.selectedLines = counts.selectedLines;
    shown.selectedCharacters = counts.selectedCharacters;
    shown.selectedWords = counts.selectedWords;
    shown.location = counts.location;
    shown.line = counts.line;
    shown.column = counts.column;
    self.counts = shown;
    self.needsDisplay = YES;
    [self updateAccessibility];
    [self updateToolTip];
}

- (void)countNow
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startCount) object:nil];
    self.waiting = NO;
    [self cancelJob];
    NSTextStorage *storage = self.textStorage;
    if (!storage)
        return;
    TSStatusBarCounts counts = self.counts;
    TSStatusBarCount([storage.string copy], [self currentRanges], YES, YES, &counts, nil);
    [self applyCounts:counts content:YES version:self.contentVersion];
}

#pragma mark File size

- (void)fileDidChangeAtURL:(NSURL *)fileURL
{
    NSNumber *size = nil;
    NSString *path = fileURL.isFileURL ? fileURL.path : nil;
    if (path) {
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
        size = attributes[NSFileSize];
    }
    self.fileSize = size;
    self.needsDisplay = YES;
    [self updateAccessibility];
    [self updateToolTip];
}

#pragma mark Drawing

static NSString *TSFormatNumber(NSUInteger value)
{
    static NSNumberFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSNumberFormatter new];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.locale = NSLocale.autoupdatingCurrentLocale;
    });
    return [formatter stringFromNumber:@(value)];
}

// "1,234", followed by " (56)" when the selection holds some; empty while not counted.
static NSString *TSCountValue(NSUInteger whole, NSUInteger selected)
{
    if (whole == NSNotFound)
        return @"";
    NSString *value = TSFormatNumber(whole);
    if (selected != NSNotFound && selected > 0)
        value = [NSString stringWithFormat:@"%@ (%@)", value, TSFormatNumber(selected)];
    return value;
}

static NSString *TSPositionValue(NSUInteger value)
{
    return value == NSNotFound ? @"" : TSFormatNumber(value);
}

static NSFont *TSBarFont(void)
{
    return [NSFont monospacedDigitSystemFontOfSize:NSFont.smallSystemFontSize weight:NSFontWeightRegular];
}

// The label in the secondary color and the value in the primary one, as "Lines: 12".
static NSAttributedString *TSItem(NSString *label, NSString *value)
{
    NSString *format = NSLocalizedString(@"%1$@: %2$@", @"status bar item: a label and its number");
    NSDictionary *labelAttributes = @{NSFontAttributeName: TSBarFont(), NSForegroundColorAttributeName: NSColor.secondaryLabelColor};
    NSDictionary *valueAttributes = @{NSFontAttributeName: TSBarFont(), NSForegroundColorAttributeName: NSColor.labelColor};
    NSMutableAttributedString *item = [NSMutableAttributedString new];
    NSScanner *scanner = [NSScanner scannerWithString:format];
    scanner.charactersToBeSkipped = nil;
    while (!scanner.atEnd) {
        NSString *text = nil;
        if ([scanner scanUpToString:@"%" intoString:&text])
            [item appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:labelAttributes]];
        if ([scanner scanString:@"%1$@" intoString:NULL])
            [item appendAttributedString:[[NSAttributedString alloc] initWithString:label attributes:labelAttributes]];
        else if ([scanner scanString:@"%2$@" intoString:NULL])
            [item appendAttributedString:[[NSAttributedString alloc] initWithString:value attributes:valueAttributes]];
        else if ([scanner scanString:@"%" intoString:NULL])
            [item appendAttributedString:[[NSAttributedString alloc] initWithString:@"%" attributes:labelAttributes]];
    }
    return item;
}

- (NSArray<NSAttributedString *> *)items
{
    TSStatusBarCounts c = self.counts;
    return @[
        TSItem(NSLocalizedString(@"Lines", @"status bar: the number of lines"), TSCountValue(c.lines, c.selectedLines)),
        TSItem(NSLocalizedString(@"Characters", @"status bar: the number of characters"), TSCountValue(c.characters, c.selectedCharacters)),
        TSItem(NSLocalizedString(@"Words", @"status bar: the number of words"), TSCountValue(c.words, c.selectedWords)),
        TSItem(NSLocalizedString(@"Location", @"status bar: the characters before the insertion point"), TSPositionValue(c.location)),
        TSItem(NSLocalizedString(@"Line", @"status bar: the line of the insertion point"), TSPositionValue(c.line)),
        TSItem(NSLocalizedString(@"Column", @"status bar: the column of the insertion point"), TSPositionValue(c.column)),
    ];
}

- (nullable NSAttributedString *)fileSizeItem
{
    if (!self.fileSize)
        return nil;
    NSString *size = [NSByteCountFormatter stringFromByteCount:self.fileSize.longLongValue countStyle:NSByteCountFormatterCountStyleFile];
    return [[NSAttributedString alloc] initWithString:size attributes:@{NSFontAttributeName: TSBarFont(), NSForegroundColorAttributeName: NSColor.labelColor}];
}

// The items that fit, from the left, and whether the file size fits at the right. An item that does not fit whole is
// left out, with all after it, rather than cut.
- (NSArray<NSAttributedString *> *)fittingItems:(NSAttributedString *_Nullable *_Nullable)fileSize
{
    CGFloat padding = TSEdgePadding();
    CGFloat room = NSWidth(self.bounds) - 2 * padding;
    NSAttributedString *size = [self fileSizeItem];
    if (size) {
        if (ceil(size.size.width) <= room)
            room -= ceil(size.size.width) + TSSizeGap;
        else
            size = nil;
    }
    if (fileSize)
        *fileSize = size;
    NSMutableArray<NSAttributedString *> *fitting = [NSMutableArray array];
    CGFloat used = 0;
    for (NSAttributedString *item in [self items]) {
        CGFloat width = ceil(item.size.width) + (fitting.count ? TSItemGap : 0);
        if (used + width > room)
            break;
        used += width;
        [fitting addObject:item];
    }
    return fitting;
}

- (NSArray<NSString *> *)visibleItems
{
    return [[self fittingItems:NULL] valueForKey:@"string"];
}

- (NSArray<NSString *> *)allItems
{
    return [[self items] valueForKey:@"string"];
}

- (nullable NSString *)visibleFileSize
{
    NSAttributedString *size = nil;
    [self fittingItems:&size];
    return size.string;
}

- (BOOL)isOpaque
{
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    // A hairline between the text and the bar.
    CGFloat scale = self.window.backingScaleFactor > 0 ? self.window.backingScaleFactor : 2;
    CGFloat line = 1 / scale;
    [NSColor.separatorColor setFill];
    NSRectFillUsingOperation(self.isFlipped ? NSMakeRect(0, 0, NSWidth(bounds), line)
                                            : NSMakeRect(0, NSMaxY(bounds) - line, NSWidth(bounds), line), NSCompositingOperationSourceOver);
    NSAttributedString *size = nil;
    NSArray<NSAttributedString *> *items = [self fittingItems:&size];
    CGFloat height = ceil(TSBarFont().boundingRectForFont.size.height);
    CGFloat y = floor((NSHeight(bounds) - line - height) / 2) + (self.isFlipped ? line : 0);
    CGFloat x = TSEdgePadding();
    for (NSAttributedString *item in items) {
        [item drawAtPoint:NSMakePoint(x, y)];
        x += ceil(item.size.width) + TSItemGap;
    }
    if (size)
        [size drawAtPoint:NSMakePoint(NSMaxX(bounds) - TSEdgePadding() - ceil(size.size.width), y)];
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    self.needsDisplay = YES;
    [self updateToolTip];
}

// When the bar is too narrow for every item, its tool tip lists them all.
- (void)updateToolTip
{
    NSArray<NSString *> *all = self.allItems;
    NSString *tip = self.visibleItems.count < all.count ? [all componentsJoinedByString:@"\n"] : nil;
    if (tip != self.toolTip && ![tip isEqual:self.toolTip])
        self.toolTip = tip;
}

- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    self.needsDisplay = YES;
}

- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    self.needsDisplay = YES;
}

- (void)updateAccessibility
{
    NSMutableArray<NSString *> *parts = [[self allItems] mutableCopy];
    NSString *size = [self fileSizeItem].string;
    if (size)
        [parts addObject:size];
    self.accessibilityValue = [parts componentsJoinedByString:@", "];
}

@end
