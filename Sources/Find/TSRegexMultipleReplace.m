// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexMultipleReplace.h"
#import "TSRegexTextFind.h"
#include <xlocale.h>

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
    | TSRegexFindIgnoreMetacharacters | TSRegexFindUseUnixLineSeparators
    | TSRegexFindUnescapesReplacement | TSRegexFindIgnoreEmptyMatches | TSRegexFindYenIsBackslash;

static BOOL TSIsBooleanValue(id value)
{
    return value && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

#pragma mark - Numbers read as Swift reads them

// CotEditor reads its options with Swift's JSONDecoder, which reads a number from its text, and only when it decodes it.
// NSJSONSerialization keeps only a double for most fractions, and refuses some numbers that Swift reads, such as
// `1e00000`. So NSJSONSerialization is given every number as `0`, and the two option numbers are read from their text.

typedef struct {
    NSStringEncoding encoding;
    NSUInteger width;       // Bytes in a code unit.
    BOOL bigEndian;
} TSJSONEncoding;

/// The encoding of JSON data, as NSJSONSerialization detects it.
static TSJSONEncoding TSJSONEncodingOfData(NSData *data)
{
    const uint8_t *b = data.bytes;
    NSUInteger n = data.length;
    if (n >= 4 && b[0] == 0 && b[1] == 0 && b[2] == 0xFE && b[3] == 0xFF)
        return (TSJSONEncoding){NSUTF32StringEncoding, 4, YES};
    if (n >= 4 && b[0] == 0xFF && b[1] == 0xFE && b[2] == 0 && b[3] == 0)
        return (TSJSONEncoding){NSUTF32StringEncoding, 4, NO};
    if (n >= 2 && b[0] == 0xFE && b[1] == 0xFF)
        return (TSJSONEncoding){NSUTF16StringEncoding, 2, YES};
    if (n >= 2 && b[0] == 0xFF && b[1] == 0xFE)
        return (TSJSONEncoding){NSUTF16StringEncoding, 2, NO};
    if (n >= 4 && b[0] == 0 && b[1] == 0 && b[2] == 0)
        return (TSJSONEncoding){NSUTF32BigEndianStringEncoding, 4, YES};
    if (n >= 4 && b[1] == 0 && b[2] == 0 && b[3] == 0)
        return (TSJSONEncoding){NSUTF32LittleEndianStringEncoding, 4, NO};
    if (n >= 2 && b[0] == 0)
        return (TSJSONEncoding){NSUTF16BigEndianStringEncoding, 2, YES};
    if (n >= 2 && b[1] == 0)
        return (TSJSONEncoding){NSUTF16LittleEndianStringEncoding, 2, NO};
    return (TSJSONEncoding){NSUTF8StringEncoding, 1, NO};
}

/// The text of JSON data, in the encoding NSJSONSerialization detects.
static NSString *_Nullable TSJSONText(NSData *data)
{
    NSString *text = [[NSString alloc] initWithData:data encoding:TSJSONEncodingOfData(data).encoding];
    if ([text hasPrefix:@"﻿"])
        text = [text substringFromIndex:1];
    return text;
}

static uint32_t TSJSONUnit(const uint8_t *bytes, NSUInteger index, TSJSONEncoding encoding)
{
    const uint8_t *unit = bytes + index * encoding.width;
    uint32_t value = 0;
    for (NSUInteger i = 0; i < encoding.width; i++)
        value |= (uint32_t)unit[encoding.bigEndian ? i : encoding.width - 1 - i] << (8 * (encoding.width - 1 - i));
    return value;
}

static void TSJSONSetUnit(uint8_t *bytes, NSUInteger index, TSJSONEncoding encoding, uint8_t character)
{
    uint8_t *unit = bytes + index * encoding.width;
    memset(unit, 0, encoding.width);
    unit[encoding.bigEndian ? encoding.width - 1 : 0] = character;
}

static BOOL TSIsJSONNumberCharacter(uint32_t c)
{
    return (c >= '0' && c <= '9') || c == '.' || c == '+' || c == '-' || c == 'e' || c == 'E';
}

/// JSON data in which every number is `0` followed by spaces, so that NSJSONSerialization accepts the numbers that
/// Swift's JSONDecoder accepts. Until it decodes a number, Swift takes as one any run of digits, `.`, `+`, `-`, `e` and
/// `E` that begins with a digit or `-`; anything else in the data stays as it is, in its own encoding.
static NSData *TSJSONDataWithPlainNumbers(NSData *data)
{
    TSJSONEncoding encoding = TSJSONEncodingOfData(data);
    NSMutableData *plain = [data mutableCopy];
    uint8_t *bytes = plain.mutableBytes;
    NSUInteger count = plain.length / encoding.width;
    BOOL inString = NO;
    for (NSUInteger i = 0; i < count; i++) {
        uint32_t c = TSJSONUnit(bytes, i, encoding);
        if (inString) {
            if (c == '\\')
                i++;
            else if (c == '"')
                inString = NO;
        } else if (c == '"') {
            inString = YES;
        } else if (c == '-' || (c >= '0' && c <= '9')) {
            TSJSONSetUnit(bytes, i, encoding, '0');
            while (i + 1 < count && TSIsJSONNumberCharacter(TSJSONUnit(bytes, i + 1, encoding)))
                TSJSONSetUnit(bytes, ++i, encoding, ' ');
        }
    }
    return plain;
}

typedef struct {
    CFStringInlineBuffer buffer;
    CFIndex length, index;
} TSJSONScanner;

static UniChar TSJSONPeek(TSJSONScanner *scanner)
{
    return scanner->index < scanner->length ? CFStringGetCharacterFromInlineBuffer(&scanner->buffer, scanner->index) : 0;
}

static void TSJSONSkipSpace(TSJSONScanner *scanner)
{
    for (UniChar c = TSJSONPeek(scanner); c == ' ' || c == '\t' || c == '\n' || c == '\r'; c = TSJSONPeek(scanner))
        scanner->index++;
}

/// Moves past the value at the scanner, which NSJSONSerialization has already found valid.
static BOOL TSJSONSkipValue(TSJSONScanner *scanner)
{
    NSInteger depth = 0;
    BOOL inString = NO;
    while (scanner->index < scanner->length) {
        UniChar c = TSJSONPeek(scanner);
        if (inString) {
            scanner->index += (c == '\\') ? 2 : 1;
            if (c == '"') {
                inString = NO;
                if (depth == 0)
                    return YES;
            }
            continue;
        }
        if (c == '"') {
            inString = YES;
        } else if (c == '{' || c == '[') {
            depth++;
        } else if (c == '}' || c == ']') {
            if (depth == 0)
                return YES;     // The end of a number or a literal that closes its container.
            if (--depth == 0) {
                scanner->index++;
                return YES;
            }
        } else if (depth == 0 && (c == ',' || c == ' ' || c == '\t' || c == '\n' || c == '\r')) {
            return YES;
        }
        scanner->index++;
    }
    return depth == 0 && !inString;
}

/// The range of the first value of each member of the object at the scanner, by key: NSJSONSerialization and Swift's
/// JSONDecoder both use the first of duplicate keys.
static NSDictionary<NSString *, NSValue *> *_Nullable TSJSONMemberRanges(TSJSONScanner *scanner, NSString *text)
{
    TSJSONSkipSpace(scanner);
    if (TSJSONPeek(scanner) != '{')
        return nil;
    scanner->index++;
    NSMutableDictionary<NSString *, NSValue *> *members = [NSMutableDictionary dictionary];
    for (;;) {
        TSJSONSkipSpace(scanner);
        if (TSJSONPeek(scanner) == '}')
            return members;
        CFIndex keyStart = scanner->index;
        if (TSJSONPeek(scanner) != '"' || !TSJSONSkipValue(scanner))
            return nil;
        NSString *keyText = [text substringWithRange:NSMakeRange((NSUInteger)keyStart, (NSUInteger)(scanner->index - keyStart))];
        id key = [keyText rangeOfString:@"\\"].location == NSNotFound
            ? [keyText substringWithRange:NSMakeRange(1, keyText.length - 2)]
            : [NSJSONSerialization JSONObjectWithData:[keyText dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]
                                              options:NSJSONReadingFragmentsAllowed error:NULL];
        TSJSONSkipSpace(scanner);
        if (![key isKindOfClass:[NSString class]] || TSJSONPeek(scanner) != ':')
            return nil;
        scanner->index++;
        TSJSONSkipSpace(scanner);
        CFIndex valueStart = scanner->index;
        if (!TSJSONSkipValue(scanner))
            return nil;
        if (!members[key])
            members[key] = [NSValue valueWithRange:NSMakeRange((NSUInteger)valueStart, (NSUInteger)(scanner->index - valueStart))];
        TSJSONSkipSpace(scanner);
        if (TSJSONPeek(scanner) == ',')
            scanner->index++;
    }
}

/// The texts of the values of the settings object, by key.
static NSDictionary<NSString *, NSString *> *TSSettingsTexts(NSData *data)
{
    NSString *text = TSJSONText(data);
    if (!text)
        return @{};
    TSJSONScanner scanner = {.length = (CFIndex)text.length, .index = 0};
    CFStringInitInlineBuffer((__bridge CFStringRef)text, &scanner.buffer, CFRangeMake(0, scanner.length));
    NSValue *settingsRange = TSJSONMemberRanges(&scanner, text)[TSDefinitionSettingsKey];
    if (!settingsRange)
        return @{};
    scanner.index = (CFIndex)settingsRange.rangeValue.location;
    NSMutableDictionary<NSString *, NSString *> *texts = [NSMutableDictionary dictionary];
    [TSJSONMemberRanges(&scanner, text) enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSValue *range, BOOL *stop) {
        texts[key] = [text substringWithRange:range.rangeValue];
    }];
    return texts;
}

