// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSAdvancedFindController.h"
#import "TSAdvancedFindHighlights.h"
#import "TSRegexTextFind.h"
#import "TSAdvancedFindTextView.h"

/// The panel's own strings are in AdvancedFind.strings; the engine's error messages in AdvancedFindEngine.strings.
NSString *TSAdvancedFindLocalized(NSString *key, NSString *english)
{
    return [NSBundle.mainBundle localizedStringForKey:key value:english table:@"AdvancedFind"];
}
#define TSLocalized TSAdvancedFindLocalized

/// A find string that finds `text` as it is with `options`. A regular expression escapes its metacharacters, unless
/// the pattern is read literally already; with spaces and # comments ignored, the white space (with the directional
/// marks ICU skips as well) and # are written as code points, and so is ¥ when it stands for a backslash.
NSString *TSAdvancedFindPatternFindingText(NSString *text, TSRegexFindOptions options)
{
    if (!(options & TSRegexFindRegularExpression) || (options & TSRegexFindIgnoreMetacharacters))
        return text;
    NSString *escaped = [NSRegularExpression escapedPatternForString:text];
    BOOL extended = (options & TSRegexFindAllowCommentsAndWhitespace) != 0;
    BOOL yen = (options & TSRegexFindYenIsBackslash) != 0;
    if (!extended && !yen)
        return escaped;
    // What ICU skips in such a pattern (Pattern_White_Space): Foundation's white space and line breaks, and the
    // left-to-right and right-to-left marks.
    NSMutableCharacterSet *whitespace = [NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];
    [whitespace addCharactersInString:@"\u200E\u200F"];
    NSMutableString *result = [NSMutableString stringWithCapacity:escaped.length];
    for (NSUInteger i = 0; i < escaped.length; i++) {
        unichar c = [escaped characterAtIndex:i];
        if ((extended && (c == '#' || [whitespace characterIsMember:c])) || (yen && c == 0x00A5))
            [result appendFormat:@"\\x{%X}", (unsigned)c];
        else
            CFStringAppendCharacters((__bridge CFMutableStringRef)result, &c, 1); // one unit: a surrogate stays whole
    }
    return result;
}

@implementation TSAdvancedFindController

+ (TSAdvancedFindController *)sharedController
{
    static TSAdvancedFindController *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        TSAdvancedFindSettings *settings = [[TSAdvancedFindSettings alloc] initWithDefaults:NSUserDefaults.standardUserDefaults
                                                                        findPasteboard:[NSPasteboard pasteboardWithName:NSPasteboardNameFind]];
        shared = [[TSAdvancedFindController alloc] initWithSettings:settings];
    });
    return shared;
}

- (instancetype)initWithSettings:(TSAdvancedFindSettings *)settings
{
    if ((self = [super init])) {
        _settings = settings;
        _beepHandler = ^{ NSBeep(); };
    }
    return self;
}

#pragma mark Validation

/// The console and the log may be edited, but show TeX's output: nothing is replaced in them.
static BOOL TSTextViewRefusesReplacing(NSTextView *textView)
{
    return [textView respondsToSelector:@selector(refusesReplacing)] && [(id<TSAdvancedFindTarget>)textView refusesReplacing];
}

- (BOOL)validateAction:(TSAdvancedFindAction)action forTextView:(NSTextView *)textView
{
    switch (action) {
        case TSAdvancedFindActionShowFindPanel:
        case TSAdvancedFindActionShowReplacePanel:
        case TSAdvancedFindActionHidePanel:
        case TSAdvancedFindActionHideReplacePanel:
        case TSAdvancedFindActionUnhighlight:
            return YES;
        case TSAdvancedFindActionNext:
        case TSAdvancedFindActionPrevious:
        case TSAdvancedFindActionSelectAll:
        case TSAdvancedFindActionSelectAllInSelection:
        case TSAdvancedFindActionHighlight:
        case TSAdvancedFindActionJumpToSelection:
            return textView.isSelectable;
        case TSAdvancedFindActionSetFindString:
        case TSAdvancedFindActionSetReplaceString:
        case TSAdvancedFindActionFindSelectedText:
            return textView.isSelectable && textView.selectedRange.length > 0;
        case TSAdvancedFindActionReplace:
        case TSAdvancedFindActionReplaceAndFind:
        case TSAdvancedFindActionReplaceAll:
        case TSAdvancedFindActionReplaceAllInSelection:
            return textView.isEditable && !TSTextViewRefusesReplacing(textView);
    }
    return NO;
}

