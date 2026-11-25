// SPDX-License-Identifier: GPL-2.0-or-later
// Replace All and Find All as background tasks: the search runs on a copy of the text, the text views are read-only
// meanwhile, and the result is applied in one step at the end.
#import "TSAdvancedFindController+Private.h"

#define TSLocalized TSAdvancedFindLocalized

/// Where to put the view back. `character` is the left of the top line, and `pin` is how far that line sits below the
/// top of the viewport. That line may end before the left edge: a short line scrolled sideways has no character
/// there, and the long line under it is what the reader is looking at. `characterX` is the character under the left
/// edge on the first line that reaches it, and `pinX` is how far that glyph sits from the left edge. `clipX` is only
/// the fallback when that character cannot be placed (#72).
typedef struct {
    NSUInteger character;
    CGFloat pin;
    CGFloat pinX;
    CGFloat clipX;
    NSUInteger characterX;
} TSScrollAnchor;

static void TSReadHorizontalAnchor(NSTextView *view, TSScrollAnchor *anchor);

static TSScrollAnchor TSAnchorForView(NSTextView *view)
{
    TSScrollAnchor anchor = {NSNotFound, 0, 0, 0, NSNotFound};
    NSClipView *clip = view.enclosingScrollView.contentView;
    if (clip)
        anchor.clipX = clip.bounds.origin.x;
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || view.string.length == 0)
        return anchor;
    // setTextColor: leaves the first glyphIndexForPoint on another wrap of the line than the one on screen. A theme
    // does that for each part of a split source. The next question returns the wrap that is painted (#72).
    NSRect visible = view.visibleRect;
    NSPoint inContainer = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x,
                                      NSMinY(visible) + 1 - view.textContainerOrigin.y);
    if (layout.numberOfGlyphs > 0)
        (void)[layout glyphIndexForPoint:inContainer inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    if (layout.numberOfGlyphs == 0)
        return anchor;
    visible = view.visibleRect;
    inContainer = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x,
                              NSMinY(visible) + 1 - view.textContainerOrigin.y);
    NSUInteger glyph = [layout glyphIndexForPoint:inContainer inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    if (glyph >= layout.numberOfGlyphs)
        glyph = layout.numberOfGlyphs - 1;
    [layout ensureLayoutForGlyphRange:NSMakeRange(glyph, 1)];
    NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    anchor.character = [layout characterIndexForGlyphAtIndex:glyph];
    anchor.pin = NSMinY(fragment) + view.textContainerOrigin.y - NSMinY(visible);
    TSReadHorizontalAnchor(view, &anchor);
    return anchor;
}

