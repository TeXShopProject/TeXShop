// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
// The parts of a shortcut list in which a shortcut is recorded in its own cell, as in Xcode's
// key bindings: Settings › Keyboard (the menu shortcuts) and the list of the macro editor.

// A shortcut in a list; assistive technologies press it to record a new one.
@interface TSShortcutKeyLabel : NSTextField
@property (copy, nullable) void (^press)(NSTextField *label);
@end

// The shortcut cell while it records: a field with the key, selected, and a button that
// removes the shortcut. The owner of the list receives the keys.
@interface TSShortcutKeyRecorder : NSView
@property (readonly) NSTextField *label;
@property (readonly) NSButton *removeButton;
@property (copy, nonatomic) NSString *shortcut;
@property (copy, nullable) dispatch_block_t resigned;
@end

// What a recording row shows in its shortcut cell: the field, and at the cell's trailing edge
// the room for the warning triangle, which shows while a key is refused.
@interface TSShortcutRecordingCell : NSView
@property (readonly) TSShortcutKeyRecorder *recorder;
@property (readonly) NSImageView *warning;
// As wide as the cell has to be for the field to show shortcut with the remove button, and the triangle.
+ (CGFloat)widthForShortcut:(NSString *)shortcut;
@end

// The warning line of the shortcut lists: the yellow triangle and small text in the label color.
NSStackView *TSShortcutWarningLine(NSString *text);
NS_ASSUME_NONNULL_END
