// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindResults.h"
#import "TSAdvancedFindTask.h"

/// As OgreKit's list: at most 30 characters (UTF-16 units) before the match, 250 in all.
static const NSUInteger TSBeforeLength = 30, TSShownLength = 250;

@interface TSAdvancedFindResultItem ()
@property (nonatomic, readwrite) NSRange currentRange;
@property (nonatomic, readwrite, getter=isStale) BOOL stale;
- (instancetype)initWithRanges:(NSArray<NSValue *> *)ranges NS_DESIGNATED_INITIALIZER;
@end

@implementation TSAdvancedFindResultItem

- (instancetype)initWithRanges:(NSArray<NSValue *> *)ranges
{
    if ((self = [super init])) {
        _foundRanges = [ranges copy];
        _currentRange = ranges.firstObject.rangeValue;
    }
    return self;
}

@end

/// The starts of the lines of a string, for line numbers by binary search. The lines are those of
/// -[NSString lineRangeForRange:], as in OgreKit: CRLF, CR, LF, U+0085, U+2028 and U+2029 end a line.
@interface TSLineStarts : NSObject
- (instancetype)initWithString:(NSString *)string;
- (NSUInteger)lineNumberAtIndex:(NSUInteger)index;
@end

@implementation TSLineStarts {
    NSMutableData *_starts;
}

- (instancetype)initWithString:(NSString *)string
{
    if ((self = [super init])) {
        _starts = [NSMutableData dataWithLength:sizeof(NSUInteger)];
        NSUInteger length = string.length, index = 0;
        while (index < length) {
            NSUInteger end = 0, contentsEnd = 0;
            [string getLineStart:NULL end:&end contentsEnd:&contentsEnd forRange:NSMakeRange(index, 0)];
            if (end >= length && contentsEnd == end)
                break; // the last line has no line break
            [_starts appendBytes:&end length:sizeof end];
            index = end;
        }
    }
    return self;
}

- (NSUInteger)lineNumberAtIndex:(NSUInteger)index
{
    const NSUInteger *starts = _starts.bytes;
    NSUInteger low = 0, high = _starts.length / sizeof(NSUInteger); // the first start after `index` is in [low, high]
    while (low < high) {
        NSUInteger middle = (low + high) / 2;
        if (starts[middle] <= index)
            low = middle + 1;
        else
            high = middle;
    }
    return low;
}

@end

@interface TSAdvancedFindResults ()
@property (nonatomic, readwrite, copy) NSArray<TSAdvancedFindResultItem *> *items;
@property (nonatomic, readwrite, copy, nullable) NSArray<NSValue *> *scopeRanges;
@property (nonatomic, copy, nullable) NSString *lineEnding;
@property (nonatomic, strong, nullable) TSLineStarts *lines;
/// Counts the edits; a search whose text has been edited since is dropped.
@property (nonatomic) NSUInteger editCount;
@property (nonatomic) BOOL editedSinceSearch;
/// The newest search; an older one stops (read from the search's queue, hence atomic).
@property (atomic) NSUInteger searchGeneration;
@end

@implementation TSAdvancedFindResults

+ (nullable NSArray<TSAdvancedFindResultItem *> *)itemsOfFind:(TSRegexTextFind *)find
                                                  cancellation:(nullable BOOL (^)(void))isCancelled
                                                      progress:(nullable void (^)(double fraction, NSUInteger count))progress
{
    NSMutableArray<TSAdvancedFindResultItem *> *matches = [NSMutableArray array];
    double length = MAX(find.string.length, 1);
    [find enumerateMatchesWithCancellation:isCancelled usingBlock:^(NSArray<NSValue *> *ranges, BOOL *stop) {
        [matches addObject:[[TSAdvancedFindResultItem alloc] initWithRanges:ranges]];
        if (progress && matches.count % 256 == 0)
            progress(NSMaxRange(ranges.firstObject.rangeValue) / length, matches.count);
    }];
    if (isCancelled && isCancelled())
        return nil;
    return matches;
}