/// The character under the left edge. The top line is not that character when the line ends further left: the point
/// then hits the end of the short line, and restoring it leaves the long line below free to slide (#72).
static void TSReadHorizontalAnchor(NSTextView *view, TSScrollAnchor *anchor)
{
    anchor->characterX = NSNotFound;
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || layout.numberOfGlyphs == 0)
        return;
    NSRect visible = view.visibleRect;
    CGFloat originX = view.textContainerOrigin.x;
    NSRect box = NSOffsetRect(visible, -originX, -view.textContainerOrigin.y);
    [layout ensureLayoutForBoundingRect:box inTextContainer:container];
    if (layout.numberOfGlyphs == 0)
        return;
    NSRange glyphRange = [layout glyphRangeForBoundingRect:box inTextContainer:container];
    if (glyphRange.length == 0 || glyphRange.location >= layout.numberOfGlyphs)
        return;
    __block NSUInteger found = NSNotFound;
    __block CGFloat foundX = 0;
    [layout enumerateLineFragmentsForGlyphRange:glyphRange usingBlock:^(NSRect fragment, NSRect used, NSTextContainer *textContainer, NSRange glyphs, BOOL *stop) {
        (void)textContainer;
        CGFloat usedLeft = originX + NSMinX(used);
        CGFloat usedRight = originX + NSMaxX(used);
        // A line that ends before the left edge, or starts to the right of it, has nothing to pin there.
        if (usedRight <= NSMinX(visible) + 0.5 || usedLeft > NSMinX(visible) + 1 || glyphs.length == 0)
            return;
        NSPoint point = NSMakePoint(NSMinX(visible) - originX, NSMinY(fragment) + 1);
        (void)[layout glyphIndexForPoint:point inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
        NSUInteger glyph = [layout glyphIndexForPoint:point inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
        if (glyph >= layout.numberOfGlyphs)
            glyph = layout.numberOfGlyphs - 1;
        if (!NSLocationInRange(glyph, glyphs))
            return;
        [layout ensureLayoutForGlyphRange:NSMakeRange(glyph, 1)];
        NSRect hit = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
        NSPoint location = [layout locationForGlyphAtIndex:glyph];
        foundX = originX + NSMinX(hit) + location.x;
        found = [layout characterIndexForGlyphAtIndex:glyph];
        *stop = YES;
    }];
    if (found == NSNotFound)
        return;
    anchor->characterX = found;
    anchor->pinX = foundX - NSMinX(view.visibleRect);
}

static NSValue *TSAnchorValue(TSScrollAnchor anchor)
{
    return [NSValue valueWithBytes:&anchor objCType:@encode(TSScrollAnchor)];
}

static TSScrollAnchor TSAnchorFromValue(NSValue *value)
{
    TSScrollAnchor anchor = {NSNotFound, 0, 0, 0, NSNotFound};
    if (value)
        [value getValue:&anchor size:sizeof anchor];
    return anchor;
}

static NSMapTable<NSTextView *, NSValue *> *TSAnchors(NSTextStorage *storage)
{
    NSMapTable *anchors = [NSMapTable weakToStrongObjectsMapTable];
    for (NSLayoutManager *layout in storage.layoutManagers) {
        for (NSTextContainer *container in layout.textContainers) {
            NSTextView *view = container.textView;
            if (view)
                [anchors setObject:TSAnchorValue(TSAnchorForView(view)) forKey:view];
        }
    }
    return anchors;
}

/// The same lines, in the text after `result`.
static NSMapTable<NSTextView *, NSValue *> *TSAnchorsFollowingEdits(NSMapTable<NSTextView *, NSValue *> *anchors, TSRegexReplaceAllResult *result)
{
    NSMapTable *mapped = [NSMapTable weakToStrongObjectsMapTable];
    for (NSTextView *view in anchors) {
        TSScrollAnchor anchor = TSAnchorFromValue([anchors objectForKey:view]);
        if (anchor.character != NSNotFound)
            anchor.character = [result locationByFollowingEdits:anchor.character];
        if (anchor.characterX != NSNotFound)
            anchor.characterX = [result locationByFollowingEdits:anchor.characterX];
        [mapped setObject:TSAnchorValue(anchor) forKey:view];
    }
    return mapped;
}

static CGFloat TSClampScroll(CGFloat value, CGFloat lower, CGFloat upper)
{
    if (upper < lower)
        upper = lower;
    if (value < lower)
        return lower;
    if (value > upper)
        return upper;
    return value;
}

static void TSScroll(NSTextView *view, CGFloat x, CGFloat y)
{
    NSScrollView *scroll = view.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!clip)
        return;
    NSRect frame = view.frame;
    x = TSClampScroll(x, NSMinX(frame), NSMaxX(frame) - NSWidth(clip.bounds));
    y = TSClampScroll(y, NSMinY(frame), NSMaxY(frame) - NSHeight(clip.bounds));
    [clip scrollToPoint:NSMakePoint(x, y)];
    [scroll reflectScrolledClipView:clip];
}