/// A decimal number as Foundation's Decimal reads its text: up to 128 bits of digits and an exponent from -128 to
/// 127, without trailing zeros. NO when Decimal refuses the text, or does not read all of it.
static BOOL TSDecimalOfNumberText(const char *s, BOOL *negative, unsigned __int128 *mantissa, int *exponent)
{
    const unsigned __int128 max = ~(unsigned __int128)0;
    unsigned __int128 m = 0;
    int e = 0;
    BOOL tooBig = NO;
    *negative = (*s == '-');
    if (*s == '-' || *s == '+')
        s++;
    for (; *s >= '0' && *s <= '9'; s++) {
        unsigned digit = (unsigned)(*s - '0');
        if (!tooBig && m <= (max - digit) / 10) {
            m = m * 10 + digit;
            continue;
        }
        // Digits that do not fit only raise the exponent.
        tooBig = YES;
        if (e == 127)
            return NO;
        e++;
    }
    if (*s == '.') {
        for (s++; *s >= '0' && *s <= '9'; s++) {
            unsigned digit = (unsigned)(*s - '0');
            if (tooBig)
                continue;
            if (m > (max - digit) / 10) {
                tooBig = YES;
                continue;
            }
            m = m * 10 + digit;
            if (e == -128)
                return NO;
            e--;
        }
    }
    if (*s == 'e' || *s == 'E') {
        s++;
        BOOL negativeExponent = (*s == '-');
        if (*s == '-' || *s == '+')
            s++;
        int value = 0;
        for (; *s >= '0' && *s <= '9'; s++) {
            value = value * 10 + (*s - '0');
            if (value > 254)
                return NO;
        }
        value = (negativeExponent ? -value : value) + e;
        if (value > 127 || value < -128)
            return NO;
        e = value;
    }
    if (*s)
        return NO;
    if (m != 0) {
        BOOL changed = NO;
        while (m % 10 == 0) {
            m /= 10;
            e++;
            changed = YES;
        }
        while (changed && e > 127) {
            m *= 10;
            e--;
        }
    }
    *mantissa = m;
    *exponent = e;
    return YES;
}

