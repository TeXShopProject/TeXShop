// SPDX-License-Identifier: GPL-2.0-or-later
// Replace All and Find All as background tasks: the search runs on a copy of the text, the text views are read-only
// meanwhile, and the result is applied in one step at the end.
#import "TSAdvancedFindController+Private.h"

#define TSLocalized TSAdvancedFindLocalized

/// The line at the top of a text view, in that view's text: which character, and how far its line sits from the top of
/// the viewport. A split source has two. The clip origin is not enough: the replacement changes the text view's
/// height, so the same origin shows other lines, or nothing when the text becomes shorter than that origin (#72).
typedef struct {
    NSUInteger character;
    CGFloat pin;
    CGFloat clipX;
} TSScrollAnchor;

static TSScrollAnchor TSAnchorForView(NSTextView *view)
{
    TSScrollAnchor anchor = {NSNotFound, 0, 0};
    NSClipView *clip = view.enclosingScrollView.contentView;
    if (clip)
        anchor.clipX = clip.bounds.origin.x;
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || view.string.length == 0 || layout.numberOfGlyphs == 0)
        return anchor;
    NSRect visible = view.visibleRect;
    NSPoint inContainer = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x,
                                      NSMinY(visible) + 1 - view.textContainerOrigin.y);
    NSUInteger glyph = [layout glyphIndexForPoint:inContainer inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    if (glyph >= layout.numberOfGlyphs)
        glyph = layout.numberOfGlyphs - 1;
    NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    anchor.character = [layout characterIndexForGlyphAtIndex:glyph];
    anchor.pin = fragment.origin.y + view.textContainerOrigin.y - NSMinY(visible);
    return anchor;
}

static NSValue *TSAnchorValue(TSScrollAnchor anchor)
{
    return [NSValue valueWithBytes:&anchor objCType:@encode(TSScrollAnchor)];
}

static TSScrollAnchor TSAnchorFromValue(NSValue *value)
{
    TSScrollAnchor anchor = {NSNotFound, 0, 0};
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
        [mapped setObject:TSAnchorValue(anchor) forKey:view];
    }
    return mapped;
}

/// Puts each view's line back where it was. The distance above the viewport is only an estimate until the text up
/// to the anchor is laid out, and that estimate moves the line after the replacement (#72). A line the shorter text
/// no longer reaches is brought into view instead of leaving the viewport below the text.
static void TSApplyAnchors(NSMapTable<NSTextView *, NSValue *> *anchors)
{
    for (NSTextView *view in anchors) {
        NSScrollView *scroll = view.enclosingScrollView;
        NSClipView *clip = scroll.contentView;
        if (!clip)
            continue;
        TSScrollAnchor anchor = TSAnchorFromValue([anchors objectForKey:view]);
        NSLayoutManager *layout = view.layoutManager;
        NSTextContainer *container = view.textContainer;
        CGFloat y = view.frame.origin.y;
        if (anchor.character != NSNotFound && layout && container && view.string.length > 0) {
            NSUInteger character = MIN(anchor.character, view.string.length - 1);
            [layout ensureLayoutForCharacterRange:NSMakeRange(0, character + 1)];
            NSUInteger glyph = [layout glyphIndexForCharacterAtIndex:character];
            if (layout.numberOfGlyphs > 0) {
                if (glyph >= layout.numberOfGlyphs)
                    glyph = layout.numberOfGlyphs - 1;
                NSRect fragment = [layout lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
                CGFloat lineTop = fragment.origin.y + view.textContainerOrigin.y;
                y = clip.bounds.origin.y + (lineTop - anchor.pin - NSMinY(view.visibleRect));
            }
        }
        NSRect frame = view.frame;
        CGFloat minY = frame.origin.y;
        CGFloat maxY = NSMaxY(frame) - clip.bounds.size.height;
        if (maxY < minY)
            maxY = minY;
        if (y < minY)
            y = minY;
        else if (y > maxY)
            y = maxY;
        [clip scrollToPoint:NSMakePoint(anchor.clipX, y)];
        [scroll reflectScrolledClipView:clip];
    }
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
        // text jumps (#72). Remember the line at the top of every view, and the carets: the replacement contains
        // them, and the text view would otherwise leave them at the end of the new text.
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