/// The logical line around `character`, capped so a file that is one long line is not laid out from the start (#72).
static NSRange TSLineRange(NSString *text, NSUInteger character)
{
    NSUInteger length = text.length;
    if (length == 0 || character == NSNotFound)
        return NSMakeRange(0, 0);
    character = MIN(character, length - 1);
    NSUInteger window = 8192;
    NSUInteger start = character > window ? character - window : 0;
    NSUInteger limit = MIN(length, character + window);
    if (start < character) {
        NSRange newline = [text rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(start, character - start)];
        if (newline.location != NSNotFound)
            start = NSMaxRange(newline);
    }
    NSUInteger end = limit;
    if (character < limit) {
        NSRange newline = [text rangeOfString:@"\n" options:0 range:NSMakeRange(character, limit - character)];
        if (newline.location != NSNotFound)
            end = MIN(length, NSMaxRange(newline));
    }
    return NSMakeRange(start, end - start);
}

/// Where `character` is drawn: the top of its line and the x of its glyph, in the text view. Laying out every
/// character above it would put the line on its final coordinates, and that stalls the main thread when the line is
/// near the end of a long file (#72). The logical line is laid out, so a wrap in the middle of it has a real
/// position, and then the lines around that position until it stops moving. `lineRight` is the right of that line, so
/// a horizontally scrolling source can be widened before the scroll is clamped into a frame that is still too narrow.
static BOOL TSPlaceOfCharacter(NSTextView *view, NSUInteger character, CGFloat *glyphX, CGFloat *lineTop, CGFloat *lineRight)
{
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || view.string.length == 0 || character == NSNotFound)
        return NO;
    character = MIN(character, view.string.length - 1);
    NSClipView *clip = view.enclosingScrollView.contentView;
    CGFloat viewport = clip ? NSHeight(clip.bounds) : NSHeight(view.visibleRect);
    NSRect fragment = NSZeroRect;
    NSUInteger glyph = NSNotFound;
    for (NSUInteger pass = 0; pass < 8; pass++) {
        [layout ensureLayoutForCharacterRange:TSLineRange(view.string, character)];
        if (layout.numberOfGlyphs == 0)
            return NO;
        glyph = [layout glyphIndexForCharacterAtIndex:character];
        if (glyph >= layout.numberOfGlyphs)
            glyph = layout.numberOfGlyphs - 1;
        NSRect next = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
        // Width too: a wrap's glyph x can still move after the fragment's y and height have settled.
        if (pass > 0 && fabs(next.origin.y - fragment.origin.y) < 0.5 && fabs(next.size.height - fragment.size.height) < 0.5
            && fabs(next.size.width - fragment.size.width) < 0.5) {
            fragment = next;
            break;
        }
        fragment = next;
        CGFloat height = MAX(viewport, NSHeight(next));
        CGFloat width = NSWidth(next);
        if (!(width > 1) || width > 100000)
            width = MAX(NSWidth(view.bounds), 1);
        [layout ensureLayoutForBoundingRect:NSMakeRect(0, NSMinY(next) - height, width, height * 2) inTextContainer:container];
    }
    NSPoint location = [layout locationForGlyphAtIndex:glyph];
    *glyphX = view.textContainerOrigin.x + NSMinX(fragment) + location.x;
    *lineTop = NSMinY(fragment) + view.textContainerOrigin.y;
    *lineRight = view.textContainerOrigin.x + NSMaxX(fragment);
    return YES;
}

/// The visual line at the top of the viewport. Its rectangle is only an estimate until the lines above it are laid
/// out, so a scroll aimed at that estimate can show a different line (#72).
static BOOL TSTopLine(NSTextView *view, NSRange *characterRange, CGFloat *lineTop, CGFloat *lineHeight)
{
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || view.string.length == 0)
        return NO;
    NSRect visible = view.visibleRect;
    [layout ensureLayoutForBoundingRect:NSOffsetRect(visible, -view.textContainerOrigin.x, -view.textContainerOrigin.y) inTextContainer:container];
    if (layout.numberOfGlyphs == 0)
        return NO;
    NSPoint point = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x + 1, NSMinY(visible) - view.textContainerOrigin.y + 1);
    NSUInteger glyph = [layout glyphIndexForPoint:point inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    if (glyph >= layout.numberOfGlyphs)
        glyph = layout.numberOfGlyphs - 1;
    NSRange glyphs;
    NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:&glyphs];
    NSRange characters = [layout characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
    if (characters.location == NSNotFound)
        return NO;
    *characterRange = characters;
    *lineTop = NSMinY(fragment) + view.textContainerOrigin.y;
    *lineHeight = MAX(NSHeight(fragment), 1);
    return YES;
}

