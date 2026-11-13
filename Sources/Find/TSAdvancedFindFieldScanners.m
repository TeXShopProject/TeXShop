// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindFieldScanners.h"
#import "TSAdvancedFindController.h"
#import "TSRegexPatternLexer.h"

#define TSLocalized TSAdvancedFindLocalized

/// The message of an invalid token.
static NSString *TSProblemMessage(TSRegexLexerProblem problem)
{
    switch (problem) {
        case TSRegexLexerProblemNone:
            return @"";
        case TSRegexLexerProblemUnmatchedParen:
            return TSLocalized(@"AdvancedFind.Mark.UnmatchedParen", @"This ) closes no group.");
        case TSRegexLexerProblemUnclosedParen:
            return TSLocalized(@"AdvancedFind.Mark.UnclosedParen", @"This group is not closed.");
        case TSRegexLexerProblemTrailingBackslash:
            return TSLocalized(@"AdvancedFind.Mark.TrailingBackslash", @"A backslash at the end escapes nothing.");
        case TSRegexLexerProblemUnclosedName:
            return TSLocalized(@"AdvancedFind.Mark.UnclosedName", @"The group name is not closed with >.");
        case TSRegexLexerProblemUnclosedClass:
            return TSLocalized(@"AdvancedFind.Mark.UnclosedClass", @"This [ is not closed with ].");
        case TSRegexLexerProblemUnclosedComment:
            return TSLocalized(@"AdvancedFind.Mark.UnclosedComment", @"This comment is not closed with ).");
        case TSRegexLexerProblemBadGroup:
            return TSLocalized(@"AdvancedFind.Mark.BadGroup", @"Unknown kind of group.");
        case TSRegexLexerProblemNothingToRepeat:
            return TSLocalized(@"AdvancedFind.Mark.NothingToRepeat", @"There is nothing before this to repeat.");
        case TSRegexLexerProblemLiteralBrace: // the explanation of the table of OgreKit's differences
            return [TSRegexFindPattern onigmoIncompatibilityOfKind:TSRegexOnigmoIncompatibilityLiteralBrace].message;
        case TSRegexLexerProblemTrailingBackslashReplacement:
            return TSLocalized(@"AdvancedFind.Mark.TrailingBackslashReplacement", @"A backslash at the end gives nothing.");
        case TSRegexLexerProblemNoSuchGroup:
        case TSRegexLexerProblemNoSuchName:
            return @""; // formatted with the group where it is found
    }
    return @"";
}

#pragma mark Pattern

@implementation TSAdvancedFindPatternScanner

- (instancetype)initWithOptions:(TSRegexFindOptions)options
{
    if ((self = [super init]))
        _options = options;
    return self;
}

- (TSRegexPatternLexer *)lexerOfString:(NSString *)string
{
    return [[TSRegexPatternLexer alloc] initWithString:string options:self.options];
}

- (NSRange)lineAlignedRangeForEditedRange:(NSRange)range inString:(NSString *)string
{
    // Groups and classes span lines, so the whole pattern is scanned again.
    return NSMakeRange(0, string.length);
}

- (void)enumerateTokensInString:(NSString *)string range:(NSRange)range usingBlock:(NS_NOESCAPE TSSyntaxTokenBlock)block
{
    TSRegexPatternLexer *lexer = [self lexerOfString:string];
    for (NSUInteger i = 0; i < lexer.numberOfTokens; i++) {
        TSRegexLexerToken token = [lexer tokenAtIndex:i];
        NSRange shown = NSIntersectionRange(token.range, range);
        if (shown.length > 0)
            block(shown, token.role, TSSyntaxTokenFlagsNoSpellCheck);
    }
}

- (NSArray<TSSyntaxDiagnostic *> *)diagnosticsInString:(NSString *)string
{
    TSRegexPatternLexer *lexer = [self lexerOfString:string];
    NSMutableArray<TSSyntaxDiagnostic *> *diagnostics = [NSMutableArray array];
    for (NSUInteger i = 0; i < lexer.numberOfTokens; i++) {
        TSRegexLexerToken token = [lexer tokenAtIndex:i];
        NSString *message = token.role == TSSyntaxRoleRegexIncompatible
            ? [TSRegexFindPattern onigmoIncompatibilityOfKind:(TSRegexOnigmoIncompatibilityKind)token.incompatibility].message
            : token.role == TSSyntaxRoleInvalid ? TSProblemMessage(token.problem) : @"";
        if (message.length > 0)
            [diagnostics addObject:[[TSSyntaxDiagnostic alloc] initWithRange:token.range role:token.role message:message]];
    }
    return diagnostics;
}

