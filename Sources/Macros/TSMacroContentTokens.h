// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSAdvancedFindTextView.h"
#import "TSTextView.h"
NS_ASSUME_NONNULL_BEGIN

// The contents of a macro show its placeholders as tokens, as the key binding
// list of Settings › Keyboard does: the occurrences that the macro replaces
// (TSSyntaxMacroContentScanner) are drawn as one rounded pill each, with what
// they stand for. The text itself keeps them as they are written (#SEL#,
// #FILEPATH#…), so saving, copying, undo and Find work on the text as before;
// a placeholder typed or pasted becomes a token as soon as it is complete.

/// Lays out each token as one glyph as wide as its pill, and draws the pill.
@interface TSMacroContentLayoutManager : TSAdvancedFindLayoutManager <NSLayoutManagerDelegate>
/// The character ranges shown as tokens, in order.
@property (nonatomic, readonly, copy) NSArray<NSValue *> *tokenRanges;
/// The token that contains the character at `index`, or NSNotFound.
- (NSRange)tokenRangeContainingIndex:(NSUInteger)index;
/// The title shown in the token of a character range from tokenRanges.
- (NSString *)titleOfTokenRange:(NSRange)range;
@end

/// Moving with the keyboard or selecting with the mouse goes by whole tokens, and deleting next to a token deletes all
/// of it. Ranges that Find, undo or the editor set stay exact.
@interface TSMacroContentTextView : TSTextView
@end

NS_ASSUME_NONNULL_END