- (instancetype)initWithTextStorage:(NSTextStorage *)storage find:(TSRegexTextFind *)find findString:(NSString *)findString
{
    return [self initWithTextStorage:storage find:find findString:findString
                               items:[TSAdvancedFindResults itemsOfFind:find cancellation:nil progress:nil] ?: @[]];
}

- (instancetype)initWithTextStorage:(NSTextStorage *)storage find:(TSRegexTextFind *)find findString:(NSString *)findString
                              items:(NSArray<TSAdvancedFindResultItem *> *)items
{
    if ((self = [super init])) {
        _textStorage = storage;
        _findString = [findString copy];
        _pattern = find.pattern;
        _lineEnding = [find.lineEnding copy];
        _scopeRanges = find.isInSelection ? [find.scopeRanges copy] : nil;
        _liveUpdateDelay = 0.3;
        _items = [items copy];
        // Before the edit is processed, as TSAdvancedFindHighlights: afterwards the text storage has widened the edited
        // range to whole paragraphs while fixing attributes, and every match in the paragraph would become stale.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(textStorageWillProcessEdit:)
                                                   name:NSTextStorageWillProcessEditingNotification object:storage];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)takeItems:(NSArray<TSAdvancedFindResultItem *> *)items
{
    self.items = items;
    self.lines = nil;
    self.editedSinceSearch = NO;
}

- (NSUInteger)staleCount
{
    NSUInteger count = 0;
    for (TSAdvancedFindResultItem *item in self.items)
        count += item.isStale;
    return count;
}

- (NSArray<NSValue *> *)currentRanges
{
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    for (TSAdvancedFindResultItem *item in self.items)
        if (!item.isStale)
            [ranges addObject:[NSValue valueWithRange:item.currentRange]];
    return ranges;
}

/// Searches the current text again, on a background queue, so a live update of a 10 MB text does not hold the
/// main thread. A newer edit or search makes an older search stop and its result be dropped.
- (void)update
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
    NSTextStorage *storage = self.textStorage;
    if (!storage)
        return;
    NSUInteger generation = ++self.searchGeneration;
    NSUInteger edits = self.editCount;
    NSArray<NSValue *> *selection = self.scopeRanges ?: @[[NSValue valueWithRange:NSMakeRange(0, 0)]];
    BOOL inSelection = self.scopeRanges != nil;
    NSString *string = [storage.string copy];
    TSRegexFindPattern *pattern = self.pattern;
    NSString *lineEnding = self.lineEnding;
    __weak typeof(self) weakSelf = self;
    BOOL (^isCancelled)(void) = ^BOOL { TSAdvancedFindResults *results = weakSelf; return !results || results.searchGeneration != generation; };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        TSRegexTextFind *find = [[TSRegexTextFind alloc] initWithString:string pattern:pattern lineEnding:lineEnding
                                                         selectedRanges:selection inSelection:inSelection error:NULL];
        // An emptied scope finds nothing.
        NSArray<TSAdvancedFindResultItem *> *items = find ? [TSAdvancedFindResults itemsOfFind:(TSRegexTextFind *_Nonnull)find cancellation:isCancelled progress:nil] : @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            TSAdvancedFindResults *results = weakSelf;
            if (!items || !results || results.searchGeneration != generation || results.editCount != edits)
                return; // stopped, or the text changed meanwhile: a newer search follows
            [results takeItems:items];
            if (results.changeHandler)
                results.changeHandler(results);
        });
    });
}

- (void)setUpdatesLive:(BOOL)updatesLive
{
    _updatesLive = updatesLive;
    if (!updatesLive) {
        // Turned off, the list stays as it is: no search waiting for its delay, nor one already running, changes it.
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
        self.searchGeneration++;
        return;
    }
    if (self.editedSinceSearch)
        [self update]; // edits since may have made new matches, not only stale ones
}

#pragma mark Edits

