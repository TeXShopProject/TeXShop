// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexReplacementRule.h"

NS_ASSUME_NONNULL_BEGIN

/// The outcome of applying a list of rules.
NS_SWIFT_NAME(RegexMultipleReplaceResult)
@interface TSRegexMultipleReplaceResult : NSObject
@property (nonatomic, readonly, copy) NSString *string;
/// The scope after all rules, when they were applied to the selection; otherwise nil.
@property (nonatomic, readonly, copy, nullable) NSArray<NSValue *> *selectedRanges;
/// Matches replaced by each rule, in the order of the rules; 0 for a disabled or invalid rule.
@property (nonatomic, readonly, copy) NSArray<NSNumber *> *counts;
/// Errors of rules whose find string is empty or invalid, keyed by the rule's index.
@property (nonatomic, readonly, copy) NSDictionary<NSNumber *, NSError *> *errors;
@property (nonatomic, readonly) NSUInteger totalCount;
- (instancetype)initWithString:(NSString *)string selectedRanges:(nullable NSArray<NSValue *> *)selectedRanges
                        counts:(NSArray<NSNumber *> *)counts errors:(NSDictionary<NSNumber *, NSError *> *)errors NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// Applies the enabled rules one after another; each rule works on the result of the previous one.
NS_SWIFT_NAME(RegexMultipleReplace)
@interface TSRegexMultipleReplace : NSObject

/// The yen sign setting of the panel applies to every rule.
+ (nullable TSRegexMultipleReplaceResult *)applyRules:(NSArray<TSRegexReplacementRule *> *)rules
                                             toString:(NSString *)string
                                       selectedRanges:(NSArray<NSValue *> *)selectedRanges
                                          inSelection:(BOOL)inSelection
                                     sharedOptions:(TSRegexFindOptions)sharedOptions
                                         cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
    NS_SWIFT_NAME(apply(_:to:selectedRanges:inSelection:sharedOptions:isCancelled:));

@end

NS_ASSUME_NONNULL_END
