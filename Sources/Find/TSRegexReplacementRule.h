// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One find-and-replace pair of a multiple replacement, as CotEditor has it: the options other than these two
/// belong to the whole set. Immutable.
NS_SWIFT_NAME(RegexReplacementRule)
@interface TSRegexReplacementRule : NSObject <NSCopying>

@property (nonatomic, readonly, copy) NSString *findString;
@property (nonatomic, readonly, copy) NSString *replaceString;
@property (nonatomic, readonly) BOOL usesRegularExpression;
@property (nonatomic, readonly) BOOL ignoresCase;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
/// A free comment shown in the list; nil when there is none.
@property (nonatomic, readonly, copy, nullable) NSString *note;

- (instancetype)initWithFindString:(NSString *)findString
                     replaceString:(NSString *)replaceString
             usesRegularExpression:(BOOL)usesRegularExpression
                       ignoresCase:(BOOL)ignoresCase
                           enabled:(BOOL)enabled
                              note:(nullable NSString *)note NS_DESIGNATED_INITIALIZER;

/// Reads one element of the `replacements` array of a CotEditor replacement definition (`.cotrpl`):
/// `findString` and `replacementString` are required; `usesRegularExpression` and `ignoresCase` default to NO,
/// `isEnabled` to YES. Returns nil when a required value is missing or a value has the wrong type.
- (nullable instancetype)initWithJSONObject:(NSDictionary<NSString *, id> *)object;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// The element written as CotEditor writes it: default values are left out.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *JSONObject;

@end

NS_ASSUME_NONNULL_END
