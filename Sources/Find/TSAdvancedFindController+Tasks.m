// SPDX-License-Identifier: GPL-2.0-or-later
// Replace All and Find All as background tasks: the search runs on a copy of the text, the text views are read-only
// meanwhile, and the result is applied in one step at the end.
#import "TSAdvancedFindController+Private.h"
#import <objc/runtime.h>

#define TSLocalized TSAdvancedFindLocalized

/// Where to put the view back. `character` is the left of the top line, and `pin` is how far that line sits below the
/// top of `visibleRect`. That line may end before the left edge: a short line scrolled sideways has no character
/// there, and the long line under it is what the reader is looking at. `characterX` is the character under the left
/// edge on the first line that reaches it, and `pinX` is how far that glyph sits from the left edge. `clipX` and
/// `clipY` are the clip origin at that moment. A source under the toolbar scrolls to a negative origin
/// (`contentInsets`); `visibleRect` is cut off at the text, so `gapX` and `gapY` are what that cuts off
/// (`visibleRect` origin minus the clip origin). The clip is put back at the line, minus the pin, minus that gap.
/// `clipX` alone is the fallback when the left-edge character cannot be placed. When `keepsOrigin` is set, every
/// match kept its length and its line breaks and the source font is fixed-pitch, so the columns do not move and the
/// clip origin is put back as it was (#72).
typedef struct {
    NSUInteger character;
    CGFloat pin;
    CGFloat pinX;
    CGFloat clipX;
    NSUInteger characterX;
    CGFloat clipY;
    BOOL keepsOrigin;
    CGFloat gapX;
    CGFloat gapY;
} TSScrollAnchor;

static void TSReadHorizontalAnchor(NSTextView *view, TSScrollAnchor *anchor);

/// The top of the text the reader sees. Under a toolbar the clip origin sits `contentInsets.top` above that line.
/// At the top of the file the clip is already above the text, and `visibleRect` starts on the text. Further down,
/// `visibleRect` includes the band the toolbar covers, so the first visible line is one inset below its top (#72).
static CGFloat TSContentTop(NSTextView *view)
{
    NSRect visible = view.visibleRect;
    NSClipView *clip = view.enclosingScrollView.contentView;
    if (!clip)
        return NSMinY(visible);
    CGFloat belowBar = NSMinY(clip.bounds) + view.enclosingScrollView.contentInsets.top;
    if (belowBar <= NSMinY(visible) + 0.5)
        return NSMinY(visible);
    return belowBar;
}

static TSScrollAnchor TSAnchorForView(NSTextView *view)
{
    TSScrollAnchor anchor = {NSNotFound, 0, 0, 0, NSNotFound};
    NSClipView *clip = view.enclosingScrollView.contentView;
    if (clip) {
        // Before any layout. Measuring the top line can resize the text view, and that resize scrolls (#72).
        anchor.clipX = clip.bounds.origin.x;
        anchor.clipY = clip.bounds.origin.y;
        // The toolbar inset scrolls the clip above the text. visibleRect then starts at the text, and a pin measured
        // from it no longer knows how far above the text the clip was (#72).
        NSRect visible = view.visibleRect;
        if (!NSIsEmptyRect(visible)) {
            anchor.gapX = NSMinX(visible) - anchor.clipX;
            anchor.gapY = NSMinY(visible) - anchor.clipY;
        }
    }
    NSLayoutManager *layout = view.layoutManager;
    NSTextContainer *container = view.textContainer;
    if (!layout || !container || view.string.length == 0)
        return anchor;
    // setTextColor: leaves the first glyphIndexForPoint on another wrap of the line than the one on screen. A theme
    // does that for each part of a split source. The next question returns the wrap that is painted (#72).
    NSRect visible = view.visibleRect;
    // The line under the toolbar, not the one the bar covers. Pinning the covered line leaves the visible line free
    // to slip by a wrap when the text above it changes height (#72).
    NSPoint inContainer = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x,
                                      TSContentTop(view) + 1 - view.textContainerOrigin.y);
    if (layout.numberOfGlyphs > 0)
        (void)[layout glyphIndexForPoint:inContainer inTextContainer:container fractionOfDistanceThroughGlyph:NULL];
    if (layout.numberOfGlyphs == 0)
        return anchor;
    visible = view.visibleRect;
    inContainer = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x,
                              TSContentTop(view) + 1 - view.textContainerOrigin.y);
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
    CGFloat contentTop = TSContentTop(view);
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
        // A line hidden under the toolbar, or one that ends before the left edge, or one that starts to the right
        // of it, has nothing to pin on the visible edge.
        if (view.textContainerOrigin.y + NSMaxY(fragment) <= contentTop + 0.5)
            return;
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

