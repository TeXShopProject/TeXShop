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
    TSRegexReplacementSyntax readAs = syntax == TSRegexReplacementSyntaxOgreKit ? TSRegexReplacementSyntaxOgreKit : TSRegexReplacementSyntaxICU;
    TSRegexFindOptions options = pattern.options;
    NSUInteger groups = _numberOfCaptureGroups;
    _tokens = _literal ? @[[[TSReplacementToken alloc] initWithKind:TSReplacementTokenText text:normalized group:0]]
                       : TSTokensOfPieces(^(NS_NOESCAPE TSRegexReplacementPieceBlock block) {
                             [TSRegexReplacementTemplate enumeratePiecesOfString:string syntax:readAs options:options numberOfCaptureGroups:groups usingBlock:block];
                         });
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

static NSString *TSCharacter(unichar c)
{
    return [NSString stringWithCharacters:&c length:1];
}

/// As OgreKit reads it.
static void TSOgreKitPieces(NSString *s, NS_NOESCAPE TSRegexReplacementPieceBlock block)
{
    NSUInteger length = s.length;
    for (NSUInteger i = 0; i < length; ) {
        unichar c = [s characterAtIndex:i];
        if (c != '\\') {
            block(TSRegexReplacementPieceText, NSMakeRange(i, 1), TSCharacter(c), 0);
            i++;
            continue;
        }
        if (i + 1 >= length) { // A lone backslash at the end stands for nothing, as in OgreKit.
            block(TSRegexReplacementPieceTrailingBackslash, NSMakeRange(i, 1), @"", 0);
            break;
        }
        unichar n = [s characterAtIndex:i + 1];
        NSRange range = NSMakeRange(i, 2);
        if (TSIsDigit(n)) {
            block(TSRegexReplacementPieceGroup, range, @"", n - '0');
        } else if (n == '&') {
            block(TSRegexReplacementPieceGroup, range, @"", 0);
        } else if (n == '+') {
            block(TSRegexReplacementPieceLastGroup, range, @"", 0);
        } else if (n == '`') {
            block(TSRegexReplacementPiecePrematch, range, @"", 0);
        } else if (n == '\'') {
            block(TSRegexReplacementPiecePostmatch, range, @"", 0);
        } else if (n == '-') {
            block(TSRegexReplacementPieceSincePreviousMatch, range, @"", 0);
        } else if (n == 't' || n == 'n' || n == 'r') {
            block(TSRegexReplacementPieceEscape, range, n == 't' ? @"\t" : n == 'n' ? @"\n" : @"\r", 0);
        } else if (n == 'x') {
            uint32_t value = 0;
            NSUInteger hexLength = TSHexEscapeLength(s, i, &value);
            if (hexLength > 0) {
                range.length = hexLength;
                if (value <= 0xFFFF) // Lets \x{D835}\x{DC00} form one surrogate pair, as in OgreKit.
                    block(TSRegexReplacementPieceEscape, range, TSCharacter((unichar)value), 0);
                else {
                    uint32_t v = value - 0x10000;
                    unichar pair[2] = {(unichar)(0xD800 + (v >> 10)), (unichar)(0xDC00 + (v & 0x3FF))};
                    block(TSRegexReplacementPieceEscape, range, [NSString stringWithCharacters:pair length:2], 0);
                }
            } else {
                block(TSRegexReplacementPieceEscape, range, @"x", 0);
            }
        } else if (n == 'g') {
            NSString *name = nil;
            NSUInteger groupLength = TSGroupEscapeLength(s, i, &name);
            if (groupLength > 0) {
                range.length = groupLength;
                BOOL numeric = YES;
                for (NSUInteger k = 0; k < name.length; k++)
                    numeric = numeric && TSIsDigit([name characterAtIndex:k]);
                if (numeric)
                    block(TSRegexReplacementPieceGroup, range, @"", (NSUInteger)name.integerValue);
                else
                    block(TSRegexReplacementPieceNamedGroup, range, (NSString *_Nonnull)name, 0);
            } else {
                block(TSRegexReplacementPieceEscape, range, @"g", 0);
            }
        } else {
            // `\\` gives a backslash; any other escaped character stands for itself.
            block(TSRegexReplacementPieceEscape, range, TSCharacter(n), 0);
        }
        i = NSMaxRange(range);
    }
}

