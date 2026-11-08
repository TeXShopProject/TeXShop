// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Text matching only. Never use this transformation for stored key assignments.
static inline NSString *TSSettingsNormalizedText(NSString *text)
{
    NSString *value = text.precomposedStringWithCompatibilityMapping;
    value = [value stringByApplyingTransform:NSStringTransformHiraganaToKatakana reverse:NO] ?: value;
    value = value.decomposedStringWithCanonicalMapping;
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if (character >= 0x0300 && character <= 0x036f) continue;
        if ([NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:character]) continue;
        [result appendFormat:@"%C", character];
    }
    // Uppercase first also folds expanding pairs such as German ß / SS.
    return result.precomposedStringWithCanonicalMapping.uppercaseString.lowercaseString;
}
static inline NSArray<NSString *> *TSSettingsQueryTokens(NSString *query)
{
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in [query.precomposedStringWithCompatibilityMapping componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        NSString *token = TSSettingsNormalizedText(part);
        if (token.length) [tokens addObject:token];
    }
    return [tokens copy];
}
static inline BOOL TSSettingsTextMatches(NSString *text, NSArray<NSString *> *tokens)
{
    NSString *normalized = TSSettingsNormalizedText(text);
    for (NSString *token in tokens) if (![normalized containsString:token]) return NO;
    return YES;
}
NS_ASSUME_NONNULL_END