/// Laying out a replacement resizes the text view. `_resizeTextViewForTextContainer:` then scrolls, and so does
/// `_scrollRangeToVisible:forceCenter:` for the caret. Both go through `scrollClipView:toPoint:`, which calls
/// `scrollToPoint:` and `translateOriginToPoint:`. A direct `setBoundsOrigin:` is the other way the frame change
/// moves the clip. The resize also goes through `_reflectDocumentViewFrameChange` → `_scrollTo:` → `tile` →
/// `translateOriginToPoint:`, which calls neither of those. With wrapping off, that draws the left edge for one
/// frame before the anchor is put back, even when the replacement keeps the advance (#72). While a hold is in
/// force all three do nothing. The anchor restore is the scroll that should happen.
static IMP TSOriginalScrollClipView;
static IMP TSOriginalSetBoundsOrigin;
static IMP TSOriginalTranslateOrigin;
static int TSClipHoldCount;
static BOOL TSAllowClipScroll;
/// Undo managers that still owe a hold to a Replace All redo. The number is how many later undos have stacked
/// their own redo above that one. Zero means the next redo is the Replace All redo (#72).
static NSMapTable<NSUndoManager *, NSNumber *> *TSRedoHolds;

static void TSExpectRedoHold(NSUndoManager *undo)
{
    if (!undo)
        return;
    if (!TSRedoHolds)
        TSRedoHolds = [NSMapTable weakToStrongObjectsMapTable];
    // WillUndo for this undo already ran, before the mark existed, so it did not count itself.
    [TSRedoHolds setObject:@0 forKey:undo];
}

/// YES when this redo is the Replace All redo and must hold. The caller pushes; the redo handler pops.
/// A redo stacked above that one returns NO and leaves the mark for the Replace All redo underneath.
static BOOL TSConsumeRedoHold(NSUndoManager *undo)
{
    NSNumber *skip = [TSRedoHolds objectForKey:undo];
    if (!skip)
        return NO;
    NSInteger left = skip.integerValue;
    if (left > 0) {
        [TSRedoHolds setObject:@(left - 1) forKey:undo];
        return NO;
    }
    [TSRedoHolds removeObjectForKey:undo];
    return YES;
}

static void TSPushClipHold(void);
static void TSPopClipHold(void);

static void TSHeldScrollClipView(NSScrollView *scroll, SEL _cmd, NSClipView *clip, NSPoint point)
{
    if (TSClipHoldCount > 0 && !TSAllowClipScroll)
        return;
    ((void (*)(id, SEL, NSClipView *, NSPoint))TSOriginalScrollClipView)(scroll, @selector(scrollClipView:toPoint:), clip, point);
}

static void TSHeldSetBoundsOrigin(NSClipView *clip, SEL _cmd, NSPoint origin)
{
    if (TSClipHoldCount > 0 && !TSAllowClipScroll)
        return;
    ((void (*)(id, SEL, NSPoint))TSOriginalSetBoundsOrigin)(clip, @selector(setBoundsOrigin:), origin);
}

