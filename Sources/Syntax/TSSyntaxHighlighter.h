// SPDX-License-Identifier: GPL-2.0-or-later
// Layer 3 of syntax coloring: applies the tokens of a scanner to one text view, with the attributes of a color
// scheme, as temporary attributes of its layout manager (TextKit 1). The text itself is not changed.
#import <AppKit/AppKit.h>
#import "TSSyntaxScanner.h"
#import "TSSyntaxColorScheme.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(SyntaxHighlighter)
@interface TSSyntaxHighlighter : NSObject
@property (nonatomic, readonly, weak) NSTextView *textView;
@property (nonatomic, readonly) id<TSSyntaxScanner> scanner;
@property (nonatomic, readonly) TSSyntaxColorScheme *scheme;

- (instancetype)initWithTextView:(NSTextView *)textView scanner:(id<TSSyntaxScanner>)scanner
                          scheme:(TSSyntaxColorScheme *)scheme NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Adds the colors of the tokens in range, a range that the scanner's -lineAlignedRangeForEditedRange:inString:
/// gave, and leaves the ranges flagged so out of spell checking. Removes nothing: the caller has cleared the range
/// as it needs, which for the source is every foreground color.
- (void)applyTokensInRange:(NSRange)range;

@end

NS_ASSUME_NONNULL_END
