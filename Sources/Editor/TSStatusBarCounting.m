// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSStatusBarCounting.m
 */

#import "TSStatusBarCounting.h"

// How many characters the loops read between two looks at `cancel`.
static const NSUInteger TSCancelStride = 1 << 14;

static inline BOOL TSIsLineEnd(unichar c)
{
    return c == '\n' || c == '\r' || c == 0x85 || c == 0x2028 || c == 0x2029;
}

// Characters that are a character of their own when the next one is one of these too: no character below
// U+0300 joins the one before or after it except LF after CR, and neither do the common kana, CJK ideographs,
// CJK punctuation, full-width forms and precomposed Hangul syllables (only conjoining jamo join a syllable,
// and they are not among these). Combining marks, joiners, variation selectors, Hangul jamo, emoji
// (surrogates) and the like take the slower path, which asks the text system for the cluster.
static inline BOOL TSIsSimple(unichar c)
{
    return c < 0x300
        || (c >= 0x3000 && c <= 0x3029) || (c >= 0x3041 && c <= 0x3096) || (c >= 0x30A1 && c <= 0x30FA) || c == 0x30FC
        || (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0xFF01 && c <= 0xFF5E);
}

// The end of the grapheme cluster that starts at `location`, within [location, end). The text system's composed
// character sequences are not grapheme clusters: they join a combining mark to a control character before it and
// do not join a prepended concatenation mark to the character after it. ICU's \X, the extended grapheme cluster of
// Unicode Standard Annex #29, is what Swift and CotEditor count.
static NSUInteger TSClusterEnd(NSString *string, NSUInteger location, NSUInteger end)
{
    static NSRegularExpression *cluster;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cluster = [NSRegularExpression regularExpressionWithPattern:@"\\X" options:0 error:NULL];
    });
    NSRange found = [cluster rangeOfFirstMatchInString:string options:NSMatchingAnchored | NSMatchingWithoutAnchoringBounds
                                                 range:NSMakeRange(location, end - location)];
    return found.location == location && found.length ? NSMaxRange(found) : location + 1;
}

NSUInteger TSStatusBarCharacterCount(NSString *string, NSRange range, TSStatusBarCancel cancel)
{
    NSUInteger length = string.length;
    if (range.location >= length || range.length == 0)
        return 0;
    NSUInteger end = MIN(NSMaxRange(range), length);
    CFStringInlineBuffer buffer;
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &buffer, CFRangeMake(0, (CFIndex)length));
    NSUInteger count = 0, i = range.location, check = i + TSCancelStride;
    while (i < end) {
        if (i >= check) {
            if (cancel && cancel())
                return count;
            check = i + TSCancelStride;
        }
        unichar c = CFStringGetCharacterFromInlineBuffer(&buffer, (CFIndex)i);
        unichar next = i + 1 < end ? CFStringGetCharacterFromInlineBuffer(&buffer, (CFIndex)(i + 1)) : 0;
        count++;
        if (c == '\r') {
            // CR LF is one character, as in Swift and in CotEditor; the text system counts two.
            i += next == '\n' ? 2 : 1;
        } else if (TSIsSimple(c) && (i + 1 >= end || TSIsSimple(next))) {
            i++;
        } else {
            NSUInteger after = TSClusterEnd(string, i, end);
            i = MAX(i + 1, after);
        }
    }
    return count;
}

NSUInteger TSStatusBarWordCount(NSString *string, NSRange range, TSStatusBarCancel cancel)
{
    NSUInteger length = string.length;
    if (range.location >= length || range.length == 0)
        return 0;
    range.length = MIN(NSMaxRange(range), length) - range.location;
    __block NSUInteger count = 0;
    [string enumerateSubstringsInRange:range
                               options:NSStringEnumerationByWords | NSStringEnumerationLocalized | NSStringEnumerationSubstringNotRequired
                            usingBlock:^(NSString *word, NSRange wordRange, NSRange enclosingRange, BOOL *stop) {
        count++;
        if ((count & 1023) == 0 && cancel && cancel())
            *stop = YES;
    }];
    return count;
}

// The number of line ends among the characters [from, to), counted for the text up to `limit`: CR LF counts once,
// at its CR, and only when its LF is before `limit`. `previous` carries the character before `from` from one call
// to the next.
static NSUInteger TSLineEnds(CFStringInlineBuffer *buffer, NSUInteger from, NSUInteger to, NSUInteger limit, NSUInteger length, unichar *previous)
{
    NSUInteger count = 0;
    unichar last = *previous;
    for (NSUInteger i = from; i < to; i++) {
        unichar c = CFStringGetCharacterFromInlineBuffer(buffer, (CFIndex)i);
        if (c == '\n' && last == '\r')
            ; // CR LF was counted at its CR
        else if (c == '\r') {
            // A CR whose LF is at or after `limit` does not end the line yet.
            BOOL followedByLF = i + 1 < length && CFStringGetCharacterFromInlineBuffer(buffer, (CFIndex)(i + 1)) == '\n';
            if (!followedByLF || i + 1 < limit)
                count++;
        } else if (TSIsLineEnd(c))
            count++;
        last = c;
    }
    *previous = last;
    return count;
}

