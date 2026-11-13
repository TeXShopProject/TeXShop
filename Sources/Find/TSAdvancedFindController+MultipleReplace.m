// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindController+MultipleReplace.h"
#import "TSAdvancedFindHighlights.h"

#define TSLocalized TSAdvancedFindLocalized

/// The part of `old` that differs from `new`: the common beginning and end are left out.
static void TSChangedRange(NSString *old, NSString *new, NSRange *oldRange, NSRange *newRange)
{
    NSUInteger oldLength = old.length, newLength = new.length, limit = MIN(oldLength, newLength);
    NSUInteger prefix = 0, suffix = 0;
    while (prefix < limit && [old characterAtIndex:prefix] == [new characterAtIndex:prefix])
        prefix++;
    while (suffix < limit - prefix && [old characterAtIndex:oldLength - 1 - suffix] == [new characterAtIndex:newLength - 1 - suffix])
        suffix++;
    // Do not split a surrogate pair or a CRLF at either edge.
    while (prefix > 0 && (CFStringIsSurrogateHighCharacter([old characterAtIndex:prefix - 1]) || [old characterAtIndex:prefix - 1] == '\r'))
        prefix--;
    while (suffix > 0 && (CFStringIsSurrogateLowCharacter([old characterAtIndex:oldLength - suffix]) || [old characterAtIndex:oldLength - suffix] == '\n'))
        suffix--;
    *oldRange = NSMakeRange(prefix, oldLength - prefix - suffix);
    *newRange = NSMakeRange(prefix, newLength - prefix - suffix);
}

/// The results are not sent to the status handler (the find panel's): the multiple replacement window shows its own.
@implementation TSAdvancedFindController (MultipleReplace)

- (nullable TSRegexMultipleReplaceResult *)applyMultipleReplace:(TSRegexMultipleReplace *)set inTextView:(NSTextView *)textView
                                                    inSelection:(BOOL)inSelection
{
    if (![self validateAction:TSAdvancedFindActionReplaceAll forTextView:textView]) {
        self.beepHandler();
        return nil;
    }
    NSString *lineEnding = self.lineEndingHandler ? self.lineEndingHandler(textView) : nil;
    NSString *old = [textView.string copy];
    TSRegexMultipleReplaceResult *result = [set applyToString:old selectedRanges:textView.selectedRanges inSelection:inSelection
                                                   lineEnding:lineEnding cancellation:nil];
    if (result)
        [self applyMultipleReplaceResult:result to:textView old:old];
    return result;
}

/// Replaces only the part of the text that changed, as one undo step.
- (void)applyMultipleReplaceResult:(TSRegexMultipleReplaceResult *)result to:(NSTextView *)textView old:(NSString *)old
{
    if (result.totalCount == 0 || [result.string isEqualToString:old]) {
        self.beepHandler();
        return;
    }
    NSRange oldRange, newRange;
    TSChangedRange(old, result.string, &oldRange, &newRange);
    NSString *replacement = [result.string substringWithRange:newRange];
    [textView breakUndoCoalescing];
    if (![textView shouldChangeTextInRange:oldRange replacementString:replacement])
        return;
    [textView.textStorage replaceCharactersInRange:oldRange withString:replacement];
    [textView didChangeText];
    [textView.undoManager setActionName:TSLocalized(@"MultipleReplace.Action", @"Multiple Replace")];
    if (result.selectedRanges.count > 0)
        textView.selectedRanges = (NSArray<NSValue *> *_Nonnull)result.selectedRanges;
}

- (NSUInteger)highlightMultipleReplace:(TSRegexMultipleReplace *)set inTextView:(NSTextView *)textView inSelection:(BOOL)inSelection
{
    NSString *lineEnding = self.lineEndingHandler ? self.lineEndingHandler(textView) : nil;
    NSArray<NSValue *> *matches = [set matchRangesInString:textView.string selectedRanges:textView.selectedRanges
                                               inSelection:inSelection lineEnding:lineEnding cancellation:nil] ?: @[];
    NSArray<NSValue *> *sorted = [matches sortedArrayUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        NSUInteger x = a.rangeValue.location, y = b.rangeValue.location;
        return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
    }];
    NSTextStorage *storage = textView.textStorage;
    if (storage)
        [TSAdvancedFindHighlights highlightsForTextStorage:storage].ranges = sorted;
    if (sorted.count == 0)
        self.beepHandler();
    return sorted.count;
}

@end
