// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindHighlights.h"
#import <objc/runtime.h>

static const void *TSAdvancedFindHighlightsKey = &TSAdvancedFindHighlightsKey;

/// The match with every group that took part: what an edit must not touch.
static NSRange TSHighlightExtent(NSRange match, const NSRange *_Nullable groups, NSUInteger groupCount)
{
    NSRange extent = match;
    for (NSUInteger k = 0; k < groupCount; k++)
        if (groups[k].location != NSNotFound)
            extent = NSUnionRange(extent, groups[k]);
    return extent;
}

static NSRange TSShiftedRange(NSRange range, NSInteger delta)
{
    if (range.location != NSNotFound)
        range.location = (NSUInteger)((NSInteger)range.location + delta);
    return range;
}

@interface TSAdvancedFindHighlights ()
- (instancetype)initWithTextStorage:(NSTextStorage *)storage NS_DESIGNATED_INITIALIZER;
@end

@implementation TSAdvancedFindHighlights {
    /// `groupCount` NSRanges for each match, in the order of the matches; nil without groups. Plain ranges, not
    /// objects: there may be hundreds of thousands of matches, and an edit moves all those after it.
    NSMutableData *_groupRanges;
    /// How far a group reaches at most before the start or after the end of its match. With them, the matches that may
    /// show in a part of the text are found from the sorted matches alone.
    NSUInteger _reachBefore, _reachAfter;
    /// Where edits took highlights away, in the edited text, to be drawn again once the edits are done;
    /// {NSNotFound, 0} if nowhere.
    NSRange _dropped;
}