static void TSHeldTranslateOrigin(NSView *view, SEL _cmd, NSPoint point)
{
    if (TSClipHoldCount > 0 && !TSAllowClipScroll && [view isKindOfClass:NSClipView.class])
        return;
    ((void (*)(id, SEL, NSPoint))TSOriginalTranslateOrigin)(view, @selector(translateOriginToPoint:), point);
}

static void TSInstallClipHold(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method scroll = class_getInstanceMethod(NSScrollView.class, @selector(scrollClipView:toPoint:));
        TSOriginalScrollClipView = method_setImplementation(scroll, (IMP)TSHeldScrollClipView);
        Method origin = class_getInstanceMethod(NSClipView.class, @selector(setBoundsOrigin:));
        TSOriginalSetBoundsOrigin = method_setImplementation(origin, (IMP)TSHeldSetBoundsOrigin);
        Method translate = class_getInstanceMethod(NSView.class, @selector(translateOriginToPoint:));
        TSOriginalTranslateOrigin = method_setImplementation(translate, (IMP)TSHeldTranslateOrigin);
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:NSUndoManagerWillUndoChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            // Posted before the undo handlers. A later undo (typing, after Replace All was undone) stacks its redo
            // on top of the Replace All redo. Counting it here keeps the hold for that redo, instead of spending it
            // on a redo that has no place handler and never pops (#72).
            NSUndoManager *undo = note.object;
            NSNumber *skip = [TSRedoHolds objectForKey:undo];
            if (undo.isUndoing && skip)
                [TSRedoHolds setObject:@(skip.integerValue + 1) forKey:undo];
        }];
        [center addObserverForName:NSUndoManagerWillRedoChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            // Posted before the text redo. The place handler runs after that text change, which is too late to stop
            // its scroll (#72).
            if (!TSConsumeRedoHold(note.object))
                return;
            TSPushClipHold();
            // The place handler pops before the run loop continues. A redo that has no place handler must not leave
            // the process-wide hold in place.
            dispatch_async(dispatch_get_main_queue(), ^{
                TSPopClipHold();
            });
        }];
        [center addObserverForName:NSUndoManagerDidCloseUndoGroupNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            NSUndoManager *undo = note.object;
            if (!undo.isUndoing && !undo.isRedoing)
                [TSRedoHolds removeObjectForKey:undo];
        }];
    });
}

static void TSPushClipHold(void)
{
    TSInstallClipHold();
    TSClipHoldCount++;
}

static void TSPopClipHold(void)
{
    if (TSClipHoldCount > 0)
        TSClipHoldCount--;
}

static void TSFinishPlace(NSMapTable<NSTextView *, NSValue *> *anchors);

