// SPDX-License-Identifier: GPL-2.0-or-later
// The lexer of regular expression find patterns, as ICU reads them: the tokens for coloring the find field, the
// brackets that pair up, and the named groups. Foundation only; the engine takes the names of the groups from it, and
// the find field's scanner (TSAdvancedFindFieldScanners) its tokens.
#import <Foundation/Foundation.h>
#import "TSRegexFindOptions.h"
#import "TSRegexOnigmoIncompatibility.h"
#import "TSSyntaxRole.h"

NS_ASSUME_NONNULL_BEGIN

/// What is wrong with an invalid token of a pattern or a replacement template.
typedef NS_ENUM(NSInteger, TSRegexLexerProblem) {
    TSRegexLexerProblemNone = 0,
    TSRegexLexerProblemUnmatchedParen,          // ) closes no group
    TSRegexLexerProblemUnclosedParen,           // ( is not closed
    TSRegexLexerProblemTrailingBackslash,       // \ at the end of a pattern
    TSRegexLexerProblemUnclosedName,            // (?<name or \k<name without >
    TSRegexLexerProblemUnclosedClass,           // [ without ]
    TSRegexLexerProblemUnclosedComment,         // (?# without )
    TSRegexLexerProblemBadGroup,                // (?…) of no known kind
    TSRegexLexerProblemNothingToRepeat,         // a quantifier after nothing
    TSRegexLexerProblemLiteralBrace,            // { or } that is not a quantifier (OgreKit read it as text)
    // Replacement templates
    TSRegexLexerProblemTrailingBackslashReplacement, // \ at the end of a replacement gives nothing
    TSRegexLexerProblemNoSuchGroup,             // $3 or \3 with fewer groups
    TSRegexLexerProblemNoSuchName,              // \g<name> with no such named group
} NS_SWIFT_NAME(RegexLexerProblem);

/// One token. `problem` is set for TSSyntaxRoleInvalid, `incompatibility` (an Onigmo difference of
/// TSRegexOnigmoIncompatibility) for TSSyntaxRoleRegexIncompatible and for a literal brace; NSNotFound otherwise.
typedef struct {
    NSRange range;
    TSSyntaxRole role;
    TSRegexLexerProblem problem;
    NSInteger incompatibility;
} TSRegexLexerToken;

NS_SWIFT_NAME(RegexPatternLexer)
@interface TSRegexPatternLexer : NSObject

/// Reads `pattern` with `options` (yen signs as backslashes, spaces and # comments ignored when they say so). With
/// "treat the pattern literally" there are no tokens, pairs or names.
- (instancetype)initWithString:(NSString *)pattern options:(TSRegexFindOptions)options NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The tokens, sorted by location (a token may lie inside an earlier one, as a group's name does not).
@property (nonatomic, readonly) NSUInteger numberOfTokens;
- (TSRegexLexerToken)tokenAtIndex:(NSUInteger)index;
/// The brackets that pair up, from the opening one to the closing one, sorted by the opening one: groups ( ) and
/// classes [ ], nested classes too. Not \( \[, nor those inside a class, a comment or \Q…\E.
@property (nonatomic, readonly, copy) NSArray<NSValue *> *bracketPairs;
/// The names of the named groups, in order. Not a `(?<name>` inside a class, a comment or \Q…\E: ICU makes no group
/// of those.
@property (nonatomic, readonly, copy) NSArray<NSString *> *groupNames;

@end

NS_ASSUME_NONNULL_END
