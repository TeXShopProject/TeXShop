// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSMacroContentTokens.h"
#import "TSPlaceholderToken.h"
#import "TSSyntaxMacroContentScanner.h"

@interface TSMacroContentLayoutManager ()
@property (nonatomic, readwrite, copy) NSArray<NSValue *> *tokenRanges;
@property (nonatomic, copy) NSArray<NSString *> *tokenSymbols;
@end

@implementation TSMacroContentLayoutManager

- (instancetype)init
{
    if ((self = [super init])) {
        _tokenRanges = @[];
        _tokenSymbols = @[];
        self.delegate = self;
    }
    return self;
}

#pragma mark Tokens

- (NSUInteger)indexOfTokenContainingCharacter:(NSUInteger)index
{
    NSArray<NSValue *> *ranges = self.tokenRanges;
    NSUInteger low = 0, high = ranges.count;
    while (low < high) {
        NSUInteger middle = (low + high) / 2;
        NSRange range = ranges[middle].rangeValue;
        if (index < range.location)
            high = middle;
        else if (index >= NSMaxRange(range))
            low = middle + 1;
        else
            return middle;
    }
    return NSNotFound;
}

- (NSRange)tokenRangeContainingIndex:(NSUInteger)index
{
    NSUInteger token = [self indexOfTokenContainingCharacter:index];
    return token == NSNotFound ? NSMakeRange(NSNotFound, 0) : self.tokenRanges[token].rangeValue;
}

- (NSString *)titleOfTokenRange:(NSRange)range
{
    NSUInteger token = [self indexOfTokenContainingCharacter:range.location];
    return token == NSNotFound ? @"" : TSPlaceholderTokenTitle(self.tokenSymbols[token]);
}

- (NSFont *)fontOfTokenAtIndex:(NSUInteger)index
{
    NSTextStorage *storage = self.textStorage;
    NSFont *font = index < storage.length ? [storage attribute:NSFontAttributeName atIndex:index effectiveRange:NULL] : nil;
    return font ?: [NSFont userFixedPitchFontOfSize:0] ?: [NSFont systemFontOfSize:0];
}

// After every edit, the tokens are found again in the whole text (the kind of a macro depends on its first line, and
// the first #INS# only is replaced); what changes, before or after, is laid out again.
- (void)processEditingForTextStorage:(NSTextStorage *)textStorage edited:(NSTextStorageEditActions)editMask
                               range:(NSRange)newCharRange changeInLength:(NSInteger)delta invalidatedRange:(NSRange)invalidatedCharRange
{
    if (editMask & NSTextStorageEditedCharacters) {
        NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
        NSMutableArray<NSString *> *symbols = [NSMutableArray array];
        [TSSyntaxMacroContentScanner enumerateTokensInString:textStorage.string usingBlock:^(NSRange range, NSString *symbol) {
            [ranges addObject:[NSValue valueWithRange:range]];
            [symbols addObject:symbol];
        }];
        // The old tokens where they are now: those after the edit moved with it, those in it are gone.
        NSUInteger oldEnd = NSMaxRange(newCharRange) - delta;
        NSMutableSet<NSValue *> *before = [NSMutableSet set];
        for (NSValue *value in self.tokenRanges) {
            NSRange range = value.rangeValue;
            if (NSMaxRange(range) <= newCharRange.location)
                [before addObject:value];
            else if (range.location >= oldEnd)
                [before addObject:[NSValue valueWithRange:NSMakeRange(range.location + delta, range.length)]];
        }
        NSSet<NSValue *> *after = [NSSet setWithArray:ranges];
        NSRange invalidated = invalidatedCharRange;
        NSUInteger length = textStorage.length;
        for (NSValue *value in before)
            if (![after containsObject:value] && NSMaxRange(value.rangeValue) <= length)
                invalidated = NSUnionRange(invalidated, value.rangeValue);
        for (NSValue *value in after)
            if (![before containsObject:value])
                invalidated = NSUnionRange(invalidated, value.rangeValue);
        self.tokenRanges = ranges;
        self.tokenSymbols = symbols;
        invalidatedCharRange = invalidated;
    }
    [super processEditingForTextStorage:textStorage edited:editMask range:newCharRange changeInLength:delta invalidatedRange:invalidatedCharRange];
}

#pragma mark Glyphs