static void TSScroll(NSTextView *view, CGFloat x, CGFloat y)
{
    NSScrollView *scroll = view.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    if (!clip)
        return;
    // The text frame starts at 0, so a clamp to that frame cannot return to the toolbar inset (a negative origin) and
    // stops short of the bottom by the bottom inset. constrainBoundsRect: is the range the scroller itself uses (#72).
    NSRect proposed = clip.bounds;
    proposed.origin = NSMakePoint(x, y);
    NSPoint point = [clip constrainBoundsRect:proposed].origin;
    x = point.x;
    y = point.y;
    // A correction of less than a point is the scroller's pixel alignment. Applying it moves the clip the test, and
    // the eye, can see as a jump (#72).
    if (fabs(x - clip.bounds.origin.x) <= 1 && fabs(y - clip.bounds.origin.y) <= 1) {
        [scroll.verticalRulerView setNeedsDisplay:YES];
        [scroll.horizontalRulerView setNeedsDisplay:YES];
        return;
    }
    TSAllowClipScroll = YES;
    [clip scrollToPoint:NSMakePoint(x, y)];
    [scroll reflectScrolledClipView:clip];
    TSAllowClipScroll = NO;
    // The line numbers draw from the clip origin. A scroll that the ruler missed leaves them on the old lines (#72).
    [scroll.verticalRulerView setNeedsDisplay:YES];
    [scroll.horizontalRulerView setNeedsDisplay:YES];
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
    NSPoint point = NSMakePoint(NSMinX(visible) - view.textContainerOrigin.x + 1, TSContentTop(view) + 1 - view.textContainerOrigin.y);
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
    // Absolute, from the origin that was saved. Adding it to the clip where the edit left the view would keep a jump
    // that had already happened, including one into the toolbar inset (#72).
    return glyphX - anchor.pinX - anchor.gapX;
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
            // The gap is the toolbar inset that visibleRect cuts off. Without it the top of a document under the
            // toolbar is put at y 0, and the first lines slide under the bar.
            // From the current visible top, not the gap saved earlier. A wrapped layout renorms its coordinates
            // (the clip origin changes by the same amount) and the saved gap would follow the old system (#72).
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
        CGFloat glyphX = 0, lineTop = 0, lineRight = 0;
        BOOL placed = anchor.character != NSNotFound && TSPlaceOfCharacter(view, anchor.character, &glyphX, &lineTop, &lineRight);
        // The clip has not moved: follow the line from where the viewport is now. A wrapped layout can renorm its
        // coordinates under a clip that did not scroll, and the characters slide unless the origin follows them.
        // The clip has moved: aim at the saved origin, or an edit that landed inside the toolbar inset stays there.
        CGFloat y = anchor.clipY;
        if (placed) {
            CGFloat relative = NSMinY(clip.bounds) + (lineTop - anchor.pin - NSMinY(view.visibleRect));
            CGFloat absolute = lineTop - anchor.pin - anchor.gapY;
            y = fabs(NSMinY(clip.bounds) - anchor.clipY) <= 1 ? relative : absolute;
        }
        if (anchor.keepsOrigin) {
            // The frame can still be the window size when a long line has not been measured again. Grow past the
            // saved origin first, or constrainBoundsRect: pulls the clip to the corner (#72). A negative origin is
            // the toolbar inset: the text does not have to grow to reach it.
            NSEdgeInsets insets = view.enclosingScrollView.contentInsets;
            CGFloat width = NSWidth(view.frame), height = NSHeight(view.frame);
            if (view.horizontallyResizable)
                width = MAX(width, anchor.clipX + NSWidth(clip.bounds) - insets.right + 2);
            if (view.verticallyResizable && anchor.clipY > 0)
                height = MAX(height, anchor.clipY + NSHeight(clip.bounds) - insets.bottom + 2);
            if (width > NSWidth(view.frame) + 0.5 || height > NSHeight(view.frame) + 0.5)
                [view setFrameSize:NSMakeSize(MAX(width, 0), MAX(height, 0))];
            // Same columns: keep the origin, unless the layout renormed and the line now sits elsewhere.
            if (!placed || fabs(y - anchor.clipY) <= 1)
                y = anchor.clipY;
            TSScroll(view, anchor.clipX, y);
            continue;
        }
        CGFloat x = TSPinnedClipX(view, anchor);
        TSScroll(view, x, y);
        TSRefineAnchor(view, anchor);
    }
    // Laying out one part of a split source can move the other's estimate. Check again once both have been laid out.
    // An origin that was saved exactly is not an estimate, and laying it out again is what scrolls (#72).
    for (NSTextView *view in anchors) {
        TSScrollAnchor anchor = TSAnchorFromValue([anchors objectForKey:view]);
        if (!anchor.keepsOrigin)
            TSRefineAnchor(view, anchor);
    }
}

