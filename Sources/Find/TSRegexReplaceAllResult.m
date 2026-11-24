// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexReplaceAllResult.h"

@implementation TSRegexReplaceAllResult

- (instancetype)initWithReplacements:(NSArray<TSRegexFindReplacement *> *)replacements
                      selectedRanges:(nullable NSArray<NSValue *> *)selectedRanges
                     numberOfMatches:(NSUInteger)numberOfMatches
                          matchEdits:(NSData *)matchEdits
{
    if ((self = [super init])) {
        _replacements = [replacements copy];
        _selectedRanges = [selectedRanges copy];
        _numberOfMatches = numberOfMatches;
        _matchEdits = [matchEdits copy];
    }
    return self;
}

- (NSUInteger)locationByFollowingEdits:(NSUInteger)location
{
    NSUInteger count = self.matchEdits.length / sizeof(TSRegexMatchEdit);
    if (count == 0 || self.matchEdits.length != count * sizeof(TSRegexMatchEdit))
        return location;
    const TSRegexMatchEdit *edits = self.matchEdits.bytes;
    NSInteger shift = 0;
    for (NSUInteger i = 0; i < count; i++) {
        TSRegexMatchEdit edit = edits[i];
        NSUInteger end = edit.location + edit.length;
        if (location < edit.location)
            break;
        if (location >= end) {
            shift += edit.delta;
            continue;
        }
        // The length change of the matches before this one cannot exceed the text before it.
        if (location == edit.location && edit.length > 0)
            return (NSUInteger)((NSInteger)location + shift);
        NSInteger atEnd = (NSInteger)end + shift + edit.delta;
        return atEnd > 0 ? (NSUInteger)atEnd : 0;
    }
    NSInteger moved = (NSInteger)location + shift;
    return moved > 0 ? (NSUInteger)moved : 0;
}

@end