/// The clip origin that puts `characterX` back where it was drawn. The saved origin is not that place once the text
/// before that character has changed width (#72). When it cannot be placed, the saved origin remains.
static CGFloat TSPinnedClipX(NSTextView *view, TSScrollAnchor anchor)
{
    NSClipView *clip = view.enclosingScrollView.contentView;
    if (!clip || anchor.characterX == NSNotFound)
        return anchor.clipX;
    CGFloat glyphX = 0, lineTop = 0, lineRight = 0;
    if (!TSPlaceOfCharacter(view, anchor.characterX, &glyphX, &lineTop, &lineRight))
        return anchor.clipX;
    // The edit can leave the frame at the window width until the long line is measured. Grow to this line first, or
    // the scroll clamps to the left and the text stays there after the frame catches up.
    if (view.horizontallyResizable && lineRight > NSWidth(view.frame) && lineRight < 1000000)
        [view setFrameSize:NSMakeSize(lineRight, NSHeight(view.frame))];
    return NSMinX(clip.bounds) + (glyphX - anchor.pinX - NSMinX(view.visibleRect));
}

/// After the estimated scroll, step by the lines actually on screen until `character` is on the top line, and at the
/// same horizontal place.
static void TSRefineAnchor(NSTextView *view, TSScrollAnchor anchor)
{
    if (anchor.character == NSNotFound || view.string.length == 0)
        return;
    NSUInteger character = MIN(anchor.character, view.string.length - 1);
    NSClipView *clip = view.enclosingScrollView.contentView;
    if (!clip)
        return;
    for (NSUInteger pass = 0; pass < 6; pass++) {
        CGFloat x = TSPinnedClipX(view, anchor);
        [view.layoutManager ensureLayoutForCharacterRange:TSLineRange(view.string, character)];
        NSRange line;
        CGFloat top = 0, height = 1;
        if (!TSTopLine(view, &line, &top, &height))
            return;
        if (NSLocationInRange(character, line)) {
            // A fragment that contains the character can still sit several lines away: its rectangle is an estimate
            // until the wrap is laid out, and a nudge of less than one line would leave the old wrap on screen (#72).
            CGFloat delta = (top - anchor.pin) - NSMinY(view.visibleRect);
            if (fabs(delta) > height * 30)
                delta = delta < 0 ? -height * 30 : height * 30;
            CGFloat beforeY = NSMinY(clip.bounds), beforeX = NSMinX(clip.bounds);
            if (fabs(delta) >= 0.5 || fabs(x - beforeX) >= 0.5)
                TSScroll(view, x, beforeY + delta);
            BOOL ySettled = fabs(delta) < height || fabs(NSMinY(clip.bounds) - beforeY) < 0.5;
            BOOL xSettled = fabs(NSMinX(clip.bounds) - x) < 1 || fabs(NSMinX(clip.bounds) - beforeX) < 0.5;
            if (ySettled && xSettled)
                return;
            continue;
        }
        CGFloat linesAway = character < line.location
            ? ((CGFloat)character - (CGFloat)line.location) / (CGFloat)MAX(line.length, 1)
            : ((CGFloat)character - (CGFloat)NSMaxRange(line)) / (CGFloat)MAX(line.length, 1) + 1;
        CGFloat delta = linesAway * height;
        if (fabs(delta) < height)
            delta = linesAway < 0 ? -height : height;
        CGFloat beforeY = NSMinY(clip.bounds), beforeX = NSMinX(clip.bounds);
        TSScroll(view, x, beforeY + delta);
        if (fabs(NSMinY(clip.bounds) - beforeY) < 0.5 && fabs(NSMinX(clip.bounds) - beforeX) < 0.5)
            return; // The text is already at the end of its scroll range.
    }
}

