// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSRegexPatternLexer.h"

static BOOL TSIsDigit(unichar c) { return c >= '0' && c <= '9'; }
static BOOL TSIsHex(unichar c) { return TSIsDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
/// YES when c is one of the ASCII characters in `set` (strchr alone would match the terminating NUL and truncate c).
static BOOL TSIn(const char *set, unichar c) { return c > 0 && c < 128 && strchr(set, (char)c) != NULL; }

@implementation TSRegexPatternLexer {
    NSMutableData *_tokens;                     // TSRegexLexerToken, in the order they were found
    NSMutableArray<NSValue *> *_pairs;
    NSMutableArray<NSString *> *_names;
    NSString *_s;
    NSUInteger _n;
    BOOL _yen, _extended;
    BOOL _canRepeat;                            // the previous item can take a quantifier
    NSMutableArray<NSNumber *> *_openGroups;   // where the unclosed groups start
}

- (instancetype)initWithString:(NSString *)string options:(TSRegexFindOptions)options
{
    if ((self = [super init])) {
        _s = string;
        _n = string.length;
        _yen = (options & TSRegexFindYenIsBackslash) != 0;
        _extended = (options & TSRegexFindAllowCommentsAndWhitespace) != 0;
        _tokens = [NSMutableData data];
        _openGroups = [NSMutableArray array];
        _pairs = [NSMutableArray array];
        _names = [NSMutableArray array];
        if (!(options & TSRegexFindIgnoreMetacharacters))
            [self scan];
        [self sortTokens];
        [_pairs sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
            return a.rangeValue.location < b.rangeValue.location ? NSOrderedAscending : a.rangeValue.location > b.rangeValue.location ? NSOrderedDescending : NSOrderedSame;
        }];
    }
    return self;
}

- (NSUInteger)numberOfTokens
{
    return _tokens.length / sizeof(TSRegexLexerToken);
}

- (TSRegexLexerToken)tokenAtIndex:(NSUInteger)index
{
    return ((const TSRegexLexerToken *)_tokens.bytes)[index];
}

- (NSArray<NSValue *> *)bracketPairs
{
    return [_pairs copy];
}

- (NSArray<NSString *> *)groupNames
{
    return [_names copy];
}

/// By location, keeping the order of tokens at the same place (the unclosed groups are found at the end).
- (void)sortTokens
{
    NSUInteger count = self.numberOfTokens;
    NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++)
        [order addObject:@(i)];
    const TSRegexLexerToken *tokens = _tokens.bytes;
    [order sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSUInteger x = tokens[a.unsignedIntegerValue].range.location, y = tokens[b.unsignedIntegerValue].range.location;
        return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableData *sorted = [NSMutableData dataWithCapacity:_tokens.length];
    for (NSNumber *index in order)
        [sorted appendBytes:&tokens[index.unsignedIntegerValue] length:sizeof(TSRegexLexerToken)];
    _tokens = sorted;
}

- (void)addToken:(NSRange)range role:(TSSyntaxRole)role problem:(TSRegexLexerProblem)problem incompatibility:(NSInteger)incompatibility
{
    if (range.length == 0)
        return;
    TSRegexLexerToken token = {range, role, problem, incompatibility};
    [_tokens appendBytes:&token length:sizeof token];
}

/// Removes the tokens that start at `location` (an open group found unclosed at the end).
- (void)removeTokensAtLocation:(NSUInteger)location
{
    NSMutableData *kept = [NSMutableData dataWithCapacity:_tokens.length];
    const TSRegexLexerToken *tokens = _tokens.bytes;
    for (NSUInteger i = 0; i < self.numberOfTokens; i++)
        if (tokens[i].range.location != location)
            [kept appendBytes:&tokens[i] length:sizeof(TSRegexLexerToken)];
    _tokens = kept;
}

- (unichar)at:(NSUInteger)i { return i < _n ? [_s characterAtIndex:i] : 0; }
- (BOOL)isBackslash:(unichar)c { return c == '\\' || (_yen && c == 0x00A5); }

/// The end of the run that starts at `i` and ends with `close`, or NSNotFound.
- (NSUInteger)find:(unichar)close from:(NSUInteger)i
{
    for (NSUInteger j = i; j < _n; j++)
        if ([self at:j] == close)
            return j;
    return NSNotFound;
}

