// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexFindPattern.h"

NS_ASSUME_NONNULL_BEGIN

/// How the replacement string of a regular expression refers to the match.
typedef NS_ENUM(NSInteger, TSRegexReplacementSyntax) {
    /// As NSRegularExpression (and CotEditor) reads it, plus \t \n \r:
    ///   $0             the whole match           $1 ...           a numbered group; as many digits are read as
    ///                                                              the number of groups has, so with 12 groups
    ///                                                              $123 is group 12 and a 3
    ///   \t \n \r       tab, line feed, carriage return
    ///   \X             the character X, so \$ is a dollar sign and \\ a backslash
    /// A `$` not followed by a digit is literal.
    TSRegexReplacementSyntaxICU = 0,
    /// As OgreKit (Onigmo) reads it, so that existing replacement strings keep working:
    ///   \0 \&          the whole match           \1 ... \9        a numbered group
    ///   \g<name>       a named group             \g<12>           a numbered group
    ///   \+             the last group that matched
    ///   \`  \'         the text before / after the match
    ///   \-             the text between the previous match and this one
    ///   \t \n \r       tab, line feed, carriage return
    ///   \x{HHHH}       a character by code (1 to 6 hex digits)
    ///   \X             the character X, so \\ is a backslash
    /// `$` is always literal, which suits TeX mathematics.
    TSRegexReplacementSyntaxOgreKit = 1,
} NS_SWIFT_NAME(RegexReplacementSyntax);

/// One piece of a replacement string as it is read, with its place in the string as written.
typedef NS_ENUM(NSInteger, TSRegexReplacementPieceKind) {
    TSRegexReplacementPieceText,                // characters that stand for themselves
    TSRegexReplacementPieceEscape,              // \t \$ \\ \x{41}…: the character in `text`
    TSRegexReplacementPieceGroup,               // $1 \1 \& \g<12>: the group number in `group` (0, the whole match)
    TSRegexReplacementPieceNamedGroup,          // \g<name>: the name in `text`
    TSRegexReplacementPieceLastGroup,           // \+
    TSRegexReplacementPiecePrematch,            // \`
    TSRegexReplacementPiecePostmatch,           // \'
    TSRegexReplacementPieceSincePreviousMatch,  // \-
    TSRegexReplacementPieceTrailingBackslash,   // a lone backslash at the end: it gives nothing
} NS_SWIFT_NAME(RegexReplacementPieceKind);

typedef void (^TSRegexReplacementPieceBlock)(TSRegexReplacementPieceKind kind, NSRange range, NSString *text, NSUInteger group);

/// A replacement string, parsed once for one pattern.
/// For plain text the replacement is literal whatever the syntax. A lone backslash at the end stands for nothing.
/// Yen signs count as backslashes when the pattern's options say so.
NS_SWIFT_NAME(RegexReplacementTemplate)
@interface TSRegexReplacementTemplate : NSObject <NSCopying>

@property (nonatomic, readonly, copy) NSString *string;
@property (nonatomic, readonly, getter=isLiteral) BOOL literal;
@property (nonatomic, readonly) TSRegexReplacementSyntax syntax;

- (instancetype)initWithString:(NSString *)string
                       pattern:(TSRegexFindPattern *)pattern
                        syntax:(TSRegexReplacementSyntax)syntax NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The pieces of a replacement string of a regular expression, in order, as the template reads them: the one lexer of
/// replacement strings, which the expansion and the coloring of the replace field share. `options` gives the yen sign
/// and, for the ICU syntax, the unescaping. With `groups` NSNotFound (an invalid pattern), `$` takes every digit.
+ (void)enumeratePiecesOfString:(NSString *)string
                         syntax:(TSRegexReplacementSyntax)syntax
                        options:(TSRegexFindOptions)options
          numberOfCaptureGroups:(NSUInteger)groups
                     usingBlock:(NS_NOESCAPE TSRegexReplacementPieceBlock)block NS_SWIFT_NAME(enumeratePieces(of:syntax:options:numberOfCaptureGroups:using:));

/// The text to put in place of one match of the pattern this template was made for.
/// `previousMatchEnd` is where the previous match ended, or the start of the scope for the first match.
- (NSString *)replacementForMatchRange:(NSRange)matchRange
                                result:(nullable NSTextCheckingResult *)result
                              inString:(NSString *)string
                      previousMatchEnd:(NSUInteger)previousMatchEnd
    NS_SWIFT_NAME(replacement(for:result:in:previousMatchEnd:));

@end

NS_ASSUME_NONNULL_END
