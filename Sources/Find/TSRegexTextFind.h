// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexFindPattern.h"
#import "TSRegexReplacementTemplate.h"
#import "TSRegexFindReplacement.h"
#import "TSRegexReplaceAllResult.h"

NS_ASSUME_NONNULL_BEGIN

/// One search over a snapshot of a text. Pure computation: it never touches a view, so it can run on any thread.
/// The string with every CRLF, CR, LF, NEL, line separator and paragraph separator replaced by the line ending.
/// The find string and the replaced text are put into the document's line ending with it, as in CotEditor.
FOUNDATION_EXPORT NSString *TSRegexStringByReplacingLineEndings(NSString *string, NSString *lineEnding);

NS_SWIFT_NAME(RegexTextFind)
@interface TSRegexTextFind : NSObject

@property (nonatomic, readonly, copy) NSString *string;
@property (nonatomic, readonly) TSRegexFindPattern *pattern;
@property (nonatomic, readonly, copy) NSArray<NSValue *> *selectedRanges;
@property (nonatomic, readonly, getter=isInSelection) BOOL inSelection;
/// The ranges searched: the selected ranges in selection mode, otherwise the whole text.
@property (nonatomic, readonly, copy) NSArray<NSValue *> *scopeRanges;

/// The line ending put into replaced text (as CotEditor does with the document's line ending), or nil to keep
/// the line endings the replacement gives.
@property (nonatomic, readonly, copy, nullable) NSString *lineEnding;
/// Fails with TSRegexFindErrorEmptySelection when searching in a selection that is empty.
- (nullable instancetype)initWithString:(NSString *)string
                                pattern:(TSRegexFindPattern *)pattern
                             lineEnding:(nullable NSString *)lineEnding
                         selectedRanges:(NSArray<NSValue *> *)selectedRanges
                            inSelection:(BOOL)inSelection
                                  error:(NSError **)error NS_DESIGNATED_INITIALIZER;
/// Keeps the line endings of the replacements.
- (nullable instancetype)initWithString:(NSString *)string
                                pattern:(TSRegexFindPattern *)pattern
                         selectedRanges:(NSArray<NSValue *> *)selectedRanges
                            inSelection:(BOOL)inSelection
                                  error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// All matches in the scope in ascending order, or nil when cancelled: once `isCancelled` has returned YES.
- (nullable NSArray<NSValue *> *)matchRangesWithCancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
    NS_SWIFT_NAME(matchRanges(isCancelled:));

/// Every match with its groups: element 0 is the match, element k is group k ({NSNotFound, 0} if it did not take part).
- (void)enumerateMatchesWithCancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
                              usingBlock:(void (NS_NOESCAPE ^)(NSArray<NSValue *> *ranges, BOOL *stop))block
    NS_SWIFT_NAME(enumerateMatches(isCancelled:using:));

/// The match to select next, starting from the first selected range.
/// `includingSelection` lets a match at the selection itself count (incremental search).
/// Returns {NSNotFound, 0} when there is none. `wrapped` tells whether the search went around the end.
- (NSRange)nextMatchInRanges:(NSArray<NSValue *> *)matches
                     forward:(BOOL)forward
          includingSelection:(BOOL)includingSelection
                       wraps:(BOOL)wraps
                     wrapped:(nullable BOOL *)wrapped
    NS_SWIFT_NAME(nextMatch(in:forward:includingSelection:wraps:wrapped:));

/// The replacement for the first match inside the first selected range, or nil if it contains none.
- (nullable TSRegexFindReplacement *)replacementInSelectionWithTemplate:(TSRegexReplacementTemplate *)replacementTemplate
    NS_SWIFT_NAME(replacementInSelection(template:));

/// Replaces every match in the scope. Returns nil when cancelled: once `isCancelled` has returned YES.
- (nullable TSRegexReplaceAllResult *)replaceAllWithTemplate:(TSRegexReplacementTemplate *)replacementTemplate
                                                cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
    NS_SWIFT_NAME(replaceAll(template:isCancelled:));

/// Replaces every match in the scope, telling `progress` on the calling thread how much of the scope has been
/// searched (0 to 1) and how many matches have been found: after every 256 matches, at the end of each scope range,
/// and last with 1. The fraction never goes down. Nothing is reported once `isCancelled` has returned YES.
/// Returns nil when cancelled: once `isCancelled` has returned YES.
- (nullable TSRegexReplaceAllResult *)replaceAllWithTemplate:(TSRegexReplacementTemplate *)replacementTemplate
                                                cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
                                                    progress:(nullable void (NS_NOESCAPE ^)(double fractionCompleted, NSUInteger numberOfMatches))progress
    NS_SWIFT_NAME(replaceAll(template:isCancelled:progress:));

@end

NS_ASSUME_NONNULL_END
