// SPDX-License-Identifier: GPL-2.0-or-later
// The coloring of the Advanced Find panel's find and replace fields with the shared syntax coloring (layer 3,
// TSSyntaxHighlighter), and the matching brackets of the find field. The fields are colored only with "Regular
// expression" on; the replace field knows the groups of the current pattern.
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindFieldScanners.h"
#import "TSRegexFindPattern.h"

@implementation TSAdvancedFindFieldView (Brackets)

- (NSRange)bracketPairAtIndex:(NSUInteger)index
{
    id<TSSyntaxScanner> scanner = self.bracketScanner;
    if (![scanner respondsToSelector:@selector(bracketPairsInString:)])
        return NSMakeRange(NSNotFound, 0);
    for (NSValue *value in [scanner bracketPairsInString:self.string]) {
        NSRange pair = value.rangeValue;
        if (pair.location == index || NSMaxRange(pair) - 1 == index)
            return pair;
    }
    return NSMakeRange(NSNotFound, 0);
}

/// The partner of the bracket right before the caret, as CotEditor does it.
- (void)setSelectedRanges:(NSArray<NSValue *> *)ranges affinity:(NSSelectionAffinity)affinity stillSelecting:(BOOL)stillSelecting
{
    [super setSelectedRanges:ranges affinity:affinity stillSelecting:stillSelecting];
    if (stillSelecting || !self.bracketScanner || ranges.count != 1 || self.window.firstResponder != self)
        return;
    NSRange caret = ranges.firstObject.rangeValue;
    if (caret.length > 0 || caret.location == 0 || caret.location > self.string.length)
        return;
    NSUInteger bracket = caret.location - 1;
    NSRange pair = [self bracketPairAtIndex:bracket];
    if (pair.location == NSNotFound)
        return;
    NSUInteger partner = pair.location == bracket ? NSMaxRange(pair) - 1 : pair.location;
    if (self.bracketIndicator)
        self.bracketIndicator(self, NSMakeRange(partner, 1));
    else
        [self showFindIndicatorForRange:NSMakeRange(partner, 1)];
}

/// A double-click on a bracket selects the pair and what is between.
- (NSRange)selectionRangeForProposedRange:(NSRange)proposed granularity:(NSSelectionGranularity)granularity
{
    NSRange range = [super selectionRangeForProposedRange:proposed granularity:granularity];
    if (!self.bracketScanner || granularity != NSSelectByWord || proposed.length > 0 || range.length != 1)
        return range;
    NSRange pair = [self bracketPairAtIndex:range.location];
    return pair.location == NSNotFound ? range : pair;
}

@end

@implementation TSAdvancedFindPanelController (Coloring)

- (void)setUpFieldColoring
{
    TSSyntaxColorScheme *scheme = TSAdvancedFindFieldColorScheme();
    self.findHighlighter = [[TSSyntaxHighlighter alloc] initWithTextView:self.findFieldView scanner:nil scheme:scheme];
    self.replaceHighlighter = [[TSSyntaxHighlighter alloc] initWithTextView:self.replaceFieldView scanner:nil scheme:scheme];
    [self.findHighlighter followEdits];
    [self.replaceHighlighter followEdits];
    [self updateFieldScanners];
}

- (void)updateFieldScanners
{
    TSAdvancedFindSettings *settings = self.findController.settings;
    TSRegexFindOptions options = settings.options;
    BOOL regex = (options & TSRegexFindRegularExpression) != 0;
    TSAdvancedFindPatternScanner *find = (TSAdvancedFindPatternScanner *)self.findHighlighter.scanner;
    if (!regex) {
        if (find)
            self.findHighlighter.scanner = nil;
        if (self.replaceHighlighter.scanner)
            self.replaceHighlighter.scanner = nil;
        self.findFieldView.bracketScanner = nil;
        return;
    }
    // A new scanner colors the whole field again: only when what it reads by has changed.
    if (!find || find.options != options) {
        find = [[TSAdvancedFindPatternScanner alloc] initWithOptions:options];
        self.findHighlighter.scanner = find;
    }
    self.findFieldView.bracketScanner = find;
    TSRegexFindPattern *pattern = settings.findString.length > 0 ? [[TSRegexFindPattern alloc] initWithFindString:settings.findString options:options error:NULL] : nil;
    TSAdvancedFindReplacementScanner *replace = [[TSAdvancedFindReplacementScanner alloc] initWithSyntax:settings.replacementSyntax options:options pattern:pattern];
    TSAdvancedFindReplacementScanner *old = (TSAdvancedFindReplacementScanner *)self.replaceHighlighter.scanner;
    if (!old || old.syntax != replace.syntax || old.options != replace.options || old.numberOfCaptureGroups != replace.numberOfCaptureGroups
        || ![old.captureGroupNames isEqualToArray:replace.captureGroupNames])
        self.replaceHighlighter.scanner = replace;
}

- (NSArray<TSSyntaxDiagnostic *> *)fieldDiagnostics
{
    NSMutableArray<TSSyntaxDiagnostic *> *diagnostics = [NSMutableArray array];
    for (TSSyntaxHighlighter *highlighter in @[self.findHighlighter, self.replaceHighlighter]) {
        id<TSSyntaxScanner> scanner = highlighter.scanner;
        NSTextView *field = highlighter.textView;
        if (field && [scanner respondsToSelector:@selector(diagnosticsInString:)])
            [diagnostics addObjectsFromArray:[scanner diagnosticsInString:field.string]];
    }
    return diagnostics;
}

@end
