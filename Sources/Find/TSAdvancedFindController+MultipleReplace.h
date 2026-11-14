// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindController.h"
#import "TSRegexMultipleReplace.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSAdvancedFindController (MultipleReplace)

/// Applies the enabled rules in order to the whole text or the selection, as one undo step, as a background task
/// (`runningTask`) with a progress sheet. Only the part of the text that changed is replaced, so the rest keeps its
/// attributes. Returns NO (and beeps) when the text view takes no replacing or another task runs; otherwise YES, and
/// `completion` later gets the result, also when nothing was replaced (then it beeps and the text is not touched),
/// or nil when the task was cancelled or the text changed meanwhile.
- (BOOL)applyMultipleReplace:(TSRegexMultipleReplace *)set
                  inTextView:(NSTextView *)textView
                 inSelection:(BOOL)inSelection
                  completion:(nullable void (^)(TSRegexMultipleReplaceResult *_Nullable result))completion;

/// Highlights what the enabled rules match in the unchanged text. Returns the number of matches.
- (NSUInteger)highlightMultipleReplace:(TSRegexMultipleReplace *)set inTextView:(NSTextView *)textView inSelection:(BOOL)inSelection;

@end

NS_ASSUME_NONNULL_END