- (NSArray<NSValue *> *)bracketPairsInString:(NSString *)string
{
    return [self lexerOfString:string].bracketPairs;
}

- (NSArray<NSString *> *)captureGroupNamesInString:(NSString *)string
{
    return [self lexerOfString:string].groupNames;
}

@end

#pragma mark Replacement

@implementation TSAdvancedFindReplacementScanner

- (instancetype)initWithSyntax:(TSRegexReplacementSyntax)syntax options:(TSRegexFindOptions)options pattern:(nullable TSRegexFindPattern *)pattern
{
    if ((self = [super init])) {
        _syntax = syntax;
        _options = options;
        _numberOfCaptureGroups = pattern ? pattern.numberOfCaptureGroups : NSNotFound;
        _captureGroupNames = pattern.captureGroupNames ?: @[];
    }
    return self;
}

- (NSRange)lineAlignedRangeForEditedRange:(NSRange)range inString:(NSString *)string
{
    return NSMakeRange(0, string.length);
}

/// Each token of `string` with its message (empty for a valid one), as the engine reads the string.
- (void)enumerateTokensOfString:(NSString *)string usingBlock:(NS_NOESCAPE void (^)(NSRange range, TSSyntaxRole role, NSString *message))block
{
    BOOL known = self.numberOfCaptureGroups != NSNotFound;
    [TSRegexReplacementTemplate enumeratePiecesOfString:string syntax:self.syntax options:self.options numberOfCaptureGroups:self.numberOfCaptureGroups
                                             usingBlock:^(TSRegexReplacementPieceKind kind, NSRange range, NSString *text, NSUInteger group) {
        switch (kind) {
            case TSRegexReplacementPieceText:
                return;
            case TSRegexReplacementPieceEscape:
                block(range, TSSyntaxRoleRegexEscape, @"");
                return;
            case TSRegexReplacementPieceGroup:
                if (known && group > self.numberOfCaptureGroups) {
                    NSString *format = TSLocalized(@"AdvancedFind.Mark.NoSuchGroup", @"The pattern has no group %lu, so this gives nothing.");
                    block(range, TSSyntaxRoleInvalid, [NSString stringWithFormat:format, (unsigned long)group]);
                } else
                    block(range, TSSyntaxRoleRegexBackreference, @"");
                return;
            case TSRegexReplacementPieceNamedGroup:
                if (known && ![self.captureGroupNames containsObject:text]) {
                    NSString *format = TSLocalized(@"AdvancedFind.Mark.NoSuchName", @"The pattern has no group named “%@”, so this gives nothing.");
                    block(range, TSSyntaxRoleInvalid, [NSString stringWithFormat:format, text]);
                } else
                    block(range, TSSyntaxRoleRegexBackreference, @"");
                return;
            case TSRegexReplacementPieceLastGroup:
            case TSRegexReplacementPiecePrematch:
            case TSRegexReplacementPiecePostmatch:
            case TSRegexReplacementPieceSincePreviousMatch:
                block(range, TSSyntaxRoleRegexBackreference, @"");
                return;
            case TSRegexReplacementPieceTrailingBackslash:
                block(range, TSSyntaxRoleInvalid, TSProblemMessage(TSRegexLexerProblemTrailingBackslashReplacement));
                return;
        }
    }];
}

- (void)enumerateTokensInString:(NSString *)string range:(NSRange)range usingBlock:(NS_NOESCAPE TSSyntaxTokenBlock)block
{
    [self enumerateTokensOfString:string usingBlock:^(NSRange token, TSSyntaxRole role, NSString *message) {
        NSRange shown = NSIntersectionRange(token, range);
        if (shown.length > 0)
            block(shown, role, TSSyntaxTokenFlagsNoSpellCheck);
    }];
}

