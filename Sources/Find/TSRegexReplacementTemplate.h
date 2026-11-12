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

/// The text to put in place of one match of the pattern this template was made for.
/// `previousMatchEnd` is where the previous match ended, or the start of the scope for the first match.
- (NSString *)replacementForMatchRange:(NSRange)matchRange
                                result:(nullable NSTextCheckingResult *)result
                              inString:(NSString *)string
                      previousMatchEnd:(NSUInteger)previousMatchEnd
    NS_SWIFT_NAME(replacement(for:result:in:previousMatchEnd:));

@end

NS_ASSUME_NONNULL_END
