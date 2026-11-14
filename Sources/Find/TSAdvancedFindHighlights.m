// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindHighlights.h"
#import <objc/runtime.h>

static const void *TSAdvancedFindHighlightsKey = &TSAdvancedFindHighlightsKey;

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

- (instancetype)initWithTextStorage:(NSTextStorage *)storage
{
    if ((self = [super init])) {
        _textStorage = storage;
        _ranges = @[];
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
    NSArray<NSValue *> *old = _ranges;
    _ranges = [ranges copy];
    [self redisplayRanges:old];
    [self redisplayRanges:_ranges];
}

- (void)removeAll
{
    self.ranges = @[];
}

- (void)redisplayRanges:(NSArray<NSValue *> *)ranges
{
    NSTextStorage *storage = self.textStorage;
    if (ranges.count == 0 || !storage)
        return;
    NSRange all = NSMakeRange(ranges.firstObject.rangeValue.location, NSMaxRange(ranges.lastObject.rangeValue) - ranges.firstObject.rangeValue.location);
    all = NSIntersectionRange(all, NSMakeRange(0, storage.length));
    for (NSLayoutManager *layout in storage.layoutManagers)
        [layout invalidateDisplayForCharacterRange:all];
}

/// Moves the ranges after an edit and drops the ones the edit touched.
- (void)textStorageWillProcessEditing:(NSNotification *)notification
{
    NSTextStorage *storage = self.textStorage;
    if (!(storage.editedMask & NSTextStorageEditedCharacters) || self.ranges.count == 0)
        return;
    NSRange edited = storage.editedRange;
    NSInteger delta = storage.changeInLength;
    NSUInteger oldEnd = (NSUInteger)((NSInteger)NSMaxRange(edited) - delta); // end of the replaced text, before the edit
    NSMutableArray<NSValue *> *moved = [NSMutableArray array];
    for (NSValue *value in self.ranges) {
        NSRange range = value.rangeValue;
        if (NSMaxRange(range) <= edited.location)
            [moved addObject:value];
        else if (range.location >= oldEnd)
            [moved addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)((NSInteger)range.location + delta), range.length)]];
    }
    _ranges = moved;
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
    [NSGraphicsContext saveGraphicsState];
    [self.color setFill];
    for (NSValue *value in highlights.ranges) {
        NSRange range = NSIntersectionRange(value.rangeValue, characters);
        if (range.length == 0)
            continue;
        NSRange glyphs = [layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
        [layoutManager enumerateEnclosingRectsForGlyphRange:glyphs withinSelectedGlyphRange:NSMakeRange(NSNotFound, 0)
                                            inTextContainer:container usingBlock:^(NSRect rect, BOOL *stop) {
            NSRectFillUsingOperation(NSOffsetRect(rect, origin.x, origin.y), NSCompositingOperationSourceOver);
        }];
    }
    [NSGraphicsContext restoreGraphicsState];
}

@end
