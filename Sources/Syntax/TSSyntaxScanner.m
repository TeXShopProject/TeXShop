// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSyntaxScanner.h"

@implementation TSSyntaxDiagnostic

- (instancetype)initWithRange:(NSRange)range role:(TSSyntaxRole)role message:(NSString *)message
{
    if ((self = [super init])) {
        _range = range;
        _role = role;
        _message = [message copy];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %ld %@", NSStringFromRange(self.range), (long)self.role, self.message];
}

@end