/// `range` after replacing the old text [a, b) with new text ending at b2 (OgreKit's six cases).
/// Returns NO when the edit touched the range: the range is then what is left of it, or empty where the edit ends.
static BOOL TSAdjustRange(NSRange *range, NSUInteger a, NSUInteger b, NSUInteger b2)
{
    NSUInteger c = range->location, d = NSMaxRange(*range);
    if (d <= a)                     // [ ] ( )
        return YES;
    if (b <= c) {                   // ( ) [ ]
        range->location = c + b2 - b;
        return YES;
    }
    if (c < a && b < d)             // [ ( ) ]: the edit inside, the match grows or shrinks with it
        *range = NSMakeRange(c, d - c + b2 - b);
    else if (a <= c && d <= b)      // ( [ ] ): the match is gone; empty where the edit ends
        *range = NSMakeRange(b2, 0);
    else if (a <= c)                // ( [ ) ]: what is left after the edit
        *range = NSMakeRange(b2, d - b);
    else                            // [ ( ] ): what is left before the edit
        *range = NSMakeRange(c, a - c);
    return NO;
}

- (void)textStorageWillProcessEdit:(NSNotification *)notification
{
    NSTextStorage *storage = self.textStorage;
    if (!(storage.editedMask & NSTextStorageEditedCharacters))
        return;
    NSRange edited = storage.editedRange;
    NSUInteger b2 = NSMaxRange(edited);
    [self followEditFrom:edited.location to:(NSUInteger)((NSInteger)b2 - storage.changeInLength) newEnd:b2];
    if (self.changeHandler)
        self.changeHandler(self);
    if (self.updatesLive) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
        // Not during the edit: the text storage is still processing it.
        [self performSelector:@selector(update) withObject:nil afterDelay:self.liveUpdateDelay inModes:@[NSRunLoopCommonModes]];
    }
}

- (void)followEdits:(NSArray<TSAdvancedFindTextEdit *> *)edits
{
    for (TSAdvancedFindTextEdit *edit in edits)
        [self followEditFrom:edit.range.location to:NSMaxRange(edit.range) newEnd:edit.range.location + edit.replacementLength];
}

/// The old text [a, b) was replaced with new text ending at b2.
- (void)followEditFrom:(NSUInteger)a to:(NSUInteger)b newEnd:(NSUInteger)b2
{
    self.editCount++;
    self.editedSinceSearch = YES;
    for (TSAdvancedFindResultItem *item in self.items) {
        NSRange range = item.currentRange;
        if (!TSAdjustRange(&range, a, b, b2))
            item.stale = YES;
        item.currentRange = range;
    }
    if (self.scopeRanges) {
        // A scope grows or shrinks with the edits inside it, and loses what an edit over its edge removed.
        NSMutableArray<NSValue *> *scope = [NSMutableArray array];
        for (NSValue *value in self.scopeRanges) {
            NSRange range = value.rangeValue;
            NSUInteger c = range.location, d = NSMaxRange(range);
            if (!TSAdjustRange(&range, a, b, b2) && c <= a && b <= d)
                range = NSMakeRange(c, d - c + b2 - b); // an edit at an inner edge stays inside
            [scope addObject:[NSValue valueWithRange:range]];
        }
        self.scopeRanges = scope;
    }
    self.lines = nil;
}

#pragma mark Showing

- (NSUInteger)lineNumberOfItem:(TSAdvancedFindResultItem *)item
{
    if (!self.lines)
        self.lines = [[TSLineStarts alloc] initWithString:self.textStorage.string ?: @""];
    return [self.lines lineNumberAtIndex:item.currentRange.location];
}

static BOOL TSIsLineBreak(unichar c)
{
    return c == '\n' || c == '\r' || c == 0x2028 || c == 0x2029 || c == 0x85;
}

