// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindHighlights.h"
#import <objc/runtime.h>

static const void *TSAdvancedFindHighlightsKey = &TSAdvancedFindHighlightsKey;

/// The match with every group that took part: what an edit must not touch, and what is redrawn.
static NSRange TSHighlightExtent(NSRange match, NSArray<NSValue *> *_Nullable groups)
{
    NSRange extent = match;
    for (NSValue *value in groups) {
        NSRange group = value.rangeValue;
        if (group.location != NSNotFound)
            extent = NSUnionRange(extent, group);
    }
    return extent;
}

@interface TSAdvancedFindHighlights ()
- (instancetype)initWithTextStorage:(NSTextStorage *)storage NS_DESIGNATED_INITIALIZER;
@end

@implementation TSAdvancedFindHighlights

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
        _groups = @[];
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

- (void)setRanges:(NSArray<NSValue *> *)ranges
{
    [self setRanges:ranges groups:@[]];
}

- (void)setRanges:(NSArray<NSValue *> *)ranges groups:(NSArray<NSArray<NSValue *> *> *)groups
{
    NSParameterAssert(groups.count == 0 || groups.count == ranges.count);
    NSRange old = self.span;
    _ranges = [ranges copy];
    _groups = groups.count == ranges.count ? [groups copy] : @[];
    [self redisplayRange:old];
    [self redisplayRange:self.span];
}

/// From the start of the first highlight to the end of the last one, with their groups; {NSNotFound, 0} if none.
- (NSRange)span
{
    NSRange span = NSMakeRange(NSNotFound, 0);
    BOOL grouped = self.groups.count > 0;
    for (NSUInteger i = 0; i < self.ranges.count; i++) {
        NSRange extent = TSHighlightExtent(self.ranges[i].rangeValue, grouped ? self.groups[i] : nil);
        span = span.location == NSNotFound ? extent : NSUnionRange(span, extent);
    }
    return span;
}

- (void)removeAll
{
    self.ranges = @[];
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

static NSValue *TSShiftedRange(NSValue *value, NSInteger delta)
{
    NSRange range = value.rangeValue;
    if (range.location == NSNotFound)
        return value;
    return [NSValue valueWithRange:NSMakeRange((NSUInteger)((NSInteger)range.location + delta), range.length)];
}

/// Moves the ranges after an edit and drops the ones the edit touched, each match with its groups.
- (void)textStorageWillProcessEditing:(NSNotification *)notification
{
    NSTextStorage *storage = self.textStorage;
    if (!(storage.editedMask & NSTextStorageEditedCharacters) || self.ranges.count == 0)
        return;
    NSRange edited = storage.editedRange;
    NSInteger delta = storage.changeInLength;
    NSUInteger oldEnd = (NSUInteger)((NSInteger)NSMaxRange(edited) - delta); // end of the replaced text, before the edit
    BOOL grouped = self.groups.count > 0;
    NSMutableArray<NSValue *> *moved = [NSMutableArray array];
    NSMutableArray<NSArray<NSValue *> *> *movedGroups = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.ranges.count; i++) {
        NSValue *value = self.ranges[i];
        NSArray<NSValue *> *groups = grouped ? self.groups[i] : nil;
        NSRange extent = TSHighlightExtent(value.rangeValue, groups);
        if (NSMaxRange(extent) <= edited.location) {
            [moved addObject:value];
            if (grouped)
                [movedGroups addObject:(NSArray<NSValue *> *_Nonnull)groups];
        } else if (extent.location >= oldEnd) {
            [moved addObject:TSShiftedRange(value, delta)];
            if (grouped) {
                NSMutableArray<NSValue *> *shifted = [NSMutableArray array];
                for (NSValue *group in groups)
                    [shifted addObject:TSShiftedRange(group, delta)];
                [movedGroups addObject:shifted];
            }
        }
    }
    _ranges = moved;
    _groups = movedGroups;
}

+ (void)drawInLayoutManager:(NSLayoutManager *)layoutManager forGlyphRange:(NSRange)glyphRange atPoint:(NSPoint)origin
{
    NSTextStorage *storage = layoutManager.textStorage;
    TSAdvancedFindHighlights *highlights = storage ? [self existingHighlightsForTextStorage:storage] : nil;
    if (highlights.ranges.count == 0)
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
    NSColor *matchColor = self.color;
    NSArray<NSColor *> *groupColors = self.groupColors;
    BOOL grouped = highlights.groups.count > 0;
    [NSGraphicsContext saveGraphicsState];
    for (NSUInteger i = 0; i < highlights.ranges.count; i++) {
        NSRange match = highlights.ranges[i].rangeValue;
        NSArray<NSValue *> *groups = grouped ? highlights.groups[i] : nil;
        NSRange extent = TSHighlightExtent(match, groups);
        if (NSIntersectionRange(extent, characters).length == 0)
            continue;
        if (groups.count == 0) {
            fill(match, matchColor);
            continue;
        }
        // A group shows its color instead of the match's, and a group inside another its own: each piece between
        // two ends takes the color of the last group over it, or of the match.
        NSMutableIndexSet *ends = [NSMutableIndexSet indexSet];
        [ends addIndex:match.location];
        [ends addIndex:NSMaxRange(match)];
        for (NSValue *value in groups) {
            NSRange group = value.rangeValue;
            if (group.location == NSNotFound || group.length == 0)
                continue;
            [ends addIndex:group.location];
            [ends addIndex:NSMaxRange(group)];
        }
        __block NSUInteger start = NSNotFound, runStart = NSNotFound;
        __block NSColor *runColor = nil;
        [ends enumerateIndexesUsingBlock:^(NSUInteger end, BOOL *stop) {
            if (start != NSNotFound) {
                NSColor *color = NSLocationInRange(start, match) ? matchColor : nil;
                for (NSUInteger k = 0; k < groups.count; k++)
                    if (NSLocationInRange(start, groups[k].rangeValue))
                        color = groupColors[k % groupColors.count];
                if (color != runColor) {
                    if (runColor)
                        fill(NSMakeRange(runStart, start - runStart), runColor);
                    runColor = color;
                    runStart = start;
                }
            }
            start = end;
        }];
        if (runColor)
            fill(NSMakeRange(runStart, start - runStart), runColor);
    }
    [NSGraphicsContext restoreGraphicsState];
}

@end