NSUInteger TSStatusBarLineCount(NSString *string, TSStatusBarCancel cancel)
{
    NSUInteger length = string.length;
    if (length == 0)
        return 0;
    CFStringInlineBuffer buffer;
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &buffer, CFRangeMake(0, (CFIndex)length));
    NSUInteger ends = 0;
    unichar previous = 0;
    for (NSUInteger from = 0; from < length; from += TSCancelStride) {
        if (from && cancel && cancel())
            return ends;
        NSUInteger to = MIN(from + TSCancelStride, length);
        ends += TSLineEnds(&buffer, from, to, length, length, &previous);
    }
    unichar last = CFStringGetCharacterFromInlineBuffer(&buffer, (CFIndex)(length - 1));
    return ends + (TSIsLineEnd(last) ? 0 : 1);
}

NSUInteger TSStatusBarLineNumber(NSString *string, NSUInteger location)
{
    NSUInteger length = string.length;
    location = MIN(location, length);
    if (location == 0)
        return 1;
    CFStringInlineBuffer buffer;
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &buffer, CFRangeMake(0, (CFIndex)length));
    unichar previous = 0;
    return 1 + TSLineEnds(&buffer, 0, location, location, length, &previous);
}

NSUInteger TSStatusBarSelectedLineCount(NSString *string, NSArray<NSValue *> *ranges)
{
    NSMutableIndexSet *lines = [NSMutableIndexSet indexSet];
    NSUInteger length = string.length;
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        if (range.length == 0 || range.location >= length)
            continue;
        NSUInteger last = MIN(NSMaxRange(range), length) - 1;
        NSUInteger first = TSStatusBarLineNumber(string, range.location);
        [lines addIndexesInRange:NSMakeRange(first, TSStatusBarLineNumber(string, last) - first + 1)];
    }
    return lines.count;
}

// The start of the line that holds `location`, as TSStatusBarLineNumber counts lines.
static NSUInteger TSLineStart(NSString *string, NSUInteger location)
{
    NSUInteger i = MIN(location, string.length);
    // A location between CR and LF is on the line of the CR.
    if (i > 0 && i < string.length && [string characterAtIndex:i - 1] == '\r' && [string characterAtIndex:i] == '\n')
        i--;
    while (i > 0 && !TSIsLineEnd([string characterAtIndex:i - 1]))
        i--;
    return i;
}

NSUInteger TSStatusBarColumn(NSString *string, NSUInteger location)
{
    location = MIN(location, string.length);
    NSUInteger start = TSLineStart(string, location);
    return TSStatusBarCharacterCount(string, NSMakeRange(start, location - start), nil);
}

TSStatusBarCounts TSStatusBarCountsUnknown(void)
{
    return (TSStatusBarCounts){NSNotFound, NSNotFound, NSNotFound, NSNotFound, NSNotFound, NSNotFound, NSNotFound, NSNotFound, NSNotFound};
}

BOOL TSStatusBarCount(NSString *string, NSArray<NSValue *> *ranges, BOOL content, BOOL selection,
                      TSStatusBarCounts *counts, TSStatusBarCancel cancel)
{
    NSUInteger length = string.length;
    if (content) {
        NSUInteger lines = TSStatusBarLineCount(string, cancel);
        if (cancel && cancel()) return NO;
        NSUInteger characters = TSStatusBarCharacterCount(string, NSMakeRange(0, length), cancel);
        if (cancel && cancel()) return NO;
        NSUInteger words = TSStatusBarWordCount(string, NSMakeRange(0, length), cancel);
        if (cancel && cancel()) return NO;
        counts->lines = lines;
        counts->characters = characters;
        counts->words = words;
    }
    if (selection) {
        NSUInteger selectedCharacters = 0, selectedWords = 0;
        for (NSValue *value in ranges) {
            NSRange range = value.rangeValue;
            selectedCharacters += TSStatusBarCharacterCount(string, range, cancel);
            selectedWords += TSStatusBarWordCount(string, range, cancel);
            if (cancel && cancel()) return NO;
        }
        NSUInteger location = MIN(ranges.count ? ranges.firstObject.rangeValue.location : 0, length);
        NSUInteger offset = TSStatusBarCharacterCount(string, NSMakeRange(0, location), cancel);
        if (cancel && cancel()) return NO;
        counts->selectedLines = TSStatusBarSelectedLineCount(string, ranges);
        counts->selectedCharacters = selectedCharacters;
        counts->selectedWords = selectedWords;
        counts->location = offset;
        counts->line = TSStatusBarLineNumber(string, location);
        counts->column = TSStatusBarColumn(string, location);
    }
    return YES;
}
