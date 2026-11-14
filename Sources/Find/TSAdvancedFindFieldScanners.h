// SPDX-License-Identifier: GPL-2.0-or-later
// The coloring of the Advanced Find panel's fields and of the multiple replacement rules: scanners of layer 1 of the
// shared syntax coloring (Sources/Syntax) for regular expression patterns and replacement strings. Their tokens come
// from the engine's own lexers (TSRegexPatternLexer, -[TSRegexReplacementTemplate enumeratePiecesOfString:…]), so a
// field is colored as the engine reads it; their messages are in AdvancedFind.strings.
#import <AppKit/AppKit.h>
#import "TSSyntaxScanner.h"
#import "TSSyntaxColorScheme.h"
#import "TSRegexReplacementTemplate.h"

NS_ASSUME_NONNULL_BEGIN

/// The find field when "Regular expression" is on: ICU syntax, with what OgreKit (Onigmo) reads otherwise marked as
/// incompatible and the errors as invalid. With "treat the pattern literally" nothing is colored.
NS_SWIFT_NAME(AdvancedFindPatternScanner)
@interface TSAdvancedFindPatternScanner : NSObject <TSSyntaxScanner>
@property (nonatomic, readonly) TSRegexFindOptions options;
- (instancetype)initWithOptions:(TSRegexFindOptions)options NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
/// The names of the named groups, as the engine takes them (TSRegexFindPattern captureGroupNames).
- (NSArray<NSString *> *)captureGroupNamesInString:(NSString *)string;
@end

/// The replace field (and a rule's replacement) when "Regular expression" is on: group references, escapes, and
/// references to groups that the pattern does not have, in the replacement syntax chosen.
NS_SWIFT_NAME(AdvancedFindReplacementScanner)
@interface TSAdvancedFindReplacementScanner : NSObject <TSSyntaxScanner>
@property (nonatomic, readonly) TSRegexReplacementSyntax syntax;
@property (nonatomic, readonly) TSRegexFindOptions options;
/// NSNotFound when the pattern is invalid: references are then not checked.
@property (nonatomic, readonly) NSUInteger numberOfCaptureGroups;
@property (nonatomic, readonly, copy) NSArray<NSString *> *captureGroupNames;
/// The groups come from the compiled pattern; a nil pattern (an invalid one) checks no reference.
- (instancetype)initWithSyntax:(TSRegexReplacementSyntax)syntax options:(TSRegexFindOptions)options
                       pattern:(nullable TSRegexFindPattern *)pattern NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// The colors of the find and replace fields, in light and dark windows: the regular expression roles have no theme
/// colors, so the panel has its own. Errors are red and underlined, incompatibilities orange with a dotted line.
FOUNDATION_EXPORT TSSyntaxColorScheme *TSAdvancedFindFieldColorScheme(void) NS_SWIFT_NAME(AdvancedFindFieldColorScheme());

/// `string` with the attributes of `scanner`'s tokens over `attributes`, for a cell of the multiple replacement rules.
FOUNDATION_EXPORT NSAttributedString *TSAdvancedFindColoredString(NSString *string, id<TSSyntaxScanner> scanner, TSSyntaxColorScheme *scheme,
                                                                  NSDictionary<NSAttributedStringKey, id> *attributes);

NS_ASSUME_NONNULL_END