/// Puts each view back on the characters it showed (#72). A scroll offset the shorter text no longer reaches, down
/// or across, is brought back into the text instead of leaving the viewport past it.
static void TSApplyAnchors(NSMapTable<NSTextView *, NSValue *> *anchors)
{
    for (NSTextView *view in anchors) {
        NSClipView *clip = view.enclosingScrollView.contentView;
        if (!clip)
            continue;
        TSScrollAnchor anchor = TSAnchorFromValue([anchors objectForKey:view]);
        CGFloat x = TSPinnedClipX(view, anchor);
        CGFloat y = NSMinY(view.frame);
        CGFloat glyphX = 0, lineTop = 0, lineRight = 0;
        if (TSPlaceOfCharacter(view, anchor.character, &glyphX, &lineTop, &lineRight))
            y = NSMinY(clip.bounds) + (lineTop - anchor.pin - NSMinY(view.visibleRect));
        TSScroll(view, x, y);
        TSRefineAnchor(view, anchor);
    }
    // Laying out one part of a split source can move the other's estimate. Check again once both have been laid out.
    for (NSTextView *view in anchors)
        TSRefineAnchor(view, TSAnchorFromValue([anchors objectForKey:view]));
}

static NSMapTable<NSTextView *, NSArray<NSValue *> *> *TSSelections(NSTextStorage *storage)
{
    NSMapTable *selections = [NSMapTable weakToStrongObjectsMapTable];
    for (NSLayoutManager *layout in storage.layoutManagers) {
        for (NSTextContainer *container in layout.textContainers) {
            NSTextView *view = container.textView;
            if (view)
                [selections setObject:[view.selectedRanges copy] forKey:view];
        }
    }
    return selections;
}

/// `ranges` followed through the length changes.
static NSArray<NSValue *> *TSRangesFollowingEdits(NSArray<NSValue *> *ranges, TSRegexReplaceAllResult *result)
{
    NSMutableArray<NSValue *> *mapped = [NSMutableArray arrayWithCapacity:ranges.count];
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        NSUInteger start = [result locationByFollowingEdits:range.location];
        NSUInteger end = [result locationByFollowingEdits:NSMaxRange(range)];
        if (end < start)
            end = start;
        [mapped addObject:[NSValue valueWithRange:NSMakeRange(start, end - start)]];
    }
    if (mapped.count == 0)
        [mapped addObject:[NSValue valueWithRange:NSMakeRange(0, 0)]];
    return mapped;
}

/// The selections to put back after the replacement. The target's selection becomes the replaced scope when the
/// search was limited to it; every other view keeps its caret on the same character.
static NSMapTable<NSTextView *, NSArray<NSValue *> *> *TSSelectionsAfterReplace(NSMapTable<NSTextView *, NSArray<NSValue *> *> *previous,
                                                                                TSRegexReplaceAllResult *result, NSTextView *target)
{
    NSMapTable *kept = [NSMapTable weakToStrongObjectsMapTable];
    for (NSTextView *view in previous) {
        NSArray<NSValue *> *ranges = (view == target && result.selectedRanges.count > 0) ? result.selectedRanges
            : TSRangesFollowingEdits([previous objectForKey:view], result);
        [kept setObject:ranges forKey:view];
    }
    return kept;
}

static void TSApplySelections(NSMapTable<NSTextView *, NSArray<NSValue *> *> *selections)
{
    for (NSTextView *view in selections) {
        NSUInteger limit = view.string.length;
        NSMutableArray<NSValue *> *clamped = [NSMutableArray array];
        for (NSValue *value in [selections objectForKey:view]) {
            NSRange range = value.rangeValue;
            if (range.location > limit)
                range = NSMakeRange(limit, 0);
            else if (NSMaxRange(range) > limit)
                range.length = limit - range.location;
            [clamped addObject:[NSValue valueWithRange:range]];
        }
        if (clamped.count > 0)
            view.selectedRanges = clamped;
    }
}