/// The replacement invalidates layout. The next measurement corrects a tall estimate of the height and scrolls to
/// follow that correction (`_resizeTextViewForTextContainer:` and the caret's `_scrollRangeToVisible:`). Doing the
/// layout while the hold is up swallows those scrolls; the anchor is what remains (#72).
static void TSFinishPlace(NSMapTable<NSTextView *, NSValue *> *anchors)
{
    // A full layout renorms a wrapped text view whose fragments still sit at a large negative y. The anchor was
    // measured in that system; laying it out first makes the saved pin aim thousands of points away. The toolbar
    // inset is only a few dozen points, and that case does need the layout or the next measurement scrolls (#72).
    BOOL estimated = NO;
    for (NSTextView *view in anchors) {
        NSClipView *clip = view.enclosingScrollView.contentView;
        if (clip && NSMinY(clip.bounds) < -200)
            estimated = YES;
    }
    if (!estimated) {
        for (NSTextView *view in anchors) {
            NSLayoutManager *layout = view.layoutManager;
            NSTextContainer *container = view.textContainer;
            if (layout && container)
                [layout ensureLayoutForTextContainer:container];
        }
    }
    TSApplyAnchors(anchors);
}

/// The origin from before the edit, without laying the document out. The resize tried to show the left edge. The hold
/// swallows that scroll, and this puts the origin back when the frame can still reach it. A target the frame cannot
/// reach is left where it is: scrolling there would clamp to the corner. The next turn lays the text out once and
/// places the anchor (#72).
static void TSRestoreClipOrigin(NSMapTable<NSTextView *, NSValue *> *anchors)
{
    for (NSTextView *view in anchors) {
        NSClipView *clip = view.enclosingScrollView.contentView;
        if (!clip)
            continue;
        TSScrollAnchor anchor = TSAnchorFromValue([anchors objectForKey:view]);
        NSRect proposed = clip.bounds;
        proposed.origin = NSMakePoint(anchor.clipX, anchor.clipY);
        NSPoint reachable = [clip constrainBoundsRect:proposed].origin;
        // The edit can leave the frame at the window width. Scrolling now would clamp to the corner and draw it.
        // The next turn grows the frame, then scrolls (#72).
        if (fabs(reachable.x - anchor.clipX) > 1 || fabs(reachable.y - anchor.clipY) > 1)
            continue;
        TSScroll(view, anchor.clipX, anchor.clipY);
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
        if (clamped.count > 0) {
            // stillSelecting leaves the caret where it is. The plain setter scrolls it into view, and with the line
            // only estimated that scroll puts the caret's line at the top of the source (#72).
            [view setSelectedRanges:clamped affinity:view.selectionAffinity stillSelecting:YES];
            [view updateInsertionPointStateAndRestartTimer:YES];
        }
    }
}

