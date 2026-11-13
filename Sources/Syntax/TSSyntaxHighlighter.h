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
/// nil: no coloring. Setting it, or the scheme, colors the whole text again when the highlighter follows edits.
@property (nonatomic, strong, nullable) id<TSSyntaxScanner> scanner;
@property (nonatomic, strong, nullable) TSSyntaxColorScheme *scheme;

- (instancetype)initWithTextView:(NSTextView *)textView scanner:(nullable id<TSSyntaxScanner>)scanner
                          scheme:(nullable TSSyntaxColorScheme *)scheme NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Adds the colors of the tokens in range, a range that the scanner's -lineAlignedRangeForEditedRange:inString:
/// gave, and leaves the ranges flagged so out of spell checking. Removes nothing: the caller has cleared the range
/// as it needs, which for the source is every foreground color.
- (void)applyTokensInRange:(NSRange)range;

/// For short texts, such as the contents of a macro: colors the whole text now, and again after every edit,
/// including a new string, removing only the attributes it added itself, so that other features keep theirs. While
/// text is being composed with an input method, it waits, and colors once the text is committed or removed.
- (void)followEdits;
/// Colors the whole text again now, or once composing ends.
- (void)highlightWholeText;
/// Removes the attributes this highlighter added and stops following edits.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