#pragma mark Actions

- (BOOL)performAction:(TSAdvancedFindAction)action inTextView:(NSTextView *)textView
{
    if (![self validateAction:action forTextView:textView]) {
        self.beepHandler();
        return NO;
    }
    switch (action) {
        case TSAdvancedFindActionShowFindPanel:
        case TSAdvancedFindActionShowReplacePanel:
            if (self.showPanelHandler)
                self.showPanelHandler(action == TSAdvancedFindActionShowReplacePanel);
            return YES;
        case TSAdvancedFindActionHidePanel:
        case TSAdvancedFindActionHideReplacePanel:
            if (self.hidePanelHandler)
                self.hidePanelHandler();
            return YES;
        case TSAdvancedFindActionNext:
            return [self findForward:YES inTextView:textView includingSelection:NO];
        case TSAdvancedFindActionPrevious:
            return [self findForward:NO inTextView:textView includingSelection:NO];
        case TSAdvancedFindActionReplace:
            return [self replaceInTextView:textView];
        case TSAdvancedFindActionReplaceAndFind:
            // One beep at most: a selection that is not a match is left as it is, and only the search for the next
            // match beeps when there is none. An invalid find string beeps once and stops there.
            if (![self replaceInTextView:textView quietly:YES] && ![self textFindForTextView:textView inSelection:NO quiet:YES])
                return [self textFindForTextView:textView inSelection:NO quiet:NO] != nil;
            return [self findForward:YES inTextView:textView includingSelection:NO];
        case TSAdvancedFindActionReplaceAll:
            return [self replaceAllInTextView:textView inSelection:self.settings.inSelection];
        case TSAdvancedFindActionReplaceAllInSelection:
            return [self replaceAllInTextView:textView inSelection:YES];
        case TSAdvancedFindActionSelectAll:
            return [self selectAllInTextView:textView inSelection:self.settings.inSelection];
        case TSAdvancedFindActionSelectAllInSelection:
            return [self selectAllInTextView:textView inSelection:YES];
        case TSAdvancedFindActionSetFindString:
            self.settings.findString = [textView.string substringWithRange:textView.selectedRange];
            [self stringsChanged];
            return YES;
        case TSAdvancedFindActionSetReplaceString:
            self.settings.replaceString = [textView.string substringWithRange:textView.selectedRange];
            [self stringsChanged];
            return YES;
        case TSAdvancedFindActionFindSelectedText: {
            // The selection is searched for as it is, whatever the regular expression setting.
            NSString *selected = [textView.string substringWithRange:textView.selectedRange];
            self.settings.findString = TSAdvancedFindPatternFindingText(selected, self.settings.options);
            [self stringsChanged];
            return [self findForward:YES inTextView:textView includingSelection:NO];
        }
        case TSAdvancedFindActionHighlight:
            return [self highlightInTextView:textView];
        case TSAdvancedFindActionUnhighlight:
            [self removeHighlightsInTextView:textView];
            return YES;
        case TSAdvancedFindActionJumpToSelection:
            [textView scrollRangeToVisible:textView.selectedRange];
            [textView showFindIndicatorForRange:textView.selectedRange];
            return YES;
    }
    return NO;
}

- (BOOL)incrementalSearchInTextView:(NSTextView *)textView
{
    if (self.settings.findString.length == 0)
        return NO;
    return [self findForward:YES inTextView:textView includingSelection:YES quiet:YES];
}

#pragma mark Searching

- (void)report:(NSString *)message isError:(BOOL)isError
{
    if (self.statusHandler)
        self.statusHandler(message, isError);
}

- (void)stringsChanged
{
    if (self.stringsChangedHandler)
        self.stringsChangedHandler();
}

- (nullable TSRegexTextFind *)textFindForTextView:(NSTextView *)textView inSelection:(BOOL)inSelection quiet:(BOOL)quiet
{
    NSError *error = nil;
    // The find string is put into the document's line ending, as the replaced text is (CotEditor does the same).
    NSString *lineEnding = self.lineEndingHandler ? self.lineEndingHandler(textView) : nil;
    NSString *findString = lineEnding ? TSRegexStringByReplacingLineEndings(self.settings.findString, lineEnding) : self.settings.findString;
    TSRegexFindPattern *pattern = [[TSRegexFindPattern alloc] initWithFindString:findString options:self.settings.options error:&error];
    NSArray<NSValue *> *selection = textView.selectedRanges;
    TSRegexTextFind *find = pattern ? [[TSRegexTextFind alloc] initWithString:textView.string pattern:pattern lineEnding:lineEnding
                                                               selectedRanges:selection inSelection:inSelection error:&error] : nil;
    if (!find && !quiet) {
        self.beepHandler();
        if (error.code == TSRegexFindErrorInvalidPattern && self.showPanelHandler)
            self.showPanelHandler(NO);
        [self report:error.localizedDescription isError:YES];
    }
    return find;
}

