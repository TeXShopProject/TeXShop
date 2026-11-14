// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN

// Placeholders shown as tokens: rounded pills with a title, in the key binding
// list of Settings › Keyboard and in the contents of the macro editor. The text
// keeps the placeholder as it is written (#SEL#, #FILEPATH#…); only its display
// is a token.

/// What a placeholder stands for: #SEL#, #INS#, #PASTE#, a line break, a tab and the mark • (key bindings and TeX
/// macros), and the paths and the name that an AppleScript macro is given (#FILEPATH# and the others).
NSString *TSPlaceholderTokenTitle(NSString *symbol);

/// The size of the token of `title` in text of `font`.
NSSize TSPlaceholderTokenSize(NSString *title, NSFont *font);

/// Draws the token of `title` for text of `font` into `rect` (as large as TSPlaceholderTokenSize).
void TSDrawPlaceholderToken(NSString *title, NSFont *font, NSRect rect);

/// The token of `title` as an image, for an attachment or a label.
NSImage *TSPlaceholderTokenImage(NSString *title, NSFont *font);

NS_ASSUME_NONNULL_END
