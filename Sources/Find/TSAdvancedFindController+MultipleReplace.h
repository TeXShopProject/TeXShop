// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindController.h"
#import "TSRegexMultipleReplace.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSAdvancedFindController (MultipleReplace)

/// Applies the enabled rules in order to the whole text or the selection, as one undo step. Only the part of the
/// text that changed is replaced, so the rest keeps its attributes. Returns nil (and beeps) when the text view takes
/// no replacing; otherwise the result, also when nothing was replaced (then it beeps and the text is not touched).
- (nullable TSRegexMultipleReplaceResult *)applyMultipleReplace:(TSRegexMultipleReplace *)set
                                                     inTextView:(NSTextView *)textView
                                                    inSelection:(BOOL)inSelection;

/// Highlights what the enabled rules match in the unchanged text. Returns the number of matches.
- (NSUInteger)highlightMultipleReplace:(TSRegexMultipleReplace *)set inTextView:(NSTextView *)textView inSelection:(BOOL)inSelection;

@end

NS_ASSUME_NONNULL_END
