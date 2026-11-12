// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexFindPattern.h"
#import "TSRegexReplacementTemplate.h"
#import "TSRegexFindReplacement.h"
#import "TSRegexReplaceAllResult.h"

NS_ASSUME_NONNULL_BEGIN

/// One search over a snapshot of a text. Pure computation: it never touches a view, so it can run on any thread.
NS_SWIFT_NAME(RegexTextFind)
@interface TSRegexTextFind : NSObject

@property (nonatomic, readonly, copy) NSString *string;
@property (nonatomic, readonly) TSRegexFindPattern *pattern;
@property (nonatomic, readonly, copy) NSArray<NSValue *> *selectedRanges;
@property (nonatomic, readonly, getter=isInSelection) BOOL inSelection;
/// The ranges searched: the selected ranges in selection mode, otherwise the whole text.
@property (nonatomic, readonly, copy) NSArray<NSValue *> *scopeRanges;

/// Fails with TSRegexFindErrorEmptySelection when searching in a selection that is empty.
- (nullable instancetype)initWithString:(NSString *)string
                                pattern:(TSRegexFindPattern *)pattern
                         selectedRanges:(NSArray<NSValue *> *)selectedRanges
                            inSelection:(BOOL)inSelection
                                  error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// All matches in the scope in ascending order, or nil when cancelled.
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

/// Replaces every match in the scope. Returns nil when cancelled.
- (nullable TSRegexReplaceAllResult *)replaceAllWithTemplate:(TSRegexReplacementTemplate *)replacementTemplate
                                                cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
    NS_SWIFT_NAME(replaceAll(template:isCancelled:));

@end

NS_ASSUME_NONNULL_END