/// Whether the text of a number passes the first checks of Swift's JSONDecoder: it begins with a digit, or `-` and a
/// digit; a leading 0 is followed by nothing, `.`, `e` or `E`; the first `e` or `E` follows a digit; it ends with a
/// digit.
static BOOL TSJSONNumberTextIsPlausible(const char *s)
{
    const char *digits = (*s == '-') ? s + 1 : s;
    if (!(*digits >= '0' && *digits <= '9'))
        return NO;
    if (*digits == '0' && digits[1] && digits[1] != '.' && digits[1] != 'e' && digits[1] != 'E')
        return NO;
    const char *e = strpbrk(digits + 1, "eE");
    if (e && !(e[-1] >= '0' && e[-1] <= '9'))
        return NO;
    char last = s[strlen(s) - 1];
    return last >= '0' && last <= '9';
}

/// Reads the text of a JSON number as the JSONDecoder of macOS reads a UInt:
/// - an integer is read exactly, from 0 to UInt64.max;
/// - anything else is read as a double, which must be a whole number below 2^64; below 2^53 that double is the value;
/// - from 2^53, or when the double is not all of the text, the text is read as a Decimal, whose digits must fit in
///   64 bits; the fraction is cut off.
/// So `1.0` is 1, `1.5`, `-1` and `01` are refused, `9007199254740993.9` is 9007199254740993, and
/// `9223372036854775807.9` is refused.
static BOOL TSUnsignedValueOfNumberText(NSString *text, uint64_t *result)
{
    const char *s = text.UTF8String;
    if (!s || !TSJSONNumberTextIsPlausible(s))
        return NO;
    if (strpbrk(s, ".eE") == NULL && *s != '-') {
        uint64_t value = 0;
        BOOL fits = YES;
        for (const char *p = s; *p && fits; p++) {
            if (*p < '0' || *p > '9')
                return NO;
            fits = !__builtin_mul_overflow(value, 10, &value) && !__builtin_add_overflow(value, (uint64_t)(*p - '0'), &value);
        }
        if (fits) {
            *result = value;
            return YES;
        }
    }
    static locale_t cLocale;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cLocale = newlocale(LC_ALL_MASK, "C", NULL);
    });
    char *end = NULL;
    double d = strtod_l(s, &end, cLocale);
    if (!*end) {
        // UInt(exactly:); -0.0 is 0. 2^64 is the first double above UInt64.max.
        if (!(d >= 0 && d < 0x1p64 && d == floor(d)))
            return NO;
        if (d < 0x1p53) {
            *result = (uint64_t)d;
            return YES;
        }
    }
    BOOL negative = NO;
    unsigned __int128 mantissa = 0;
    int exponent = 0;
    if (!TSDecimalOfNumberText(s, &negative, &mantissa, &exponent) || negative || mantissa > UINT64_MAX)
        return NO;
    uint64_t value = (uint64_t)mantissa;
    for (; exponent < 0; exponent++)
        value /= 10;
    for (; exponent > 0; exponent--) {
        if (__builtin_mul_overflow(value, 10, &value))
            return NO;
    }
    *result = value;
    return YES;
}