- (void)reportPosition:(NSRange)range inMatches:(NSArray<NSValue *> *)matches wrapped:(BOOL)wrapped
{
    NSUInteger index = [matches indexOfObject:[NSValue valueWithRange:range]];
    NSString *format = TSLocalized(@"AdvancedFind.Position", @"%1$lu of %2$lu");
    NSString *message = [NSString stringWithFormat:format, (unsigned long)index + 1, (unsigned long)matches.count];
    if (wrapped)
        message = [message stringByAppendingFormat:@" %@", TSLocalized(@"AdvancedFind.Wrapped", @"(wrapped)")];
    [self report:message isError:NO];
}

- (BOOL)findForward:(BOOL)forward inTextView:(NSTextView *)textView includingSelection:(BOOL)includingSelection
{
    return [self findForward:forward inTextView:textView includingSelection:includingSelection quiet:NO];
}

- (BOOL)findForward:(BOOL)forward inTextView:(NSTextView *)textView includingSelection:(BOOL)includingSelection quiet:(BOOL)quiet
{
    // Next and previous always search the whole text; "in selection" applies to the actions on all matches.
    TSRegexTextFind *find = [self textFindForTextView:textView inSelection:NO quiet:quiet];
    if (!find)
        return NO;
    if (self.settings.startsFromTop && forward) {
        find = [[TSRegexTextFind alloc] initWithString:find.string pattern:find.pattern lineEnding:find.lineEnding
                                        selectedRanges:@[[NSValue valueWithRange:NSMakeRange(0, 0)]] inSelection:NO error:NULL];
        includingSelection = YES;
        self.settings.startsFromTop = NO;
    }
    NSArray<NSValue *> *matches = [self matchesOfFind:find inTextView:textView];
    BOOL wrapped = NO;
    NSRange found = [find nextMatchInRanges:matches forward:forward includingSelection:includingSelection wraps:self.settings.wraps wrapped:&wrapped];
    if (!quiet)
        [self.settings noteFindString];
    if (found.location == NSNotFound) {
        if (!quiet)
            self.beepHandler();
        [self report:TSLocalized(@"AdvancedFind.NotFound", @"Not found") isError:NO];
        return NO;
    }
    textView.selectedRange = found;
    [textView scrollRangeToVisible:found];
    [textView showFindIndicatorForRange:found];
    [self reportPosition:found inMatches:matches wrapped:wrapped];
    return YES;
}

/// The matches of `find`. Every action searches the text again.
- (NSArray<NSValue *> *)matchesOfFind:(TSRegexTextFind *)find inTextView:(NSTextView *)textView
{
    return [find matchRangesWithCancellation:nil] ?: @[];
}

#pragma mark Replacing

- (BOOL)applyReplacements:(NSArray<TSRegexFindReplacement *> *)replacements
               toTextView:(NSTextView *)textView
           selectedRanges:(nullable NSArray<NSValue *> *)selectedRanges
               actionName:(NSString *)actionName
{
    if (replacements.count == 0)
        return NO;
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (TSRegexFindReplacement *replacement in replacements) {
        [ranges addObject:[NSValue valueWithRange:replacement.range]];
        [strings addObject:replacement.string];
    }
    // A replacement is its own undo step, never merged into the typing around it.
    [textView breakUndoCoalescing];
    if (![textView shouldChangeTextInRanges:ranges replacementStrings:strings])
        return NO;
    NSTextStorage *storage = textView.textStorage;
    [storage beginEditing];
    for (TSRegexFindReplacement *replacement in replacements.reverseObjectEnumerator)
        [storage replaceCharactersInRange:replacement.range withString:replacement.string];
    [storage endEditing];
    [textView didChangeText];
    [textView.undoManager setActionName:actionName];
    if (selectedRanges.count > 0)
        textView.selectedRanges = (NSArray<NSValue *> *_Nonnull)selectedRanges;
    return YES;
}

- (BOOL)replaceInTextView:(NSTextView *)textView
{
    return [self replaceInTextView:textView quietly:NO];
}

