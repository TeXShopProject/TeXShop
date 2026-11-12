// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The options of one search. A plain option set, so that it becomes an OptionSet in Swift.
typedef NS_OPTIONS(NSUInteger, TSRegexFindOptions) {
    /// The find string is an ICU regular expression; otherwise it is plain text.
    TSRegexFindRegularExpression        = 1 << 0,
    TSRegexFindIgnoreCase               = 1 << 1,
    /// Regular expression: `.` also matches line separators.
    TSRegexFindDotMatchesLineSeparators = 1 << 2,
    /// Regular expression: `^` and `$` match at every line, as in Ruby. Without it they match only at the ends of the text.
    TSRegexFindAnchorsMatchLines        = 1 << 3,
    /// Regular expression: whitespace and `#` comments in the pattern are ignored.
    TSRegexFindAllowCommentsAndWhitespace = 1 << 4,
    /// Regular expression: `\b` follows the Unicode word boundaries.
    TSRegexFindUnicodeWordBoundaries    = 1 << 5,
    /// Empty matches are not reported.
    TSRegexFindIgnoreEmptyMatches       = 1 << 6,
    /// Plain text: a match must not continue a word on either side.
    TSRegexFindWholeWord                = 1 << 7,
    /// Plain text: the find string is a list of words separated by whitespace; any of them matches.
    TSRegexFindDelimitByWhitespace      = 1 << 8,
    /// Plain text: a and ä match each other.
    TSRegexFindIgnoreDiacritics         = 1 << 9,
    /// Plain text: full-width and half-width forms match each other.
    TSRegexFindIgnoreWidth              = 1 << 10,
    /// Plain text: compare characters exactly, without canonical equivalence.
    TSRegexFindLiteral                  = 1 << 11,
    /// A yen sign (U+00A5) typed in the find or replacement string stands for a backslash.
    TSRegexFindYenIsBackslash           = 1 << 12,
} NS_SWIFT_NAME(RegexFindOptions);

/// The options used when nothing has been chosen yet: anchors match lines, as in OgreKit's Ruby syntax.
FOUNDATION_EXPORT const TSRegexFindOptions TSRegexFindDefaultOptions NS_SWIFT_NAME(RegexFindOptions.default);

/// Errors of the find engine.
FOUNDATION_EXPORT NSErrorDomain const TSRegexFindErrorDomain;

typedef NS_ERROR_ENUM(TSRegexFindErrorDomain, TSRegexFindError) {
    TSRegexFindErrorEmptyFindString = 1,
    TSRegexFindErrorInvalidPattern  = 2,
    TSRegexFindErrorEmptySelection  = 3,
} NS_SWIFT_NAME(RegexFindError);

NS_ASSUME_NONNULL_END
