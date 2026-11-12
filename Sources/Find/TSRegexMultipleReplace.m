// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexMultipleReplace.h"
#import "TSRegexTextFind.h"

@implementation TSRegexMultipleReplaceResult

- (instancetype)initWithString:(NSString *)string selectedRanges:(nullable NSArray<NSValue *> *)selectedRanges
                        counts:(NSArray<NSNumber *> *)counts errors:(NSDictionary<NSNumber *, NSError *> *)errors
{
    if ((self = [super init])) {
        _string = [string copy];
        _selectedRanges = [selectedRanges copy];
        _counts = [counts copy];
        _errors = [errors copy];
    }
    return self;
}

- (NSUInteger)totalCount
{
    NSUInteger total = 0;
    for (NSNumber *count in self.counts)
        total += count.unsignedIntegerValue;
    return total;
}

@end

@implementation TSRegexMultipleReplace

+ (nullable TSRegexMultipleReplaceResult *)applyRules:(NSArray<TSRegexReplacementRule *> *)rules
                                             toString:(NSString *)string
                                       selectedRanges:(NSArray<NSValue *> *)selectedRanges
                                          inSelection:(BOOL)inSelection
                                        sharedOptions:(TSRegexFindOptions)sharedOptions
                                         cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
{
    NSString *current = [string copy];
    NSArray<NSValue *> *scope = selectedRanges;
    NSMutableArray<NSNumber *> *counts = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSError *> *errors = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < rules.count; index++) {
        TSRegexReplacementRule *rule = rules[index];
        [counts addObject:@0];
        if (!rule.enabled)
            continue;
        NSError *error = nil;
        TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:rule.findString options:rule.options | sharedOptions error:&error];
        TSRegexTextFind *find = pattern ? [[TSRegexTextFind alloc] initWithString:current pattern:pattern selectedRanges:scope inSelection:inSelection error:&error] : nil;
        if (!find) {
            errors[@(index)] = error;
            continue;
        }
        TSRegexReplacementTemplate *template = [[TSRegexReplacementTemplate alloc] initWithString:rule.replaceString pattern:pattern syntax:rule.replacementSyntax];
        TSRegexReplaceAllResult *result = [find replaceAllWithTemplate:template cancellation:isCancelled];
        if (!result)
            return nil;
        counts[index] = @(result.numberOfMatches);
        if (result.replacements.count > 0) {
            NSMutableString *next = [current mutableCopy];
            for (TSRegexFindReplacement *replacement in result.replacements.reverseObjectEnumerator)
                [next replaceCharactersInRange:replacement.range withString:replacement.string];
            current = next;
        }
        if (inSelection && result.selectedRanges)
            scope = result.selectedRanges;
    }
    return [[TSRegexMultipleReplaceResult alloc] initWithString:current selectedRanges:inSelection ? scope : nil counts:counts errors:errors];
}

@end