- (NSArray<TSSyntaxDiagnostic *> *)diagnosticsInString:(NSString *)string
{
    NSMutableArray<TSSyntaxDiagnostic *> *diagnostics = [NSMutableArray array];
    [self enumerateTokensOfString:string usingBlock:^(NSRange range, TSSyntaxRole role, NSString *message) {
        if (message.length > 0)
            [diagnostics addObject:[[TSSyntaxDiagnostic alloc] initWithRange:range role:role message:message]];
    }];
    return diagnostics;
}

@end

#pragma mark Colors

static NSColor *TSDynamicColor(NSString *name, unsigned light, unsigned dark)
{
    NSColor *(^rgb)(unsigned) = ^NSColor *(unsigned value) {
        return [NSColor colorWithSRGBRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0 blue:(value & 0xFF) / 255.0 alpha:1];
    };
    NSColor *lightColor = rgb(light), *darkColor = rgb(dark);
    return [NSColor colorWithName:name dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [match isEqualToString:NSAppearanceNameDarkAqua] ? darkColor : lightColor;
    }];
}

TSSyntaxColorScheme *TSAdvancedFindFieldColorScheme(void)
{
    static TSSyntaxColorScheme *scheme;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary<NSAttributedStringKey, id> *(^color)(NSString *, unsigned, unsigned) = ^(NSString *name, unsigned light, unsigned dark) {
            return @{NSForegroundColorAttributeName: TSDynamicColor(name, light, dark)};
        };
        NSColor *red = TSDynamicColor(@"AdvancedFindInvalid", 0xD12F1B, 0xFF6B5A);
        NSColor *orange = TSDynamicColor(@"AdvancedFindIncompatible", 0xC86400, 0xFFA14A);
        scheme = [[TSSyntaxColorScheme alloc] initWithAttributes:@{
            @(TSSyntaxRoleRegexCharacterClass): color(@"AdvancedFindClass", 0x0F68A0, 0x6BB8F0),
            @(TSSyntaxRoleRegexBackreference): color(@"AdvancedFindBackreference", 0x8A2BB8, 0xD58BF5),
            @(TSSyntaxRoleRegexQuantifier): color(@"AdvancedFindQuantifier", 0xB0560A, 0xF2A65A),
            @(TSSyntaxRoleRegexAnchor): color(@"AdvancedFindAnchor", 0xC2185B, 0xFF7AB0),
            @(TSSyntaxRoleRegexSymbol): color(@"AdvancedFindSymbol", 0x2E7D32, 0x7FD483),
            @(TSSyntaxRoleRegexEscape): color(@"AdvancedFindEscape", 0x7A5C1E, 0xD9B76A),
            @(TSSyntaxRoleComment): color(@"AdvancedFindComment", 0x8A8A8A, 0x8E8E93),
            @(TSSyntaxRoleRegexIncompatible): @{
                NSUnderlineStyleAttributeName: @(NSUnderlineStyleThick | NSUnderlinePatternDot),
                NSUnderlineColorAttributeName: orange,
                NSForegroundColorAttributeName: orange,
            },
            @(TSSyntaxRoleInvalid): @{
                NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                NSUnderlineColorAttributeName: red,
                NSForegroundColorAttributeName: red,
            },
        } activeLineAttributes:@{} braceHighlightAttributes:@{} contentHighlightAttributes:@{}];
    });
    return scheme;
}

NSAttributedString *TSAdvancedFindColoredString(NSString *string, id<TSSyntaxScanner> scanner, TSSyntaxColorScheme *scheme,
                                                NSDictionary<NSAttributedStringKey, id> *attributes)
{
    NSMutableAttributedString *colored = [[NSMutableAttributedString alloc] initWithString:string attributes:attributes];
    [scanner enumerateTokensInString:string range:[scanner lineAlignedRangeForEditedRange:NSMakeRange(0, string.length) inString:string]
                          usingBlock:^(NSRange range, TSSyntaxRole role, TSSyntaxTokenFlags flags) {
        NSDictionary<NSAttributedStringKey, id> *roleAttributes = [scheme attributesForRole:role];
        if (roleAttributes.count > 0)
            [colored addAttributes:roleAttributes range:range];
    }];
    return colored;
}