static BOOL TSTextViewUsesFixedPitch(NSTextView *view)
{
    NSTextStorage *storage = view.textStorage;
    if (!storage || storage.length == 0)
        return NO;
    NSFont *font = [storage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    return font.isFixedPitch;
}

/// Same length and the same line breaks: in a fixed-pitch source the columns on screen do not move (#72).
static BOOL TSReplacementsKeepColumns(NSString *text, NSArray<TSRegexFindReplacement *> *replacements)
{
    if (replacements.count == 0 || !text)
        return NO;
    NSCharacterSet *breaks = NSCharacterSet.newlineCharacterSet;
    for (TSRegexFindReplacement *replacement in replacements) {
        NSRange range = replacement.range;
        NSString *inserted = replacement.string ?: @"";
        if (inserted.length != range.length || NSMaxRange(range) > text.length)
            return NO;
        NSString *previous = [text substringWithRange:range];
        NSUInteger oldBreaks = 0, newBreaks = 0;
        for (NSUInteger i = 0; i < previous.length; i++)
            if ([breaks characterIsMember:[previous characterAtIndex:i]])
                oldBreaks++;
        for (NSUInteger i = 0; i < inserted.length; i++)
            if ([breaks characterIsMember:[inserted characterAtIndex:i]])
                newBreaks++;
        if (oldBreaks != newBreaks)
            return NO;
    }
    return YES;
}

static void TSSetAnchorsKeepOrigin(NSMapTable<NSTextView *, NSValue *> *anchors)
{
    for (NSTextView *view in [anchors copy]) {
        TSScrollAnchor anchor = TSAnchorFromValue([anchors objectForKey:view]);
        anchor.keepsOrigin = YES;
        [anchors setObject:TSAnchorValue(anchor) forKey:view];
    }
}

/// One undo step's worth of places. Registered inside the text change's group, so this handler runs before the text
/// is put back. The hold covers that text change. The place is put back when the undo finishes, still inside `-undo`,
/// and the redo handler does the same the other way once the text has been put forward again (#72).
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
            // WillRedo pushed the hold before the text redo, which is registered ahead of this handler.
            NSUndoManager *redoUndo = again.undoManager;
            TSRegisterPlaceUndo(redoUndo, again, beforeSelections, beforeAnchors, afterSelections, afterAnchors);
            if (TSClipHoldCount == 0)
                TSPushClipHold();
            [redoUndo disableUndoRegistration];
            TSApplySelections(afterSelections);
            TSFinishPlace(afterAnchors);
            [redoUndo enableUndoRegistration];
            TSPopClipHold();
        }];
        TSExpectRedoHold(manager);
        TSPushClipHold();
        __block id token = nil;
        token = [NSNotificationCenter.defaultCenter addObserverForName:NSUndoManagerDidUndoChangeNotification object:manager
                                                                 queue:nil usingBlock:^(NSNotification *note) {
            (void)note;
            [NSNotificationCenter.defaultCenter removeObserver:token];
            NSUndoManager *undo = current.undoManager;
            [undo disableUndoRegistration];
            TSApplySelections(beforeSelections);
            TSFinishPlace(beforeAnchors);
            [undo enableUndoRegistration];
            TSPopClipHold();
        }];
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
        // them at the end of the new text. The hold covers the edit, which is what scrolls onto the caret's line.
        NSTextStorage *storage = textView.textStorage;
        BOOL keepsColumns = TSTextViewUsesFixedPitch(textView) && storage
            && TSReplacementsKeepColumns(storage.string, result.replacements);
        // Measured before the hold. The first glyph query after setTextColor: names the wrong wrap, and blocking the
        // scroll that query makes leaves the second query wrong too (#72).
        NSMapTable *previousAnchors = storage ? TSAnchors(storage) : [NSMapTable weakToStrongObjectsMapTable];
        if (keepsColumns)
            TSSetAnchorsKeepOrigin(previousAnchors);
        TSPushClipHold();
        NSMapTable *keptAnchors = TSAnchorsFollowingEdits(previousAnchors, result);
        NSMapTable *previous = storage ? TSSelections(storage) : [NSMapTable weakToStrongObjectsMapTable];
        NSMapTable *kept = TSSelectionsAfterReplace(previous, result, textView);
        BOOL applied = [self applyReplacements:result.replacements toTextView:textView selectedRanges:nil
                                    actionName:TSLocalized(@"AdvancedFind.ReplaceAllAction", @"Replace All")];
        if (!applied) {
            TSPopClipHold();
            return; // Nothing was registered, so a refused change leaves the redo stack as it was (#72).
        }
        NSUndoManager *undo = textView.undoManager;
        if (undo && result.replacements.count > 0) {
            // Inside the group the text change opened, so it is the same undo step. It runs before the text is put
            // back; the line and the carets are put back on the next pass, and the redo does the same the other way,
            // including the undo after that redo (#72).
            TSRegisterPlaceUndo(undo, textView, previous, previousAnchors, kept, keptAnchors);
        }
        [undo disableUndoRegistration];
        TSApplySelections(kept);
        // The frame resize already tried to put the clip at the left edge. Put that origin back before this turn
        // draws. Laying the whole document out here as well as on the next turn is what stalls a long file (#72).
        TSRestoreClipOrigin(keptAnchors);
        [undo enableUndoRegistration];
        // Measuring the text after this returns corrects the height estimate and scrolls the caret into view. Lay it
        // out once, while the hold still swallows that scroll, then put the place back (#72).
        dispatch_async(dispatch_get_main_queue(), ^{
            [undo disableUndoRegistration];
            TSFinishPlace(keptAnchors);
            [undo enableUndoRegistration];
            TSPopClipHold();
        });
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
