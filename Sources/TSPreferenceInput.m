// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSPreferenceInput.h"
#import <math.h>
@implementation TSPreferenceInput
- (instancetype)initWithKey:(TSPreferenceKey)key kind:(TSPreferenceInputKind)kind
                    minimum:(double)minimum maximum:(double)maximum allowsEmpty:(BOOL)allowsEmpty
               notification:(nullable NSNotificationName)notification
{
    self = [super init];
    if (self == nil) return nil;
    _key = [key copy]; _kind = kind; _minimum = minimum; _maximum = maximum;
    _allowsEmpty = allowsEmpty; _notification = [notification copy];
    return self;
}
- (nullable id)validatedValue:(NSString *)text
{
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (self.kind == TSPreferenceInputText) {
        if (!self.allowsEmpty && trimmed.length == 0) return nil;
        if ([trimmed rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
        return trimmed;
    }
    if (trimmed.length == 0) return nil;
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    scanner.locale = NSLocale.currentLocale;
    double number;
    if (![scanner scanDouble:&number] || !scanner.isAtEnd || !isfinite(number)) return nil;
    number = MIN(self.maximum, MAX(self.minimum, number));
    if (self.kind == TSPreferenceInputInteger) return @((NSInteger)number);
    return @(number / 100.0);
}
- (NSString *)displayStringForValue:(id)value
{
    if (self.kind == TSPreferenceInputText) return [value isKindOfClass:NSString.class] ? value : @"";
    if (![value isKindOfClass:NSNumber.class]) return @"";
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.usesGroupingSeparator = NO;
    formatter.maximumFractionDigits = 6;
    NSNumber *number = self.kind == TSPreferenceInputPercentage ? @([value doubleValue] * 100) : value;
    return [formatter stringFromNumber:number] ?: @"";
}
@end
