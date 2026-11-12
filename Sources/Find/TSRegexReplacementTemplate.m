// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexReplacementTemplate.h"

typedef NS_ENUM(NSInteger, TSReplacementTokenKind) {
    TSReplacementTokenText,
    TSReplacementTokenGroup,
    TSReplacementTokenNamedGroup,
    TSReplacementTokenLastGroup,
    TSReplacementTokenPrematch,
    TSReplacementTokenPostmatch,
    TSReplacementTokenSincePreviousMatch,
};

/// One piece of a parsed template. In Swift this becomes an enum with associated values.
@interface TSReplacementToken : NSObject
@property (nonatomic, readonly) TSReplacementTokenKind kind;
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly) NSUInteger group;
- (instancetype)initWithKind:(TSReplacementTokenKind)kind text:(NSString *)text group:(NSUInteger)group NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation TSReplacementToken
- (instancetype)initWithKind:(TSReplacementTokenKind)kind text:(NSString *)text group:(NSUInteger)group
{
    if ((self = [super init])) {
        _kind = kind;
        _text = [text copy];
        _group = group;
    }
    return self;
}
@end

@interface TSRegexReplacementTemplate ()
@property (nonatomic, readonly, copy) NSArray<TSReplacementToken *> *tokens;
@property (nonatomic, readonly, copy) NSArray<NSString *> *groupNames;
@property (nonatomic, readonly) NSUInteger numberOfCaptureGroups;
@end

@implementation TSRegexReplacementTemplate