// The first character of a token becomes one control glyph as wide as the pill; the others take no room.
- (NSUInteger)layoutManager:(NSLayoutManager *)layoutManager shouldGenerateGlyphs:(const CGGlyph *)glyphs
                 properties:(const NSGlyphProperty *)properties characterIndexes:(const NSUInteger *)characterIndexes
                       font:(NSFont *)font forGlyphRange:(NSRange)glyphRange
{
    if (self.tokenRanges.count == 0)
        return 0;
    NSGlyphProperty *changed = NULL;
    for (NSUInteger i = 0; i < glyphRange.length; i++) {
        NSRange token = [self tokenRangeContainingIndex:characterIndexes[i]];
        if (token.location == NSNotFound)
            continue;
        if (changed == NULL) {
            changed = malloc(sizeof(NSGlyphProperty) * glyphRange.length);
            memcpy(changed, properties, sizeof(NSGlyphProperty) * glyphRange.length);
        }
        changed[i] = characterIndexes[i] == token.location ? NSGlyphPropertyControlCharacter : NSGlyphPropertyNull;
    }
    if (changed == NULL)
        return 0;
    [layoutManager setGlyphs:glyphs properties:changed characterIndexes:characterIndexes font:font forGlyphRange:glyphRange];
    free(changed);
    return glyphRange.length;
}

- (NSControlCharacterAction)layoutManager:(NSLayoutManager *)layoutManager shouldUseAction:(NSControlCharacterAction)action
               forControlCharacterAtIndex:(NSUInteger)characterIndex
{
    NSRange token = [self tokenRangeContainingIndex:characterIndex];
    return token.location == characterIndex ? NSControlCharacterActionWhitespace : action;
}

- (NSRect)layoutManager:(NSLayoutManager *)layoutManager boundingBoxForControlGlyphAtIndex:(NSUInteger)glyphIndex
       forTextContainer:(NSTextContainer *)textContainer proposedLineFragment:(NSRect)proposedRect
          glyphPosition:(NSPoint)glyphPosition characterIndex:(NSUInteger)characterIndex
{
    NSRange token = [self tokenRangeContainingIndex:characterIndex];
    if (token.location != characterIndex)
        return NSMakeRect(glyphPosition.x, glyphPosition.y, 0, 0);
    NSSize size = TSPlaceholderTokenSize([self titleOfTokenRange:token], [self fontOfTokenAtIndex:characterIndex]);
    return NSMakeRect(glyphPosition.x, glyphPosition.y, size.width, size.height);
}

#pragma mark Drawing

- (void)drawGlyphsForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin
{
    [super drawGlyphsForGlyphRange:glyphsToShow atPoint:origin];
    NSRange characters = [self characterRangeForGlyphRange:glyphsToShow actualGlyphRange:NULL];
    for (NSValue *value in self.tokenRanges) {
        NSRange token = value.rangeValue;
        if (NSMaxRange(token) <= characters.location)
            continue;
        if (token.location >= NSMaxRange(characters))
            break;
        NSUInteger glyph = [self glyphIndexForCharacterAtIndex:token.location];
        NSTextContainer *container = [self textContainerForGlyphAtIndex:glyph effectiveRange:NULL];
        if (container == nil)
            continue;
        NSRect line = [self lineFragmentUsedRectForGlyphAtIndex:glyph effectiveRange:NULL];
        NSPoint location = [self locationForGlyphAtIndex:glyph];
        NSFont *font = [self fontOfTokenAtIndex:token.location];
        NSString *title = [self titleOfTokenRange:token];
        NSSize size = TSPlaceholderTokenSize(title, font);
        CGFloat height = MIN(size.height, NSHeight(line));
        NSRect pill = NSMakeRect(origin.x + NSMinX(line) + location.x, origin.y + NSMidY(line) - height / 2, size.width, height);
        TSDrawPlaceholderToken(title, font, pill);
    }
}

