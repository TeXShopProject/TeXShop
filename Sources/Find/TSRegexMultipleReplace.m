// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexMultipleReplace.h"
#import "TSRegexTextFind.h"

// The keys of a CotEditor replacement definition.
static NSString *const TSDefinitionRulesKey = @"replacements";
static NSString *const TSDefinitionSettingsKey = @"settings";
static NSString *const TSSettingsTextualKey = @"textualOptions";
static NSString *const TSSettingsRegexKey = @"regexOptions";
static NSString *const TSSettingsWholeWordKey = @"matchesFullWord";
static NSString *const TSSettingsUnescapesKey = @"unescapesReplacementString";
// TeXShop's own keys; CotEditor ignores them.
static NSString *const TSSettingsSyntaxKey = @"texshopReplacementSyntax";
static NSString *const TSSettingsYenKey = @"texshopYenIsBackslash";
static NSString *const TSSettingsEmptyKey = @"texshopIgnoresEmptyMatches";
static NSString *const TSSettingsWordsKey = @"texshopDelimitsByWhitespace";
static NSString *const TSSyntaxOgreKitValue = @"OgreKit";
static NSString *const TSSyntaxICUValue = @"ICU";

static const TSRegexFindOptions TSTextualOptionsMask = TSRegexFindIgnoreCase | TSRegexFindLiteral | TSRegexFindIgnoreDiacritics
    | TSRegexFindIgnoreWidth | TSRegexFindWholeWord | TSRegexFindDelimitByWhitespace | TSRegexFindYenIsBackslash;
static const TSRegexFindOptions TSRegexOptionsMask = TSRegexFindIgnoreCase | TSRegexFindDotMatchesLineSeparators
    | TSRegexFindAnchorsMatchLines | TSRegexFindAllowCommentsAndWhitespace | TSRegexFindUnicodeWordBoundaries
    | TSRegexFindUnescapesReplacement | TSRegexFindIgnoreEmptyMatches | TSRegexFindYenIsBackslash;