/// Replaces the selection when it is a match. `quietly`: no beep and no message when it is not, or when the find
/// string is invalid (Replace & Find goes on to find).
- (BOOL)replaceInTextView:(NSTextView *)textView quietly:(BOOL)quietly
{
    TSRegexTextFind *find = [self textFindForTextView:textView inSelection:NO quiet:quietly];
    if (!find)
        return NO;
    TSRegexReplacementTemplate *template = [[TSRegexReplacementTemplate alloc] initWithString:self.settings.replaceString pattern:find.pattern syntax:self.settings.replacementSyntax];
    TSRegexFindReplacement *replacement = [find replacementInSelectionWithTemplate:template];
    [self.settings noteReplaceString];
    if (!replacement) {
        if (!quietly)
            self.beepHandler();
        return NO;
    }
    NSRange selection = NSMakeRange(replacement.range.location, replacement.string.length);
    BOOL done = [self applyReplacements:@[replacement] toTextView:textView selectedRanges:@[[NSValue valueWithRange:selection]]
                             actionName:TSLocalized(@"AdvancedFind.ReplaceAction", @"Replace")];
    if (done)
        [textView scrollRangeToVisible:selection];
    return done;
}

/// Replace All in one step on the main thread, undone at once.
- (BOOL)replaceAllInTextView:(NSTextView *)textView inSelection:(BOOL)inSelection
{
    TSRegexTextFind *find = [self textFindForTextView:textView inSelection:inSelection quiet:NO];
    if (!find)
        return NO; // already beeped and reported
    TSRegexReplacementTemplate *template = [[TSRegexReplacementTemplate alloc] initWithString:self.settings.replaceString pattern:find.pattern
                                                                                         syntax:self.settings.replacementSyntax];
    [self.settings noteReplaceString];
    TSRegexReplaceAllResult *result = [find replaceAllWithTemplate:template cancellation:nil];
    if (result.numberOfMatches == 0) {
        self.beepHandler();
        [self report:TSLocalized(@"AdvancedFind.NotFound", @"Not found") isError:NO];
        return NO;
    }
    if (![self applyReplacements:result.replacements toTextView:textView selectedRanges:result.selectedRanges
                      actionName:TSLocalized(@"AdvancedFind.ReplaceAllAction", @"Replace All")])
        return NO;
    NSString *format = TSLocalized(@"AdvancedFind.Replaced", @"%lu replaced");
    [self report:[NSString stringWithFormat:format, (unsigned long)result.numberOfMatches] isError:NO];
    return YES;
}

- (BOOL)selectAllInTextView:(NSTextView *)textView inSelection:(BOOL)inSelection
{
    TSRegexTextFind *find = [self textFindForTextView:textView inSelection:inSelection quiet:NO];
    if (!find)
        return NO; // already beeped and reported
    NSArray<NSValue *> *matches = [self matchesOfFind:find inTextView:textView];
    [self.settings noteFindString];
    if (matches.count == 0) {
        self.beepHandler();
        [self report:TSLocalized(@"AdvancedFind.NotFound", @"Not found") isError:NO];
        return NO;
    }
    textView.selectedRanges = matches;
    [textView scrollRangeToVisible:matches.firstObject.rangeValue];
    NSString *format = TSLocalized(@"AdvancedFind.Found", @"%lu found");
    [self report:[NSString stringWithFormat:format, (unsigned long)matches.count] isError:NO];
    return YES;
}

#pragma mark Highlights

- (void)removeHighlightsInTextView:(NSTextView *)textView
{
    NSTextStorage *storage = textView.textStorage;
    if (storage)
        [[TSAdvancedFindHighlights existingHighlightsForTextStorage:storage] removeAll];
}

- (BOOL)highlightInTextView:(NSTextView *)textView
{
    TSRegexTextFind *find = [self textFindForTextView:textView inSelection:self.settings.inSelection quiet:NO];
    NSTextStorage *storage = textView.textStorage;
    if (!find || !storage)
        return NO;
    NSArray<NSValue *> *matches = [self matchesOfFind:find inTextView:textView];
    [TSAdvancedFindHighlights highlightsForTextStorage:storage].ranges = matches;
    NSString *format = TSLocalized(@"AdvancedFind.Found", @"%lu found");
    [self report:[NSString stringWithFormat:format, (unsigned long)matches.count] isError:NO];
    if (matches.count == 0)
        self.beepHandler();
    return matches.count > 0;
}

@end
