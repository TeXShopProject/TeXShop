// The checks of the layout of windows, panels and views, shared by the check of
// the localized nibs (InterfaceLabelFit.m) and of the windows the application
// builds in code (CodeBuiltLayout.m). Each prints what it finds:
//   CLIPPED  a label, button, matrix cell, pop-up choice, tab or placeholder is
//            narrower (or, when it wraps, shorter) than its text;
//   OUTSIDE  what a control draws reaches past its window, box, tab or other
//            enclosing view, which cuts it off;
//   OVERLAP  two controls draw over each other;
//   FOCUS    an input field's focus ring has less than 3 points of room inside
//            the window or beside the controls and scroll views next to it;
//   UNEVEN   an input field that wraps has more room above two lines of its
//            text than below, or, between a scroll view and the window edge,
//            is further from one than from the other;
//   TOUCH    two controls side by side or one above the other, or two cells of
//            one matrix (radio buttons, push buttons), are closer than 4 points:
//            their bezels touch, or a title runs into the next button;
//   WORDBREAK a label that wraps has a word wider than its lines, which breaks it;
//   HEADER   a column header of a table is cut off;
//   HIDDEN   the first row of a table starts under its header;
//   STRAY    a view draws outside the view that holds it, which does not clip
//            it (a line running past a scroll view to the window edge).
// Tables without rows get three sample rows while they are checked and drawn.
// Each control is drawn on its own with cacheDisplayInRect: to find the pixels it
// draws. What is typed into an editable field is not measured; its placeholder is.
// The including file imports Cocoa, objc/runtime.h and TestAppKitIsolation.h.
#import <objc/message.h>
// NSLocalizedString in the application's code returns the strings of the
// language whose nib is being checked.
static NSDictionary<NSString *, NSString *> *LocalizedStrings;
// Other tables of the same language, when the including file asks for them (UseLocalizedTables).
static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *LocalizedTables;
static IMP OriginalLocalizedString;
static NSString *LocalizedString(NSBundle *self, SEL _cmd, NSString *key, NSString *value, NSString *table) {
    if (self == NSBundle.mainBundle && (table == nil || [table isEqual:@"Localizable"]) && LocalizedStrings[key]) return LocalizedStrings[key];
    if (self == NSBundle.mainBundle && table != nil && LocalizedTables[table][key]) return LocalizedTables[table][key];
    return ((NSString *(*)(id, SEL, NSString *, NSString *, NSString *))OriginalLocalizedString)(self, _cmd, key, value, table);
}

static int problems;
static BOOL automaticBezel;
static NSString *imagesDirectory;
static BOOL imagesWithFocusRings;

static BOOL Placeholder(NSString *title) {
    return [title isEqual:@"Button"] || [title isEqual:@"Radio"] || [title isEqual:@"Switch"]
        || [title rangeOfString:@"^Item [0-9]+$" options:NSRegularExpressionSearch].location != NSNotFound;
}
static void Report(NSString *line) { printf("%s\n", line.UTF8String); problems++; }
static void CheckWordBreaks(NSTextField *field, NSString *text, NSString *where);
static NSString *Describe(NSView *v) {
    NSString *text = nil;
    if ([v isKindOfClass:NSPopUpButton.class]) text = ((NSPopUpButton *)v).titleOfSelectedItem;
    else if ([v isKindOfClass:NSButton.class]) text = ((NSButton *)v).title;
    else if ([v isKindOfClass:NSTextField.class]) text = ((NSTextField *)v).stringValue;
    else if ([v isKindOfClass:NSMatrix.class]) text = [[((NSMatrix *)v).cells valueForKey:@"title"] componentsJoinedByString:@" / "];
    else if ([v isKindOfClass:NSBox.class]) text = ((NSBox *)v).title;
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"⏎"];
    if (text.length > 60) text = [[text substringToIndex:60] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:@"%@ \"%@\"", NSStringFromClass(v.class), text ?: @""];
}

// What one control draws, and where, in the coordinates of the root view.
@interface Ink : NSObject
@property (strong) NSView *view;
@property (strong) NSBitmapImageRep *bitmap;
@property NSRect drawn;   // the bounding box of the pixels it draws, in the root view
@property NSRect faint;   // the same with the faint pixels of a light bezel (macOS 26 fills bezels thinly)
@end
@implementation Ink @end

static unsigned char Alpha(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    NSInteger spp = rep.samplesPerPixel, bps = rep.bitsPerPixel / 8;
    unsigned char *p = rep.bitmapData + y * rep.bytesPerRow + x * bps;
    if (!rep.hasAlpha) return 255;
    return rep.bitmapFormat & NSBitmapFormatAlphaFirst ? p[0] : p[spp - 1];
}
static Ink *Draw(NSView *v, NSView *root) {
    if (NSIsEmptyRect(v.bounds)) return nil;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    if (!rep) return nil;
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    NSInteger w = rep.pixelsWide, h = rep.pixelsHigh;
    Ink *ink = [Ink new];
    ink.view = v; ink.bitmap = rep;
    CGFloat sx = w / NSWidth(v.bounds), sy = h / NSHeight(v.bounds);
    for (int faint = 0; faint < 2; faint++) {
        NSInteger minx = w, miny = h, maxx = -1, maxy = -1;
        unsigned char threshold = faint ? 6 : 24;
        for (NSInteger y = 0; y < h; y++) for (NSInteger x = 0; x < w; x++)
            if (Alpha(rep, x, y) > threshold) { minx = MIN(minx, x); maxx = MAX(maxx, x); miny = MIN(miny, y); maxy = MAX(maxy, y); }
        NSRect found = NSZeroRect;
        if (maxx >= 0) {
            // Bitmap rows run from the top; the view may or may not be flipped.
            NSRect local = NSMakeRect(NSMinX(v.bounds) + minx / sx, 0, (maxx - minx + 1) / sx, (maxy - miny + 1) / sy);
            local.origin.y = v.isFlipped ? NSMinY(v.bounds) + miny / sy : NSMaxY(v.bounds) - (maxy + 1) / sy;
            found = [root convertRect:local fromView:v];
        }
        if (faint) ink.faint = found; else ink.drawn = found;
    }
    return ink;
}
// Whether the control draws a pixel at a point of the root view.
static BOOL InksAbove(Ink *ink, NSPoint p, NSView *root, unsigned char threshold);
static BOOL Inks(Ink *ink, NSPoint p, NSView *root) { return InksAbove(ink, p, root, 24); }
static BOOL InksAbove(Ink *ink, NSPoint p, NSView *root, unsigned char threshold) {
    NSView *v = ink.view;
    NSPoint q = [v convertPoint:p fromView:root];
    NSBitmapImageRep *rep = ink.bitmap;
    CGFloat sx = rep.pixelsWide / NSWidth(v.bounds), sy = rep.pixelsHigh / NSHeight(v.bounds);
    NSInteger x = floor((q.x - NSMinX(v.bounds)) * sx), y = floor((v.isFlipped ? q.y - NSMinY(v.bounds) : NSMaxY(v.bounds) - q.y) * sy);
    if (x < 0 || y < 0 || x >= rep.pixelsWide || y >= rep.pixelsHigh) return NO;
    return Alpha(rep, x, y) > threshold;
}

