// SPDX-License-Identifier: GPL-2.0-or-later
// Layer 1 of syntax coloring: the protocol of the scanners, which split a text into tokens with roles. Foundation
// only; a scanner knows nothing of views, documents or preferences, and gets its settings as values.
#import <Foundation/Foundation.h>
#import "TSSyntaxRole.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, TSSyntaxTokenFlags) {
    TSSyntaxTokenFlagsNone = 0,
    /// Leave the range out of spell checking.
    TSSyntaxTokenFlagsNoSpellCheck = 1 << 0,
} NS_SWIFT_NAME(SyntaxTokenFlags);

/// A message about part of the text, such as why it is invalid or how it differs from Onigmo.
NS_SWIFT_NAME(SyntaxDiagnostic)
@interface TSSyntaxDiagnostic : NSObject
@property (nonatomic, readonly) NSRange range;
@property (nonatomic, readonly) TSSyntaxRole role;
@property (nonatomic, readonly, copy) NSString *message;
- (instancetype)initWithRange:(NSRange)range role:(TSSyntaxRole)role message:(NSString *)message NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// A token, or a range that only carries flags (role TSSyntaxRoleNone). Tokens may overlap; a later one is shown
/// over an earlier one, so they are applied in the order they come.
typedef void (^TSSyntaxTokenBlock)(NSRange range, TSSyntaxRole role, TSSyntaxTokenFlags flags);

/// Splits a text into tokens. Immutable: one object per grammar and its options.
NS_SWIFT_NAME(SyntaxScanner)
@protocol TSSyntaxScanner <NSObject>
/// The range to scan again after an edit: whole lines for TeX, the whole text for grammars with multi-line structure.
- (NSRange)lineAlignedRangeForEditedRange:(NSRange)range inString:(NSString *)string;
/// The tokens in `range`, which is a range that -lineAlignedRangeForEditedRange:inString: gave. Text that is not a
/// token keeps the plain color.
- (void)enumerateTokensInString:(NSString *)string range:(NSRange)range usingBlock:(NS_NOESCAPE TSSyntaxTokenBlock)block;
@optional
/// Messages for the invalid and incompatible tokens of the whole text.
- (NSArray<TSSyntaxDiagnostic *> *)diagnosticsInString:(NSString *)string;
/// The brackets that pair up, each as the range from the opening bracket to the closing one (both included), in the
/// order of their opening brackets. Only real brackets of the grammar: not escaped ones, nor those in strings or comments.
- (NSArray<NSValue *> *)bracketPairsInString:(NSString *)string;
@end

NS_ASSUME_NONNULL_END