/// One undo step's worth of places. Registered inside the text change's group. Undoing puts `before` back, and that
/// registers the redo of `after`, which registers this again, so a later undo keeps doing it (#72). The text change
/// itself is still in the group: the place is put back on the next pass, once that change has been undone or redone.
static void TSRegisterPlaceUndo(NSUndoManager *undo, NSTextView *view,
                                NSMapTable<NSTextView *, NSArray<NSValue *> *> *beforeSelections,
                                NSMapTable<NSTextView *, NSValue *> *beforeAnchors,
                                NSMapTable<NSTextView *, NSArray<NSValue *> *> *afterSelections,
                                NSMapTable<NSTextView *, NSValue *> *afterAnchors)
{
    if (!undo)
        return;
    [undo registerUndoWithTarget:view handler:^(NSTextView *current) {
        NSUndoManager *manager = current.undoManager;
        [manager registerUndoWithTarget:current handler:^(NSTextView *again) {
            TSRegisterPlaceUndo(again.undoManager, again, beforeSelections, beforeAnchors, afterSelections, afterAnchors);
            dispatch_async(dispatch_get_main_queue(), ^{
                NSUndoManager *redo = again.undoManager;
                [redo disableUndoRegistration];
                TSApplySelections(afterSelections);
                TSApplyAnchors(afterAnchors);
                [redo enableUndoRegistration];
            });
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUndoManager *back = current.undoManager;
            [back disableUndoRegistration];
            TSApplySelections(beforeSelections);
            TSApplyAnchors(beforeAnchors);
            [back enableUndoRegistration];
        });
    }];
}

@implementation TSAdvancedFindController (Tasks)

/// Replace All, undone at once.
- (BOOL)replaceAllInTextView:(NSTextView *)textView inSelection:(BOOL)inSelection
{
    TSRegexTextFind *find = [self textFindForTextView:textView inSelection:inSelection quiet:NO];
    if (!find)
        return NO; // already beeped and reported
    TSRegexReplacementTemplate *template = [[TSRegexReplacementTemplate alloc] initWithString:self.settings.replaceString pattern:find.pattern
                                                                                         syntax:self.settings.replacementSyntax];
    [self.settings noteReplaceString];
    NSString *searching = TSLocalized(@"AdvancedFind.Searching", @"Searching…");
    NSString *format = TSLocalized(@"AdvancedFind.SearchingCount", @"Searching… %lu");
    [self runTaskNamed:TSLocalized(@"AdvancedFind.ReplaceAll", @"Replace All") inTextView:textView work:^id _Nullable(TSAdvancedFindTask *task) {
        task.message = searching;
        // How far the search has come, and the matches found so far
        return [find replaceAllWithTemplate:template cancellation:task.cancellation progress:^(double fraction, NSUInteger count) {
            task.progress = fraction;
            task.message = [NSString localizedStringWithFormat:format, (unsigned long)count];
        }];
    } completion:^(TSRegexReplaceAllResult *_Nullable found) {
        if (!found)
            return;
        TSRegexReplaceAllResult *result = (TSRegexReplaceAllResult *_Nonnull)found;
        if (result.numberOfMatches == 0) {
            self.beepHandler();
            [self report:TSLocalized(@"AdvancedFind.NotFound", @"Not found") isError:NO];
            return;
        }
        // Rewriting a scope makes NSLayoutManager resize the text view and scroll a stale range into view, so the
        // text jumps (#72). Remember the top line, the character under the left edge (a lower line, when the top line
        // ends sooner), and the carets. The replacement contains the carets, and the text view would otherwise leave
        // them at the end of the new text.
        NSTextStorage *storage = textView.textStorage;
        NSMapTable *previousAnchors = storage ? TSAnchors(storage) : [NSMapTable weakToStrongObjectsMapTable];
        NSMapTable *keptAnchors = TSAnchorsFollowingEdits(previousAnchors, result);
        NSMapTable *previous = storage ? TSSelections(storage) : [NSMapTable weakToStrongObjectsMapTable];
        NSMapTable *kept = TSSelectionsAfterReplace(previous, result, textView);
        BOOL applied = [self applyReplacements:result.replacements toTextView:textView selectedRanges:nil
                                    actionName:TSLocalized(@"AdvancedFind.ReplaceAllAction", @"Replace All")];
        if (!applied)
            return; // Nothing was registered, so a refused change leaves the redo stack as it was (#72).
        NSUndoManager *undo = textView.undoManager;
        if (undo && result.replacements.count > 0) {
            // Inside the group the text change opened, so it is the same undo step. It runs before the text is put
            // back; the line and the carets are put back on the next pass, and the redo does the same the other way,
            // including the undo after that redo (#72).
            TSRegisterPlaceUndo(undo, textView, previous, previousAnchors, kept, keptAnchors);
        }
        [undo disableUndoRegistration];
        TSApplySelections(kept);
        TSApplyAnchors(keptAnchors);
        [undo enableUndoRegistration];
        NSString *replaced = TSLocalized(@"AdvancedFind.Replaced", @"%lu replaced");
        [self report:[NSString stringWithFormat:replaced, (unsigned long)result.numberOfMatches] isError:NO];
    }];
    return YES;
}

