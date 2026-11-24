// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSStatusBarCounting.m
 */

#import "TSStatusBarCounting.h"
#import <unicode/uchar.h>

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

NSUInteger TSStatusBarCharacterEnd(NSString *string, NSUInteger location, NSUInteger end)
{
    end = MIN(end, string.length);
    if (location >= end)
        return location;
    unichar c = [string characterAtIndex:location];
    unichar next = location + 1 < end ? [string characterAtIndex:location + 1] : 0;
    if (c == '\r')
        return location + (next == '\n' ? 2 : 1);
    if (TSIsSimple(c) && (location + 1 >= end || TSIsSimple(next)))
        return location + 1;
    return MAX(location + 1, TSClusterEnd(string, location, end));
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

// The code point at `i` (a lone surrogate stands for itself) and the number of UTF-16 units it takes.
static inline UChar32 TSCodePointAt(CFStringInlineBuffer *buffer, NSUInteger i, NSUInteger end, NSUInteger *units)
{
    unichar c = CFStringGetCharacterFromInlineBuffer(buffer, (CFIndex)i);
    if (CFStringIsSurrogateHighCharacter(c) && i + 1 < end) {
        unichar d = CFStringGetCharacterFromInlineBuffer(buffer, (CFIndex)(i + 1));
        if (CFStringIsSurrogateLowCharacter(d)) {
            *units = 2;
            return (UChar32)CFStringGetLongCharacterForSurrogatePair(c, d);
        }
    }
    *units = 1;
    return c;
}

// A location in the middle of a surrogate pair, moved to the start of the pair. The word boundaries can fall
// there after a combining mark (́🏽): the word is taken from the start of the code point, as Swift takes it.
static inline NSUInteger TSScalarStart(CFStringInlineBuffer *buffer, NSUInteger i, NSUInteger length)
{
    if (i > 0 && i < length && CFStringIsSurrogateLowCharacter(CFStringGetCharacterFromInlineBuffer(buffer, (CFIndex)i))
        && CFStringIsSurrogateHighCharacter(CFStringGetCharacterFromInlineBuffer(buffer, (CFIndex)(i - 1))))
        return i - 1;
    return i;
}

// Characters that are drawn with the one before them or not at all: variation selectors, combining marks
// (Grapheme_Extend), format characters such as the zero width joiner and the other default ignorable code points.
static inline BOOL TSIsAttached(UChar32 c)
{
    if (c < 0xAD)
        return NO;  // none below SOFT HYPHEN
    return u_hasBinaryProperty(c, UCHAR_VARIATION_SELECTOR) || u_hasBinaryProperty(c, UCHAR_GRAPHEME_EXTEND)
        || u_hasBinaryProperty(c, UCHAR_DEFAULT_IGNORABLE_CODE_POINT) || u_charType(c) == U_FORMAT_CHAR;
}

// Whether the word boundaries made a word of attached characters alone, such as the variation selector after
// 葛 in 葛󠄀. Such a word belongs to the word before it, and is not a word of its own at the start either.
static BOOL TSIsAttachedOnly(CFStringInlineBuffer *buffer, NSRange word, NSUInteger length)
{
    NSUInteger end = TSScalarStart(buffer, NSMaxRange(word), length), units;
    for (NSUInteger i = TSScalarStart(buffer, word.location, length); i < end; i += units)
        if (!TSIsAttached(TSCodePointAt(buffer, i, end, &units)))
            return NO;
    return YES;
}

// Whether a grapheme cluster outside every word is shown as an emoji (Unicode Technical Standard #51):
// - not when U+FE0E asks for text presentation;
// - a flag or a lone regional indicator (Regional_Indicator);
// - a character shown as emoji by default (Emoji_Presentation), such as 😀, and the sequences that start with
//   one: skin tones and ZWJ sequences such as 🧑‍🧑‍🧒‍🧒;
// - an emoji character shown as text by default (Emoji) followed by U+FE0F, an emoji modifier or the keycap
//   U+20E3: ❤️, ☝🏽, #️⃣ (1️⃣ is already a word, as the number 1);
// - a pictographic code point that this version of Unicode has not assigned yet (Extended_Pictographic):
//   an emoji newer than the system, which shows emoji by default.
// © ™ ❤ and other symbols without U+FE0F are text, like § or ★, and are not words.
static BOOL TSIsEmojiCluster(CFStringInlineBuffer *buffer, NSUInteger start, NSUInteger end)
{
    NSUInteger units;
    UChar32 first = TSCodePointAt(buffer, start, end, &units);
    BOOL presentationSelector = NO, textSelector = NO, modifier = NO, keycap = NO;
    for (NSUInteger i = start + units; i < end; ) {
        NSUInteger n;
        UChar32 c = TSCodePointAt(buffer, i, end, &n);
        if (c == 0xFE0F) presentationSelector = YES;
        else if (c == 0xFE0E) textSelector = YES;
        else if (c == 0x20E3) keycap = YES;
        else if (u_hasBinaryProperty(c, UCHAR_EMOJI_MODIFIER)) modifier = YES;
        i += n;
    }
    if (textSelector)
        return NO;
    if (u_hasBinaryProperty(first, UCHAR_REGIONAL_INDICATOR) || u_hasBinaryProperty(first, UCHAR_EMOJI_PRESENTATION))
        return YES;
    if (u_hasBinaryProperty(first, UCHAR_EMOJI) && (presentationSelector || modifier || keycap))
        return YES;
    return u_hasBinaryProperty(first, UCHAR_EXTENDED_PICTOGRAPHIC) && u_charType(first) == U_UNASSIGNED;
}

// Whether a code point can start an emoji: a quick test before the grapheme cluster is looked for.
static inline BOOL TSMayStartEmoji(UChar32 c)
{
    if (c < 0x80)
        return c == '#' || c == '*' || (c >= '0' && c <= '9');  // the keycaps
    if (c < 0xA9 || (c >= 0x3000 && c <= 0x302F) || (c >= 0x3041 && c <= 0x30FF) || (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0xFF01 && c <= 0xFF5E))
        return NO;  // Latin-1 before ©, CJK punctuation, kana, ideographs and full-width forms hold no emoji
    return (u_hasBinaryProperty(c, UCHAR_EMOJI) || u_hasBinaryProperty(c, UCHAR_EXTENDED_PICTOGRAPHIC));
}

// The end of the grapheme cluster at `start` in a gap. Joiners and marks at the start of a gap, after a word, are
// a cluster of their own, as when the gap is taken by itself (Swift's Characters of the substring): ICU's \X
// would join a ZWJ there to the pictograph after it.
static NSUInteger TSGapClusterEnd(NSString *string, CFStringInlineBuffer *buffer, NSUInteger start, NSUInteger to)
{
    NSUInteger units, i = start;
    while (i < to) {
        UChar32 c = TSCodePointAt(buffer, i, to, &units);
        int32_t kind = u_getIntPropertyValue(c, UCHAR_GRAPHEME_CLUSTER_BREAK);
        if (kind != U_GCB_EXTEND && kind != U_GCB_ZWJ && kind != U_GCB_SPACING_MARK)
            break;
        i += units;
    }
    if (i > start)
        return i;
    return MIN(MAX(start + 1, TSClusterEnd(string, start, to)), to);
}

// The emoji among the characters [from, to), which lie outside every word. Sets `*stopped` when `cancel` stops it.
static NSUInteger TSEmojiCount(NSString *string, CFStringInlineBuffer *buffer, NSUInteger from, NSUInteger to,
                               TSStatusBarCancel cancel, BOOL *stopped)
{
    NSUInteger count = 0, units, check = from + TSCancelStride, boundary = from;
    for (NSUInteger i = from; i < to; ) {
        if (i >= check) {
            if (cancel && cancel()) {
                *stopped = YES;
                return count;
            }
            check = i + TSCancelStride;
        }
        UChar32 c = TSCodePointAt(buffer, i, to, &units);
        if (!TSMayStartEmoji(c)) {
            // A simple character before another ends a cluster: the search below starts there.
            if (units == 1 && c != '\r' && TSIsSimple((unichar)c) && i + 1 < to && TSIsSimple(CFStringGetCharacterFromInlineBuffer(buffer, (CFIndex)(i + 1))))
                boundary = i + 1;
            i += units;
            continue;
        }
        // The grapheme cluster that holds it, found from the last boundary known, as a mark or a prepended
        // character before it can make it part of a cluster that is not an emoji.
        NSUInteger start = boundary, after;
        while ((after = TSGapClusterEnd(string, buffer, start, to)) <= i)
            start = after;
        if (TSIsEmojiCluster(buffer, start, after))
            count++;
        boundary = i = after;
    }
    return count;
}

NSUInteger TSStatusBarWordCount(NSString *string, NSRange range, TSStatusBarCancel cancel)
{
    NSUInteger length = string.length;
    if (range.location >= length || range.length == 0)
        return 0;
    range.length = MIN(NSMaxRange(range), length) - range.location;
    // The words of the system's word boundaries, as CotEditor counts them, but a word of attached characters
    // alone is not one, and each emoji outside the words is one.
    __block CFStringInlineBuffer buffer;
    CFStringInitInlineBuffer((__bridge CFStringRef)string, &buffer, CFRangeMake(0, (CFIndex)length));
    __block NSUInteger count = 0, seen = 0, gap = range.location;
    __block BOOL stopped = NO;
    [string enumerateSubstringsInRange:range
                               options:NSStringEnumerationByWords | NSStringEnumerationLocalized | NSStringEnumerationSubstringNotRequired
                            usingBlock:^(NSString *word, NSRange wordRange, NSRange enclosingRange, BOOL *stop) {
        NSUInteger start = TSScalarStart(&buffer, wordRange.location, length);
        if (start > gap) {
            BOOL gapStopped = NO;
            count += TSEmojiCount(string, &buffer, gap, start, cancel, &gapStopped);
            if (gapStopped) {
                stopped = YES;
                *stop = YES;
                return;
            }
        }
        gap = MAX(gap, TSScalarStart(&buffer, NSMaxRange(wordRange), length));
        if (!TSIsAttachedOnly(&buffer, wordRange, length))
            count++;
        if ((++seen & 1023) == 0 && cancel && cancel()) {
            stopped = YES;
            *stop = YES;
        }
    }];
    if (!stopped && gap < NSMaxRange(range))
        count += TSEmojiCount(string, &buffer, gap, NSMaxRange(range), cancel, &stopped);
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

NSString *TSStatusBarFormattedNumber(NSUInteger value)
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