- (instancetype)initWithString:(NSString *)string pattern:(TSRegexFindPattern *)pattern syntax:(TSRegexReplacementSyntax)syntax
{
    if (!(self = [super init]))
        return nil;
    _string = [string copy];
    _literal = !pattern.regularExpression;
    _syntax = syntax;
    _groupNames = pattern.captureGroupNames;
    _numberOfCaptureGroups = pattern.numberOfCaptureGroups;
    NSString *normalized = [TSRegexFindPattern normalizedString:string options:pattern.options];
    _tokens = _literal ? @[[[TSReplacementToken alloc] initWithKind:TSReplacementTokenText text:normalized group:0]]
             : syntax == TSRegexReplacementSyntaxOgreKit ? [TSRegexReplacementTemplate ogreKitTokensOfString:normalized]
                                                         : [TSRegexReplacementTemplate icuTokensOfString:normalized numberOfCaptureGroups:_numberOfCaptureGroups];
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone
{
    return self;
}

#pragma mark Parsing

static BOOL TSIsDigit(unichar c) { return c >= '0' && c <= '9'; }
static BOOL TSIsHexDigit(unichar c) { return TSIsDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
static BOOL TSIsNameCharacter(unichar c) { return TSIsDigit(c) || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }

/// The length of `\x{H...}` at `index` (the backslash), or 0 if the text there is not one.
static NSUInteger TSHexEscapeLength(NSString *s, NSUInteger index, uint32_t *value)
{
    NSUInteger length = s.length, i = index + 2;
    if (i >= length || [s characterAtIndex:i] != '{')
        return 0;
    uint32_t result = 0;
    NSUInteger digits = 0;
    for (i++; i < length && TSIsHexDigit([s characterAtIndex:i]); i++, digits++) {
        unichar c = [s characterAtIndex:i];
        result = result * 16 + (TSIsDigit(c) ? c - '0' : (c | 0x20) - 'a' + 10);
    }
    if (digits == 0 || digits > 6 || i >= length || [s characterAtIndex:i] != '}' || result > 0x10FFFF)
        return 0;
    *value = result;
    return i + 1 - index;
}

/// The length of `\g<...>` at `index` (the backslash), or 0 if the text there is not one.
static NSUInteger TSGroupEscapeLength(NSString *s, NSUInteger index, NSString *_Nullable *_Nonnull name)
{
    NSUInteger length = s.length, i = index + 2;
    if (i >= length || [s characterAtIndex:i] != '<')
        return 0;
    NSUInteger start = ++i;
    while (i < length && TSIsNameCharacter([s characterAtIndex:i]))
        i++;
    if (i == start || i >= length || [s characterAtIndex:i] != '>')
        return 0;
    *name = [s substringWithRange:NSMakeRange(start, i - start)];
    return i + 1 - index;
}

+ (NSArray<TSReplacementToken *> *)ogreKitTokensOfString:(NSString *)s
{
    NSMutableArray<TSReplacementToken *> *tokens = [NSMutableArray array];
    NSMutableString *text = [NSMutableString string];
    void (^flushText)(void) = ^{
        if (text.length > 0) {
            [tokens addObject:[[TSReplacementToken alloc] initWithKind:TSReplacementTokenText text:text group:0]];
            [text setString:@""];
        }
    };
    void (^addToken)(TSReplacementTokenKind, NSString *, NSUInteger) = ^(TSReplacementTokenKind kind, NSString *name, NSUInteger group) {
        flushText();
        [tokens addObject:[[TSReplacementToken alloc] initWithKind:kind text:name group:group]];
    };
    NSUInteger length = s.length;
    for (NSUInteger i = 0; i < length; ) {
        unichar c = [s characterAtIndex:i];
        if (c != '\\') {
            [text appendFormat:@"%C", c];
            i++;
            continue;
        }
        if (i + 1 >= length) // A lone backslash at the end stands for nothing, as in OgreKit.
            break;
        unichar n = [s characterAtIndex:i + 1];
        NSUInteger consumed = 2;
        if (TSIsDigit(n)) {
            addToken(TSReplacementTokenGroup, @"", n - '0');
        } else if (n == '&') {
            addToken(TSReplacementTokenGroup, @"", 0);
        } else if (n == '+') {
            addToken(TSReplacementTokenLastGroup, @"", 0);
        } else if (n == '`') {
            addToken(TSReplacementTokenPrematch, @"", 0);
        } else if (n == '\'') {
            addToken(TSReplacementTokenPostmatch, @"", 0);
        } else if (n == '-') {
            addToken(TSReplacementTokenSincePreviousMatch, @"", 0);
        } else if (n == 't') {
            [text appendString:@"\t"];
        } else if (n == 'n') {
            [text appendString:@"\n"];
        } else if (n == 'r') {
            [text appendString:@"\r"];
        } else if (n == 'x') {
            uint32_t value = 0;
            NSUInteger hexLength = TSHexEscapeLength(s, i, &value);
            if (hexLength > 0) {
                consumed = hexLength;
                if (value <= 0xFFFF) // Lets \x{D835}\x{DC00} form one surrogate pair, as in OgreKit.
                    [text appendFormat:@"%C", (unichar)value];
                else {
                    uint32_t v = value - 0x10000;
                    unichar pair[2] = {(unichar)(0xD800 + (v >> 10)), (unichar)(0xDC00 + (v & 0x3FF))};
                    [text appendString:[NSString stringWithCharacters:pair length:2]];
                }
            } else {
                [text appendString:@"x"];
            }
        } else if (n == 'g') {
            NSString *name = nil;
            NSUInteger groupLength = TSGroupEscapeLength(s, i, &name);
            if (groupLength > 0) {
                consumed = groupLength;
                BOOL numeric = YES;
                for (NSUInteger k = 0; k < name.length; k++)
                    numeric = numeric && TSIsDigit([name characterAtIndex:k]);
                if (numeric)
                    addToken(TSReplacementTokenGroup, @"", (NSUInteger)name.integerValue);
                else
                    addToken(TSReplacementTokenNamedGroup, name, 0);
            } else {
                [text appendString:@"g"];
            }
        } else {
            // `\\` gives a backslash; any other escaped character stands for itself.
            [text appendFormat:@"%C", n];
        }
        i += consumed;
    }
    flushText();
    return tokens;
}

/// Reads a template as NSRegularExpression does, and also takes \t \n \r for tab, line feed and carriage return.
+ (NSArray<TSReplacementToken *> *)icuTokensOfString:(NSString *)s numberOfCaptureGroups:(NSUInteger)groups
{
    NSMutableArray<TSReplacementToken *> *tokens = [NSMutableArray array];
    NSMutableString *text = [NSMutableString string];
    NSUInteger length = s.length;
    for (NSUInteger i = 0; i < length; ) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\') {
            if (i + 1 >= length) // A lone backslash at the end stands for nothing, as in NSRegularExpression.
                break;
            unichar n = [s characterAtIndex:i + 1];
            [text appendString:n == 't' ? @"\t" : n == 'n' ? @"\n" : n == 'r' ? @"\r" : [NSString stringWithCharacters:&n length:1]];
            i += 2;
        } else if (c == '$' && i + 1 < length && TSIsDigit([s characterAtIndex:i + 1])) {
            // As many digits are read as the number of groups has (at least one), as NSRegularExpression does;
            // a group that does not exist gives nothing.
            NSUInteger maxDigits = 1;
            for (NSUInteger n = groups; n >= 10; n /= 10)
                maxDigits++;
            NSUInteger group = 0, digits = 0;
            for (i++; i < length && digits < maxDigits && TSIsDigit([s characterAtIndex:i]); i++, digits++)
                group = group * 10 + ([s characterAtIndex:i] - '0');
            if (text.length > 0) {
                [tokens addObject:[[TSReplacementToken alloc] initWithKind:TSReplacementTokenText text:text group:0]];
                [text setString:@""];
            }
            [tokens addObject:[[TSReplacementToken alloc] initWithKind:TSReplacementTokenGroup text:@"" group:group]];
        } else {
            [text appendFormat:@"%C", c];
            i++;
        }
    }
    if (text.length > 0)
        [tokens addObject:[[TSReplacementToken alloc] initWithKind:TSReplacementTokenText text:text group:0]];
    return tokens;
}