- (void)add:(NSUInteger)start end:(NSUInteger)end role:(TSSyntaxRole)role
{
    [self addToken:NSMakeRange(start, end - start) role:role problem:TSRegexLexerProblemNone incompatibility:NSNotFound];
}

/// Valid in ICU, but read otherwise by Onigmo (OgreKit).
- (void)add:(NSUInteger)start end:(NSUInteger)end incompatibility:(TSRegexOnigmoIncompatibilityKind)kind
{
    [self addToken:NSMakeRange(start, end - start) role:TSSyntaxRoleRegexIncompatible problem:TSRegexLexerProblemNone incompatibility:kind];
}

- (void)add:(NSUInteger)start end:(NSUInteger)end problem:(TSRegexLexerProblem)problem
{
    [self addToken:NSMakeRange(start, end - start) role:TSSyntaxRoleInvalid problem:problem incompatibility:NSNotFound];
}

- (void)scan
{
    NSUInteger i = 0;
    while (i < _n) {
        unichar c = [self at:i];
        if ([self isBackslash:c])
            i = [self escapeAt:i];
        else if (c == '[')
            i = [self characterClassAt:i];
        else if (c == '(')
            i = [self groupAt:i];
        else if (c == ')') {
            if (_openGroups.count == 0)
                [self add:i end:i + 1 problem:TSRegexLexerProblemUnmatchedParen];
            else {
                NSUInteger open = _openGroups.lastObject.unsignedIntegerValue;
                [_openGroups removeLastObject];
                [_pairs addObject:[NSValue valueWithRange:NSMakeRange(open, i + 1 - open)]];
                [self add:i end:i + 1 role:TSSyntaxRoleRegexSymbol];
            }
            _canRepeat = YES;
            i++;
        } else if (c == '|') {
            [self add:i end:i + 1 role:TSSyntaxRoleRegexSymbol];
            _canRepeat = NO;
            i++;
        } else if (c == '*' || c == '+' || c == '?')
            i = [self quantifierAt:i length:1];
        else if (c == '{')
            i = [self braceAt:i];
        else if (c == '}')
            i = [self literalBraceAt:i];
        else if (c == '^' || c == '$') {
            [self add:i end:i + 1 role:TSSyntaxRoleRegexAnchor];
            _canRepeat = NO;
            i++;
        } else if (c == '.') {
            [self add:i end:i + 1 role:TSSyntaxRoleRegexCharacterClass];
            _canRepeat = YES;
            i++;
        } else if (_extended && c == '#') {
            NSUInteger j = i;
            while (j < _n && [self at:j] != '\n' && [self at:j] != '\r')
                j++;
            [self add:i end:j role:TSSyntaxRoleComment];
            i = j;
        } else if (_extended && (c == ' ' || c == '\t' || c == '\n' || c == '\r')) {
            i++;
        } else {
            _canRepeat = YES;
            i += CFStringIsSurrogateHighCharacter(c) && CFStringIsSurrogateLowCharacter([self at:i + 1]) ? 2 : 1;
        }
    }
    for (NSNumber *start in _openGroups) {
        [self removeTokensAtLocation:start.unsignedIntegerValue];
        [self add:start.unsignedIntegerValue end:start.unsignedIntegerValue + 1 problem:TSRegexLexerProblemUnclosedParen];
    }
}