// The part of the root view in which a view can be seen: the bounds of each
// enclosing view, except that a scroll view's contents can be scrolled to.
static BOOL Scrolls(NSView *v) {
    for (NSView *a = v.superview; a; a = a.superview) if ([a isKindOfClass:NSClipView.class]) return YES;
    return NO;
}
static NSRect Visible(NSView *v, NSView *root) {
    NSRect r = root.bounds;
    for (NSView *a = v.superview; a && a != root; a = a.superview) r = NSIntersectionRect(r, [root convertRect:a.bounds fromView:a]);
    return r;
}

// Controls whose pixels are checked: everything a person reads or clicks.
static BOOL Measured(NSView *v) {
    if (![v isKindOfClass:NSControl.class]) return NO;
    if ([v isKindOfClass:NSScroller.class] || [v isKindOfClass:NSTableView.class]) return NO;
    return YES;
}

static void CheckText(NSView *v, NSString *where) {
    if ([v isKindOfClass:NSButton.class] && ![v isKindOfClass:NSPopUpButton.class]) {
        NSButton *b = (NSButton *)v;
        if (b.title.length && !Placeholder(b.title) && b.imagePosition != NSImageOnly) {
            // Toolbar buttons use the automatic bezel on macOS 26 and later.
            if (automaticBezel) b.bezelStyle = NSBezelStyleAutomatic;
            CGFloat need = [b.cell attributedTitle].size.width, have = [b.cell titleRectForBounds:b.bounds].size.width;
            if (need > have + 0.5) Report([NSString stringWithFormat:@"CLIPPED %@ button \"%@\"%@: needs %.1f, has %.1f", where, b.title, automaticBezel ? @" (automatic bezel)" : @"", need, have]);
        }
    }
    if ([v isKindOfClass:NSMatrix.class] && !automaticBezel) {
        // Each titled cell of a matrix (radio buttons, check boxes, button grids) fits the cell size.
        NSMatrix *m = (NSMatrix *)v;
        for (NSCell *cell in m.cells) {
            if (![cell isKindOfClass:NSButtonCell.class] || !cell.title.length || Placeholder(cell.title)) continue;
            NSButtonCell *b = (NSButtonCell *)cell;
            if (b.imagePosition == NSImageOnly) continue;
            NSRect bounds = NSMakeRect(0, 0, m.cellSize.width, m.cellSize.height);
            // A cell that wraps its title must be as tall as the lines need.
            BOOL wraps = b.wraps;
            CGFloat need = wraps ? [b cellSizeForBounds:NSMakeRect(0, 0, m.cellSize.width, CGFLOAT_MAX)].height : b.attributedTitle.size.width;
            CGFloat have = wraps ? m.cellSize.height : [b titleRectForBounds:bounds].size.width;
            if (need > have + 0.5) Report([NSString stringWithFormat:@"CLIPPED %@ matrix cell \"%@\": needs %.1f, has %.1f", where, b.title, need, have]);
        }
    }
    if ([v isKindOfClass:NSPopUpButton.class] && !automaticBezel) {
        // Every choice of a pop-up menu, and the title of a pull-down menu, fits the
        // button: each item is selected in a copy of the cell and measured with it.
        // The title of a pull-down menu is its first item, which the menu hides, so a
        // hidden first item is measured too. Placeholder items ("Item 1") are replaced
        // at run time.
        NSPopUpButton *p = (NSPopUpButton *)v;
        CGFloat have = p.bounds.size.width;
        NSInteger count = p.pullsDown ? MIN(1, p.numberOfItems) : p.numberOfItems;
        for (NSInteger i = 0; i < count; i++) {
            NSMenuItem *item = [p itemAtIndex:i];
            if (item.isSeparatorItem || (item.isHidden && !p.pullsDown) || !item.title.length) continue;
            if (Placeholder(item.title) || [item.title hasPrefix:@"-- DO NOT LOCALIZE"]) continue;
            NSPopUpButtonCell *cell = [(NSPopUpButtonCell *)p.cell copy];
            [cell removeAllItems]; [cell addItemWithTitle:item.title]; [cell selectItemAtIndex:0];
            if (p.pullsDown) {
                // A pull-down button draws its title in the room its arrow leaves, as a button
                // does (cellSize asks for more room than the title takes there).
                CGFloat text = cell.attributedTitle.size.width, room = [cell titleRectForBounds:p.bounds].size.width;
                if (text > room + 0.5) Report([NSString stringWithFormat:@"CLIPPED %@ pull-down \"%@\": needs %.1f, has %.1f", where, item.title, text, room]);
                continue;
            }
            CGFloat need = cell.cellSize.width;
            if (need > have + 1) Report([NSString stringWithFormat:@"CLIPPED %@ popup \"%@\": needs %.1f, has %.1f", where, item.title, need, have]);
        }
    }
    if ([v isKindOfClass:NSTextField.class] && ((NSTextField *)v).isEditable && !automaticBezel) {
        // The placeholder of an empty field, at the window's usual size.
        NSTextField *field = (NSTextField *)v;
        NSString *placeholder = field.placeholderString ?: field.placeholderAttributedString.string;
        if (placeholder.length && ![[field.cell stringValue] length]) {
            NSTextFieldCell *cell = [field.cell copy];
            cell.stringValue = placeholder;
            BOOL wraps = cell.wraps && !cell.usesSingleLineMode;
            CGFloat need = wraps ? [cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(field.bounds), CGFLOAT_MAX)].height : cell.cellSize.width;
            CGFloat have = wraps ? NSHeight(field.bounds) : NSWidth(field.bounds);
            if (need > have + 1) Report([NSString stringWithFormat:@"CLIPPED %@ placeholder \"%@\": needs %.1f, has %.1f", where, placeholder, need, have]);
        }
    }
    if ([v isKindOfClass:NSTextField.class] && !((NSTextField *)v).isEditable && !automaticBezel) {
        NSString *text = [[(NSTextField *)v stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
        if (text.length && !Placeholder(text)) {
            NSTextFieldCell *cell = [[(NSTextField *)v cell] copy];
            cell.stringValue = text;
            NSRect b = v.bounds;
            BOOL wraps = (cell.lineBreakMode == NSLineBreakByWordWrapping || cell.lineBreakMode == NSLineBreakByCharWrapping) && !cell.usesSingleLineMode;
            CGFloat need = wraps ? [cell cellSizeForBounds:NSMakeRect(0, 0, b.size.width, CGFLOAT_MAX)].height : cell.cellSize.width;
            CGFloat have = wraps ? b.size.height : b.size.width;
            if (need > have + 1) Report([NSString stringWithFormat:@"CLIPPED %@ \"%@\": needs %.1f, has %.1f", where, text, need, have]);
            if (wraps) CheckWordBreaks((NSTextField *)v, text, where);
        }
    }
}

static void Collect(NSView *v, NSView *root, NSString *where, NSMutableArray<Ink *> *inks, NSMutableArray<NSTabView *> *tabViews) {
    if (v.isHidden) return;
    CheckText(v, where);
    if (!automaticBezel && Measured(v) && !Scrolls(v)) {
        Ink *ink = Draw(v, root);
        if (ink) [inks addObject:ink];
    }
    if ([v isKindOfClass:NSTabView.class]) {
        NSTabView *tabs = (NSTabView *)v;
        [tabViews addObject:tabs];
        // The tabs themselves: NSTabView truncates labels that do not fit.
        if (!automaticBezel && tabs.tabViewType != NSNoTabsBezelBorder && tabs.tabViewType != NSNoTabsLineBorder && tabs.tabViewType != NSNoTabsNoBorder) {
            CGFloat need = tabs.minimumSize.width, have = NSWidth(tabs.bounds);
            if (need > have + 1) Report([NSString stringWithFormat:@"CLIPPED %@ tabs \"%@\": need %.1f, have %.1f", where,
                                         [[tabs.tabViewItems valueForKey:@"label"] componentsJoinedByString:@" / "], need, have]);
        }
    }
    // A matrix draws its own cells; a control's own subviews are part of what it draws.
    if ([v isKindOfClass:NSMatrix.class] || ([v isKindOfClass:NSControl.class] && Measured(v))) return;
    for (NSView *s in v.subviews) Collect(s, root, where, inks, tabViews);
}

static void CheckGeometry(NSView *root, NSString *where, NSArray<Ink *> *inks) {
    for (Ink *ink in inks) {
        if (NSIsEmptyRect(ink.drawn)) continue;
        NSRect visible = Visible(ink.view, root), d = ink.drawn;
        // A Return or Escape button placed out of sight on purpose only gives the
        // panel its key equivalent.
        if ([ink.view isKindOfClass:NSButton.class] && !NSIntersectsRect(d, visible)) {
            NSString *key = ((NSButton *)ink.view).keyEquivalent;
            if ([key isEqual:@"\r"] || [key isEqual:@"\033"]) continue;
        }
        CGFloat left = NSMinX(visible) - NSMinX(d), right = NSMaxX(d) - NSMaxX(visible);
        CGFloat bottom = NSMinY(visible) - NSMinY(d), top = NSMaxY(d) - NSMaxY(visible);
        CGFloat worst = MAX(MAX(left, right), MAX(bottom, top));
        if (worst > 1) {
            NSMutableArray *sides = [NSMutableArray array];
            if (left > 1) [sides addObject:[NSString stringWithFormat:@"left %.0f", left]];
            if (right > 1) [sides addObject:[NSString stringWithFormat:@"right %.0f", right]];
            if (bottom > 1) [sides addObject:[NSString stringWithFormat:@"bottom %.0f", bottom]];
            if (top > 1) [sides addObject:[NSString stringWithFormat:@"top %.0f", top]];
            NSView *clip = ink.view.superview == root ? root : ink.view.superview;
            Report([NSString stringWithFormat:@"OUTSIDE %@ %@ draws past its %@ (%@ points)", where, Describe(ink.view),
                    clip == root ? @"window" : NSStringFromClass(clip.class), [sides componentsJoinedByString:@", "]]);
        }
    }
    for (NSUInteger a = 0; a < inks.count; a++) for (NSUInteger b = a + 1; b < inks.count; b++) {
        Ink *p = inks[a], *q = inks[b];
        if ([p.view isDescendantOf:q.view] || [q.view isDescendantOf:p.view]) continue;
        NSRect both = NSIntersectionRect(NSIntersectionRect(p.drawn, q.drawn), NSIntersectionRect(Visible(p.view, root), Visible(q.view, root)));
        // Square buttons placed edge to edge share one border line, like the console's.
        if (NSWidth(both) <= 1.5 || NSHeight(both) <= 1.5) continue;
        // Count the points both draw, sampled every half point.
        NSUInteger shared = 0;
        for (CGFloat y = NSMinY(both) + 0.25; y < NSMaxY(both); y += 0.5)
            for (CGFloat x = NSMinX(both) + 0.25; x < NSMaxX(both); x += 0.5)
                if (Inks(p, NSMakePoint(x, y), root) && Inks(q, NSMakePoint(x, y), root)) shared++;
        if (shared >= 8)
            Report([NSString stringWithFormat:@"OVERLAP %@ %@ and %@ draw over each other (%.1f square points)", where, Describe(p.view), Describe(q.view), shared / 4.0]);
    }
}

static void SaveImage(NSView *root, NSString *name) {
    if (!imagesDirectory) return;
    NSBitmapImageRep *rep = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
    [root cacheDisplayInRect:root.bounds toBitmapImageRep:rep];
    // The content view draws no window background of its own.
    NSImage *image = [[NSImage alloc] initWithSize:root.bounds.size];
    [image lockFocus];
    [NSColor.windowBackgroundColor setFill]; NSRectFill(root.bounds);
    [rep drawInRect:root.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:NO hints:nil];
    // With --focus-rings, the ring each input field would show when focused,
    // cut off by the window edge as it is on screen.
    if (imagesWithFocusRings) {
        NSMutableArray<NSView *> *fields = [NSMutableArray array], *queue = [NSMutableArray arrayWithObject:root];
        while (queue.count) {
            NSView *v = queue.lastObject; [queue removeLastObject];
            if (v.isHidden || [v isKindOfClass:NSClipView.class]) continue;
            if ([v isKindOfClass:NSTextField.class] && ((NSTextField *)v).isEditable && v.focusRingType != NSFocusRingTypeNone) [fields addObject:v];
            [queue addObjectsFromArray:v.subviews];
        }
        for (NSView *field in fields) {
            [NSGraphicsContext saveGraphicsState];
            NSSetFocusRingStyle(NSFocusRingOnly);
            [[NSBezierPath bezierPathWithRoundedRect:[root convertRect:field.bounds fromView:field] xRadius:5 yRadius:5] fill];
            [NSGraphicsContext restoreGraphicsState];
        }
    }
    [image unlockFocus];
    NSBitmapImageRep *out = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
    NSString *file = [[name stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByAppendingPathExtension:@"png"];
    [[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[imagesDirectory stringByAppendingPathComponent:file] atomically:YES];
}

// An input field draws its focus ring outside its bezel. The ring needs room
// within the window and must not run into the controls and scroll views beside
// the field.
static const CGFloat FocusRingRoom = 3;
static void CollectScrollViews(NSView *v, NSMutableArray<NSView *> *out) {
    if (v.isHidden) return;
    if ([v isKindOfClass:NSScrollView.class]) { [out addObject:v]; return; }
    for (NSView *s in v.subviews) CollectScrollViews(s, out);
}
static void CheckFocusRings(NSView *root, NSString *where, NSArray<Ink *> *inks) {
    NSMutableArray<NSView *> *scrolls = [NSMutableArray array];
    CollectScrollViews(root, scrolls);
    for (Ink *ink in inks) {
        NSView *v = ink.view;
        if (![v isKindOfClass:NSTextField.class] || !((NSTextField *)v).isEditable || v.focusRingType == NSFocusRingTypeNone) continue;
        // The ring follows the bezel; a field that is not focused reports no mask.
        NSRect mask = NSIsEmptyRect(v.focusRingMaskBounds) ? v.bounds : v.focusRingMaskBounds;
        NSRect ring = NSInsetRect([root convertRect:mask fromView:v], -FocusRingRoom, -FocusRingRoom), b = root.bounds;
        NSMutableArray *sides = [NSMutableArray array];
        // A view loaded on its own, such as a toolbar item, has no window edge of its own.
        if (root.window.contentView == root) {
            if (NSMinX(b) - NSMinX(ring) > 0.5) [sides addObject:[NSString stringWithFormat:@"left %.0f", NSMinX(b) - NSMinX(ring)]];
            if (NSMaxX(ring) - NSMaxX(b) > 0.5) [sides addObject:[NSString stringWithFormat:@"right %.0f", NSMaxX(ring) - NSMaxX(b)]];
            if (NSMinY(b) - NSMinY(ring) > 0.5) [sides addObject:[NSString stringWithFormat:@"bottom %.0f", NSMinY(b) - NSMinY(ring)]];
            if (NSMaxY(ring) - NSMaxY(b) > 0.5) [sides addObject:[NSString stringWithFormat:@"top %.0f", NSMaxY(ring) - NSMaxY(b)]];
            if (sides.count) Report([NSString stringWithFormat:@"FOCUS %@ %@ has no room for its focus ring at the window edge (%@ points short)", where, Describe(v), [sides componentsJoinedByString:@", "]]);
        }
        NSMutableArray<NSValue *> *neighbours = [NSMutableArray array];
        NSMutableArray<NSView *> *views = [NSMutableArray array];
        // A stepper is measured by its frame: its arrows sit inside it, but the ring
        // must stay off the whole control, as in Settings.
        for (Ink *other in inks) if (!NSIsEmptyRect(other.drawn)) {
            NSRect r = [other.view isKindOfClass:NSStepper.class] ? [root convertRect:[other.view alignmentRectForFrame:other.view.frame] fromView:other.view.superview] : other.drawn;
            [neighbours addObject:[NSValue valueWithRect:r]]; [views addObject:other.view];
        }
        for (NSView *scroll in scrolls) { [neighbours addObject:[NSValue valueWithRect:[root convertRect:scroll.bounds fromView:scroll]]]; [views addObject:scroll]; }
        for (NSUInteger i = 0; i < views.count; i++) {
            NSView *other = views[i];
            if (other == v || [v isDescendantOf:other] || [other isDescendantOf:v]) continue;
            NSRect x = NSIntersectionRect(ring, NSIntersectionRect(neighbours[i].rectValue, Visible(other, root)));
            if (NSWidth(x) > 0.5 && NSHeight(x) > 0.5)
                Report([NSString stringWithFormat:@"FOCUS %@ %@ has no room for its focus ring beside %@ (%.1f by %.1f points)", where, Describe(v), [other isKindOfClass:NSScrollView.class] ? @"a scroll view" : Describe(other), NSWidth(x), NSHeight(x)]);
        }
    }
}

// An input field that wraps its text, like the console's, shows two lines with
// the same room above the first line's box (ascender to descender) as below
// the second's, as the field editor lays them out. When it sits between a
// scroll view above and the window edge below, it is as far from each.
static const CGFloat EvenTolerance = 0.5;
static void CheckEvenMargins(NSView *root, NSString *where, NSArray<Ink *> *inks) {
    NSWindow *window = root.window;
    if (window.contentView != root) return;
    NSMutableArray<NSView *> *scrolls = [NSMutableArray array];
    CollectScrollViews(root, scrolls);
    for (Ink *ink in inks) {
        if (![ink.view isKindOfClass:NSTextField.class]) continue;
        NSTextField *field = (NSTextField *)ink.view;
        NSTextFieldCell *cell = field.cell;
        if (!field.isEditable || !cell.wraps || cell.usesSingleLineMode) continue;
        // Two lines of text inside the field.
        BOOL enabled = field.enabled; NSString *value = field.stringValue;
        field.enabled = YES; field.stringValue = @"";
        // The first time a window's field editor edits more than one line, it lays
        // them out 1 point closer than afterwards and than the field draws them;
        // measure the lines as they are from the second time on.
        if ([window makeFirstResponder:field] && [field.currentEditor isKindOfClass:NSTextView.class]) {
            NSTextView *warm = (NSTextView *)field.currentEditor;
            [warm insertText:@"Hxgy\u2028Hxgy" replacementRange:NSMakeRange(0, warm.string.length)];
            [warm.layoutManager ensureLayoutForTextContainer:warm.textContainer];
            [window makeFirstResponder:nil]; field.stringValue = @"";
        }
        if (![window makeFirstResponder:field] || ![field.currentEditor isKindOfClass:NSTextView.class]) { field.enabled = enabled; continue; }
        NSTextView *editor = (NSTextView *)field.currentEditor;
        [editor insertText:@"Hxgy Hxgy" replacementRange:NSMakeRange(0, editor.string.length)];
        NSLayoutManager *lm = editor.layoutManager; [lm ensureLayoutForTextContainer:editor.textContainer];
        NSFont *font = [editor.textStorage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] ?: field.font;
        NSMutableArray<NSNumber *> *baselines = [NSMutableArray array];
        [lm enumerateLineFragmentsForGlyphRange:NSMakeRange(0, lm.numberOfGlyphs) usingBlock:^(NSRect rect, NSRect used, NSTextContainer *c, NSRange glyphs, BOOL *stop) {
            NSPoint baseline = NSMakePoint(0, NSMinY(rect) + [lm locationForGlyphAtIndex:glyphs.location].y);
            [baselines addObject:@([field convertPoint:NSMakePoint(editor.textContainerOrigin.x, editor.textContainerOrigin.y + baseline.y) fromView:editor].y)];
        }];
        [window makeFirstResponder:nil];
        field.stringValue = value; field.enabled = enabled;
        if (baselines.count == 2) {
            // The field is flipped: y grows downwards.
            CGFloat top = baselines[0].doubleValue - font.ascender, bottom = NSHeight(field.bounds) - (baselines[1].doubleValue - font.descender);
            if (fabs(top - bottom) > EvenTolerance)
                Report([NSString stringWithFormat:@"UNEVEN %@ %@ has %.2f points above two lines of text and %.2f below", where, Describe(field), top, bottom]);
        }
        // Between a scroll view above and the window edge below.
        NSRect f = [root convertRect:field.bounds fromView:field];
        NSView *above = nil; CGFloat aboveY = CGFLOAT_MAX;
        for (NSView *scroll in scrolls) {
            NSRect r = [root convertRect:scroll.bounds fromView:scroll];
            if (NSMinY(r) >= NSMaxY(f) - 0.5 && NSMinX(r) < NSMaxX(f) && NSMaxX(r) > NSMinX(f) && NSMinY(r) < aboveY) { above = scroll; aboveY = NSMinY(r); }
        }
        BOOL lowest = YES;
        for (Ink *other in inks) if (other != ink && !NSIsEmptyRect(other.drawn) && NSMinY(other.drawn) < NSMinY(f)) lowest = NO;
        if (above && lowest) {
            CGFloat gapAbove = aboveY - NSMaxY(f), gapBelow = NSMinY(f) - NSMinY(root.bounds);
            if (fabs(gapAbove - gapBelow) > EvenTolerance)
                Report([NSString stringWithFormat:@"UNEVEN %@ %@ is %.1f points below the scroll view above it but %.1f above the window edge", where, Describe(field), gapAbove, gapBelow]);
        }
    }
}


// Controls closer than this, and cells of a matrix, look as if they touch. The title of a radio button or
// check box needs more room before the next control beside it, or it reads as that control's title.
static const CGFloat MinimumGap = 4, ChoiceGap = 8;
@interface NSButtonCell (LayoutChecksPrivate) - (NSInteger)_buttonType; @end
static BOOL CellIsChoice(NSCell *cell) {
    if (![cell isKindOfClass:NSButtonCell.class] || ![cell respondsToSelector:@selector(_buttonType)]) return NO;
    NSInteger type = ((NSInteger (*)(id, SEL))objc_msgSend)(cell, @selector(_buttonType));
    return type == NSButtonTypeSwitch || type == NSButtonTypeRadio;
}
// A button cell that draws its bezel all the time.
static BOOL CellShowsBezel(NSCell *cell) {
    if (![cell isKindOfClass:NSButtonCell.class]) return NO;
    NSButtonCell *b = (NSButtonCell *)cell;
    return b.isBordered && !b.showsBorderOnlyWhileMouseInside && !CellIsChoice(b);
}
static NSString *CellName(NSCell *cell) {
    NSString *title = [cell isKindOfClass:NSButtonCell.class] ? ((NSButtonCell *)cell).title : cell.stringValue;
    return title.length ? [NSString stringWithFormat:@"\"%@\"", title] : (cell.image ? @"(picture)" : @"(empty)");
}

// The cells of a matrix: each cell's drawn pixels, within its own frame, keep MinimumGap from those of the
// next cell in its row and in its column when either draws a bezel or is a radio button or check box (its
// title must not run into the next mark); other cells must not touch.
static void CheckMatrixCells(Ink *ink, NSView *root, NSString *where) {
    NSMatrix *m = (NSMatrix *)ink.view;
    if (NSIsEmptyRect(m.bounds)) return;
    // The cells alone, without the background a matrix may fill behind them.
    BOOL background = m.drawsBackground, cellBackground = m.drawsCellBackground;
    m.drawsBackground = NO; m.drawsCellBackground = NO;
    NSBitmapImageRep *rep = [m bitmapImageRepForCachingDisplayInRect:m.bounds];
    [m cacheDisplayInRect:m.bounds toBitmapImageRep:rep];
    m.drawsBackground = background; m.drawsCellBackground = cellBackground;
    if (!rep) return;
    CGFloat sx = rep.pixelsWide / NSWidth(m.bounds), sy = rep.pixelsHigh / NSHeight(m.bounds);
    NSInteger rows = m.numberOfRows, columns = m.numberOfColumns;
    NSRect boxes[rows * columns + 1];
    for (NSInteger r = 0; r < rows; r++) for (NSInteger c = 0; c < columns; c++) {
        NSRect frame = NSIntersectionRect([m cellFrameAtRow:r column:c], m.bounds), box = NSZeroRect;
        NSCell *cell = [m cellAtRow:r column:c];
        if (cell && !NSIsEmptyRect(frame)) {
            NSInteger x0 = floor((NSMinX(frame) - NSMinX(m.bounds)) * sx), x1 = ceil((NSMaxX(frame) - NSMinX(m.bounds)) * sx);
            NSInteger y0 = floor((m.isFlipped ? NSMinY(frame) - NSMinY(m.bounds) : NSMaxY(m.bounds) - NSMaxY(frame)) * sy), y1 = y0 + ceil(NSHeight(frame) * sy);
            NSInteger minx = NSIntegerMax, maxx = -1, miny = NSIntegerMax, maxy = -1;
            for (NSInteger y = MAX(0, y0); y < MIN(y1, rep.pixelsHigh); y++) for (NSInteger x = MAX(0, x0); x < MIN(x1, rep.pixelsWide); x++)
                if (Alpha(rep, x, y) > 6) { minx = MIN(minx, x); maxx = MAX(maxx, x); miny = MIN(miny, y); maxy = MAX(maxy, y); }
            // In points from the top left of the matrix.
            if (maxx >= 0) box = NSMakeRect(minx / sx, miny / sy, (maxx - minx + 1) / sx, (maxy - miny + 1) / sy);
        }
        boxes[r * columns + c] = box;
    }
    for (NSInteger r = 0; r < rows; r++) for (NSInteger c = 0; c < columns; c++) {
        NSRect a = boxes[r * columns + c];
        if (NSIsEmptyRect(a)) continue;
        NSCell *cell = [m cellAtRow:r column:c];
        for (int next = 0; next < 2; next++) {
            NSInteger r2 = r + (next ? 1 : 0), c2 = c + (next ? 0 : 1);
            if (r2 >= rows || c2 >= columns) continue;
            NSRect b = boxes[r2 * columns + c2];
            if (NSIsEmptyRect(b)) continue;
            NSCell *other = [m cellAtRow:r2 column:c2];
            CGFloat gap = next ? NSMinY(b) - NSMaxY(a) : NSMinX(b) - NSMaxX(a);
            BOOL framed = CellShowsBezel(cell) || CellShowsBezel(other) || CellIsChoice(cell);
            CGFloat need = !next && CellIsChoice(cell) ? ChoiceGap : framed ? MinimumGap : 1;
            if (gap < need)
                Report([NSString stringWithFormat:@"TOUCH %@ %@: cells %@ and %@ %@ are %.1f points apart (need %.0f)", where, Describe(m),
                        CellName(cell), CellName(other), next ? @"one above the other" : @"side by side", gap, need]);
        }
    }
}

// Two controls side by side or one above the other keep MinimumGap between what they draw.
static void CheckGaps(NSView *root, NSString *where, NSArray<Ink *> *inks) {
    for (NSUInteger a = 0; a < inks.count; a++) for (NSUInteger b = a + 1; b < inks.count; b++) {
        Ink *p = inks[a], *q = inks[b];
        if (NSIsEmptyRect(p.faint) || NSIsEmptyRect(q.faint)) continue;
        if ([p.view isDescendantOf:q.view] || [q.view isDescendantOf:p.view]) continue;
        NSRect r = p.faint, t = q.faint;
        CGFloat dx = MAX(NSMinX(t) - NSMaxX(r), NSMinX(r) - NSMaxX(t)), dy = MAX(NSMinY(t) - NSMaxY(r), NSMinY(r) - NSMaxY(t));
        // Two that share a row (or a column) by more than 2 points; when both overlap, by how much (a negative
        // gap): faint bezels that overlap are not counted by OVERLAP.
        CGFloat gap = dx < -1.5 && dy < -1.5 ? MAX(dx, dy) : dy < -2 ? dx : dx < -2 ? dy : CGFLOAT_MAX;
        if (dx < -1.5 && dy < -1.5) {
            // Overlapping boxes count only where both draw, like a bezel under another control; a label in an
            // empty part of a matrix does not.
            NSRect both = NSIntersectionRect(r, t);
            NSUInteger shared = 0;
            for (CGFloat y = NSMinY(both) + 0.25; y < NSMaxY(both) && shared < 4; y += 0.5)
                for (CGFloat x = NSMinX(both) + 0.25; x < NSMaxX(both) && shared < 4; x += 0.5)
                    if (InksAbove(p, NSMakePoint(x, y), root, 6) && InksAbove(q, NSMakePoint(x, y), root, 6)) shared++;
            if (shared < 4) continue;
        }
        // A radio button or check box with its title on the left of another control, side by side.
        NSView *left = NSMinX(r) <= NSMinX(t) ? p.view : q.view;
        BOOL choice = dy < -2 && [left isKindOfClass:NSButton.class] && ((NSButton *)left).title.length && CellIsChoice(((NSButton *)left).cell);
        CGFloat need = choice ? ChoiceGap : MinimumGap;
        if (gap < need)
            Report([NSString stringWithFormat:@"TOUCH %@ %@ and %@ are %.1f points apart (need %.0f)", where, Describe(p.view), Describe(q.view), gap, need]);
    }
}

// A label that wraps breaks its lines between words: no word may be wider than a line. Words of Chinese and
// Japanese, which are not separated by spaces and wrap between any two characters, are not counted.
static BOOL WrapsAnywhere(NSString *word) {
    for (NSUInteger i = 0; i < word.length; i++) {
        unichar c = [word characterAtIndex:i];
        if ((c >= 0x3000 && c <= 0x9FFF) || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0xFF00 && c <= 0xFFEF)) return YES;
    }
    return NO;
}
static void CheckWordBreaks(NSTextField *field, NSString *text, NSString *where) {
    // Each word on a line of its own, as the field's cell measures it, with its insets and padding.
    NSTextFieldCell *cell = [field.cell copy];
    CGFloat line = NSWidth(field.bounds);
    for (NSString *word in [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (!word.length || WrapsAnywhere(word)) continue;
        cell.stringValue = word;
        CGFloat need = cell.cellSize.width;
        if (need > line + 0.5)
            Report([NSString stringWithFormat:@"WORDBREAK %@ \"%@\": the word \"%@\" needs %.1f, a line has %.1f", where, text, word, need, line]);
    }
}

// Tables: every column header shows its whole title, and the first row starts below the header.
@interface SampleRows : NSObject <NSTableViewDataSource> @end
@implementation SampleRows
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 3; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r { return @"Sample"; }
@end
static SampleRows *sampleRows;
static void CollectTables(NSView *v, NSMutableArray<NSTableView *> *out) {
    if (v.isHidden) return;
    if ([v isKindOfClass:NSTableView.class]) [out addObject:(NSTableView *)v];
    for (NSView *s in v.subviews) CollectTables(s, out);
}
// Tables without rows are given sample rows while the window is checked; returns what to restore.
static NSArray *GiveSampleRows(NSView *root) {
    NSMutableArray<NSTableView *> *tables = [NSMutableArray array];
    CollectTables(root, tables);
    NSMutableArray *restore = [NSMutableArray array];
    if (!sampleRows) sampleRows = [SampleRows new];
    for (NSTableView *table in tables) {
        if (table.numberOfRows > 0 || [table isKindOfClass:NSOutlineView.class]) continue;
        [restore addObject:@[table, table.dataSource ?: NSNull.null]];
        table.dataSource = sampleRows;
        [table reloadData];
    }
    return restore;
}
static void TakeSampleRows(NSArray *restore) {
    for (NSArray *entry in restore) {
        NSTableView *table = entry[0];
        table.dataSource = entry[1] == NSNull.null ? nil : entry[1];
        [table reloadData];
    }
}
static void CheckTables(NSView *root, NSString *where) {
    NSMutableArray<NSTableView *> *tables = [NSMutableArray array];
    CollectTables(root, tables);
    for (NSTableView *table in tables) {
        for (NSTableColumn *column in table.tableColumns) {
            if (column.isHidden || !column.headerCell.stringValue.length) continue;
            CGFloat need = column.headerCell.cellSize.width, have = column.width;
            if (need > have + 0.5)
                Report([NSString stringWithFormat:@"HEADER %@ column header \"%@\" needs %.1f, has %.1f", where, column.headerCell.stringValue, need, have]);
        }
        NSTableHeaderView *header = table.headerView;
        if (!header || header.isHiddenOrHasHiddenAncestor || !header.window || table.numberOfRows == 0) continue;
        NSRect row = [root convertRect:[table rectOfRow:0] fromView:table];
        NSRect top = [root convertRect:header.visibleRect fromView:header];
        CGFloat under = MIN(NSMaxY(row), NSMaxY(top)) - MAX(NSMinY(row), NSMinY(top));
        if (under > 0.5 && NSMinX(row) < NSMaxX(top) && NSMaxX(row) > NSMinX(top))
            Report([NSString stringWithFormat:@"HIDDEN %@ the first row of %@ is %.1f points under its header", where, NSStringFromClass(table.class), under]);
    }
}

// A view that draws outside the view holding it, where nothing clips it: since macOS 14 views do not clip
// their subviews unless asked to.
static BOOL ClipsBelow(NSView *v) { return v.clipsToBounds || [v isKindOfClass:NSClipView.class]; }
static void CheckStrays(NSView *v, NSView *root, NSString *where) {
    for (NSView *s in v.subviews) {
        if (s.isHidden || s.alphaValue <= 0) continue;
        // Controls are OUTSIDE's (which knows the buttons placed out of sight on purpose).
        BOOL control = [s isKindOfClass:NSControl.class] && Measured(s);
        if (!control && !ClipsBelow(v) && !NSIsEmptyRect(s.frame) && !NSContainsRect(NSInsetRect(v.bounds, -2, -2), s.frame)) {
            Ink *ink = Draw(s, root);
            NSRect holder = [root convertRect:v.bounds fromView:v];
            if (ink && !NSIsEmptyRect(ink.drawn) && !NSContainsRect(NSInsetRect(holder, -2, -2), ink.drawn)) {
                // Where it draws past its holder, on each side.
                NSRect d = ink.drawn;
                CGFloat worst = MAX(MAX(NSMinX(holder) - NSMinX(d), NSMaxX(d) - NSMaxX(holder)), MAX(NSMinY(holder) - NSMinY(d), NSMaxY(d) - NSMaxY(holder)));
                Report([NSString stringWithFormat:@"STRAY %@ %@ draws %.0f points outside the %@ that holds it", where, NSStringFromClass(s.class), worst, NSStringFromClass(v.class)]);
                continue;
            }
        }
        // The controls' own parts are checked as controls (OUTSIDE).
        if (control) continue;
        CheckStrays(s, root, where);
    }
}

static void CheckRoot(NSView *root, NSString *where) {
    NSMutableArray<Ink *> *inks = [NSMutableArray array];
    NSMutableArray<NSTabView *> *tabViews = [NSMutableArray array];
    [root layoutSubtreeIfNeeded];
    Collect(root, root, where, inks, tabViews);
    if (!automaticBezel) {
        CheckGeometry(root, where, inks); CheckFocusRings(root, where, inks); CheckEvenMargins(root, where, inks);
        CheckGaps(root, where, inks); CheckTables(root, where); CheckStrays(root, root, where);
        for (Ink *ink in inks) if ([ink.view isKindOfClass:NSMatrix.class]) CheckMatrixCells(ink, root, where);
    }
    // Each tab that is not selected, chosen as a person would choose it.
    for (NSTabView *tabs in tabViews) {
        NSTabViewItem *selected = tabs.selectedTabViewItem;
        for (NSTabViewItem *item in tabs.tabViewItems) {
            if (item == selected || !item.view) continue;
            [tabs selectTabViewItem:item];
            [root layoutSubtreeIfNeeded];
            NSMutableArray<Ink *> *page = [NSMutableArray array];
            NSString *tab = [NSString stringWithFormat:@"%@ tab \"%@\"", where, item.label];
            Collect(item.view, root, tab, page, [NSMutableArray array]);
            if (!automaticBezel) {
                CheckGeometry(root, tab, page); CheckFocusRings(root, tab, page); CheckEvenMargins(root, tab, page);
                CheckGaps(root, tab, page); CheckTables(item.view, tab); CheckStrays(item.view, root, tab);
                for (Ink *ink in page) if ([ink.view isKindOfClass:NSMatrix.class]) CheckMatrixCells(ink, root, tab);
            }
        }
        if (selected) [tabs selectTabViewItem:selected];
    }
}

// TSDocument.nib keeps the custom views of the toolbars (pop-up menus, check boxes,
// page fields) in a view of their own, of class NSMatrix but without cells. The
// toolbar takes each view out of it, so the text of each part is checked on its own,
// and where the parts lie in that view does not matter.
static BOOL ToolbarParts(NSView *v) {
    return [v isKindOfClass:NSMatrix.class] && ((NSMatrix *)v).cells.count == 0 && v.subviews.count > 0;
}
static void CheckToolbarParts(NSView *box, NSString *where) {
    for (NSView *part in box.subviews) Collect(part, part, where, [NSMutableArray array], [NSMutableArray array]);
    if (!automaticBezel) SaveImage(box, where);
}

// A window as it opens, and, when it can be made smaller, at its smallest size,
// where it must still show everything.
static void CheckWindow(NSWindow *w, NSString *where) {
    NSArray *samples = automaticBezel ? @[] : GiveSampleRows(w.contentView);
    CheckRoot(w.contentView, where);
    if (!automaticBezel) SaveImage(w.contentView, where);
    NSSize smallest = [w contentRectForFrameRect:NSMakeRect(0, 0, w.minSize.width, w.minSize.height)].size;
    if (!NSEqualSizes(w.contentMinSize, NSZeroSize)) smallest = NSMakeSize(MAX(smallest.width, w.contentMinSize.width), MAX(smallest.height, w.contentMinSize.height));
    NSSize current = w.contentView.bounds.size;
    if (!automaticBezel && (w.styleMask & NSWindowStyleMaskResizable) && smallest.width > 1 && smallest.height > 1
        && (smallest.width < current.width - 0.5 || smallest.height < current.height - 0.5)) {
        [w setContentSize:NSMakeSize(MIN(current.width, MAX(smallest.width, 1)), MIN(current.height, MAX(smallest.height, 1)))];
        NSString *smallestWhere = [where stringByAppendingFormat:@" at its smallest size %.0fx%.0f", NSWidth(w.contentView.bounds), NSHeight(w.contentView.bounds)];
        CheckRoot(w.contentView, smallestWhere);
        SaveImage(w.contentView, smallestWhere);
        [w setContentSize:current];
    }
    TakeSampleRows(samples);
}

// Install before NSApplication: NSLocalizedString then returns LocalizedStrings.
static void InstallLocalizedStrings(void) {
    Method localized = class_getInstanceMethod(NSBundle.class, @selector(localizedStringForKey:value:table:));
    OriginalLocalizedString = method_setImplementation(localized, (IMP)LocalizedString);
}
static void UseLocalizedStrings(NSString *path) {
    NSString *source = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    LocalizedStrings = source ? [source propertyListFromStringsFileFormat] : @{};
}
// The tables beside the Localizable.strings at path, or, where the language has none (English), in Base.lproj.
__attribute__((unused)) static void UseLocalizedTables(NSString *path, NSArray<NSString *> *tables) {
    NSMutableDictionary *loaded = [NSMutableDictionary dictionary];
    NSString *folder = path.stringByDeletingLastPathComponent;
    NSString *base = [folder.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"Base.lproj"];
    for (NSString *table in tables) {
        NSString *name = [table stringByAppendingPathExtension:@"strings"];
        NSString *file = [folder stringByAppendingPathComponent:name];
        if (![NSFileManager.defaultManager fileExistsAtPath:file]) file = [base stringByAppendingPathComponent:name];
        NSString *source = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
        loaded[table] = source ? [source propertyListFromStringsFileFormat] : @{};
    }
    LocalizedTables = loaded;
}
