// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexReplaceAllResult.h"

@implementation TSRegexReplaceAllResult

- (instancetype)initWithReplacements:(NSArray<TSRegexFindReplacement *> *)replacements
                      selectedRanges:(nullable NSArray<NSValue *> *)selectedRanges
                     numberOfMatches:(NSUInteger)numberOfMatches
{
    if ((self = [super init])) {
        _replacements = [replacements copy];
        _selectedRanges = [selectedRanges copy];
        _numberOfMatches = numberOfMatches;
    }
    return self;
}

@end