- (NSUInteger)escapeAt:(NSUInteger)i
{
    if (i + 1 >= _n) {
        [self add:i end:i + 1 problem:TSRegexLexerProblemTrailingBackslash];
        return i + 1;
    }
    unichar d = [self at:i + 1];
    NSUInteger end = i + 2;
    TSSyntaxRole role = TSSyntaxRoleRegexEscape;
    _canRepeat = YES;
    if (d >= '1' && d <= '9') {
        while (TSIsDigit([self at:end]))
            end++;
        role = TSSyntaxRoleRegexBackreference;
    } else if (d == 'k' && [self at:end] == '<') {
        NSUInteger close = [self find:'>' from:end];
        if (close == NSNotFound) {
            [self add:i end:_n problem:TSRegexLexerProblemUnclosedName];
            return _n;
        }
        end = close + 1;
        role = TSSyntaxRoleRegexBackreference;
    } else if (TSIn("dDwWsSXRvV", d)) {
        role = TSSyntaxRoleRegexCharacterClass;
    } else if (d == 'p' || d == 'P' || d == 'N') {
        if ([self at:end] == '{') {
            NSUInteger close = [self find:'}' from:end];
            end = close == NSNotFound ? _n : close + 1;
        } else if (d != 'N')
            end++;
        role = d == 'N' ? TSSyntaxRoleRegexEscape : TSSyntaxRoleRegexCharacterClass;
    } else if (d == 'h' || d == 'H') {
        [self add:i end:end incompatibility:TSRegexOnigmoIncompatibilityHexDigit];
        return end;
    } else if (TSIn("bBAzZG", d)) {
        role = TSSyntaxRoleRegexAnchor;
        _canRepeat = NO;
    } else if (d == 'K') {
        [self add:i end:end incompatibility:TSRegexOnigmoIncompatibilityKeep];
        return end;
    } else if (d == 'g') {
        if ([self at:end] == '<') {
            NSUInteger close = [self find:'>' from:end];
            end = close == NSNotFound ? _n : close + 1;
        }
        [self add:i end:end incompatibility:TSRegexOnigmoIncompatibilityCall];
        return end;
    } else if (d == 'Q') {
        [self add:i end:end role:TSSyntaxRoleRegexEscape];
        NSUInteger j = end;
        while (j + 1 < _n && !([self isBackslash:[self at:j]] && [self at:j + 1] == 'E'))
            j++;
        if (j + 1 < _n) {
            [self add:j end:j + 2 role:TSSyntaxRoleRegexEscape];
            return j + 2;
        }
        return _n;
    } else if (d == 'x') {
        if ([self at:end] == '{') {
            NSUInteger close = [self find:'}' from:end];
            end = close == NSNotFound ? _n : close + 1;
        } else
            while (end < i + 4 && TSIsHex([self at:end]))
                end++;
    } else if (d == 'u') {
        while (end < i + 6 && TSIsHex([self at:end]))
            end++;
    } else if (d == 'U') {
        while (end < i + 10 && TSIsHex([self at:end]))
            end++;
    } else if (d == 'c') {
        end = MIN(end + 1, _n);
    } else if (d == '0') {
        while (end < i + 5 && [self at:end] >= '0' && [self at:end] <= '7')
            end++;
    } else if (CFStringIsSurrogateHighCharacter(d) && CFStringIsSurrogateLowCharacter([self at:end])) {
        end++;
    }
    [self add:i end:end role:role];
    return end;
}

- (NSUInteger)characterClassAt:(NSUInteger)i
{
    NSUInteger j = i + 1;
    if ([self at:j] == '^')
        j++;
    if ([self at:j] == ']')
        j++;
    NSUInteger depth = 1;
    NSMutableArray<NSNumber *> *opens = [NSMutableArray arrayWithObject:@(i)]; // nested classes: [a-z&&[^aeiou]]
    NSMutableArray<NSValue *> *pairs = [NSMutableArray array];
    while (j < _n) {
        unichar c = [self at:j];
        if ([self isBackslash:c])
            j += 2;
        else if (c == '[' && [self at:j + 1] == ':') {
            NSUInteger close = j + 2;
            while (close + 1 < _n && !([self at:close] == ':' && [self at:close + 1] == ']'))
                close++;
            j = close + 2;
        } else if (c == '[') {
            depth++;
            [opens addObject:@(j)];
            j++;
        } else if (c == ']') {
            NSUInteger open = opens.lastObject.unsignedIntegerValue;
            [opens removeLastObject];
            [pairs addObject:[NSValue valueWithRange:NSMakeRange(open, j + 1 - open)]];
            j++;
            if (--depth == 0)
                break;
        } else
            j++;
    }
    if (depth == 0)
        [_pairs addObjectsFromArray:pairs];
    if (depth > 0) {
        [self add:i end:_n problem:TSRegexLexerProblemUnclosedClass];
        return _n;
    }
    [self add:i end:j role:TSSyntaxRoleRegexCharacterClass];
    _canRepeat = YES;
    return j;
}

