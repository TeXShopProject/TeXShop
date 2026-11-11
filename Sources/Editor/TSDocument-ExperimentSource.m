// SPDX-License-Identifier: GPL-2.0-or-later
//
// The source of the Experiment window shows its text as the document's source does:
// the same font, tabs, line spacing, wrapping, invisible characters, line numbers,
// syntax colors, active line, block cursor and brace matching. When one of these
// changes in the document, from a menu or from Settings, the document applies it here
// too. The Experiment source is a ScrapTextView, not a TSTextView, and has no delegate.

#import "TSDocument.h"
#import "ScrapTextView.h"
#import "TSTextView.h"
#import "TSLayoutManager.h"
#import "NoodleLineNumberView.h"
#import "NSText-Extras.h"
#import "globals.h"

@implementation TSDocument (ExperimentSource)

- (BOOL)experimentSourceShown
{
    return scrapTextView.window.isVisible;
}

#pragma mark Notifications

- (void)observeExperimentSource
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSClipView *clipView = scrapTextView.enclosingScrollView.contentView;
    [center removeObserver:self name:NSTextDidChangeNotification object:scrapTextView];
    [center removeObserver:self name:NSTextViewDidChangeSelectionNotification object:scrapTextView];
    [center removeObserver:self name:NSViewFrameDidChangeNotification object:scrapTextView];
    if (clipView)
        [center removeObserver:self name:NSViewBoundsDidChangeNotification object:clipView];
    if (!scrapTextView)
        return;
    [center addObserver:self selector:@selector(experimentSourceDidChange:)
                   name:NSTextDidChangeNotification object:scrapTextView];
    [center addObserver:self selector:@selector(experimentSelectionDidChange:)
                   name:NSTextViewDidChangeSelectionNotification object:scrapTextView];
    [center addObserver:self selector:@selector(viewFrameDidChange:)
                   name:NSViewFrameDidChangeNotification object:scrapTextView];
    if (clipView) {
        clipView.postsBoundsChangedNotifications = YES;
        [center addObserver:self selector:@selector(viewBoundsDidChange:)
                       name:NSViewBoundsDidChangeNotification object:clipView];
    }
}

// The Experiment source is short, so its visible area is colored again after each change.
- (void)experimentSourceDidChange:(NSNotification *)notification
{
    [self colorizeExperimentSource];
}

// As -textViewDidChangeSelection: for the document's source. The active line follows
// the insertion point through -[ScrapTextView updateInsertionPointStateAndRestartTimer:].
- (void)experimentSelectionDidChange:(NSNotification *)notification
{
    if ([self experimentSourceShown])
        [self matchBracesForSelectionInTextView:scrapTextView];
}

#pragma mark Display settings

- (void)syncExperimentSourceDisplay
{
    [self applyExperimentTextLayout];
    [self applyExperimentInvisibleCharacters];
    [self applyExperimentLineNumbers];
    [self refreshExperimentCurrentLine];
}

// Font, tabs, line spacing, indents and wrapping, from the document's source.
- (void)applyExperimentTextLayout
{
    NSTextView *source = [self textView] ?: textView1;
    if (!scrapTextView || !source)
        return;

    NSFont *font = source.font;
    if (font)
        [scrapTextView setFontSafely:font];

    NSParagraphStyle *sourceStyle = source.defaultParagraphStyle;
    if (!sourceStyle && self.textStorage.length > 0)
        sourceStyle = [self.textStorage attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    NSMutableParagraphStyle *style = [(sourceStyle ?: [NSParagraphStyle defaultParagraphStyle]) mutableCopy];
    style.lineBreakMode = lineBreakMode;

    scrapTextView.defaultParagraphStyle = style;
    NSMutableDictionary *typingAttributes = [scrapTextView.typingAttributes mutableCopy];
    typingAttributes[NSParagraphStyleAttributeName] = style;
    if (scrapTextView.font)
        typingAttributes[NSFontAttributeName] = scrapTextView.font;
    scrapTextView.typingAttributes = typingAttributes;
    NSTextStorage *storage = scrapTextView.textStorage;
    if (storage.length > 0)
        [storage addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, storage.length)];

    // Wrapping, as -setLineBreakMode: does for the document's source.
    NSScrollView *experimentScrollView = scrapTextView.enclosingScrollView;
    NSTextContainer *container = scrapTextView.textContainer;
    if (lineBreakMode == NSLineBreakByClipping) {
        NSSize maximumSize = NSMakeSize(FLT_MAX, FLT_MAX);
        experimentScrollView.hasHorizontalScroller = YES;
        container.widthTracksTextView = NO;
        container.containerSize = maximumSize;
        scrapTextView.maxSize = maximumSize;
        scrapTextView.horizontallyResizable = YES;
    } else {
        experimentScrollView.hasHorizontalScroller = NO;
        scrapTextView.horizontallyResizable = NO;
        scrapTextView.autoresizingMask = NSViewWidthSizable;
        NSSize contentSize = experimentScrollView ? experimentScrollView.contentSize : scrapTextView.frame.size;
        [scrapTextView setFrameSize:NSMakeSize(contentSize.width, NSHeight(scrapTextView.frame))];
        // Set the width as well: the frame may already have it, and then would not
        // bring a container left wide by clipping back to the view.
        container.containerSize = NSMakeSize(MAX(contentSize.width - 2 * scrapTextView.textContainerInset.width, 0), FLT_MAX);
        container.widthTracksTextView = YES;
        NSClipView *clipView = experimentScrollView.contentView;
        if (clipView && NSMinX(clipView.bounds) != 0) {
            [clipView scrollToPoint:NSMakePoint(0, NSMinY(clipView.bounds))];
            [experimentScrollView reflectScrolledClipView:clipView];
        }
    }
    [self colorizeExperimentSource];
}