#pragma mark Expansion

static NSString *TSSubstring(NSString *string, NSRange range)
{
    if (range.location == NSNotFound || NSMaxRange(range) > string.length)
        return @"";
    return [string substringWithRange:range];
}

- (NSString *)replacementForMatchRange:(NSRange)matchRange
                                result:(nullable NSTextCheckingResult *)result
                              inString:(NSString *)string
                      previousMatchEnd:(NSUInteger)previousMatchEnd
{
    if (self.tokens.count == 1 && self.tokens[0].kind == TSReplacementTokenText)
        return self.tokens[0].text;
    NSMutableString *output = [NSMutableString string];
    for (TSReplacementToken *token in self.tokens) {
        switch (token.kind) {
            case TSReplacementTokenText:
                [output appendString:token.text];
                break;
            case TSReplacementTokenGroup:
                if (token.group == 0)
                    [output appendString:TSSubstring(string, matchRange)];
                else if (result && token.group < result.numberOfRanges)
                    [output appendString:TSSubstring(string, [result rangeAtIndex:token.group])];
                break;
            case TSReplacementTokenNamedGroup:
                // rangeWithName: raises for an unknown name, so only ask for names the pattern defines.
                if (result && [self.groupNames containsObject:token.text])
                    [output appendString:TSSubstring(string, [result rangeWithName:token.text])];
                break;
            case TSReplacementTokenLastGroup:
                if (result)
                    for (NSUInteger k = result.numberOfRanges; k-- > 1; )
                        if ([result rangeAtIndex:k].location != NSNotFound) {
                            [output appendString:TSSubstring(string, [result rangeAtIndex:k])];
                            break;
                        }
                break;
            case TSReplacementTokenPrematch:
                [output appendString:[string substringToIndex:matchRange.location]];
                break;
            case TSReplacementTokenPostmatch:
                [output appendString:[string substringFromIndex:NSMaxRange(matchRange)]];
                break;
            case TSReplacementTokenSincePreviousMatch:
                if (previousMatchEnd <= matchRange.location)
                    [output appendString:[string substringWithRange:NSMakeRange(previousMatchEnd, matchRange.location - previousMatchEnd)]];
                break;
        }
    }
    return output;
}

@end
