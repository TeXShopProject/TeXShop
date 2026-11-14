// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// One input field of the panel: a rounded box with the history menu at the leading edge (an icon with a chevron),
/// the multi-line text in the middle, and a short status ("3 of 12", "Not found") and a clear button at the
/// trailing edge. The box takes all the height it is given, and draws a focus ring while its text view is active.
NS_SWIFT_NAME(AdvancedFindInputBox)
@interface TSAdvancedFindInputBox : NSView

@property (nonatomic, readonly) NSTextView *textView;
@property (nonatomic, readonly) NSButton *historyButton;
@property (nonatomic, readonly) NSButton *clearButton;
@property (nonatomic, readonly) NSTextField *statusLabel;
@property (nonatomic, getter=isFocused) BOOL focused;
/// The background inside the border; nil: that of text fields.
@property (nonatomic, strong, nullable) NSColor *fillColor;

/// `symbolName` is the SF Symbol of the history button (magnifyingglass for find, pencil for replace).
- (instancetype)initWithTextView:(NSTextView *)textView symbolName:(NSString *)symbolName
                     historyTitle:(NSString *)historyTitle NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Shows the clear button only when there is text. Call after the text changed.
- (void)textDidChange;

@end

NS_ASSUME_NONNULL_END