// A font chosen in the Experiment source goes to the document's source as
// -[TSTextView changeFont:] does it there, and comes back with the tabs.
- (void)applyExperimentFontToSource:(NSFont *)font
{
    if (!font)
        return;
    NSTextView *source = [self textView] ?: textView1;
    textView1.font = font;
    textView2.font = font;
    if ([source respondsToSelector:@selector(fixupTabs)])
        [(TSTextView *)source fixupTabs];
    [self applyExperimentTextLayout];
}

// TSLayoutManager draws the invisible characters (and control characters) in the
// document's source; the Experiment source gets one too.
- (void)applyExperimentInvisibleCharacters
{
    if (!scrapTextView)
        return;
    TSLayoutManager *layoutManager = (TSLayoutManager *)scrapTextView.layoutManager;
    if (![layoutManager isKindOfClass:[TSLayoutManager class]]) {
        layoutManager = [[TSLayoutManager alloc] init];
        layoutManager.allowsNonContiguousLayout = ![SUD boolForKey:@"ContiguousTextLayout"];
        [scrapTextView.textContainer replaceLayoutManager:layoutManager];
    }
    [layoutManager setInvisibleCharactersEnabled:invisibleCharactersShowing];
    NSUInteger length = scrapTextView.textStorage.length;
    if (length > 0)
        [layoutManager invalidateDisplayForCharacterRange:NSMakeRange(0, length)];
    [self colorizeExperimentSource];
}

- (void)applyExperimentLineNumbers
{
    NSScrollView *experimentScrollView = scrapTextView.enclosingScrollView;
    if (!experimentScrollView)
        return;
    if (lineNumbersShowing && ![experimentScrollView.verticalRulerView isKindOfClass:[NoodleLineNumberView class]]) {
        NoodleLineNumberView *lineNumberView = [[NoodleLineNumberView alloc] initWithScrollView:experimentScrollView];
        experimentScrollView.verticalRulerView = lineNumberView;
        experimentScrollView.hasVerticalRuler = YES;
        experimentScrollView.hasHorizontalRuler = NO;
    }
    if ([experimentScrollView.verticalRulerView isKindOfClass:[NoodleLineNumberView class]])
        experimentScrollView.rulersVisible = lineNumbersShowing;
    [experimentScrollView tile];
}

#pragma mark Colors

- (void)colorizeExperimentSource
{
    if ([self experimentSourceShown])
        [self colorizeVisibleAreaInTextView:scrapTextView];
}

// The active line and the block cursor, after Highlight Current Line, Block Cursor or
// a theme change.
- (void)refreshExperimentCurrentLine
{
    if (!scrapTextView)
        return;
    if (!self.syntaxcolorEntry)
        [self removeCurrentLineColor:scrapTextView];
    else if ([self experimentSourceShown])
        [self cursorMoved:scrapTextView];
}

#pragma mark Brace matching

// The counterparts of -resetHighlight:, -highlightBracesAt:, -highlightContent:,
// -showIndicator:, -resetBackgroundColor: and -resetBackgroundColorOfTextView:.
// They run later than the selection change, after which the text may be shorter.

static NSRange TSExperimentRange(NSTextView *view, NSRange range)
{
    NSUInteger length = view.string.length;
    if (range.location >= length)
        return NSMakeRange(length, 0);
    return NSMakeRange(range.location, MIN(range.length, length - range.location));
}

- (void)resetExperimentHighlight:(id)sender
{
    if (scrapBraceHighlighting) {
        [scrapTextView.layoutManager removeTemporaryAttribute:NSForegroundColorAttributeName
                                            forCharacterRange:NSMakeRange(0, scrapTextView.string.length)];
        scrapBraceHighlighting = NO;
    }
    if (scrapTextView.hasMarkedText)
        return;
    [self colorizeExperimentSource];
}

- (void)highlightExperimentBracesAt:(NSArray *)locations
{
    for (NSNumber *location in [locations subarrayWithRange:NSMakeRange(0, MIN(locations.count, 2))]) {
        NSRange range = TSExperimentRange(scrapTextView, NSMakeRange(location.integerValue, 1));
        if (range.length > 0)
            [scrapTextView.layoutManager addTemporaryAttributes:highlightBracesColorDict forCharacterRange:range];
    }
    scrapBraceHighlighting = YES;
}

- (void)highlightExperimentContent:(NSString *)rangeString
{
    scrapContentHighlighting = YES;
    NSRange range = TSExperimentRange(scrapTextView, NSRangeFromString(rangeString));
    if (range.length > 0)
        [scrapTextView.layoutManager addTemporaryAttributes:highlightContentColorDict forCharacterRange:range];
}

- (void)showExperimentIndicator:(NSString *)rangeString
{
    NSRange range = TSExperimentRange(scrapTextView, NSRangeFromString(rangeString));
    if (range.length > 0)
        [scrapTextView showFindIndicatorForRange:range];
}

- (void)resetExperimentBackgroundColor:(id)sender
{
    [scrapTextView.layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName
                                        forCharacterRange:NSMakeRange(0, scrapTextView.string.length)];
    scrapContentHighlighting = NO;
}

// After the flash for an unmatched brace, the theme's background again.
- (void)resetExperimentBackgroundColorOfTextView:(id)sender
{
    if ([scrapTextView respondsToSelector:@selector(updateExperimentColors:)])
        [(ScrapTextView *)scrapTextView updateExperimentColors:nil];
}

@end
