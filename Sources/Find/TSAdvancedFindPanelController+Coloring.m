// SPDX-License-Identifier: GPL-2.0-or-later
// The coloring of the Advanced Find panel's find and replace fields with the shared syntax coloring (layer 3,
// TSSyntaxHighlighter), in the source's theme and font, and the matching brackets of the find field. With "Regular
// expression" on, the fields are read as the engine reads them, and the replace field knows the groups of the current
// pattern; with it off, as the source reads TeX.
#import "TSAdvancedFindPanelController+Private.h"
#import "TSAdvancedFindFieldScanners.h"
#import "TSRegexFindPattern.h"
#import "TSSyntaxTeXScanner.h"

static void *TSFieldAppearanceContext = &TSFieldAppearanceContext;

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
    self.findHighlighter = [[TSSyntaxHighlighter alloc] initWithTextView:self.findFieldView scanner:nil scheme:nil];
    self.replaceHighlighter = [[TSSyntaxHighlighter alloc] initWithTextView:self.replaceFieldView scanner:nil scheme:nil];
    [self.findHighlighter followEdits];
    [self.replaceHighlighter followEdits];
    [self applyFieldStyle];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fieldStyleDidChange:) name:TSAdvancedFindFieldStyleDidChangeNotification object:nil];
    // The application's appearance (light or dark in System Settings), or the window's own.
    [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:TSFieldAppearanceContext];
    [self.window addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:TSFieldAppearanceContext];
}

- (void)tearDownFieldColoring
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:TSAdvancedFindFieldStyleDidChangeNotification object:nil];
    [NSApp removeObserver:self forKeyPath:@"effectiveAppearance" context:TSFieldAppearanceContext];
    [self.window removeObserver:self forKeyPath:@"effectiveAppearance" context:TSFieldAppearanceContext];
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(nullable void *)context
{
    if (context == TSFieldAppearanceContext)
        [self applyFieldStyle];
    else
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)fieldStyleDidChange:(NSNotification *)notification
{
    [self applyFieldStyle];
}

/// As the macro editor's contents: the theme's text, background and insertion point colors, and the source font.
- (void)applyFieldStyle
{
    TSAdvancedFindFieldStyle *style = [TSAdvancedFindFieldStyle styleForWindow:self.window];
    self.fieldStyle = style;
    for (TSAdvancedFindFieldView *field in @[self.findFieldView, self.replaceFieldView]) {
        field.font = style.fieldFont;
        field.textColor = style.textColor ?: NSColor.textColor;
        field.insertionPointColor = style.insertionPointColor ?: NSColor.textColor;
        NSMutableDictionary<NSAttributedStringKey, id> *typing = [field.typingAttributes mutableCopy] ?: [NSMutableDictionary dictionary];
        typing[NSForegroundColorAttributeName] = field.textColor;
        typing[NSFontAttributeName] = field.font;
        field.typingAttributes = typing;
        field.box.appearance = style.fieldAppearance;
        field.box.fillColor = style.backgroundColor;
    }
    TSSyntaxColorScheme *scheme = style.fieldScheme;
    self.findHighlighter.scheme = scheme;
    self.replaceHighlighter.scheme = scheme;
    [self updateFieldScanners];
}

- (void)updateFieldScanners
{
    TSAdvancedFindSettings *settings = self.findController.settings;
    TSRegexFindOptions options = settings.options;
    BOOL regex = (options & TSRegexFindRegularExpression) != 0;
    if (!regex) {
        // A new scanner colors the whole field again: only when the TeX settings have changed.
        TSSyntaxTeXOptions *tex = self.fieldStyle.texOptions;
        for (TSSyntaxHighlighter *highlighter in @[self.findHighlighter, self.replaceHighlighter]) {
            TSSyntaxTeXScanner *old = (TSSyntaxTeXScanner *)highlighter.scanner;
            if (![old isKindOfClass:[TSSyntaxTeXScanner class]] || ![old.options isEqual:tex])
                highlighter.scanner = [[TSSyntaxTeXScanner alloc] initWithOptions:tex];
        }
        self.findFieldView.bracketScanner = nil;
        return;
    }
    TSAdvancedFindPatternScanner *find = (TSAdvancedFindPatternScanner *)self.findHighlighter.scanner;
    if (![find isKindOfClass:[TSAdvancedFindPatternScanner class]] || find.options != options) {
        find = [[TSAdvancedFindPatternScanner alloc] initWithOptions:options];
        self.findHighlighter.scanner = find;
    }
    self.findFieldView.bracketScanner = find;
    TSRegexFindPattern *pattern = settings.findString.length > 0 ? [[TSRegexFindPattern alloc] initWithFindString:settings.findString options:options error:NULL] : nil;
    TSAdvancedFindReplacementScanner *replace = [[TSAdvancedFindReplacementScanner alloc] initWithSyntax:settings.replacementSyntax options:options pattern:pattern];
    TSAdvancedFindReplacementScanner *old = (TSAdvancedFindReplacementScanner *)self.replaceHighlighter.scanner;
    if (![old isKindOfClass:[TSAdvancedFindReplacementScanner class]] || old.syntax != replace.syntax || old.options != replace.options
        || old.numberOfCaptureGroups != replace.numberOfCaptureGroups || ![old.captureGroupNames isEqualToArray:replace.captureGroupNames])
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