+ (instancetype)highlightsForTextStorage:(NSTextStorage *)storage
{
    TSAdvancedFindHighlights *highlights = [self existingHighlightsForTextStorage:storage];
    if (!highlights) {
        highlights = [[TSAdvancedFindHighlights alloc] initWithTextStorage:storage];
        objc_setAssociatedObject(storage, TSAdvancedFindHighlightsKey, highlights, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return highlights;
}

+ (nullable instancetype)existingHighlightsForTextStorage:(NSTextStorage *)storage
{
    return objc_getAssociatedObject(storage, TSAdvancedFindHighlightsKey);
}

+ (NSColor *)color
{
    return [NSColor.findHighlightColor colorWithAlphaComponent:0.45];
}

+ (NSArray<NSColor *> *)groupColors
{
    NSArray<NSColor *> *base = @[NSColor.systemTealColor, NSColor.systemPinkColor, NSColor.systemPurpleColor, NSColor.systemOrangeColor, NSColor.systemBlueColor];
    NSMutableArray<NSColor *> *colors = [NSMutableArray array];
    for (NSColor *color in base)
        [colors addObject:[color colorWithAlphaComponent:0.35]];
    return colors;
}

- (instancetype)initWithTextStorage:(NSTextStorage *)storage
{
    if ((self = [super init])) {
        _textStorage = storage;
        _ranges = @[];
        _dropped = NSMakeRange(NSNotFound, 0);
        // Before the edit is processed: afterwards the text storage has widened the edited range to whole paragraphs
        // while fixing attributes, and every highlight in the paragraph would be dropped.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(textStorageWillProcessEditing:)
                                                   name:NSTextStorageWillProcessEditingNotification object:storage];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSArray<NSArray<NSValue *> *> *)groups
{
    NSUInteger count = self.groupCount;
    if (count == 0)
        return @[];
    const NSRange *groups = _groupRanges.bytes;
    NSMutableArray<NSArray<NSValue *> *> *all = [NSMutableArray arrayWithCapacity:self.ranges.count];
    for (NSUInteger i = 0; i < self.ranges.count; i++) {
        NSMutableArray<NSValue *> *own = [NSMutableArray arrayWithCapacity:count];
        for (NSUInteger k = 0; k < count; k++)
            [own addObject:[NSValue valueWithRange:groups[i * count + k]]];
        [all addObject:own];
    }
    return all;
}

- (void)setRanges:(NSArray<NSValue *> *)ranges
{
    [self setRanges:ranges groupRanges:[NSData data] groupCount:0];
}

- (void)setRanges:(NSArray<NSValue *> *)ranges groups:(NSArray<NSArray<NSValue *> *> *)groups
{
    NSParameterAssert(groups.count == 0 || groups.count == ranges.count);
    NSUInteger count = groups.count == ranges.count ? groups.firstObject.count : 0;
    NSMutableData *data = [NSMutableData dataWithCapacity:ranges.count * count * sizeof(NSRange)];
    for (NSArray<NSValue *> *own in count ? groups : @[]) {
        NSParameterAssert(own.count == count);
        for (NSUInteger k = 0; k < count; k++) {
            NSRange group = k < own.count ? own[k].rangeValue : NSMakeRange(NSNotFound, 0);
            [data appendBytes:&group length:sizeof group];
        }
    }
    [self setRanges:ranges groupRanges:data groupCount:count];
}

- (void)setRanges:(NSArray<NSValue *> *)ranges groupRanges:(NSData *)groupRanges groupCount:(NSUInteger)groupCount
{
    NSParameterAssert(groupRanges.length == ranges.count * groupCount * sizeof(NSRange));
    if (groupRanges.length != ranges.count * groupCount * sizeof(NSRange) || ranges.count == 0)
        groupCount = 0;
    NSRange old = self.span;
    _ranges = [ranges copy];
    _groupCount = groupCount;
    _groupRanges = groupCount ? [groupRanges mutableCopy] : nil;
    _reachBefore = _reachAfter = 0;
    if (groupCount) {
        const NSRange *groups = _groupRanges.bytes;
        NSUInteger i = 0;
        for (NSValue *value in _ranges) {
            NSRange match = value.rangeValue;
            for (NSUInteger k = 0; k < groupCount; k++) {
                NSRange group = groups[i * groupCount + k];
                if (group.location == NSNotFound)
                    continue;
                if (group.location < match.location)
                    _reachBefore = MAX(_reachBefore, match.location - group.location);
                if (NSMaxRange(group) > NSMaxRange(match))
                    _reachAfter = MAX(_reachAfter, NSMaxRange(group) - NSMaxRange(match));
            }
            i++;
        }
    }
    [self redisplayRange:old];
    [self redisplayRange:self.span];
}

- (void)removeAll
{
    self.ranges = @[];
}

/// From where the first highlight may start to where the last may end, with their groups; {NSNotFound, 0} if none.
/// Found from the first and the last match only, so it costs nothing with many matches.
- (NSRange)span
{
    if (self.ranges.count == 0)
        return NSMakeRange(NSNotFound, 0);
    NSRange first = self.ranges.firstObject.rangeValue, last = self.ranges.lastObject.rangeValue;
    NSUInteger start = first.location - MIN(_reachBefore, first.location);
    return NSMakeRange(start, NSMaxRange(last) + _reachAfter - start);
}

/// The first match that may show at `location` or after it: every match before it, with its groups, ends before.
- (NSUInteger)firstMatchReaching:(NSUInteger)location
{
    NSUInteger low = 0, high = self.ranges.count;
    while (low < high) {
        NSUInteger middle = low + (high - low) / 2;
        if (NSMaxRange(self.ranges[middle].rangeValue) + _reachAfter <= location)
            low = middle + 1;
        else
            high = middle;
    }
    return low;
}

- (void)redisplayRange:(NSRange)range
{
    NSTextStorage *storage = self.textStorage;
    if (range.location == NSNotFound || !storage)
        return;
    NSRange all = NSIntersectionRange(range, NSMakeRange(0, storage.length));
    for (NSLayoutManager *layout in storage.layoutManagers)
        [layout invalidateDisplayForCharacterRange:all];
}

/// `range` of the text before an edit, in the edited text: moved if after the edit, else up to the edit's end too.
static NSRange TSRangeAfterEdit(NSRange range, NSRange edited, NSUInteger oldEnd, NSInteger delta)
{
    if (NSMaxRange(range) <= edited.location)
        return range;
    if (range.location >= oldEnd)
        return TSShiftedRange(range, delta);
    NSUInteger start = MIN(range.location, edited.location);
    NSUInteger end = NSMaxRange(range) > oldEnd ? (NSUInteger)((NSInteger)NSMaxRange(range) + delta) : NSMaxRange(edited);
    return NSMakeRange(start, MAX(end, start) - start);
}

/// Moves the ranges after an edit and drops the ones the edit touched, each match with its groups. The layout manager
/// redraws only around the edited text: where a dropped match or group lies beyond it (a match over lines, a group
/// outside its match), it is drawn again once the edits are done, before the window is drawn.
- (void)textStorageWillProcessEditing:(NSNotification *)notification
{
    NSTextStorage *storage = self.textStorage;
    if (!(storage.editedMask & NSTextStorageEditedCharacters))
        return;
    NSRange edited = storage.editedRange;
    NSInteger delta = storage.changeInLength;
    NSUInteger oldEnd = (NSUInteger)((NSInteger)NSMaxRange(edited) - delta); // end of the replaced text, before the edit
    if (_dropped.location != NSNotFound) // dropped by an earlier edit, still to be drawn
        _dropped = TSRangeAfterEdit(_dropped, edited, oldEnd, delta);
    if (self.ranges.count == 0)
        return;
    NSArray<NSValue *> *ranges = self.ranges;
    NSUInteger count = ranges.count, groupCount = self.groupCount;
    NSRange *groups = groupCount ? _groupRanges.mutableBytes : NULL;
    // The matches before `first` end before the edit with their groups and stay as they are.
    NSUInteger first = [self firstMatchReaching:edited.location];
    NSMutableArray<NSValue *> *moved = [NSMutableArray arrayWithCapacity:count];
    [moved addObjectsFromArray:[ranges subarrayWithRange:NSMakeRange(0, first)]];
    NSUInteger kept = first;
    NSRange dropped = NSMakeRange(NSNotFound, 0);
    for (NSUInteger i = first; i < count; i++) {
        NSValue *value = ranges[i];
        NSRange match = value.rangeValue;
        NSRange *own = groups ? groups + i * groupCount : NULL;
        NSRange extent = TSHighlightExtent(match, own, groupCount);
        BOOL before = NSMaxRange(extent) <= edited.location, after = extent.location >= oldEnd;
        if (before || after) {
            if (after && delta != 0)
                value = [NSValue valueWithRange:TSShiftedRange(match, delta)];
            [moved addObject:value];
            if (groupCount) {
                NSRange *target = groups + kept * groupCount;
                if (target != own)
                    memmove(target, own, groupCount * sizeof(NSRange));
                if (after && delta != 0)
                    for (NSUInteger k = 0; k < groupCount; k++)
                        target[k] = TSShiftedRange(target[k], delta);
            }
            kept++;
        } else {
            NSRange place = TSRangeAfterEdit(extent, edited, oldEnd, delta);
            dropped = dropped.location == NSNotFound ? place : NSUnionRange(dropped, place);
        }
    }
    _ranges = moved;
    if (groupCount)
        _groupRanges.length = kept * groupCount * sizeof(NSRange);
    if (dropped.location == NSNotFound)
        return;
    BOOL scheduled = _dropped.location != NSNotFound;
    _dropped = scheduled ? NSUnionRange(_dropped, dropped) : dropped;
    if (!scheduled)
        [self redisplayDroppedLater];
}

/// The layout managers cannot draw again while the text storage processes the edit (they would lay out text they do
/// not know yet): after it, in the same pass of the run loop, before the window is drawn.
- (void)redisplayDroppedLater
{
    __weak TSAdvancedFindHighlights *weakSelf = self;
    CFRunLoopRef loop = CFRunLoopGetMain();
    CFRunLoopPerformBlock(loop, kCFRunLoopCommonModes, ^{
        TSAdvancedFindHighlights *highlights = weakSelf;
        NSTextStorage *storage = highlights.textStorage;
        if (!highlights || !storage)
            return;
        if (storage.editedMask != 0) { // inside another edit: after that one
            [highlights redisplayDroppedLater];
            return;
        }
        NSRange dropped = highlights->_dropped;
        highlights->_dropped = NSMakeRange(NSNotFound, 0);
        [highlights redisplayRange:dropped];
    });
    CFRunLoopWakeUp(loop);
}

+ (void)drawInLayoutManager:(NSLayoutManager *)layoutManager forGlyphRange:(NSRange)glyphRange atPoint:(NSPoint)origin
{
    NSTextStorage *storage = layoutManager.textStorage;
    TSAdvancedFindHighlights *highlights = storage ? [self existingHighlightsForTextStorage:storage] : nil;
    NSArray<NSValue *> *ranges = highlights.ranges;
    if (ranges.count == 0)
        return;
    NSRange characters = [layoutManager characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
    NSTextContainer *container = [layoutManager textContainerForGlyphAtIndex:glyphRange.location effectiveRange:NULL];
    if (!container)
        return;
    void (^fill)(NSRange, NSColor *) = ^(NSRange range, NSColor *color) {
        range = NSIntersectionRange(range, characters);
        if (range.length == 0)
            return;
        [color setFill];
        NSRange glyphs = [layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
        [layoutManager enumerateEnclosingRectsForGlyphRange:glyphs withinSelectedGlyphRange:NSMakeRange(NSNotFound, 0)
                                            inTextContainer:container usingBlock:^(NSRect rect, BOOL *stop) {
            NSRectFillUsingOperation(NSOffsetRect(rect, origin.x, origin.y), NSCompositingOperationSourceOver);
        }];
    };
    NSUInteger groupCount = highlights.groupCount;
    const NSRange *groups = groupCount ? highlights->_groupRanges.bytes : NULL;
    NSColor *matchColor = self.color;
    NSArray<NSColor *> *groupColors = groupCount ? self.groupColors : @[];
    // Only the matches that may show here: from the first that reaches the drawn text to the last that starts before
    // its end, with the reach of the groups on both sides.
    NSUInteger last = NSMaxRange(characters) + highlights->_reachBefore;
    NSUInteger *ends = groupCount ? malloc((2 + 2 * groupCount) * sizeof(NSUInteger)) : NULL;
    [NSGraphicsContext saveGraphicsState];
    for (NSUInteger i = [highlights firstMatchReaching:characters.location]; i < ranges.count; i++) {
        NSRange match = ranges[i].rangeValue;
        if (match.location >= last)
            break;
        if (groupCount == 0) {
            fill(match, matchColor);
            continue;
        }
        // A group shows its color instead of the match's, and a group inside another its own: each piece between
        // two ends takes the color of the last group over it, or of the match.
        const NSRange *own = groups + i * groupCount;
        NSUInteger count = 0;
        ends[count++] = match.location;
        ends[count++] = NSMaxRange(match);
        for (NSUInteger k = 0; k < groupCount; k++)
            if (own[k].location != NSNotFound && own[k].length > 0) {
                ends[count++] = own[k].location;
                ends[count++] = NSMaxRange(own[k]);
            }
        for (NSUInteger a = 1; a < count; a++) // a handful of ends: insertion sort
            for (NSUInteger b = a; b > 0 && ends[b - 1] > ends[b]; b--) {
                NSUInteger swap = ends[b];
                ends[b] = ends[b - 1];
                ends[b - 1] = swap;
            }
        NSUInteger runStart = NSNotFound;
        NSColor *runColor = nil;
        for (NSUInteger e = 0; e + 1 < count; e++) {
            NSUInteger start = ends[e];
            if (start == ends[e + 1])
                continue;
            NSColor *color = NSLocationInRange(start, match) ? matchColor : nil;
            for (NSUInteger k = 0; k < groupCount; k++)
                if (own[k].location != NSNotFound && NSLocationInRange(start, own[k]))
                    color = groupColors[k % groupColors.count];
            if (color != runColor) {
                if (runColor)
                    fill(NSMakeRange(runStart, start - runStart), runColor);
                runColor = color;
                runStart = start;
            }
        }
        if (runColor)
            fill(NSMakeRange(runStart, ends[count - 1] - runStart), runColor);
    }
    [NSGraphicsContext restoreGraphicsState];
    free(ends);
}

@end
