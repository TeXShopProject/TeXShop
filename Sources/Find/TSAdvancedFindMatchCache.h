// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// The matches last found in one text storage, so "Next" and "Highlight" do not search the whole
/// text again while neither the text nor the search changed. Any edit of the characters (typing, Undo, a replacement,
/// another view of a split window) clears it and counts up `version`. Each text storage has its own.
NS_SWIFT_NAME(AdvancedFindMatchCache)
@interface TSAdvancedFindMatchCache : NSObject

+ (instancetype)cacheForTextStorage:(NSTextStorage *)storage;

/// Counts the edits of the characters; a background task checks it before applying its result.
@property (nonatomic, readonly) NSUInteger version;
/// How many times a lookup found its matches here (for the self test).
@property (nonatomic, readonly) NSUInteger hits;

/// `key` names the search: the pattern, its options, the line ending and the scope.
- (nullable NSArray<NSValue *> *)matchesForKey:(NSString *)key;
/// Keeps the matches of the last few searches.
- (void)setMatches:(NSArray<NSValue *> *)matches forKey:(NSString *)key;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