// The colors of the text stay off the tokens: no underline below a pill.
- (void)drawUnderlineForGlyphRange:(NSRange)glyphRange underlineType:(NSUnderlineStyle)underlineVal baselineOffset:(CGFloat)baselineOffset
                  lineFragmentRect:(NSRect)lineRect lineFragmentGlyphRange:(NSRange)lineGlyphRange containerOrigin:(NSPoint)containerOrigin
{
    NSUInteger start = glyphRange.location, end = NSMaxRange(glyphRange), run = start;
    for (NSUInteger glyph = start; glyph < end; glyph++) {
        NSUInteger character = [self characterIndexForGlyphAtIndex:glyph];
        if ([self tokenRangeContainingIndex:character].location == NSNotFound)
            continue;
        if (glyph > run)
            [super drawUnderlineForGlyphRange:NSMakeRange(run, glyph - run) underlineType:underlineVal baselineOffset:baselineOffset
                             lineFragmentRect:lineRect lineFragmentGlyphRange:lineGlyphRange containerOrigin:containerOrigin];
        run = glyph + 1;
    }
    if (end > run)
        [super drawUnderlineForGlyphRange:NSMakeRange(run, end - run) underlineType:underlineVal baselineOffset:baselineOffset
                         lineFragmentRect:lineRect lineFragmentGlyphRange:lineGlyphRange containerOrigin:containerOrigin];
}

@end

@implementation TSMacroContentTextView

- (nullable TSMacroContentLayoutManager *)tokenLayout
{
    NSLayoutManager *layout = self.layoutManager;
    return [layout isKindOfClass:TSMacroContentLayoutManager.class] ? (TSMacroContentLayoutManager *)layout : nil;
}

// The ranges with every token they touch taken in; an insertion point inside a token goes to the end it moves toward:
// the start when it moved back from `previous`, else the end.
- (NSArray<NSValue *> *)rangesSnappedToTokens:(NSArray<NSValue *> *)ranges previous:(NSUInteger)previous
{
    TSMacroContentLayoutManager *layout = self.tokenLayout;
    if (layout.tokenRanges.count == 0)
        return ranges;
    NSMutableArray<NSValue *> *snapped = [NSMutableArray arrayWithCapacity:ranges.count];
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        NSRange first = [layout tokenRangeContainingIndex:range.location];
        if (range.length == 0) {
            if (first.location != NSNotFound && range.location > first.location)
                range.location = range.location < previous ? first.location : NSMaxRange(first);
        } else {
            NSUInteger start = range.location, end = NSMaxRange(range);
            if (first.location != NSNotFound && start > first.location)
                start = first.location;
            NSRange last = [layout tokenRangeContainingIndex:end - 1];
            if (last.location != NSNotFound)
                end = MAX(end, NSMaxRange(last));
            range = NSMakeRange(start, end - start);
        }
        [snapped addObject:[NSValue valueWithRange:range]];
    }
    return snapped;
}

// Only what the user does moves the selection by whole tokens: the movement commands of the keyboard, and the mouse.
// Find, replace, undo and the editor set exact ranges, which stay as they are (a match may be part of a token).
- (void)doCommandBySelector:(SEL)selector
{
    NSUInteger previous = self.selectedRange.location;
    [super doCommandBySelector:selector];
    if (![NSStringFromSelector(selector) hasPrefix:@"move"])
        return;
    NSArray<NSValue *> *ranges = self.selectedRanges, *snapped = [self rangesSnappedToTokens:ranges previous:previous];
    if (![snapped isEqualToArray:ranges])
        [self setSelectedRanges:snapped affinity:self.selectionAffinity stillSelecting:NO];
}

// A click or a drag: a click on a token puts the insertion point after it.
- (NSRange)selectionRangeForProposedRange:(NSRange)proposedCharRange granularity:(NSSelectionGranularity)granularity
{
    NSRange range = [super selectionRangeForProposedRange:proposedCharRange granularity:granularity];
    return [[self rangesSnappedToTokens:@[[NSValue valueWithRange:range]] previous:0].firstObject rangeValue];
}

- (void)deleteToken:(NSRange)token
{
    if (![self shouldChangeTextInRange:token replacementString:@""])
        return;
    [self.textStorage replaceCharactersInRange:token withString:@""];
    [self didChangeText];
    self.selectedRange = NSMakeRange(token.location, 0);
}

- (void)deleteBackward:(id)sender
{
    NSRange selection = self.selectedRange;
    if (selection.length == 0 && selection.location > 0) {
        NSRange token = [self.tokenLayout tokenRangeContainingIndex:selection.location - 1];
        if (token.location != NSNotFound) {
            [self deleteToken:token];
            return;
        }
    }
    [super deleteBackward:sender];
}

- (void)deleteForward:(id)sender
{
    NSRange selection = self.selectedRange;
    if (selection.length == 0) {
        NSRange token = [self.tokenLayout tokenRangeContainingIndex:selection.location];
        if (token.location != NSNotFound) {
            [self deleteToken:token];
            return;
        }
    }
    [super deleteForward:sender];
}

@end