- (NSUInteger)groupAt:(NSUInteger)i
{
    if ([self at:i + 1] != '?') {
        [self add:i end:i + 1 role:TSSyntaxRoleRegexSymbol];
        [_openGroups addObject:@(i)];
        _canRepeat = NO;
        return i + 1;
    }
    unichar k = [self at:i + 2];
    if (k == '#') {
        NSUInteger close = [self find:')' from:i + 3];
        if (close == NSNotFound) {
            [self add:i end:_n problem:TSRegexLexerProblemUnclosedComment];
            return _n;
        }
        [self add:i end:close + 1 role:TSSyntaxRoleComment];
        return close + 1;
    }
    NSUInteger end = i + 3;
    if (k == '<' && [self at:i + 3] != '=' && [self at:i + 3] != '!') {
        NSUInteger close = [self find:'>' from:i + 3];
        if (close == NSNotFound) {
            [self add:i end:_n problem:TSRegexLexerProblemUnclosedName];
            return _n;
        }
        end = close + 1;
        [_names addObject:[_s substringWithRange:NSMakeRange(i + 3, close - i - 3)]];
    } else if (k == '<')
        end = i + 4;
    else if (k == '~') {
        [self add:i end:i + 3 incompatibility:TSRegexOnigmoIncompatibilityAbsent];
        [_openGroups addObject:@(i)];
        _canRepeat = NO;
        return i + 3;
    } else if (!TSIn(":=!>", k)) {
        // Flags: (?i) (?im-sx) or (?i:…)
        NSUInteger j = i + 2;
        BOOL multiline = NO;
        while (j < _n && TSIn("imsxwu-", [self at:j])) {
            multiline = multiline || [self at:j] == 'm';
            j++;
        }
        unichar close = [self at:j];
        if (close != ')' && close != ':') {
            [self add:i end:MIN(j + 1, _n) problem:TSRegexLexerProblemBadGroup];
            return MIN(j + 1, _n);
        }
        if (multiline)
            [self add:i end:j + 1 incompatibility:TSRegexOnigmoIncompatibilityMultiline];
        else
            [self add:i end:j + 1 role:TSSyntaxRoleRegexSymbol];
        if (close == ':')
            [_openGroups addObject:@(i)];
        _canRepeat = NO;
        return j + 1;
    }
    [self add:i end:end role:TSSyntaxRoleRegexSymbol];
    [_openGroups addObject:@(i)];
    _canRepeat = NO;
    return end;
}

- (NSUInteger)quantifierAt:(NSUInteger)i length:(NSUInteger)length
{
    NSUInteger end = i + length;
    unichar next = [self at:end];
    if (next == '?' || next == '+')
        end++;
    if (!_canRepeat)
        [self add:i end:end problem:TSRegexLexerProblemNothingToRepeat];
    else
        [self add:i end:end role:TSSyntaxRoleRegexQuantifier];
    _canRepeat = NO;
    return end;
}

- (NSUInteger)literalBraceAt:(NSUInteger)i
{
    [self addToken:NSMakeRange(i, 1) role:TSSyntaxRoleInvalid problem:TSRegexLexerProblemLiteralBrace incompatibility:TSRegexOnigmoIncompatibilityLiteralBrace];
    _canRepeat = YES;
    return i + 1;
}

- (NSUInteger)braceAt:(NSUInteger)i
{
    // {n} {n,} {n,m}. ICU refuses any other brace (OgreKit read it as a literal one).
    NSUInteger j = i + 1;
    if (!TSIsDigit([self at:j]))
        return [self literalBraceAt:i];
    while (TSIsDigit([self at:j]))
        j++;
    if ([self at:j] == ',') {
        j++;
        while (TSIsDigit([self at:j]))
            j++;
    }
    if ([self at:j] != '}')
        return [self literalBraceAt:i];
    if (_canRepeat && [self at:j + 1] == '+') {
        [self add:i end:j + 2 incompatibility:TSRegexOnigmoIncompatibilityPossessive];
        _canRepeat = NO;
        return j + 2;
    }
    return [self quantifierAt:i length:j + 1 - i];
}

@end