/// Reads an option number of the settings as Swift's JSONDecoder reads a UInt. Booleans are refused.
static BOOL TSUnsignedValue(id value, NSString *_Nullable text, uint64_t *result)
{
    if (![value isKindOfClass:[NSNumber class]] || TSIsBooleanValue(value) || !text)
        return NO;
    return TSUnsignedValueOfNumberText((NSString *_Nonnull)text, result);
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
    id root = [NSJSONSerialization JSONObjectWithData:TSJSONDataWithPlainNumbers(data) options:0 error:&parseError];
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
    uint64_t compareValue = 0, regexValue = 0;
    NSDictionary<NSString *, NSString *> *texts = TSSettingsTexts(data);
    if (!TSUnsignedValue(textual, texts[TSSettingsTextualKey], &compareValue) || !TSUnsignedValue(regex, texts[TSSettingsRegexKey], &regexValue)
        || (wholeWord && !TSIsBooleanValue(wholeWord)) || (unescapes && !TSIsBooleanValue(unescapes))) {
        if (error)
            *error = TSDefinitionError(@"The settings of the replacement definition are not valid.");
        return nil;
    }
    // Comparison options that the panel does not show (backwards, anchored, numeric, regular expression...) are
    // ignored rather than kept, so that nothing invisible changes what a set does (user's decision, 2026-11-12).
    NSStringCompareOptions compare = (NSStringCompareOptions)compareValue;
    NSRegularExpressionOptions regexOptions = (NSRegularExpressionOptions)regexValue;
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
    if (regexOptions & NSRegularExpressionIgnoreMetacharacters) regularExpressionOptions |= TSRegexFindIgnoreMetacharacters;
    if (regexOptions & NSRegularExpressionUseUnixLineSeparators) regularExpressionOptions |= TSRegexFindUseUnixLineSeparators;
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
    if (regex & TSRegexFindIgnoreMetacharacters) regexOptions |= NSRegularExpressionIgnoreMetacharacters;
    if (regex & TSRegexFindUseUnixLineSeparators) regexOptions |= NSRegularExpressionUseUnixLineSeparators;
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
    return [self applyToString:string selectedRanges:selectedRanges inSelection:inSelection lineEnding:lineEnding cancellation:isCancelled progress:nil];
}

- (nullable TSRegexMultipleReplaceResult *)applyToString:(NSString *)string
                                          selectedRanges:(NSArray<NSValue *> *)selectedRanges
                                             inSelection:(BOOL)inSelection
                                              lineEnding:(nullable NSString *)lineEnding
                                            cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
                                                progress:(nullable void (NS_NOESCAPE ^)(NSUInteger, NSUInteger, double))progress
{
    NSUInteger ruleCount = self.rules.count;
    void (^ruleDone)(NSUInteger) = ^(NSUInteger index) {
        if (progress)
            progress(index, ruleCount, 1.0);
    };
    NSString *current = [string copy];
    NSArray<NSValue *> *scope = selectedRanges;
    NSMutableArray<NSNumber *> *counts = [NSMutableArray array];
    NSMutableDictionary<NSNumber *, NSError *> *errors = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < self.rules.count; index++) {
        TSRegexReplacementRule *rule = self.rules[index];
        [counts addObject:@0];
        if (!rule.enabled) {
            ruleDone(index);
            continue;
        }
        NSError *error = nil;
        TSRegexTextFind *find = [self textFindForRule:rule string:current selectedRanges:scope inSelection:inSelection lineEnding:lineEnding error:&error];
        if (!find) {
            errors[@(index)] = error;
            ruleDone(index);
            continue;
        }
        TSRegexReplacementTemplate *template = [[TSRegexReplacementTemplate alloc] initWithString:rule.replaceString pattern:find.pattern syntax:self.replacementSyntax];
        // The rule's own report of 1 is its last.
        TSRegexReplaceAllResult *result = [find replaceAllWithTemplate:template cancellation:isCancelled progress:progress ? ^(double fraction, NSUInteger matches) {
            progress(index, ruleCount, fraction);
        } : nil];
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
