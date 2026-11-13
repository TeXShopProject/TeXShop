// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexFindOptions.h"

NS_ASSUME_NONNULL_BEGIN

/// A compiled find string. Immutable and independent of any text, view or user defaults.
NS_SWIFT_NAME(RegexFindPattern)
@interface TSRegexFindPattern : NSObject <NSCopying>

/// The find string as the user typed it.
@property (nonatomic, readonly, copy) NSString *findString;
@property (nonatomic, readonly) TSRegexFindOptions options;
@property (nonatomic, readonly, getter=isRegularExpression) BOOL regularExpression;
/// The number of capture groups; 0 for plain text.
@property (nonatomic, readonly) NSUInteger numberOfCaptureGroups;
/// The names of the named groups, in the order they appear in the pattern.
@property (nonatomic, readonly, copy) NSArray<NSString *> *captureGroupNames;

/// Compiles the find string. Fails with TSRegexFindErrorEmptyFindString or TSRegexFindErrorInvalidPattern.
- (nullable instancetype)initWithFindString:(NSString *)findString options:(TSRegexFindOptions)options error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Enumerates the matches that lie entirely in `range`, in ascending order and without overlaps.
/// Text outside `range` is visible to look-around and word checks. `result` is nil for plain text.
/// `isCancelled` is polled during long scans; when it returns YES the enumeration ends early.
- (void)enumerateMatchesInString:(NSString *)string
                           range:(NSRange)range
                    cancellation:(nullable BOOL (NS_NOESCAPE ^)(void))isCancelled
                      usingBlock:(void (NS_NOESCAPE ^)(NSRange matchRange, NSTextCheckingResult *_Nullable result, BOOL *stop))block
    NS_SWIFT_NAME(enumerateMatches(in:range:isCancelled:using:));

/// Converts yen signs to backslashes when the options ask for it.
+ (NSString *)normalizedString:(NSString *)string options:(TSRegexFindOptions)options;

@end

NS_ASSUME_NONNULL_END
