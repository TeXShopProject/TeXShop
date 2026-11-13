// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexFindOptions.h"
#import "TSRegexReplacementRule.h"
#import "TSRegexReplacementTemplate.h"

NS_ASSUME_NONNULL_BEGIN

/// The outcome of applying a multiple replacement.
NS_SWIFT_NAME(RegexMultipleReplaceResult)
@interface TSRegexMultipleReplaceResult : NSObject
@property (nonatomic, readonly, copy) NSString *string;
/// The scope after all rules, when they were applied to the selection; otherwise nil.
@property (nonatomic, readonly, copy, nullable) NSArray<NSValue *> *selectedRanges;
/// Matches replaced by each rule, in the order of the rules; 0 for a disabled or skipped rule.
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *counts;
/// Why enabled rules were skipped (an empty or invalid find string, or an empty selection), keyed by the rule's index.
@property (nonatomic, readonly, copy) NSDictionary<NSNumber *, NSError *> *errors;
@property (nonatomic, readonly) NSUInteger totalCount;
- (instancetype)initWithString:(NSString *)string selectedRanges:(nullable NSArray<NSValue *> *)selectedRanges
                        counts:(NSArray<NSNumber *> *)counts errors:(NSDictionary<NSNumber *, NSError *> *)errors NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// A set of rules applied one after another, each to the result of the previous one, with the options of the whole
/// set, as CotEditor's multiple replacement does. It reads and writes CotEditor's replacement definitions (`.cotrpl`);
/// TeXShop's own options are kept in keys that CotEditor ignores. Immutable.
NS_SWIFT_NAME(RegexMultipleReplace)
@interface TSRegexMultipleReplace : NSObject <NSCopying>

@property (nonatomic, readonly, copy) NSArray<TSRegexReplacementRule *> *rules;
/// Options of the rules that are not regular expressions: case, literal, diacritics, width, whole word,
/// and TeXShop's words separated by whitespace and yen sign.
@property (nonatomic, readonly) TSRegexFindOptions textualOptions;
/// Options of the regular expression rules: every NSRegularExpression option (case, comments, literal pattern, dot,
/// anchors, Unix line separators, Unicode word boundaries), unescaping the replacement string, and TeXShop's empty
/// matches and yen sign.
@property (nonatomic, readonly) TSRegexFindOptions regularExpressionOptions;
@property (nonatomic, readonly) TSRegexReplacementSyntax replacementSyntax;

/// CotEditor's defaults for a new set: anchors match lines and the replacement string is unescaped. A new set made
/// in TeXShop also reads a yen sign as a backslash, as the panel does.
+ (TSRegexFindOptions)defaultTextualOptions;
+ (TSRegexFindOptions)defaultRegularExpressionOptions;

/// Options outside each kind's list are dropped; a rule's own regular expression and case options always win.
- (instancetype)initWithRules:(NSArray<TSRegexReplacementRule *> *)rules
               textualOptions:(TSRegexFindOptions)textualOptions
     regularExpressionOptions:(TSRegexFindOptions)regularExpressionOptions
            replacementSyntax:(TSRegexReplacementSyntax)replacementSyntax NS_DESIGNATED_INITIALIZER;

/// Reads a replacement definition written by CotEditor or by TeXShop. Fails, as CotEditor does, when the
/// structure or a required value is missing or has the wrong type. Comparison options that the panel does not show
/// are ignored, and are not written again.
- (nullable instancetype)initWithJSONData:(NSData *)data error:(NSError **)error;
/// Reads lines of `find<TAB>replacement` as CotEditor does: other columns are ignored, and a line without a tab
/// or with an empty find string is skipped. The set has CotEditor's defaults.
- (instancetype)initWithTabSeparatedText:(NSString *)text;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The definition as CotEditor writes it (pretty printed, sorted keys, slashes not escaped).
@property (nonatomic, readonly, copy) NSData *JSONData;

/// The pattern options of a rule: the set's options of its kind, with the rule's own regular expression and case.
- (TSRegexFindOptions)optionsForRule:(TSRegexReplacementRule *)rule;

/// Applies the enabled rules in order; a rule that cannot be used is skipped. The find strings and the replaced
/// text are put into the line ending when one is given. Returns nil when cancelled.
- (nullable TSRegexMultipleReplaceResult *)applyToString:(NSString *)string
                                          selectedRanges:(NSArray<NSValue *> *)selectedRanges
                                             inSelection:(BOOL)inSelection
                                              lineEnding:(nullable NSString *)lineEnding
                                            cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
    NS_SWIFT_NAME(apply(to:selectedRanges:inSelection:lineEnding:isCancelled:));

/// The same, telling `progress` on the calling thread which rule is being applied (from 0), the number of rules, and
/// how much of the scope that rule has searched (0 to 1). Every rule, used or not, ends with 1; the reports never go
/// back. Nothing is reported once `isCancelled` has returned YES.
- (nullable TSRegexMultipleReplaceResult *)applyToString:(NSString *)string
                                          selectedRanges:(NSArray<NSValue *> *)selectedRanges
                                             inSelection:(BOOL)inSelection
                                              lineEnding:(nullable NSString *)lineEnding
                                            cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
                                                progress:(nullable void (NS_NOESCAPE ^)(NSUInteger ruleIndex, NSUInteger ruleCount, double fractionCompleted))progress
    NS_SWIFT_NAME(apply(to:selectedRanges:inSelection:lineEnding:isCancelled:progress:));

/// The matches of every enabled rule in the unchanged string, rule after rule (for highlighting). Nil when cancelled.
- (nullable NSArray<NSValue *> *)matchRangesInString:(NSString *)string
                                      selectedRanges:(NSArray<NSValue *> *)selectedRanges
                                         inSelection:(BOOL)inSelection
                                          lineEnding:(nullable NSString *)lineEnding
                                        cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
    NS_SWIFT_NAME(matchRanges(in:selectedRanges:inSelection:lineEnding:isCancelled:));

@end

NS_ASSUME_NONNULL_END
