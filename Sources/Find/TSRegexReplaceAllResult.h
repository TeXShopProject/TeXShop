// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexFindReplacement.h"

NS_ASSUME_NONNULL_BEGIN

/// One match whose replacement has a different length, in the original text. Matches that keep their length are left
/// out. In ascending order and without overlaps, so a location can be followed through the whole replacement.
typedef struct {
    NSUInteger location;
    NSUInteger length;
    NSInteger delta;
} TSRegexMatchEdit;

/// The outcome of replacing every match in the scope.
NS_SWIFT_NAME(RegexReplaceAllResult)
@interface TSRegexReplaceAllResult : NSObject

/// One replacement per scope range that changed, in ascending order. Applying them all at once gives the new text.
@property (nonatomic, readonly, copy) NSArray<TSRegexFindReplacement *> *replacements;
/// The scope ranges after the replacement, when the search was limited to the selection; otherwise nil.
@property (nonatomic, readonly, copy, nullable) NSArray<NSValue *> *selectedRanges;
@property (nonatomic, readonly) NSUInteger numberOfMatches;
/// `TSRegexMatchEdit` records, packed. Empty when every match kept its length.
@property (nonatomic, readonly, copy) NSData *matchEdits;

- (instancetype)initWithReplacements:(NSArray<TSRegexFindReplacement *> *)replacements
                      selectedRanges:(nullable NSArray<NSValue *> *)selectedRanges
                     numberOfMatches:(NSUInteger)numberOfMatches
                          matchEdits:(NSData *)matchEdits NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Where `location` is after the length changes. A location on the first character of a match stays at the start of
/// what replaced it; one further inside the match goes to the end of that replacement, since the matched text is gone.
- (NSUInteger)locationByFollowingEdits:(NSUInteger)location;

@end

NS_ASSUME_NONNULL_END