static BOOL TSIsBooleanValue(id value)
{
    return value && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

/// A non-negative integer that is not a boolean, as a Swift UInt.
static BOOL TSIsUnsignedValue(id value)
{
    if (![value isKindOfClass:[NSNumber class]] || TSIsBooleanValue(value))
        return NO;
    NSNumber *number = value;
    return number.doubleValue >= 0 && number.doubleValue == floor(number.doubleValue) && number.doubleValue <= (double)NSUIntegerMax;
}

static NSError *TSDefinitionError(NSString *description)
{
    return [NSError errorWithDomain:TSRegexFindErrorDomain code:TSRegexFindErrorInvalidDefinition
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

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

+ (TSRegexFindOptions)defaultTextualOptions
{
    return TSRegexFindYenIsBackslash;
}

+ (TSRegexFindOptions)defaultRegularExpressionOptions
{
    return TSRegexFindAnchorsMatchLines | TSRegexFindUnescapesReplacement | TSRegexFindYenIsBackslash;
}

- (instancetype)initWithRules:(NSArray<TSRegexReplacementRule *> *)rules
               textualOptions:(TSRegexFindOptions)textualOptions
     regularExpressionOptions:(TSRegexFindOptions)regularExpressionOptions
            replacementSyntax:(TSRegexReplacementSyntax)replacementSyntax
{
    if ((self = [super init])) {
        _rules = [rules copy];
        // The yen sign is one setting of the whole set.
        TSRegexFindOptions yen = (textualOptions | regularExpressionOptions) & TSRegexFindYenIsBackslash;
        _textualOptions = (textualOptions & TSTextualOptionsMask) | yen;
        _regularExpressionOptions = (regularExpressionOptions & TSRegexOptionsMask) | yen;
        _replacementSyntax = replacementSyntax == TSRegexReplacementSyntaxOgreKit ? TSRegexReplacementSyntaxOgreKit : TSRegexReplacementSyntaxICU;
    }
    return self;
}

- (nullable instancetype)initWithJSONData:(NSData *)data error:(NSError **)error
{
    NSError *parseError = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    NSDictionary *settings = [root isKindOfClass:[NSDictionary class]] ? root[TSDefinitionSettingsKey] : nil;
    NSArray *objects = [root isKindOfClass:[NSDictionary class]] ? root[TSDefinitionRulesKey] : nil;
    if (![settings isKindOfClass:[NSDictionary class]] || ![objects isKindOfClass:[NSArray class]]) {
        if (error)
            *error = parseError ?: TSDefinitionError(@"The replacement definition has no replacements or settings.");
        return nil;
    }
    NSMutableArray<TSRegexReplacementRule *> *rules = [NSMutableArray array];
    for (id object in objects) {
        TSRegexReplacementRule *rule = [[TSRegexReplacementRule alloc] initWithJSONObject:object];
        if (!rule) {
            if (error)
                *error = TSDefinitionError(@"A replacement of the definition is not valid.");
            return nil;
        }
        [rules addObject:rule];
    }
    id textual = settings[TSSettingsTextualKey], regex = settings[TSSettingsRegexKey];
    id wholeWord = settings[TSSettingsWholeWordKey], unescapes = settings[TSSettingsUnescapesKey];
    id syntax = settings[TSSettingsSyntaxKey];
    id yen = settings[TSSettingsYenKey], empty = settings[TSSettingsEmptyKey], words = settings[TSSettingsWordsKey];
    if (wholeWord == (id)kCFNull) wholeWord = nil;
    if (unescapes == (id)kCFNull) unescapes = nil;
    if (!TSIsUnsignedValue(textual) || !TSIsUnsignedValue(regex)
        || (wholeWord && !TSIsBooleanValue(wholeWord)) || (unescapes && !TSIsBooleanValue(unescapes))) {
        if (error)
            *error = TSDefinitionError(@"The settings of the replacement definition are not valid.");
        return nil;
    }
    NSStringCompareOptions compare = [textual unsignedIntegerValue];
    NSRegularExpressionOptions regexOptions = [regex unsignedIntegerValue];
    TSRegexFindOptions textualOptions = 0, regularExpressionOptions = 0;
    if (compare & NSCaseInsensitiveSearch) textualOptions |= TSRegexFindIgnoreCase;
    if (compare & NSLiteralSearch) textualOptions |= TSRegexFindLiteral;
    if (compare & NSDiacriticInsensitiveSearch) textualOptions |= TSRegexFindIgnoreDiacritics;
    if (compare & NSWidthInsensitiveSearch) textualOptions |= TSRegexFindIgnoreWidth;
    if ([wholeWord boolValue]) textualOptions |= TSRegexFindWholeWord;
    if (regexOptions & NSRegularExpressionCaseInsensitive) regularExpressionOptions |= TSRegexFindIgnoreCase;
    if (regexOptions & NSRegularExpressionAllowCommentsAndWhitespace) regularExpressionOptions |= TSRegexFindAllowCommentsAndWhitespace;
    if (regexOptions & NSRegularExpressionDotMatchesLineSeparators) regularExpressionOptions |= TSRegexFindDotMatchesLineSeparators;
    if (regexOptions & NSRegularExpressionAnchorsMatchLines) regularExpressionOptions |= TSRegexFindAnchorsMatchLines;
    if (regexOptions & NSRegularExpressionUseUnicodeWordBoundaries) regularExpressionOptions |= TSRegexFindUnicodeWordBoundaries;
    // CotEditor reads a missing value as NO, though a new set unescapes.
    if ([unescapes boolValue]) regularExpressionOptions |= TSRegexFindUnescapesReplacement;
    // TeXShop's own keys: anything but true is NO, so that CotEditor's files mean what they mean in CotEditor.
    if (TSIsBooleanValue(yen) && [yen boolValue]) textualOptions |= TSRegexFindYenIsBackslash;
    if (TSIsBooleanValue(empty) && [empty boolValue]) regularExpressionOptions |= TSRegexFindIgnoreEmptyMatches;
    if (TSIsBooleanValue(words) && [words boolValue]) textualOptions |= TSRegexFindDelimitByWhitespace;
    TSRegexReplacementSyntax replacementSyntax = [syntax isEqual:TSSyntaxOgreKitValue] ? TSRegexReplacementSyntaxOgreKit : TSRegexReplacementSyntaxICU;
    return [self initWithRules:rules textualOptions:textualOptions regularExpressionOptions:regularExpressionOptions replacementSyntax:replacementSyntax];
}

- (instancetype)initWithTabSeparatedText:(NSString *)text
{
    static NSRegularExpression *lines;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Swift's Character.isNewline.
        lines = [NSRegularExpression regularExpressionWithPattern:@"\\r\\n|[\\n\\u000B\\u000C\\r\\u0085\\u2028\\u2029]" options:0 error:NULL];
    });
    NSMutableArray<TSRegexReplacementRule *> *rules = [NSMutableArray array];
    __block NSUInteger start = 0;
    void (^addLine)(NSRange) = ^(NSRange range) {
        if (range.length == 0)
            return;
        NSArray<NSString *> *items = [[text substringWithRange:range] componentsSeparatedByString:@"\t"];
        if (items.count < 2 || items[0].length == 0)
            return;
        [rules addObject:[[TSRegexReplacementRule alloc] initWithFindString:items[0] replaceString:items[1]
                                                     usesRegularExpression:NO ignoresCase:NO enabled:YES note:nil]];
    };
    [lines enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        addLine(NSMakeRange(start, result.range.location - start));
        start = NSMaxRange(result.range);
    }];
    addLine(NSMakeRange(start, text.length - start));
    return [self initWithRules:rules textualOptions:0 regularExpressionOptions:TSRegexFindAnchorsMatchLines | TSRegexFindUnescapesReplacement
             replacementSyntax:TSRegexReplacementSyntaxICU];
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:[TSRegexMultipleReplace class]])
        return NO;
    TSRegexMultipleReplace *other = object;
    return [other.rules isEqualToArray:self.rules] && other.textualOptions == self.textualOptions
        && other.regularExpressionOptions == self.regularExpressionOptions && other.replacementSyntax == self.replacementSyntax;
}