/// Hands the list of every match to `findAllHandler`; nothing is listed when there is no match. As in OgreKit, the
/// text is not highlighted: that is "Highlight All".
- (BOOL)findAllInTextView:(NSTextView *)textView
{
    TSRegexTextFind *find = [self textFindForTextView:textView inSelection:self.settings.inSelection quiet:NO];
    NSTextStorage *storage = textView.textStorage;
    if (!find || !storage)
        return NO; // already beeped and reported
    [self.settings noteFindString];
    NSString *findString = self.settings.findString;
    NSString *searching = TSLocalized(@"AdvancedFind.Searching", @"Searching…");
    NSString *format = TSLocalized(@"AdvancedFind.SearchingCount", @"Searching… %lu");
    // A console or a log may receive output meanwhile: the matches then follow those changes, as they follow later
    // ones (an edit that touched a match makes it stale), and are not thrown away.
    [self runTaskNamed:TSLocalized(@"AdvancedFind.FindAll", @"Find All") inTextView:textView followingEditsWork:^id _Nullable(TSAdvancedFindTask *task) {
        task.message = searching;
        return [TSAdvancedFindResults itemsOfFind:find cancellation:task.cancellation progress:^(double fraction, NSUInteger count) {
            task.progress = fraction;
            task.message = [NSString localizedStringWithFormat:format, (unsigned long)count];
        }];
    } completion:^(NSArray<TSAdvancedFindResultItem *> *_Nullable listed, NSArray<TSAdvancedFindTextEdit *> *edits) {
        if (!listed)
            return;
        NSArray<TSAdvancedFindResultItem *> *items = (NSArray<TSAdvancedFindResultItem *> *_Nonnull)listed;
        if (items.count == 0) {
            self.beepHandler();
            [self report:TSLocalized(@"AdvancedFind.NotFound", @"Not found") isError:NO];
            return;
        }
        TSAdvancedFindResults *results = [[TSAdvancedFindResults alloc] initWithTextStorage:storage find:find findString:findString items:items];
        [results followEdits:edits];
        NSString *found = TSLocalized(@"AdvancedFind.Found", @"%lu found");
        [self report:[NSString stringWithFormat:found, (unsigned long)items.count] isError:NO];
        if (self.findAllHandler)
            self.findAllHandler(results, textView);
    }];
    return YES;
}

@end
