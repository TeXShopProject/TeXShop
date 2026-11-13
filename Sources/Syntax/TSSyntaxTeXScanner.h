// SPDX-License-Identifier: GPL-2.0-or-later
// TeX, and XML such as PreTeXt, as the source window colors them (layer 1).
#import "TSSyntaxScanner.h"
#import "TSSyntaxTeXOptions.h"

NS_ASSUME_NONNULL_BEGIN

/// Commands, comments, $ and &, the three kinds of brackets, the arguments of \index and \footnote, expl3 names,
/// fullwidth symbols, and the ranges left out of spell checking. Works line by line: a range to scan starts and ends
/// at line boundaries, and nothing is carried from one call to the next.
NS_SWIFT_NAME(SyntaxTeXScanner)
@interface TSSyntaxTeXScanner : NSObject <TSSyntaxScanner>
@property (nonatomic, readonly, copy) TSSyntaxTeXOptions *options;
- (instancetype)initWithOptions:(TSSyntaxTeXOptions *)options NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// Fullwidth letters, digits and symbols, which are easily mistaken for ASCII: U+FF01-U+FF0B, U+FF0D, U+FF0F-U+FF5D
/// and U+2212 (the minus sign). The fullwidth comma and full stop are ordinary Japanese punctuation.
static inline BOOL TSIsHighlightedFullwidthCharacter(unichar c)
{
    return (c >= 0xFF01 && c <= 0xFF0B) || c == 0xFF0D || (c >= 0xFF0F && c <= 0xFF5D) || c == 0x2212;
}

NS_ASSUME_NONNULL_END