- (NSUInteger)hash
{
    return self.rules.count ^ self.textualOptions ^ (self.regularExpressionOptions << 8);
}

- (NSData *)JSONData
{
    TSRegexFindOptions textual = self.textualOptions, regex = self.regularExpressionOptions;
    NSStringCompareOptions compare = 0;
    if (textual & TSRegexFindIgnoreCase) compare |= NSCaseInsensitiveSearch;
    if (textual & TSRegexFindLiteral) compare |= NSLiteralSearch;
    if (textual & TSRegexFindIgnoreDiacritics) compare |= NSDiacriticInsensitiveSearch;
    if (textual & TSRegexFindIgnoreWidth) compare |= NSWidthInsensitiveSearch;
    NSRegularExpressionOptions regexOptions = 0;
    if (regex & TSRegexFindIgnoreCase) regexOptions |= NSRegularExpressionCaseInsensitive;
    if (regex & TSRegexFindAllowCommentsAndWhitespace) regexOptions |= NSRegularExpressionAllowCommentsAndWhitespace;
    if (regex & TSRegexFindDotMatchesLineSeparators) regexOptions |= NSRegularExpressionDotMatchesLineSeparators;
    if (regex & TSRegexFindAnchorsMatchLines) regexOptions |= NSRegularExpressionAnchorsMatchLines;
    if (regex & TSRegexFindUnicodeWordBoundaries) regexOptions |= NSRegularExpressionUseUnicodeWordBoundaries;
    NSMutableDictionary<NSString *, id> *settings = [@{
        TSSettingsTextualKey: @(compare),
        TSSettingsRegexKey: @(regexOptions),
        TSSettingsWholeWordKey: (textual & TSRegexFindWholeWord) ? @YES : @NO,
        TSSettingsUnescapesKey: (regex & TSRegexFindUnescapesReplacement) ? @YES : @NO,
    } mutableCopy];
    if (self.replacementSyntax == TSRegexReplacementSyntaxOgreKit)
        settings[TSSettingsSyntaxKey] = TSSyntaxOgreKitValue;
    if (textual & TSRegexFindYenIsBackslash)
        settings[TSSettingsYenKey] = @YES;
    if (regex & TSRegexFindIgnoreEmptyMatches)
        settings[TSSettingsEmptyKey] = @YES;
    if (textual & TSRegexFindDelimitByWhitespace)
        settings[TSSettingsWordsKey] = @YES;
    NSMutableArray *objects = [NSMutableArray array];
    for (TSRegexReplacementRule *rule in self.rules)
        [objects addObject:rule.JSONObject];
    // Strings, numbers and booleans in dictionaries and arrays always serialize.
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{TSDefinitionRulesKey: objects, TSDefinitionSettingsKey: settings}
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:NULL];
    return data ?: [NSData data];
}

