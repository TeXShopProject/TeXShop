// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexTextFind.h"

@implementation TSRegexTextFind

- (nullable instancetype)initWithString:(NSString *)string
                                pattern:(TSRegexFindPattern *)pattern
                         selectedRanges:(NSArray<NSValue *> *)selectedRanges
                            inSelection:(BOOL)inSelection
                                  error:(NSError **)error
{
    NSParameterAssert(selectedRanges.count > 0);
    if (!(self = [super init]))
        return nil;
    NSMutableArray<NSValue *> *scope = [NSMutableArray array];
    if (inSelection) {
        for (NSValue *value in selectedRanges)
            if (value.rangeValue.length > 0)
                [scope addObject:value];
        if (scope.count == 0) {
            if (error)
                *error = [NSError errorWithDomain:TSRegexFindErrorDomain code:TSRegexFindErrorEmptySelection
                                         userInfo:@{NSLocalizedDescriptionKey: @"There is no selection to search in."}];
            return nil;
        }
        [scope sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
            NSUInteger x = a.rangeValue.location, y = b.rangeValue.location;
            return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
        }];
    } else {
        [scope addObject:[NSValue valueWithRange:NSMakeRange(0, string.length)]];
    }
    _string = [string copy];
    _pattern = pattern;
    _selectedRanges = [selectedRanges copy];
    _inSelection = inSelection;
    _scopeRanges = scope;
    return self;
}

- (nullable NSArray<NSValue *> *)matchRangesWithCancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
{
    NSMutableArray<NSValue *> *matches = [NSMutableArray array];
    for (NSValue *scope in self.scopeRanges) {
        [self.pattern enumerateMatchesInString:self.string range:scope.rangeValue cancellation:isCancelled usingBlock:^(NSRange matchRange, NSTextCheckingResult *result, BOOL *stop) {
            [matches addObject:[NSValue valueWithRange:matchRange]];
        }];
        if (isCancelled && isCancelled())
            return nil;
    }
    return matches;
}

- (void)enumerateMatchesWithCancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
                              usingBlock:(void (NS_NOESCAPE ^)(NSArray<NSValue *> *, BOOL *))block
{
    __block BOOL stopped = NO;
    for (NSValue *scope in self.scopeRanges) {
        [self.pattern enumerateMatchesInString:self.string range:scope.rangeValue cancellation:isCancelled usingBlock:^(NSRange matchRange, NSTextCheckingResult *result, BOOL *stop) {
            NSMutableArray<NSValue *> *ranges = [NSMutableArray arrayWithObject:[NSValue valueWithRange:matchRange]];
            for (NSUInteger k = 1; k < result.numberOfRanges; k++)
                [ranges addObject:[NSValue valueWithRange:[result rangeAtIndex:k]]];
            block(ranges, stop);
            stopped = *stop;
        }];
        if (stopped || (isCancelled && isCancelled()))
            return;
    }
}

- (NSRange)nextMatchInRanges:(NSArray<NSValue *> *)matches
                     forward:(BOOL)forward
          includingSelection:(BOOL)includingSelection
                       wraps:(BOOL)wraps
                     wrapped:(nullable BOOL *)wrapped
{
    if (wrapped)
        *wrapped = NO;
    if (matches.count == 0)
        return NSMakeRange(NSNotFound, 0);
    if (self.inSelection)
        return (forward ? matches.firstObject : matches.lastObject).rangeValue;
    NSRange selection = self.selectedRanges.firstObject.rangeValue;
    if (forward) {
        NSUInteger start = includingSelection ? selection.location : NSMaxRange(selection);
        for (NSValue *value in matches) {
            NSRange match = value.rangeValue;
            // An empty match at the caret is skipped, or the search would never move.
            if (match.location >= start && !(!includingSelection && NSEqualRanges(match, selection)))
                return match;
        }
    } else {
        NSUInteger start = includingSelection ? NSMaxRange(selection) : selection.location;
        for (NSValue *value in matches.reverseObjectEnumerator) {
            NSRange match = value.rangeValue;
            if (NSMaxRange(match) <= start && !NSEqualRanges(match, selection))
                return match;
        }
    }
    if (!wraps)
        return NSMakeRange(NSNotFound, 0);
    if (wrapped)
        *wrapped = YES;
    return (forward ? matches.firstObject : matches.lastObject).rangeValue;
}

- (nullable TSRegexFindReplacement *)replacementInSelectionWithTemplate:(TSRegexReplacementTemplate *)replacementTemplate
{
    NSRange selection = self.selectedRanges.firstObject.rangeValue;
    __block TSRegexFindReplacement *replacement = nil;
    [self.pattern enumerateMatchesInString:self.string range:selection cancellation:nil usingBlock:^(NSRange matchRange, NSTextCheckingResult *result, BOOL *stop) {
        NSString *text = [replacementTemplate replacementForMatchRange:matchRange result:result inString:self.string previousMatchEnd:selection.location];
        replacement = [[TSRegexFindReplacement alloc] initWithRange:matchRange string:text];
        *stop = YES;
    }];
    return replacement;
}

- (nullable TSRegexReplaceAllResult *)replaceAllWithTemplate:(TSRegexReplacementTemplate *)replacementTemplate
                                                cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
{
    NSString *string = self.string;
    NSMutableArray<TSRegexFindReplacement *> *replacements = [NSMutableArray array];
    NSMutableArray<NSValue *> *selectedRanges = [NSMutableArray array];
    NSUInteger total = 0;
    NSInteger offset = 0;
    for (NSValue *scopeValue in self.scopeRanges) {
        NSRange scope = scopeValue.rangeValue;
        // Build each scope's new text in order; replacing in place would move the rest at every match.
        NSMutableString *scopeText = [NSMutableString string];
        __block NSUInteger location = scope.location;
        __block NSUInteger count = 0;
        [self.pattern enumerateMatchesInString:string range:scope cancellation:isCancelled usingBlock:^(NSRange matchRange, NSTextCheckingResult *result, BOOL *stop) {
            [scopeText appendString:[string substringWithRange:NSMakeRange(location, matchRange.location - location)]];
            [scopeText appendString:[replacementTemplate replacementForMatchRange:matchRange result:result inString:string previousMatchEnd:location]];
            location = NSMaxRange(matchRange);
            count++;
        }];
        if (isCancelled && isCancelled())
            return nil;
        [scopeText appendString:[string substringWithRange:NSMakeRange(location, NSMaxRange(scope) - location)]];
        total += count;
        // Literal comparison catches changes between canonically equivalent texts.
        if (count > 0 && [scopeText compare:[string substringWithRange:scope] options:NSLiteralSearch] != NSOrderedSame)
            [replacements addObject:[[TSRegexFindReplacement alloc] initWithRange:scope string:scopeText]];
        if (self.inSelection) {
            [selectedRanges addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)((NSInteger)scope.location + offset), scopeText.length)]];
            offset += (NSInteger)scopeText.length - (NSInteger)scope.length;
        }
    }
    return [[TSRegexReplaceAllResult alloc] initWithReplacements:replacements
                                                  selectedRanges:self.inSelection ? selectedRanges : nil
                                                 numberOfMatches:total];
}

@end
