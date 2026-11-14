// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN

/// The shortcut of a macro, set as in Settings > Keyboard: a click on the field and the
/// keys pressed set it; ⊗ in the field (or Delete while it waits) removes it; Escape
/// keeps it as it was. The owner turns a key press into a shortcut (recordEvent) and
/// says what the field shows (shortcut).
@interface TSMacroShortcutField : NSView

/// The field looks like the text field it is given (its bezel and font).
- (instancetype)initWithFrame:(NSRect)frame model:(nullable NSTextField *)model
                  placeholder:(NSString *)placeholder clearTitle:(NSString *)clearTitle NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, readonly) NSTextField *display;
@property (nonatomic, readonly) NSButton *clearButton;
/// The shortcut as it is shown, for example ⇧⌘M; empty when there is none.
@property (nonatomic, copy) NSString *shortcut;
@property (nonatomic, getter=isEnabled) BOOL enabled;
/// From a click (or the keyboard) until a shortcut is set, Escape, or another control.
@property (nonatomic, readonly, getter=isRecording) BOOL recording;
/// A key pressed while the field waits: YES when it became the shortcut; NO beeps and waits on.
@property (nonatomic, copy, nullable) BOOL (^recordEvent)(NSEvent *event);
/// ⊗, or Delete while the field waits.
@property (nonatomic, copy, nullable) dispatch_block_t clearShortcut;

/// The width that shows the waiting text and ⊗ side by side.
@property (nonatomic, readonly) CGFloat minimumWidth;

- (void)beginRecording;
- (void)endRecording;

@end

NS_ASSUME_NONNULL_END