/// As NSRegularExpression reads it.
static void TSICUPieces(NSString *s, NSUInteger groups, NS_NOESCAPE TSRegexReplacementPieceBlock block)
{
    // As many digits are read as the number of groups has (at least one), as NSRegularExpression does; a group that
    // does not exist gives nothing. With the groups unknown (NSNotFound), every digit.
    NSUInteger maxDigits = 1;
    if (groups == NSNotFound)
        maxDigits = NSUIntegerMax;
    else
        for (NSUInteger n = groups; n >= 10; n /= 10)
            maxDigits++;
    NSUInteger length = s.length;
    for (NSUInteger i = 0; i < length; ) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\') {
            if (i + 1 >= length) { // A lone backslash at the end stands for nothing, as in NSRegularExpression.
                block(TSRegexReplacementPieceTrailingBackslash, NSMakeRange(i, 1), @"", 0);
                break;
            }
            // The escaped character is one UTF-16 unit, as in NSRegularExpression.
            block(TSRegexReplacementPieceEscape, NSMakeRange(i, 2), [s substringWithRange:NSMakeRange(i + 1, 1)], 0);
            i += 2;
        } else if (c == '$' && i + 1 < length && TSIsDigit([s characterAtIndex:i + 1])) {
            NSUInteger start = i, group = 0, digits = 0;
            for (i++; i < length && digits < maxDigits && TSIsDigit([s characterAtIndex:i]); i++, digits++)
                group = group * 10 + ([s characterAtIndex:i] - '0');
            block(TSRegexReplacementPieceGroup, NSMakeRange(start, i - start), @"", group);
        } else if (CFStringIsSurrogateHighCharacter(c) || CFStringIsSurrogateLowCharacter(c)) {
            // NSRegularExpression copies a surrogate and the unit after it as they stand, whatever that unit is
            // (macOS 27.2): `😀$1` gives `😀a`, but `\😀$1` gives `😀$1` and a lone surrogate keeps the `$1` after it.
            NSUInteger size = MIN((NSUInteger)2, length - i);
            block(TSRegexReplacementPieceText, NSMakeRange(i, size), [s substringWithRange:NSMakeRange(i, size)], 0);
            i += size;
        } else {
            block(TSRegexReplacementPieceText, NSMakeRange(i, 1), TSCharacter(c), 0);
            i++;
        }
    }
}

/// CotEditor's unescaping, before the template is read: \0 \t \n \r \" \' become the characters they stand for, from
/// left to right; `\\` stays `\\`, so that the template still reads it as one backslash. `places` gets, for each unit
/// of the result, the range of the string it comes from.
static NSString *TSUnescapedTemplate(NSString *s, NSMutableData *places)
{
    NSMutableString *result = [NSMutableString stringWithCapacity:s.length];
    void (^add)(NSString *, NSRange) = ^(NSString *units, NSRange from) {
        [result appendString:units];
        for (NSUInteger k = 0; k < units.length; k++)
            [places appendBytes:&from length:sizeof from];
    };
    NSUInteger length = s.length;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [s characterAtIndex:i];
        unichar n = i + 1 < length ? [s characterAtIndex:i + 1] : 0;
        if (c != '\\' || !(n == '0' || n == 't' || n == 'n' || n == 'r' || n == '"' || n == '\'' || n == '\\')) {
            add(TSCharacter(c), NSMakeRange(i, 1));
            continue;
        }
        if (n == '\\') {
            add(@"\\", NSMakeRange(i, 1));
            add(@"\\", NSMakeRange(i + 1, 1));
        } else {
            unichar character = n == '0' ? 0 : n == 't' ? '\t' : n == 'n' ? '\n' : n == 'r' ? '\r' : n;
            add(TSCharacter(character), NSMakeRange(i, 2));
        }
        i++;
    }
    return result;
}

