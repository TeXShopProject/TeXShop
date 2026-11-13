// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexFindReplacement.h"

NS_ASSUME_NONNULL_BEGIN

/// The outcome of replacing every match in the scope.
NS_SWIFT_NAME(RegexReplaceAllResult)
@interface TSRegexReplaceAllResult : NSObject

/// One replacement per scope range that changed, in ascending order. Applying them all at once gives the new text.
@property (nonatomic, readonly, copy) NSArray<TSRegexFindReplacement *> *replacements;
/// The scope ranges after the replacement, when the search was limited to the selection; otherwise nil.
@property (nonatomic, readonly, copy, nullable) NSArray<NSValue *> *selectedRanges;
@property (nonatomic, readonly) NSUInteger numberOfMatches;

- (instancetype)initWithReplacements:(NSArray<TSRegexFindReplacement *> *)replacements
                      selectedRanges:(nullable NSArray<NSValue *> *)selectedRanges
                     numberOfMatches:(NSUInteger)numberOfMatches NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
