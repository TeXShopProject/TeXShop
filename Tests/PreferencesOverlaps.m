// Render every Preferences tab of each localization offscreen, in the light and dark
// appearances. Find each control's drawn extent by hiding it and diffing the rendering,
// and print controls that overlap or touch, that run over a box title or out of their
// box or are cut off by it, or whose text does not fit.
// Usage: PreferencesOverlaps Resources/Interfaces/<lang>.lproj/Preferences.nib ...
// The controls around the tabs are checked too. Each tab also prints a STAT line with the number of controls checked and how many of
// them drew nothing, so a change in how controls draw cannot make the check vacuous.
#import <Cocoa/Cocoa.h>
@interface TSPreferences : NSObject @end
@implementation TSPreferences
- (void)setValue:(id)v forUndefinedKey:(NSString *)k {}
- (id)valueForUndefinedKey:(NSString *)k { return nil; }
@end
static NSTabView *MainTabs(NSView *v) {
    if ([v isKindOfClass:NSTabView.class] && ((NSTabView *)v).numberOfTabViewItems == 9) return (NSTabView *)v;
    for (NSView *c in v.subviews) { NSTabView *t = MainTabs(c); if (t) return t; }
    return nil;
}
static NSString *Name(NSView *v) {
    NSString *s = nil;
    if ([v isKindOfClass:NSPopUpButton.class]) s = ((NSPopUpButton *)v).titleOfSelectedItem;
    else if ([v isKindOfClass:NSButton.class]) s = ((NSButton *)v).title;
    else if ([v isKindOfClass:NSTextField.class]) s = ((NSTextField *)v).stringValue;
    else if ([v isKindOfClass:NSMatrix.class]) s = [[(NSMatrix *)v cells].firstObject title];
    else if ([v isKindOfClass:NSBox.class]) s = ((NSBox *)v).title;
    if (s.length > 22) s = [[s substringToIndex:22] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:@"%@[%@]\"%@\"", NSStringFromClass(v.class), v.identifier ?: @"", s ?: @""];
}
static NSView *gSkip; // A subtree Collect leaves out.
static void Collect(NSView *v, NSMutableArray *out, NSMutableArray *boxes) {
    for (NSView *c in v.subviews) {
        if (c.hiddenOrHasHiddenAncestor || c == gSkip) continue;
        if ([c isKindOfClass:NSControl.class] || [c isKindOfClass:NSImageView.class]) [out addObject:c];
        else {
            if ([c isKindOfClass:NSBox.class]) [boxes addObject:c];
            Collect(c, out, boxes);
        }
    }
}
static NSBox *EnclosingBox(NSView *v) {
    for (NSView *s = v.superview; s; s = s.superview) if ([s isKindOfClass:NSBox.class]) return (NSBox *)s;
    return nil;
}
static NSBitmapImageRep *Render(NSView *v) {
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    return rep;
}
// Bounding box (in points, view coordinates with origin top-left) of pixels that differ.
static NSRect Diff(NSBitmapImageRep *a, NSBitmapImageRep *b, CGFloat scale) {
    NSInteger w = a.pixelsWide, h = a.pixelsHigh, bpr = a.bytesPerRow, spp = a.bitsPerPixel / 8;
    unsigned char *p = a.bitmapData, *q = b.bitmapData;
    NSInteger minx = w, miny = h, maxx = -1, maxy = -1;
    for (NSInteger y = 0; y < h; y++) {
        unsigned char *r1 = p + y * bpr, *r2 = q + y * bpr;
        if (memcmp(r1, r2, w * spp) == 0) continue;
        for (NSInteger x = 0; x < w; x++) {
            unsigned char *c1 = r1 + x * spp, *c2 = r2 + x * spp; int d = 0;
            for (int k = 0; k < spp; k++) d = MAX(d, abs(c1[k] - c2[k]));
            if (d > 8) { minx = MIN(minx, x); maxx = MAX(maxx, x); miny = MIN(miny, y); maxy = MAX(maxy, y); }
        }
    }
    if (maxx < 0) return NSZeroRect;
    return NSMakeRect(minx / scale, miny / scale, (maxx - minx + 1) / scale, (maxy - miny + 1) / scale);
}
// A rect of view v in root coordinates with the origin at the top left, like Diff.
static NSRect InRoot(NSView *v, NSRect r, NSView *root) {
    NSRect x = [v convertRect:r toView:root];
    if (!root.isFlipped) x.origin.y = root.bounds.size.height - NSMaxY(x);
    return x;
}
// Text wider than the room its cell gives it for the title, or a wrapping label taller
// than its frame.
static CGFloat TextWidth(NSString *t, NSFont *f) {
    return [t sizeWithAttributes:@{NSFontAttributeName: f ?: [NSFont systemFontOfSize:0]}].width;
}
static void Fit(NSString *where, NSView *c, NSCell *cell, NSString *title, NSRect b, NSMutableString *report) {
    if (!title.length || [title hasPrefix:@"-- DO NOT LOCALIZE"]) return;
    CGFloat need = TextWidth(title, cell.font), have = [cell titleRectForBounds:b].size.width;
    if (need > have + 1)
        [report appendFormat:@"%@\tTRUNC need=%.1f have=%.1f\t%@ \"%@\"\n", where, need, have, Name(c), title];
}
static void CheckFit(NSString *where, NSView *c, NSMutableString *report) {
    if ([c isKindOfClass:NSMatrix.class]) {
        NSMatrix *m = (NSMatrix *)c;
        for (NSCell *cell in m.cells) Fit(where, c, cell, cell.title, (NSRect){NSZeroPoint, m.cellSize}, report);
        return;
    }
    if ([c isKindOfClass:NSPopUpButton.class]) {
        // Any item can be the one shown once it is chosen, so every item must fit.
        // A pull-down menu always shows its first item.
        NSPopUpButton *p = (NSPopUpButton *)c;
        if (p.pullsDown) { Fit(where, c, p.cell, p.itemArray.firstObject.title, p.bounds, report); return; }
        // The room for the title depends on the item shown, so show each in turn.
        NSInteger selected = p.indexOfSelectedItem;
        for (NSInteger i = 0; i < p.numberOfItems; i++) {
            NSMenuItem *item = [p itemAtIndex:i];
            if (item.isSeparatorItem || item.isHidden) continue;
            [p selectItemAtIndex:i];
            Fit(where, c, p.cell, item.title, p.bounds, report);
        }
        [p selectItemAtIndex:selected];
    } else if ([c isKindOfClass:NSButton.class]) {
        NSButton *bt = (NSButton *)c;
        if (bt.imagePosition != NSImageOnly) Fit(where, c, bt.cell, bt.title, bt.bounds, report);
    } else if ([c isKindOfClass:NSTextField.class] && !((NSTextField *)c).isEditable) {
        NSTextField *f = (NSTextField *)c; NSCell *cell = f.cell;
        if (!f.stringValue.length) return;
        if (cell.wraps) {
            NSSize need = [cell cellSizeForBounds:NSMakeRect(0, 0, f.bounds.size.width, CGFLOAT_MAX)];
            if (need.height > f.bounds.size.height + 1)
                [report appendFormat:@"%@\tTRUNC need-height=%.1f have=%.1f\t%@\n", where, need.height, f.bounds.size.height, Name(c)];
        } else Fit(where, c, cell, f.stringValue, f.bounds, report);
    }
}
// The part of a control's bounds its content occupies.
static NSRect ContentRect(NSView *c) {
    NSRect b = c.bounds;
    if ([c isKindOfClass:NSMatrix.class]) {
        NSMatrix *m = (NSMatrix *)c; NSRect u = NSZeroRect;
        for (NSInteger r = 0; r < m.numberOfRows; r++) for (NSInteger k = 0; k < m.numberOfColumns; k++) {
            NSRect f = [m cellFrameAtRow:r column:k]; NSSize n = [m cellAtRow:r column:k].cellSize;
            u = NSUnionRect(u, NSMakeRect(f.origin.x, f.origin.y, MIN(n.width, f.size.width), f.size.height));
        }
        return u;
    }
    if (![c isKindOfClass:NSControl.class]) return b;
    NSCell *cell = ((NSControl *)c).cell;
    if (!cell) return b;
    NSSize n = cell.cellSize;
    if ([c isKindOfClass:NSTextField.class] && cell.wraps) n = [cell cellSizeForBounds:NSMakeRect(0, 0, b.size.width, CGFLOAT_MAX)];
    n.width = MIN(n.width, b.size.width); n.height = MIN(n.height, b.size.height);
    CGFloat x = 0;
    if ([c isKindOfClass:NSTextField.class]) {
        NSTextAlignment a = cell.alignment;
        if (a == NSTextAlignmentCenter) x = (b.size.width - n.width) / 2;
        else if (a == NSTextAlignmentRight) x = b.size.width - n.width;
    } else if ([c isKindOfClass:NSButton.class] && ((NSButton *)c).bezelStyle != NSBezelStyleRegularSquare && ![c isKindOfClass:NSPopUpButton.class]) {
        return b; // Push buttons fill their frame.
    }
    // Text fields draw their text from the top; buttons center it vertically.
    CGFloat y = [c isKindOfClass:NSTextField.class] ? (c.isFlipped ? 0 : b.size.height - n.height) : (b.size.height - n.height) / 2;
    return NSMakeRect(NSMinX(b) + x, NSMinY(b) + y, n.width, n.height);
}
static void Check(NSString *where, NSView *root, NSView *tv, NSMutableString *report) {
    Render(root); // The first rendering after a tab switch can still differ (tab bar).
    NSBitmapImageRep *base = Render(root);
    CGFloat scale = base.pixelsWide / root.bounds.size.width;
    NSMutableArray *leaves = [NSMutableArray array], *boxes = [NSMutableArray array]; Collect(tv, leaves, boxes);
    NSMutableArray *rects = [NSMutableArray array];
    NSRect noise = Diff(base, Render(root), scale);
    if (!NSIsEmptyRect(noise)) [report appendFormat:@"%@\tNOISE %@\n", where, NSStringFromRect(noise)];
    NSUInteger empty = 0;
    for (NSView *c in leaves) {
        c.hidden = YES; [root displayIfNeeded]; NSBitmapImageRep *img = Render(root); c.hidden = NO; [root displayIfNeeded];
        NSRect d = Diff(base, img, scale);
        if (NSIsEmptyRect(d)) empty++;
        [rects addObject:[NSValue valueWithRect:d]];
        CheckFit(where, c, report);
        // Part of what the control draws is cut off by an enclosing view, e.g. when it
        // was pushed out of its box. The content is the cell's natural size, placed in
        // the bounds by the control's alignment, so a frame wider than its text is fine.
        if (!c.enclosingScrollView) {
            NSRect content = ContentRect(c), vis = c.visibleRect;
            if (!NSIsEmptyRect(content) && !NSContainsRect(NSInsetRect(vis, -0.5, -0.5), content))
                [report appendFormat:@"%@\tCLIPPED content=%@ visible=%@\t%@\n", where, NSStringFromRect(content), NSStringFromRect(vis), Name(c)];
        }
    }
    [report appendFormat:@"%@\tSTAT controls=%lu empty=%lu\n", where, (unsigned long)leaves.count, (unsigned long)empty];
    for (NSUInteger i = 0; i < leaves.count; i++) for (NSUInteger j = i + 1; j < leaves.count; j++) {
        NSRect a = [rects[i] rectValue], b = [rects[j] rectValue];
        if (NSIsEmptyRect(a) || NSIsEmptyRect(b)) continue;
        NSRect x = NSIntersectionRect(a, b);
        if (x.size.width >= 1 && x.size.height >= 1)
            [report appendFormat:@"%@\tOVERLAP %.1fx%.1f\t%@ %@\t%@ %@\n", where, x.size.width, x.size.height, Name(leaves[i]), NSStringFromRect(a), Name(leaves[j]), NSStringFromRect(b)];
        else {
            // Vertically stacked with horizontal overlap and a gap under 2pt.
            CGFloat hov = MIN(NSMaxX(a), NSMaxX(b)) - MAX(NSMinX(a), NSMinX(b));
            CGFloat gap = MAX(NSMinY(a), NSMinY(b)) - MIN(NSMaxY(a), NSMaxY(b));
            CGFloat vov = MIN(NSMaxY(a), NSMaxY(b)) - MAX(NSMinY(a), NSMinY(b));
            CGFloat hgap = MAX(NSMinX(a), NSMinX(b)) - MIN(NSMaxX(a), NSMaxX(b));
            if (hov > 0 && gap >= 0 && gap < 2) [report appendFormat:@"%@\tTIGHT-V gap=%.1f\t%@ %@\t%@ %@\n", where, gap, Name(leaves[i]), NSStringFromRect(a), Name(leaves[j]), NSStringFromRect(b)];
            else if (vov > 0 && hgap >= 0 && hgap < 2) [report appendFormat:@"%@\tTIGHT-H gap=%.1f\t%@ %@\t%@ %@\n", where, hgap, Name(leaves[i]), NSStringFromRect(a), Name(leaves[j]), NSStringFromRect(b)];
        }
    }
    // Box titles and borders: a control must not run over the title of any box, nor
    // out of the border of the box it is in.
    for (NSBox *box in boxes) {
        if (box.boxType == NSBoxSeparator) continue;
        NSRect title = box.titlePosition == NSNoTitle || !box.title.length ? NSZeroRect : InRoot(box, box.titleRect, root);
        NSRect border = InRoot(box, box.borderRect, root);
        for (NSUInteger i = 0; i < leaves.count; i++) {
            NSRect a = [rects[i] rectValue];
            if (NSIsEmptyRect(a) || [leaves[i] superview] == box) continue;
            NSRect x = NSIntersectionRect(a, title);
            if (x.size.width >= 1 && x.size.height >= 1)
                [report appendFormat:@"%@\tOVER-TITLE %.1fx%.1f\t%@ %@\t%@ %@\n", where, x.size.width, x.size.height, Name(leaves[i]), NSStringFromRect(a), Name(box), NSStringFromRect(title)];
            // The box's own title field is a subview of the box, outside its border.
            if (box.isTransparent || EnclosingBox(leaves[i]) != box || [leaves[i] superview] == box) continue;
            if (!NSContainsRect(NSInsetRect(border, -0.5, -0.5), a))
                [report appendFormat:@"%@\tOUT-OF-BOX\t%@ %@\t%@ %@\n", where, Name(leaves[i]), NSStringFromRect(a), Name(box), NSStringFromRect(border)];
        }
    }
}
int main(int argc, char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSMutableString *report = [NSMutableString string];
    TSPreferences *owner = [TSPreferences new];
    NSArray *appearances = @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua];
    for (int a = 1; a < argc; a++) {
        NSString *path = @(argv[a]);
        NSString *file = [path stringByAppendingPathComponent:@"keyedobjects-101300.nib"];
        if (![NSFileManager.defaultManager fileExistsAtPath:file]) file = [path stringByAppendingPathComponent:@"keyedobjects.nib"];
        NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:file] bundle:nil];
        NSString *lang = path.stringByDeletingLastPathComponent.lastPathComponent.stringByDeletingPathExtension;
        for (NSString *appearance in appearances) {
            NSArray *objects;
            if (![nib instantiateWithOwner:owner topLevelObjects:&objects]) { fprintf(stderr, "load failed %s\n", argv[a]); return 1; }
            for (id o in objects) {
                if (![o isKindOfClass:NSWindow.class]) continue;
                NSWindow *w = o; NSTabView *tabs = MainTabs(w.contentView);
                if (!tabs) continue;
                w.appearance = [NSAppearance appearanceNamed:appearance];
                NSString *mode = [appearance isEqual:NSAppearanceNameAqua] ? @"light" : @"dark";
                for (NSInteger t = 0; t < tabs.numberOfTabViewItems; t++) {
                    [tabs selectTabViewItemAtIndex:t];
                    NSView *tv = tabs.tabViewItems[t].view;
                    NSMutableArray *nested = [NSMutableArray array]; NSMutableArray *st = [NSMutableArray arrayWithObject:tv];
                    while (st.count) { NSView *v = st.lastObject; [st removeLastObject]; if (v != tv && [v isKindOfClass:NSTabView.class]) [nested addObject:v]; [st addObjectsFromArray:v.subviews]; }
                    NSInteger inner = 1; for (NSTabView *n in nested) inner = MAX(inner, n.numberOfTabViewItems);
                    for (NSInteger k = 0; k < inner; k++) {
                        for (NSTabView *n in nested) if (k < n.numberOfTabViewItems) [n selectTabViewItemAtIndex:k];
                        [w.contentView layoutSubtreeIfNeeded]; [w displayIfNeeded];
                        NSString *tag = nested.count ? [NSString stringWithFormat:@"%ld.%ld", (long)t, (long)k] : [NSString stringWithFormat:@"%ld", (long)t];
                        Check([NSString stringWithFormat:@"%@\t%@\t%@", lang, mode, tag], w.contentView, tv, report);
                    }
                }
                // The controls around the tabs (settings profile, Cancel, OK).
                gSkip = tabs;
                Check([NSString stringWithFormat:@"%@\t%@\tbar", lang, mode], w.contentView, w.contentView, report);
                gSkip = nil;
                [w close];
            }
        }
    }
    fputs(report.UTF8String, stdout);
} return 0; }
