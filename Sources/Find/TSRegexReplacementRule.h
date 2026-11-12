// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
#import "TSRegexFindOptions.h"
#import "TSRegexReplacementTemplate.h"

NS_ASSUME_NONNULL_BEGIN

/// One find-and-replace pair of a multiple replacement. Immutable; stored as a property list dictionary.
NS_SWIFT_NAME(RegexReplacementRule)
@interface TSRegexReplacementRule : NSObject <NSCopying>

@property (nonatomic, readonly, copy) NSString *findString;
@property (nonatomic, readonly, copy) NSString *replaceString;
/// Only the options of the pattern itself (regular expression, case, word, width...); the scope is the set's.
@property (nonatomic, readonly) TSRegexFindOptions options;
/// Each rule keeps its own syntax, so that a saved list means the same thing to everyone.
@property (nonatomic, readonly) TSRegexReplacementSyntax replacementSyntax;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
/// A free comment shown in the list.
@property (nonatomic, readonly, copy) NSString *note;

- (instancetype)initWithFindString:(NSString *)findString
                     replaceString:(NSString *)replaceString
                           options:(TSRegexFindOptions)options
                 replacementSyntax:(TSRegexReplacementSyntax)replacementSyntax
                           enabled:(BOOL)enabled
                              note:(NSString *)note NS_DESIGNATED_INITIALIZER;
/// Reads a dictionary written by dictionaryRepresentation; nil if the find string is missing.
/// A missing or unknown syntax reads as ICU.
- (nullable instancetype)initWithDictionary:(NSDictionary<NSString *, id> *)dictionary;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