+ (void)enumeratePiecesOfString:(NSString *)string syntax:(TSRegexReplacementSyntax)syntax options:(TSRegexFindOptions)options
          numberOfCaptureGroups:(NSUInteger)groups usingBlock:(NS_NOESCAPE TSRegexReplacementPieceBlock)block
{
    NSString *normalized = [TSRegexFindPattern normalizedString:string options:options]; // ¥ → \ keeps every place
    if (syntax == TSRegexReplacementSyntaxOgreKit) {
        TSOgreKitPieces(normalized, block);
        return;
    }
    if ((options & TSRegexFindUnescapesReplacement) != 0) {
        // Read after the unescaping, each piece then given the place in the string as written that it comes from.
        NSMutableData *places = [NSMutableData data];
        NSString *unescaped = TSUnescapedTemplate(normalized, places);
        const NSRange *from = places.bytes;
        TSICUPieces(unescaped, groups, ^(TSRegexReplacementPieceKind kind, NSRange range, NSString *text, NSUInteger group) {
            if (kind != TSRegexReplacementPieceText) {
                NSUInteger start = from[range.location].location, end = NSMaxRange(from[NSMaxRange(range) - 1]);
                block(kind, NSMakeRange(start, end - start), text, group);
                return;
            }
            // Text the template copies: each unit the unescaping made of an escape (two units as written) is that escape.
            for (NSUInteger k = range.location; k < NSMaxRange(range); k++)
                block(from[k].length > 1 ? TSRegexReplacementPieceEscape : TSRegexReplacementPieceText, from[k], [unescaped substringWithRange:NSMakeRange(k, 1)], 0);
        });
    } else
        TSICUPieces(normalized, groups, block);
}

/// The pieces as the expansion uses them: the text of text and escapes joined.
static NSArray<TSReplacementToken *> *TSTokensOfPieces(void (^enumerate)(NS_NOESCAPE TSRegexReplacementPieceBlock block))
{
    NSMutableArray<TSReplacementToken *> *tokens = [NSMutableArray array];
    NSMutableString *text = [NSMutableString string];
    enumerate(^(TSRegexReplacementPieceKind kind, NSRange range, NSString *pieceText, NSUInteger group) {
        TSReplacementTokenKind tokenKind;
        switch (kind) {
            case TSRegexReplacementPieceText:
            case TSRegexReplacementPieceEscape:
                [text appendString:pieceText];
                return;
            case TSRegexReplacementPieceTrailingBackslash:
                return;
            case TSRegexReplacementPieceGroup: tokenKind = TSReplacementTokenGroup; break;
            case TSRegexReplacementPieceNamedGroup: tokenKind = TSReplacementTokenNamedGroup; break;
            case TSRegexReplacementPieceLastGroup: tokenKind = TSReplacementTokenLastGroup; break;
            case TSRegexReplacementPiecePrematch: tokenKind = TSReplacementTokenPrematch; break;
            case TSRegexReplacementPiecePostmatch: tokenKind = TSReplacementTokenPostmatch; break;
            case TSRegexReplacementPieceSincePreviousMatch: tokenKind = TSReplacementTokenSincePreviousMatch; break;
        }
        if (text.length > 0) {
            [tokens addObject:[[TSReplacementToken alloc] initWithKind:TSReplacementTokenText text:text group:0]];
            [text setString:@""];
        }
        [tokens addObject:[[TSReplacementToken alloc] initWithKind:tokenKind text:kind == TSRegexReplacementPieceNamedGroup ? pieceText : @"" group:group]];
    });
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
