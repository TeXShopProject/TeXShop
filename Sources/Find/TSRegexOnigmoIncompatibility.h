// SPDX-License-Identifier: GPL-2.0-or-later
// What OgreKit (Onigmo) users meet in ICU: the one table that the regular expression cheat sheet, the marks of the
// find field and the tests all read. Foundation only.
#import <Foundation/Foundation.h>
#import "TSRegexFindPattern.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TSRegexOnigmoIncompatibilityKind) {
    // Marked in the find field: written as in OgreKit, they mean something else in ICU, or nothing
    TSRegexOnigmoIncompatibilityHexDigit,        // \h \H
    TSRegexOnigmoIncompatibilityMultiline,       // (?m)
    TSRegexOnigmoIncompatibilityPossessive,      // {n}+
    TSRegexOnigmoIncompatibilityKeep,            // \K
    TSRegexOnigmoIncompatibilityCall,            // \g<name>
    TSRegexOnigmoIncompatibilityAbsent,          // (?~…)
    TSRegexOnigmoIncompatibilityLiteralBrace,    // { } (an error in ICU)
    // Explained in the cheat sheet only: common, and not wrong
    TSRegexOnigmoIncompatibilityUnicodeClasses,  // \d \w \s \b
    TSRegexOnigmoIncompatibilityNamedNumbers,    // (?<name>…) has a number
    TSRegexOnigmoIncompatibilityNegatedProperty, // \p{^…} (an error in ICU)
} NS_SWIFT_NAME(RegexOnigmoIncompatibility.Kind);

/// One difference between OgreKit's regular expressions and ICU's. Immutable.
NS_SWIFT_NAME(RegexOnigmoIncompatibility)
@interface TSRegexOnigmoIncompatibility : NSObject
@property (nonatomic, readonly) TSRegexOnigmoIncompatibilityKind kind;
/// How it is written, as the cheat sheet shows it ("\h", "(?m)").
@property (nonatomic, readonly, copy) NSString *term;
/// YES when the find field marks it; the others are only explained.
@property (nonatomic, readonly, getter=isMarked) BOOL marked;
/// The explanation, in the user's language (AdvancedFindEngine.strings).
@property (nonatomic, readonly, copy) NSString *message;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface TSRegexFindPattern (OnigmoIncompatibilities)
/// Every difference from OgreKit, in the order the cheat sheet lists them: the everyday ones first.
@property (class, nonatomic, readonly, copy) NSArray<TSRegexOnigmoIncompatibility *> *onigmoIncompatibilities;
+ (TSRegexOnigmoIncompatibility *)onigmoIncompatibilityOfKind:(TSRegexOnigmoIncompatibilityKind)kind NS_SWIFT_NAME(onigmoIncompatibility(of:));
@end

NS_ASSUME_NONNULL_END