- (TSRegexFindOptions)optionsForRule:(TSRegexReplacementRule *)rule
{
    TSRegexFindOptions options = rule.usesRegularExpression ? self.regularExpressionOptions | TSRegexFindRegularExpression : self.textualOptions;
    return rule.ignoresCase ? options | TSRegexFindIgnoreCase : options;
}

- (nullable TSRegexTextFind *)textFindForRule:(TSRegexReplacementRule *)rule string:(NSString *)string
                               selectedRanges:(NSArray<NSValue *> *)selectedRanges inSelection:(BOOL)inSelection
                                   lineEnding:(nullable NSString *)lineEnding error:(NSError **)error
{
    NSString *findString = lineEnding ? TSRegexStringByReplacingLineEndings(rule.findString, (NSString *_Nonnull)lineEnding) : rule.findString;
    TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:findString options:[self optionsForRule:rule] error:error];
    if (!pattern)
        return nil;
    return [[TSRegexTextFind alloc] initWithString:string pattern:pattern lineEnding:lineEnding
                                    selectedRanges:selectedRanges inSelection:inSelection error:error];
}

- (nullable TSRegexMultipleReplaceResult *)applyToString:(NSString *)string
                                          selectedRanges:(NSArray<NSValue *> *)selectedRanges
                                             inSelection:(BOOL)inSelection
                                              lineEnding:(nullable NSString *)lineEnding
                                            cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
{
    NSString *current = [string copy];
    NSArray<NSValue *> *scope = selectedRanges;
    NSMutableArray<NSNumber *> *counts = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSError *> *errors = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < self.rules.count; index++) {
        TSRegexReplacementRule *rule = self.rules[index];
        [counts addObject:@0];
        if (!rule.enabled)
            continue;
        NSError *error = nil;
        TSRegexTextFind *find = [self textFindForRule:rule string:current selectedRanges:scope inSelection:inSelection lineEnding:lineEnding error:&error];
        if (!find) {
            errors[@(index)] = error;
            continue;
        }
        TSRegexReplacementTemplate *template = [[TSRegexReplacementTemplate alloc] initWithString:rule.replaceString pattern:find.pattern syntax:self.replacementSyntax];
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

- (nullable NSArray<NSValue *> *)matchRangesInString:(NSString *)string
                                      selectedRanges:(NSArray<NSValue *> *)selectedRanges
                                         inSelection:(BOOL)inSelection
                                          lineEnding:(nullable NSString *)lineEnding
                                        cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
{
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    for (TSRegexReplacementRule *rule in self.rules) {
        if (!rule.enabled)
            continue;
        TSRegexTextFind *find = [self textFindForRule:rule string:string selectedRanges:selectedRanges inSelection:inSelection lineEnding:lineEnding error:NULL];
        if (!find)
            continue;
        NSArray<NSValue *> *matches = [find matchRangesWithCancellation:isCancelled];
        if (!matches)
            return nil;
        [ranges addObjectsFromArray:matches];
    }
    return ranges;
}

@end
