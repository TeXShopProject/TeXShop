// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexFindReplacement.h"

@implementation TSRegexFindReplacement

- (instancetype)initWithRange:(NSRange)range string:(NSString *)string
{
    if ((self = [super init])) {
        _range = range;
        _string = [string copy];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:[TSRegexFindReplacement class]])
        return NO;
    TSRegexFindReplacement *other = object;
    return NSEqualRanges(other.range, self.range) && [other.string isEqualToString:self.string];
}

- (NSUInteger)hash
{
    return self.range.location ^ self.string.hash;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ -> %@", NSStringFromRange(self.range), self.string];
}

@end