- (NSAttributedString *)lineTextOfItem:(TSAdvancedFindResultItem *)item
                            attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes
                            matchColor:(NSColor *)matchColor
                           groupColors:(NSArray<NSColor *> *)groupColors
{
    NSString *string = self.textStorage.string ?: @"";
    NSRange match = item.currentRange;
    NSUInteger length = string.length;
    if (NSMaxRange(match) > length)
        return [[NSAttributedString alloc] initWithString:@"" attributes:attributes];

    NSUInteger lineStart = 0, contentsEnd = 0;
    [string getLineStart:&lineStart end:NULL contentsEnd:NULL forRange:NSMakeRange(match.location, 0)];
    [string getLineStart:NULL end:NULL contentsEnd:&contentsEnd forRange:NSMakeRange(NSMaxRange(match), 0)];
    NSUInteger before = lineStart;
    BOOL cutBefore = match.location - lineStart > TSBeforeLength;
    if (cutBefore) {
        before = match.location - TSBeforeLength;
        NSRange composed = [string rangeOfComposedCharacterSequenceAtIndex:before];
        if (composed.location < before)
            before = NSMaxRange(composed);
    }
    // To the end of the line where the match ends (a match over lines shows "⏎"), 250 characters at most.
    NSUInteger after = MAX(contentsEnd, NSMaxRange(match));
    BOOL cutAfter = after - before > TSShownLength;
    if (cutAfter)
        after = [string rangeOfComposedCharacterSequenceAtIndex:before + TSShownLength].location;

    // The shown text, made of pieces of the document; a line break is one "⏎", a tab one space.
    NSMutableString *shown = [NSMutableString string];
    NSMutableData *pieces = [NSMutableData data]; // pairs of NSRange: in the document, in `shown`
    void (^addPiece)(NSRange, NSRange) = ^(NSRange document, NSRange inShown) {
        NSRange pair[2] = {document, inShown};
        [pieces appendBytes:pair length:sizeof pair];
    };
    if (cutBefore)
        [shown appendString:@"…"];
    NSUInteger index = before;
    while (index < after) {
        unichar c = [string characterAtIndex:index];
        if (TSIsLineBreak(c)) {
            NSUInteger breakLength = (c == '\r' && index + 1 < after && [string characterAtIndex:index + 1] == '\n') ? 2 : 1;
            addPiece(NSMakeRange(index, breakLength), NSMakeRange(shown.length, 1));
            [shown appendString:@"⏎"];
            index += breakLength;
            continue;
        }
        NSUInteger run = index;
        while (run < after && !TSIsLineBreak([string characterAtIndex:run]))
            run++;
        NSString *text = [[string substringWithRange:NSMakeRange(index, run - index)] stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
        addPiece(NSMakeRange(index, run - index), NSMakeRange(shown.length, text.length));
        [shown appendString:text];
        index = run;
    }
    if (cutAfter)
        [shown appendString:@"…"];

    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:shown attributes:attributes];
    // The cut marks are gray, as in OgreKit.
    if (cutBefore)
        [text addAttribute:NSForegroundColorAttributeName value:NSColor.secondaryLabelColor range:NSMakeRange(0, 1)];
    if (cutAfter)
        [text addAttribute:NSForegroundColorAttributeName value:NSColor.secondaryLabelColor range:NSMakeRange(text.length - 1, 1)];
    if (item.isStale) {
        // An edit touched the match: what is there now, without colors.
        [text addAttribute:NSForegroundColorAttributeName value:NSColor.tertiaryLabelColor range:NSMakeRange(0, text.length)];
        return text;
    }
    const NSRange *pairs = pieces.bytes;
    NSUInteger pieceCount = pieces.length / (2 * sizeof(NSRange));
    void (^color)(NSRange, NSColor *) = ^(NSRange documentRange, NSColor *background) {
        for (NSUInteger i = 0; i < pieceCount; i++) {
            NSRange document = pairs[2 * i], inShown = pairs[2 * i + 1];
            NSRange common = NSIntersectionRange(documentRange, document);
            if (common.length == 0)
                continue;
            NSRange target = document.length == inShown.length ? NSMakeRange(inShown.location + common.location - document.location, common.length) : inShown;
            [text addAttribute:NSBackgroundColorAttributeName value:background range:target];
        }
    };
    color(match, matchColor);
    // The groups moved with the match (no edit touched it). Outer groups first, so a group inside another shows its own color.
    NSInteger shift = (NSInteger)match.location - (NSInteger)item.foundRanges.firstObject.rangeValue.location;
    for (NSUInteger k = 1; k < item.foundRanges.count && groupColors.count > 0; k++) {
        NSRange group = item.foundRanges[k].rangeValue;
        if (group.location == NSNotFound)
            continue;
        group.location = (NSUInteger)((NSInteger)group.location + shift);
        color(group, groupColors[(k - 1) % groupColors.count]);
    }
    return text;
}

@end
